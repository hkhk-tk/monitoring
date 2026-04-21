# Päev 2 · Zabbix Labor

Eeldused: päev 1 (Docker, pull-mudel, trigger-olekud).

7 osa, raskus kasvab. Klassis jõuad enamuse, ülejäänu kodus.

1. Stack üles
2. Host + template + trigger
3. User macros
4. HTTP Agent + Dependent items
5. UserParameter
6. LLD + oma template
7. Discord

Päev 1 stack maha enne alustamist:

```bash
cd ~/paev1 && docker compose down && cd ~
```

mon-target ja mon-target-web peale on `zabbix-agent` juba paigaldatud. Kontrolli:

```bash
nc -zv 192.168.35.140 10050 && nc -zv 192.168.35.141 10050
```

Mõlemad `succeeded`. Kui ei ole, ütle koolitajale.

---

## Osa 1 · Stack üles

Zabbix on neli komponenti: **MySQL** hoiab konfi ja ajalugu, **Server** teeb päringuid ja arvutab trigger'id, **Web** on UI, **Agent** kogub sinu VM-ist mõõdikuid (demo-jaoks — päris agent'id on mon-target ja mon-target-web peal).

Ehitame neid ükshaaval ja testime iga sammu eraldi. Kui midagi kukub, tead **täpselt** kus.

```bash
mkdir -p ~/paev2/zabbix/config && cd ~/paev2
```

### 1.1 Baas

Loo `docker-compose.yml` järgmise sisuga — teenuseid lisame järgmistes alaosades.

```yaml
services:
  # teenused lisanduvad siia

volumes:
  mysql-data:
```

Paneme `mysql-data` volume kohe alguses — ilma selleta kaotaks `docker compose down` kogu Zabbix konfi.

### 1.2 MySQL

Zabbix Server ei käivitu ilma andmebaasita. Alustame sellest.

Lisa `services:` alla:

```yaml
  mysql:
    image: mysql:8.0
    container_name: mysql
    environment:
      MYSQL_DATABASE: zabbix          # DB nimi — Server ootab täpselt seda
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pwd
      MYSQL_ROOT_PASSWORD: root_pwd
      TZ: Europe/Tallinn              # muidu logid UTC-s, segav
    command:
      - mysqld
      - --character-set-server=utf8mb4    # Zabbix 7 nõue — utf8mb4
      - --collation-server=utf8mb4_bin    # täpne string-võrdlus (hoia tabelite nime)
    volumes:
      - mysql-data:/var/lib/mysql     # ilma selleta down = kogu DB maha
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-uroot", "-proot_pwd"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s               # esmakäivitus loob skeemi, võtab ~60s
    restart: unless-stopped
```

Testi ainult MySQL:

```bash
docker compose up -d mysql
docker compose ps
```

Oota kuni status on `Up (healthy)` — esmakäivitusel ~60s. Kontroll:

```bash
docker exec mysql mysql -uzabbix -pzabbix_pwd -e 'SHOW DATABASES;'
```

Pead nägema rida `zabbix`. Kui ei, vaata `docker compose logs mysql`.

### 1.3 Zabbix Server

Server on monitooringu süda — küsib agent'idelt andmeid, arvutab trigger'id, salvestab MySQL-i.

Lisa `services:` alla MySQL-i järele:

```yaml
  zabbix-server:
    image: zabbix/zabbix-server-mysql:ubuntu-7.0.6
    container_name: zabbix-server
    depends_on:
      mysql:
        condition: service_healthy    # oota MySQL healthcheck rohelisena
    environment:
      DB_SERVER_HOST: mysql           # DNS-nimi Docker võrgus (= konteineri nimi)
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pwd
      TZ: Europe/Tallinn
    ports:
      - "10051:10051"                 # agent'id saadavad active-andmeid siia
    restart: unless-stopped
```

`DB_SERVER_HOST: mysql` — **DNS-nimi, mitte IP**. Docker bridge-võrgus iga konteiner saab teistele viidata nende container_name kaudu. IP muutub restart'iga, nimi ei muutu.

`depends_on.condition: service_healthy` — ilma selleta käivituks Server enne kui MySQL valmis ja restartuks paar korda.

Testi Server:

```bash
docker compose up -d zabbix-server
docker compose logs -f zabbix-server
```

Oota rida:

```
Zabbix Server started. Zabbix 7.0.6 (revision xxxxxx).
```

Ctrl+C logidest välja. Kontrolli kas skeem ehitati:

```bash
docker exec mysql mysql -uzabbix -pzabbix_pwd zabbix -e 'SHOW TABLES;' | wc -l
```

Tabeleid umbes **170**. Server lõi need ise esmakäivitusel — ilma sinu abita.

### 1.4 Zabbix Web

Web on PHP + Nginx UI. Vajab **kahte** andmeallikat: MySQL-i konfi jaoks (host'id, trigger'id), Server-it live-andmete jaoks (hetkeväärtused, graafikud).

Lisa:

```yaml
  zabbix-web:
    image: zabbix/zabbix-web-nginx-mysql:ubuntu-7.0.6
    container_name: zabbix-web
    depends_on:
      mysql:
        condition: service_healthy
      zabbix-server:
        condition: service_started
    environment:
      ZBX_SERVER_HOST: zabbix-server  # live-andmed siit
      DB_SERVER_HOST: mysql           # config siit
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pwd
      PHP_TZ: Europe/Tallinn          # PHP ajatsoon — graafikud õige ajaga
      TZ: Europe/Tallinn
    ports:
      - "8080:8080"
    restart: unless-stopped
```

Testi:

```bash
docker compose up -d zabbix-web
```

Brauseris `http://192.168.35.12X:8080`. Login: `Admin` / `zabbix` (vaheta kohe: ülal parempoolne ikoon → Users → Admin → Change password → `Monitor2026!`).

Kui leht ei lae:

```bash
docker compose logs zabbix-web | tail -30
```

Tavaline viga — "Database is not available" — tähendab et MySQL pole veel healthy. Oota 30s ja proovi uuesti.

### 1.5 Zabbix Agent

Selle labori jaoks käivitame demo-agent'i meie enda Compose stack'is. Päris agent'id jooksevad juba mon-target ja mon-target-web peal.

Lisa:

```yaml
  zabbix-agent:
    image: zabbix/zabbix-agent:ubuntu-7.0.6
    container_name: zabbix-agent
    depends_on:
      - zabbix-server
    environment:
      ZBX_SERVER_HOST: zabbix-server  # kellel on luba küsida (passive)
      ZBX_HOSTNAME: docker-agent      # agent'i identifikaator
      TZ: Europe/Tallinn
    volumes:
      - ./zabbix/config:/etc/zabbix/zabbix_agentd.d:ro  # UserParameter'id osa 5
    restart: unless-stopped
```

`ZBX_HOSTNAME` **peab** ühtima sellega, mida kasutad UI-s host-i loomisel (osa 2). Agent saadab seda nime koos andmetega — kui ei vasta host-i nimele, Server viskab andmed ära.

`./zabbix/config` mount — siia tuleb `test.conf`, `applog.conf` jm osa 5 ja 6-s. Agent loeb neid automaatselt restart'i peale.

Testi:

```bash
docker compose up -d zabbix-agent
docker exec zabbix-server zabbix_get -s zabbix-agent -k agent.ping
```

Peab tagastama `1`. `zabbix_get` on debug-tööriist — küsib agent'ilt ühe mõõdiku, ei salvesta kuhugi. Kasutame seda läbi kogu labori enne kui vormistame item'i UI-s.

### 1.6 Kokkuvõte

```bash
docker compose ps
```

Neli teenust `Up`, MySQL `(healthy)`. Kõik portid hallatud: Server 10051, Web 8080. Oled valmis host'e lisama.

---

## Osa 2 · Esimene host, template, trigger

**Mõisted:** Host = objekt mida jälgid. Interface = ligipääsumoodus (Agent, SNMP, IPMI, JMX). Template = item'ite + trigger'ite pakk mida host'ile kinnitad. Item = üks mõõdik. [Zabbix docs / hosts](https://www.zabbix.com/documentation/7.0/en/manual/config/hosts).

### 2.1 docker-agent (localhost Docker võrgus)

*Data collection → Hosts → Create host*:

- Host name: `docker-agent`
- Host groups: `Linux servers`
- Interfaces → Add → Agent → DNS name `zabbix-agent`, Connect to **DNS**, port `10050`
- Templates → Select → `Linux by Zabbix agent`

Add. Oota 60s. *Hosts* lehel peab olema roheline ZBX.

Miks DNS mitte IP? Docker võrgu konteineri IP muutub restart'iga. DNS-nimi (= container name) jääb.

### 2.2 mon-target (päris server)

Loo teine host samamoodi, aga Interface on IP, mitte DNS:

- Host name: `mon-target`
- Interface → Agent → IP `192.168.35.140`, Connect to **IP**, port `10050`
- Templates → `Linux by Zabbix agent`

Kui availability jääb punaseks, testi:

```bash
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k agent.ping
```

Peab tagastama `1`.

### 2.3 Trigger Firing → OK

`Linux by Zabbix agent` template sisaldab juba CPU triggerit. SSH mon-target'ile:

```bash
ssh maria@192.168.35.140
sudo stress-ng --cpu 4 --timeout 180s &
```

*Monitoring → Problems* — 1-2 min pärast ilmub `High CPU utilization`. Peata koormus (`sudo pkill stress-ng`) → trigger läheb Resolved ise. Sama loogika kui Prometheus alert'idel — tingimus kehtib → käivitub, ei kehti enam → kaob.

---

## Osa 3 · User macros

Zabbix item-konfis kirjutad tihti asju mida ei tohiks seal olla: URL'id, tokenid, paroole. Lahendus on **user macro** — `{$NIMI}` süntaksiga viide, väärtus hoitud eraldi (host- või template-tasandil). Audit-log näitab ainult macro nime.

*Data collection → Hosts → `docker-agent` → Macros* tab → *Add*:

| Macro | Value | Type |
|-------|-------|------|
| `{$APP.ENV}` | `production` | Text |
| `{$APP.LOG.PATH}` | `/var/log/app/app.log` | Text |
| `{$APP.DB.PASSWORD}` | `secret_123` | **Secret text** |

Update.

**Secret text** tüüp peidab väärtuse UI-s ja audit-logis. Tavalist Text näeb iga operaator.

Miks host-level? Host'i näeb vähem inimesi kui globaalset konfi. Kui token leki, ühe host'i tasand on väiksem kahju kui kogu Zabbix.

Tööstuses kasutatakse ka [Vault macro](https://www.zabbix.com/documentation/7.0/en/manual/config/macros/secret_macros#vault-macros) — Zabbix loeb macro väärtust otse HashiCorp Vault'ist, siis pole isegi Zabbix DB-s.

Kasutame macro'sid päriselt osa 5-s UserParameter'i parameetrites.

---

## Osa 4 · HTTP Agent + Dependent items

### Mõisted

**HTTP Agent item** — Server teeb HTTP päringu otse URL'ile. Agent'i ei vaja. [Docs](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/http).

**Dependent item** — tuletatud item master'i tulemusest. Üks HTTP päring → N mõõdikut. [Docs](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/dependent_items).

**Preprocessing** — teisendus enne salvestamist: regex, JSONPath, Prometheus parser, jne. [Docs](https://www.zabbix.com/documentation/7.0/en/manual/config/items/preprocessing).

Päev 1 Prometheuses sama tulemus saavutati `nginx-prometheus-exporter` konteineriga. Zabbix teeb selle exporter'ita — HTTP Agent kutsub endpoint'i otse.

### 4.1 Host ilma agent'ita

Loo `nginx-web` host. Host group: loo uus `Applications`. **Interface'i ära lisa** — HTTP Agent kasutab URL'i otse.

### 4.2 Master item

Sama host'i *Items → Create*:

- Name: `Nginx status raw`
- Type: **HTTP agent**
- Key: `nginx.status.raw`
- URL: `http://192.168.35.141:8080/stub_status`
- Type of information: **Text**
- Update interval: `30s`

Add. Minut hiljem *Latest data* näitab:

```
Active connections: 1
server accepts handled requests
 47 47 89
Reading: 0 Writing: 1 Waiting: 0
```

See on [Nginx stub_status formaat](https://nginx.org/en/docs/http/ngx_http_stub_status_module.html) — viis numbrit ühel request'il.

### 4.3 Dependent item

*Items → Create*:

- Name: `Active connections`
- Type: **Dependent item**
- Master item: `nginx-web: Nginx status raw`
- Key: `nginx.connections.active`
- Type of information: **Numeric (unsigned)**
- Preprocessing → Add → Regular expression: pattern `Active connections: (\d+)`, output `\1`

Add. Tekita liiklust:

```bash
for i in {1..20}; do curl -s http://192.168.35.141:8080/ > /dev/null & done; wait
```

Graafikul peaks olema spike.

### 4.4 Lisa veel üks ise

Tee dependent item `Requests total` mis võtab middle number'i `47 47 89` reast (see on "handled"). Regex: `requests\s+\d+\s+(\d+)\s+\d+`.

Üks HTTP päring annab meile kolm mõõdikut. Viis päringut oleks sama info = viiekordne koormus Nginx'ile. Oluline kui jälgid asja mida ei tohi koormata.

---

## Osa 5 · UserParameter

UserParameter on shell-käsk mida agent käivitab, kui server küsib võtmega. See on Zabbix'i kõige võimsam feature — üks rida ja sul on uus mõõdik. [Docs](https://www.zabbix.com/documentation/7.0/en/manual/config/items/userparameters).

### 5.1 Kiire proov

Su VM-is Compose faili agent mount'ib `~/paev2/zabbix/config`.

```bash
echo 'UserParameter=minu.test, echo 42' > ~/paev2/zabbix/config/test.conf
docker restart zabbix-agent
sleep 5
docker exec zabbix-server zabbix_get -s zabbix-agent -k minu.test
```

Vastus: `42`.

`zabbix_get` küsib ühe väärtuse agent'i käest, ei salvesta kuhugi. See on debug-tööriist.

### 5.2 Parameetrid

```bash
cat > ~/paev2/zabbix/config/test.conf <<'EOF'
UserParameter=minu.topelt[*], echo $(($1 * 2))
EOF
docker restart zabbix-agent
sleep 5
```

```bash
docker exec zabbix-server zabbix_get -s zabbix-agent -k "minu.topelt[5]"
docker exec zabbix-server zabbix_get -s zabbix-agent -k "minu.topelt[100]"
```

`[*]` võtme lõpus → parameetrid lubatud. `$1`, `$2` viitavad neile.

### 5.3 Päris mõõdik

mon-target'il kirjutab log-generator `/var/log/app/app.log`:

```
2026-04-25T10:23:41 [ERROR] [payment] Payment failed
```

Kirjuta UserParameter mis loeb error'id teenuse järgi. SSH mon-target:

```bash
ssh maria@192.168.35.140
sudo tee /etc/zabbix/zabbix_agentd.d/applog.conf <<'EOF'
UserParameter=applog.errors[*], tail -n 1000 /var/log/app/app.log | grep -c "\[ERROR\] \[$1\]"
UserParameter=applog.count[*], tail -n 1000 /var/log/app/app.log | grep -c "\[$1\] \[$2\]"
EOF
sudo systemctl restart zabbix-agent
exit
```

Tagasi oma VM-is testi:

```bash
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k "applog.errors[payment]"
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k "applog.count[WARN,auth]"
```

Numbrid. Kui `ZBX_NOTSUPPORTED`, süntaksiviga — vaata `sudo cat /etc/zabbix/zabbix_agentd.d/applog.conf`.

### 5.4 Item + trigger UI-s

mon-target host → *Items → Create*:

- Name: `Payment errors (last 1000 lines)`
- Type: Zabbix agent
- Key: `applog.errors[payment]`
- Type of information: Numeric (unsigned)
- Update interval: `30s`

*Triggers → Create*:

- Name: `Too many payment errors on {HOST.NAME}`
- Severity: Warning
- Expression: `last(/mon-target/applog.errors[payment])>10`

### 5.5 Torm

```bash
ssh maria@192.168.35.140 \
  'for i in $(seq 1 100); do echo "$(date -Iseconds) [ERROR] [payment] Spam_$i" | sudo tee -a /var/log/app/app.log > /dev/null; done'
```

1 min → *Problems* → trigger Firing.

---

## Osa 6 · LLD + oma template

Osa 5 tegid `applog.errors[payment]` käsitsi. Aga teenuseid on 5 (payment, auth, api, database, cache), tasemeid 3 (INFO, WARN, ERROR) → 15 kombinatsiooni. Käsitsi pole mõistlik.

LLD = Zabbix küsib agent'ilt JSON-i, iga kirje = üks uus item. Kirjutad **ühe mustri**, Zabbix rakendab seda igale avastatud objektile. [Docs](https://www.zabbix.com/documentation/7.0/en/manual/discovery/low_level_discovery).

Panema selle oma **template'isse**, et saaks korduvkasutada.

### 6.1 Discovery skript

mon-target'ile:

```bash
ssh maria@192.168.35.140
sudo tee /usr/local/bin/applog-discovery.sh <<'EOF'
#!/bin/bash
tail -n 5000 /var/log/app/app.log 2>/dev/null \
  | grep -oE '\[(INFO|WARN|ERROR)\] \[[a-z]+\]' \
  | sort -u \
  | awk '
    BEGIN { printf "[" }
    NR > 1 { printf "," }
    {
      sev = $1; svc = $2
      gsub(/[\[\]]/, "", sev); gsub(/[\[\]]/, "", svc)
      printf "{\"{#SEVERITY}\":\"%s\",\"{#SERVICE}\":\"%s\"}", sev, svc
    }
    END { print "]" }
  '
EOF
sudo chmod +x /usr/local/bin/applog-discovery.sh

sudo tee -a /etc/zabbix/zabbix_agentd.d/applog.conf <<'EOF'
UserParameter=applog.discovery, /usr/local/bin/applog-discovery.sh
EOF
sudo systemctl restart zabbix-agent
exit
```

Testi:

```bash
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k applog.discovery
```

Valid JSON:

```json
[{"{#SEVERITY}":"ERROR","{#SERVICE}":"auth"},{"{#SEVERITY}":"ERROR","{#SERVICE}":"payment"},...]
```

`{#SEVERITY}` ja `{#SERVICE}` on LLD macros — Zabbix asendab need avastatud väärtustega iga item'i loomisel.

### 6.2 Oma template

*Data collection → Templates → Create template*:

- Template name: `App Log Monitoring`
- Template groups: loo uus `Templates/Applications`

Kliki loodud template'il:

**Discovery rules → Create discovery rule**:

- Name: `Log services discovery`
- Type: Zabbix agent
- Key: `applog.discovery`
- Update interval: `2m`

Avab discovery rule'i:

**Item prototypes → Create**:

- Name: `{#SEVERITY} count for {#SERVICE}`
- Type: Zabbix agent
- Key: `applog.count[{#SEVERITY},{#SERVICE}]`
- Type of information: Numeric (unsigned)
- Update interval: `30s`

**Trigger prototypes → Create**:

- Name: `Too many {#SEVERITY} in {#SERVICE} on {HOST.NAME} (>20)`
- Severity: Warning
- Expression: `last(/App Log Monitoring/applog.count[{#SEVERITY},{#SERVICE}])>20`

### 6.3 Filter — INFO välja

INFO'sid tekib pidevalt — trigger iga INFO peal = alert fatigue. Discovery rule → **Filters** tab:

| Macro | Regex | Match |
|-------|-------|-------|
| `{#SEVERITY}` | `ERROR\|WARN` | Matches |

### 6.4 Template host'ile

*Hosts → mon-target → Templates* tab → Select → `App Log Monitoring` → Update.

2-3 min → mon-target Items all on ~10 uut item'it (5 teenust × 2 severity taset).

### 6.5 Dünaamilisuse proov

Lisa uus teenus:

```bash
ssh maria@192.168.35.140 \
  'for i in $(seq 1 50); do echo "$(date -Iseconds) [ERROR] [shipping] Package_lost_$i" | sudo tee -a /var/log/app/app.log > /dev/null; done'
```

2-3 min pärast (discovery interval + processing) → `ERROR count for shipping` item ilmub ise. Trigger samuti.

20 serverile sama monitooringu lisamiseks: *Hosts → vali kõik → Mass update → Link templates*. Üks klikk.

---

## Osa 7 · Discord webhook

Trigger tuvastab, **Action** reageerib. [Docs](https://www.zabbix.com/documentation/7.0/en/manual/config/notifications/action). Komponente neli:

1. Media type — kuidas (Discord, email, script)
2. User media — kasutaja seaded (mis kanalisse, mis severity-st alates)
3. Action — millal käivitada
4. Webhook URL — kuhu saata

### 7.1 Discord webhook URL

Discord'is: Server Settings (hammasratas) → Integrations → Webhooks → **New Webhook** → kanal → **Copy Webhook URL**. Vorm:

```
https://discord.com/api/webhooks/1234567890/abcdefghij...
```

[Discord dokumentatsioon](https://support.discord.com/hc/en-us/articles/228383668-Intro-to-Webhooks).

### 7.2 Zabbix Media type

Zabbix 7-l on Discord juba sees. *Alerts → Media types* → `Discord` → kliki.

**Parameters** tab → `discord_endpoint` lahtrisse kleebi webhook URL. Update. Ülal **Enabled**.

### 7.3 User media

*Users → Users → Admin → Media* → Add:

- Type: Discord
- Send to: `#alerts` (kanali nimi — webhook suunab juba õigesse, see on ainult visuaalne)
- Severity: kõik linnutatud

Update.

### 7.4 Action

*Alerts → Actions → Trigger actions → Create action*:

**Action** tab:
- Name: `Send Discord notifications`
- Conditions → Add → Trigger severity → ≥ Warning

**Operations** tab:
- Add → Send to users: Admin → Send only to: Discord

**Recovery operations** tab:
- Add → sama (muidu recovery-sõnum ei tule)

Add.

### 7.5 Proov

```bash
ssh maria@192.168.35.140 \
  'for i in $(seq 1 100); do echo "$(date -Iseconds) [ERROR] [payment] Spam_$i" | sudo tee -a /var/log/app/app.log > /dev/null; done'
```

1-2 min → Discord kanalis sõnum. Peatus:

```bash
ssh maria@192.168.35.140 'sudo truncate -s 0 /var/log/app/app.log'
```

Recovery-sõnum 2-3 min pärast.

---

## Kontrolli enne lõpetamist

- [ ] `docker compose ps` — 4 konteinerit Up
- [ ] docker-agent ja mon-target host'id availability roheline
- [ ] User macros on docker-agent peal (Secret text tüüp töötab)
- [ ] nginx-web HTTP Agent item tagastab stub_status teksti, dependent item Active connections numbri
- [ ] `zabbix_get -k "applog.errors[payment]"` tagastab numbri
- [ ] Trigger Too many payment errors läks Firing ja lahenes
- [ ] Oma template App Log Monitoring olemas
- [ ] LLD lõi ≥ 10 item'it ise, uue teenuse lisandumisel tekkis veel
- [ ] Discord kanalis alert-sõnum

---

## Edasijõudnu — kui aega või kodus

### zabbix_sender (aktiivne mudel)

Siiani: server küsib agent'ilt (passive). Teine muster: **saadad ise** serverile.

```bash
ssh maria@192.168.35.140
echo "mon-target deployment.version 7.0.6" > /tmp/deploy.txt
zabbix_sender -z 192.168.35.120 -p 10051 -i /tmp/deploy.txt
```

UI-s loo item tüübiga **Zabbix trapper** (mitte Agent). See item lihtsalt ootab — kui zabbix_sender saadab, salvestab.

Päriselus: CI/CD pipeline saadab deployment'i fakti, batch-job saadab "valmis" sõnumi, skript välises süsteemis saadab oma andmeid. [zabbix_sender docs](https://www.zabbix.com/documentation/7.0/en/manpages/zabbix_sender).

### Trigger hysteresis

Trigger `last(...) > 10` läheb Firing > 10, OK ≤ 10. Kui väärtus kõikleb piiri ümber (9-10-11-9-12), saad 5 üleminekut 10 minutiga = alert spam.

Hysteresis:

- Problem expression: `last(/host/key) > 10`
- OK event generation mode: **Recovery expression**
- Recovery expression: `last(/host/key) < 5`

Firing > 10, OK ainult kui < 5. [Docs](https://www.zabbix.com/documentation/7.0/en/manual/config/triggers/expression#problem-severity-and-hysteresis).

### Kohandatud sõnum

Action → Operations → Message:

```
🔴 {TRIGGER.SEVERITY}: {TRIGGER.NAME}

Host: {HOST.NAME} ({HOST.IP})
Item: {ITEM.NAME}
Value: {ITEM.VALUE}

Time: {EVENT.DATE} {EVENT.TIME}
Event ID: {EVENT.ID}
```

Recovery:

```
✅ RESOLVED: {TRIGGER.NAME}
Host: {HOST.NAME}
Duration: {EVENT.DURATION}
```

Kõik macros: [docs](https://www.zabbix.com/documentation/7.0/en/manual/appendix/macros/supported_by_location).

### Zabbix API + Ansible

[Zabbix JSON-RPC API](https://www.zabbix.com/documentation/7.0/en/manual/api) võimaldab host'e, template'eid, trigger'id skriptiga hallata. [Community Ansible collection](https://galaxy.ansible.com/ui/repo/published/community/zabbix/).

---

## Veaotsing

| Probleem | Esimene kontroll |
|----------|------------------|
| zabbix-web restartub | `docker compose logs zabbix-web` — MySQL healthcheck'i oota |
| mon-target availability punane | `docker exec zabbix-server zabbix_get -s 192.168.35.140 -k agent.ping` |
| ZBX_NOTSUPPORTED UserParameter'iga | `ssh mon-target 'sudo cat /etc/zabbix/zabbix_agentd.d/applog.conf'` |
| applog.discovery annab `[]` | Log-generator pole kõiki kombinatsioone genereerinud, oota 2-3 min |
| LLD ei loo item'eid | `docker logs zabbix-server 2>&1 \| grep -i discovery`, oota 2× discovery interval |
| Trigger ei Firing | Latest data väärtus — kas tingimus tegelikult kehtib? |
| HTTP Agent 403 / timeout | `curl -v http://192.168.35.141:8080/stub_status` otse |
| Discord sõnum ei tule | *Reports → Audit log* — Action käivitus? Media type *Test* nupp |

---

## Allikad

- [Zabbix 7.0 manuaal](https://www.zabbix.com/documentation/7.0/en/manual)
- [UserParameters](https://www.zabbix.com/documentation/7.0/en/manual/config/items/userparameters)
- [Low-Level Discovery](https://www.zabbix.com/documentation/7.0/en/manual/discovery/low_level_discovery)
- [HTTP Agent](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/http)
- [Discord integration](https://www.zabbix.com/integrations/discord)
- [Community templates](https://github.com/zabbix/community-templates)

Versioonid: Zabbix 7.0.6 LTS, MySQL 8.0, Docker Compose v2.
