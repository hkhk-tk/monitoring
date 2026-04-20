# Päev 2 osa 1: Zabbix — Labor

**Kestus:** 4 tundi
**Tase:** Keskaste
**VM:** sinu isiklik VM (nt `ssh kaarel@192.168.35.121`)

---

## 🎯 Õpiväljundid

Pärast selle labi läbimist õpilane:

**Teadmised:**

1. Selgitab Zabbixi arhitektuuri — MySQL, Server, Web, Agent — ja iga komponendi rolli
2. Eristab Zabbixi pull-mudelit Prometheuse pull-mudelist (agent passive vs exporter)
3. Kirjeldab Item → Trigger → Action voogu
4. Eristab sisseehitatud template'i ja kohandatud monitooringu (UserParameter, LLD) rolli

**Oskused:**

5. Ehitab Zabbix stacki Docker Compose-iga ja lisab esimese monitooritava hosti
6. Loob trigger'i mõõdikule ja näeb seda läbi Pending → Firing → Resolved tsükli
7. **Kirjutab oma custom monitooringumõõdiku** UserParameter'ina ja testib `zabbix_get`-iga
8. **Loob Low-Level Discovery reegli** mis avastab ise mitu monitooritavat objekti ühest allikast
9. Seadistab Action'i, mis saadab trigger'i käivitumisel teavituse

---

## Meie keskkond

> **Loengust:** Zabbix pull-mudel küsib agentidelt andmeid, aga suudab ka passiivselt võtta vastu (Trapper). Täna teeme klassikalise pull-variandi — server küsib, agent vastab.

Sinu infrastruktuur on sama mis päev 1. Kolm masinat on üleval, sinu VM saab Zabbix stacki.

| Masin | IP | Mis seal jookseb |
|-------|-----|------------------|
| **Sinu VM** | 192.168.35.12X | Docker — Zabbix stack (sina ehitad täna) |
| **mon-target** | 192.168.35.140 | node_exporter :9100, zabbix-agent :10050, logi-generaator |
| **mon-target-web** | 192.168.35.141 | Nginx :80, stub_status :8080, zabbix-agent :10050 |

**Kirjuta oma VM IP siia:** `__________________`

---

## Eeltöö — puhasta eelmine stack

Päev 1 Prometheus stack koormab RAM-i. Peata see enne kui Zabbix üles lükkad:

```bash
cd ~/paev1
docker compose down -v
cd ~
```

⚡ **Kiirkontroll:**
```bash
docker ps
```
Peab olema tühi (või ainult süsteemi konteinerid).

---

## Osa 1: Stack üles (30 min)

> **Loengust:** Zabbix ei ole üks binary — ta on neljast tükist kokku pandud süsteem. Andmebaas hoiab konfi ja ajalugu, server töötleb, web on liides, agent mõõdab. Ilma ühetagi ei tööta.

### 1.1 Töökaust ja failid

```bash
mkdir -p ~/paev2/zabbix/config
cd ~/paev2
```

### 1.2 docker-compose.yml

Loome terve stacki ühe kompositsiooni faili sisse. Sisaldab nelja tavapärast Zabbixi komponenti **pluss** kaks tööriista mida hiljem vajame — `log-generator` (tekitab logisid `/var/log/app/app.log`-i) ja mount'id mis lubavad meil pärast oma skripte agendile üles laadida.

```bash
cat > docker-compose.yml << 'EOF'
services:
  mysql:
    image: mysql:8.0
    container_name: mysql
    environment:
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pwd
      MYSQL_ROOT_PASSWORD: root_pwd
      TZ: Europe/Tallinn
    command:
      - mysqld
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_bin
    volumes:
      - mysql-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-uroot", "-proot_pwd"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s
    restart: unless-stopped

  zabbix-server:
    image: zabbix/zabbix-server-mysql:ubuntu-7.0.6
    container_name: zabbix-server
    depends_on:
      mysql:
        condition: service_healthy
    environment:
      DB_SERVER_HOST: mysql
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pwd
      TZ: Europe/Tallinn
    ports:
      - "10051:10051"
    restart: unless-stopped

  zabbix-web:
    image: zabbix/zabbix-web-nginx-mysql:ubuntu-7.0.6
    container_name: zabbix-web
    depends_on:
      mysql:
        condition: service_healthy
      zabbix-server:
        condition: service_started
    environment:
      ZBX_SERVER_HOST: zabbix-server
      DB_SERVER_HOST: mysql
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pwd
      PHP_TZ: Europe/Tallinn
      TZ: Europe/Tallinn
    ports:
      - "8080:8080"
    restart: unless-stopped

  zabbix-agent:
    image: zabbix/zabbix-agent:ubuntu-7.0.6
    container_name: zabbix-agent
    depends_on:
      - zabbix-server
    environment:
      ZBX_SERVER_HOST: zabbix-server
      ZBX_HOSTNAME: docker-agent
      TZ: Europe/Tallinn
    volumes:
      - ./zabbix/config/applog.conf:/etc/zabbix/zabbix_agentd.d/applog.conf:ro
      - ./zabbix/config/discover-services.sh:/usr/local/bin/discover-services.sh:ro
      - app-logs:/var/log/app:ro
    restart: unless-stopped

  log-generator:
    image: busybox:latest
    container_name: log-generator
    command:
      - sh
      - -c
      - |
        mkdir -p /var/log/app
        SERVICES="payment auth api database cache"
        LEVELS="INFO INFO INFO INFO INFO WARN ERROR"
        MSGS="Request_OK User_login Cache_miss DB_slow_query Payment_failed Connection_retry"
        while true; do
          S=$$(echo $$SERVICES | tr " " "\n" | shuf -n1)
          L=$$(echo $$LEVELS | tr " " "\n" | shuf -n1)
          M=$$(echo $$MSGS | tr " " "\n" | shuf -n1)
          echo "$$(date -Iseconds) [$$L] [$$S] $$M" >> /var/log/app/app.log
          sleep 2
        done
    volumes:
      - app-logs:/var/log/app
    restart: unless-stopped

volumes:
  mysql-data:
  app-logs:
EOF
```

### 1.3 Loome tühjad failid mida agent vajab

Agent ootab neid kahte faili — praegu on tühjad, osad 6-8 jooksul täidame:

```bash
touch zabbix/config/applog.conf
cat > zabbix/config/discover-services.sh << 'EOF'
#!/bin/sh
echo "[]"
EOF
chmod +x zabbix/config/discover-services.sh
```

### 1.4 Käivita

```bash
docker compose up -d
```

⏱️ **Oota ~60 sek** — Zabbix server loob esimesel käivitumisel ~140 tabelit andmebaasi.

```bash
docker compose ps
```

Kõik viis konteinerit peavad olema `Up`. MySQL peab olema `Up (healthy)`.

💡 **Miks healthcheck?** Ilma selleta läheb zabbix-server käima enne kui MySQL on valmis, ja kukub kokku. `depends_on: service_healthy` ootab healthcheck'i rohelist tulemust.

### 1.5 Login

Ava brauseris: `http://192.168.35.12X:8080`

| Väli | Väärtus |
|------|---------|
| Username | `Admin` |
| Password | `zabbix` |

**Vaheta parool kohe:**

1. Ülemine parem nurk → kasutaja ikoon → *Users* → *Admin*
2. *Password* → *Change password*
3. Uus parool: `Monitor2026!` (sama mis VM parool, et meelde jääks)
4. *Update*

⚡ **Kiirkontroll:** Sa näed Dashboard'i. Kusagil keskel on viide "Zabbix server" hostile — see on Zabbix server ise, monitoorib iseennast. Seda ei puuduta.

---

## Osa 2: Esimene host + template (25 min)

> **Loengust:** Host on Zabbixis loogiline mõõtmisobjekt. Item on üks mõõdik hostilt. Template on item'ite, trigger'ite ja graafikute pakett mis saab host'ile külge panna ühe klikiga.

Meil on kaks agenti üleval — `zabbix-agent` container sinu stacki sees ja `mon-target` 192.168.35.140 peal. Alustame sisemisest (container).

### 2.1 Loo host

1. Vasakus menüüs: *Data collection* → *Hosts*
2. Paremal üleval: *Create host*
3. Täida:

| Väli | Väärtus |
|------|---------|
| Host name | `docker-agent` |
| Visible name | (jäta tühjaks) |
| Host groups | Otsi ja vali `Linux servers` |
| Interfaces → Add → Agent | |
| ↳ DNS name | `zabbix-agent` |
| ↳ Connect to | **DNS** (mitte IP!) |
| ↳ Port | `10050` |

💡 **Miks DNS, mitte IP?** Docker network'is pole IP stabiilne — container restart → uus IP. DNS nimi `zabbix-agent` jääb samaks alati.

### 2.2 Lisa template

Sama host'i lehel, **Templates** tab:

1. *Select* nupp
2. Otsi: `Linux by Zabbix agent`
3. *Select*
4. All alumine **Add** nupp

### 2.3 Vaata et ühendus töötab

*Data collection* → *Hosts*

Sinu uus `docker-agent` host. **Availability** veerus peaks olema roheline **ZBX**.

⏱️ **Oota ~60 sek** esimese kontrolli jaoks.

💡 **Kui ZBX on punane:** Agent ei vasta. Kiirkontroll: `docker logs zabbix-agent | tail -20`. Kõige sagedasem põhjus — `ZBX_SERVER_HOST` vale (peab olema `zabbix-server`, mitte localhost).

### 2.4 Vaata päriselu mõõdikuid

*Monitoring* → *Latest data*

Filter:
- Hosts: `docker-agent`
- *Apply*

Näed ~200 mõõdikut — CPU, RAM, disk, network, protsessid. Kõik, mida `Linux by Zabbix agent` template on valmis seadistanud.

Kliki mõne mõõdiku juures **Graph** ikoonile → näed graafikut.

⚡ **Kiirkontroll — vasta:**

- Mitu CPU tuuma sinu VM-il on? (Filter: `CPU` → `System: Number of CPUs`)
- Mis on vaba mälu MB-des? (`Available memory in %` või `Available memory`)

---

## Osa 3: Esimene trigger (25 min)

> **Loengust:** Trigger on tingimus mis kaitseb sind. Item kogub andmeid, trigger ütleb millal on midagi valesti.

### 3.1 Vaata template triggereid

Template `Linux by Zabbix agent` tuli juba ~30 trigger'iga. Vaata neid:

*Data collection* → *Hosts* → `docker-agent` real kliki **Triggers** lingile (number nt "30").

Paneb tähele — iga trigger on seotud item'iga.

### 3.2 Tekita CPU koormus

Ava eraldi terminal, SSH oma VM-i:

```bash
docker exec zabbix-agent sh -c 'dd if=/dev/zero of=/dev/null & dd if=/dev/zero of=/dev/null & dd if=/dev/zero of=/dev/null & dd if=/dev/zero of=/dev/null &'
```

See käivitab 4 paralleelset `dd` protsessi mis söövad CPU-d 100%.

### 3.3 Vaata kuidas trigger käivitub

*Monitoring* → *Problems*

⏱️ **Oota 1-2 min.** Peab ilmuma punane rida:

> **High CPU utilization** on docker-agent

Trigger läbib kolm olekut:
1. 🟢 **OK** — kõik hästi (enne stress-testi)
2. 🟡 **Pending** — tingimus kehtib, aga `for:` aeg pole möödas (ei ilmu UI-sse)
3. 🔴 **Firing** — alert käivitunud → Problems UI-s

### 3.4 Peata koormus

```bash
docker exec zabbix-agent pkill dd
```

⏱️ **Oota 1-2 min.** Problem kaob automaatselt — Zabbix tuvastas et tingimus enam ei kehti.

💡 **Võrdlus päev 1 Prometheus'iga:** Prometheus'is oli alert rule YAML-failis, Zabbixis on trigger UI-s (või template'ist). Idee sama — mõlemas on `for:` aeg enne kui alert on päriselt "elus".

---

## Osa 4: mon-target üle võrgu (25 min)

Nüüd lisame teise hosti mis pole meie stacki sees, vaid eraldi serveris. `mon-target` peal jookseb Zabbix agent juba — vaata.

### 4.1 Kontrolli et agent vastab

```bash
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k agent.ping
```

**Oodatud vastus:** `1`

Kui saad `1` — agent vastab ja server näeb teda. Kui saad vea → küsi koolitajalt.

### 4.2 Lisa host

*Data collection* → *Hosts* → *Create host*

| Väli | Väärtus |
|------|---------|
| Host name | `mon-target` |
| Host groups | `Linux servers` |
| Interfaces → Add → Agent | |
| ↳ IP address | `192.168.35.140` |
| ↳ Connect to | **IP** |
| ↳ Port | `10050` |

**Templates** tab:
- *Select* → `Linux by Zabbix agent` → *Add*

### 4.3 Kontrolli ja vaata

*Data collection* → *Hosts* — mon-target availability peaks ~60 sek jooksul minema roheliseks.

*Monitoring* → *Latest data* → filter: `mon-target` — näed kõiki 200 mõõdikut.

⚡ **Kiirkontroll — võrdle kahte hosti:**

Ava *Latest data*, filtreeri mõlemat hosti korraga (jäta Hosts tühjaks, vali 2 hosti). Vaata `System: System uptime`.

- Kumb süsteem on kauem üleval — sinu VM (kui ta on) või mon-target?
- Miks? (Viga päev 1 reboot, või mon-target ise reboot)

---

## Osa 5: UserParameter — kirjuta oma mõõdik (60 min)

> **Loengust:** Template'id katavad 80% igapäevast vajadust. Aga iga ettevõte kirjutab varem või hiljem **oma mõõdikuid**. Zabbixis on see UserParameter — agenti sisse kleebitud käsk, mille server saab käivitada.

Meil on `log-generator` container mis kirjutab ridu failis `/var/log/app/app.log`, formaadis:

```
2026-04-25T10:23:41+03:00 [ERROR] [payment] Payment_failed
```

Tahame teada: **mitu ERROR-rida on viimase 1000 rea seas iga teenuse kohta?**

### 5.1 Vaata logi

```bash
docker exec zabbix-agent tail -n 5 /var/log/app/app.log
```

Peaks nägema 5 rida ajatempliga, tasemega, teenusega ja sõnumiga.

### 5.2 Kirjuta UserParameter

Avame faili mis on juba Docker'i sisse mount'itud — kirjutame sinna UserParameter'i defineerinud rea:

```bash
cat > zabbix/config/applog.conf << 'EOF'
# Loendab viimase 1000 rea seas ERROR ridu antud teenuse kohta
UserParameter=applog.errors[*], tail -n 1000 /var/log/app/app.log | grep -c "\[ERROR\] \[$1\]"

# Loendab viimase 1000 rea seas ridu antud taseme ja teenuse kohta
UserParameter=applog.count[*], tail -n 1000 /var/log/app/app.log | grep -c "\[$1\] \[$2\]"

# Kasutatakse LLD jaoks osa 6-s
UserParameter=applog.discovery, /usr/local/bin/discover-services.sh
EOF
```

### 5.3 Restart agent

UserParameter luetakse ainult käivitumisel sisse — kui muudad faili, agent peab uuesti käivituma.

```bash
docker restart zabbix-agent
```

⏱️ **Oota 10 sek.**

### 5.4 Testi `zabbix_get`-iga

`zabbix_get` on tööriist millega server küsib agendilt **ühte** mõõdikut otse, ilma et midagi salvestuks. Ideaalne debug'iks.

```bash
docker exec zabbix-server zabbix_get -s zabbix-agent -k "applog.errors[payment]"
```

Peaksid saama numbri — nt `15` või midagi taolist.

Proovi veel:

```bash
docker exec zabbix-server zabbix_get -s zabbix-agent -k "applog.count[WARN,auth]"
docker exec zabbix-server zabbix_get -s zabbix-agent -k "applog.errors[database]"
```

💡 **Kui saad `ZBX_NOTSUPPORTED`:** UserParameter faili sisse sattus trükiviga, või `grep` süntaks läks valeks. Kontrolli: `docker exec zabbix-agent cat /etc/zabbix/zabbix_agentd.d/applog.conf`.

### 5.5 Loo item Zabbixis

*Data collection* → *Hosts* → `docker-agent` → *Items* → *Create item*

| Väli | Väärtus |
|------|---------|
| Name | `Payment errors (last 1000 lines)` |
| Type | `Zabbix agent` |
| Key | `applog.errors[payment]` |
| Type of information | `Numeric (unsigned)` |
| Update interval | `30s` |

*Add*.

⏱️ **Oota 2 min.**

*Monitoring* → *Latest data* → filtreeri `docker-agent` + `Payment` → näed numbri.

### 5.6 Loo trigger

Sama host'i *Triggers* tab → *Create trigger*

| Väli | Väärtus |
|------|---------|
| Name | `Too many payment errors` |
| Severity | `Warning` |
| Expression | `last(/docker-agent/applog.errors[payment])>10` |

*Add*.

### 5.7 Stress-test — tekita error-torm

Sunnime `log-generator`-i iga rea ERROR tasemega kirjutama:

```bash
docker exec log-generator sh -c '
for i in $(seq 1 100); do
  echo "$(date -Iseconds) [ERROR] [payment] Payment_failed_spam_$i" >> /var/log/app/app.log
done'
```

⏱️ **Oota 30-60 sek** järgmise kontrolli jaoks.

*Monitoring* → *Problems* — peab ilmuma:

> **Too many payment errors** on docker-agent

🎉 **Sa kirjutasid oma esimese custom mõõdiku.** Tavaline template ei teadnud midagi sinu rakenduse logidest. Sina defineerisid mida mõõta, kuidas mõõta ja millal alarm.

---

## Osa 6: Low-Level Discovery — autodiscovery (60 min)

> **Loengust:** Käsitsi 5 item'i loomine on OK. 50-ga juba mitte. LLD lubab Zabbixil **ise avastada mida monitoorida**: loeb skriptilt JSON-i, loob item'id ja trigger'id prototüüpide järgi.

Osa 5-s tegime `applog.errors[payment]`. Aga teenuseid on 5 (payment, auth, api, database, cache) ja tasemeid 3 (INFO, WARN, ERROR). See on 15 kombinatsiooni. Ja homme võib tulla juurde kuues teenus.

**LLD lahendab selle:** kirjutad ühe reegli, saad 15 item'i automaatselt.

### 6.1 Kirjuta discovery skript

Skript mille agent käivitab. Tagastab JSON massiivi millest Zabbix saab macro'd `{#SEVERITY}` ja `{#SERVICE}`.

```bash
cat > zabbix/config/discover-services.sh << 'EOF'
#!/bin/sh
# Avastab [SEVERITY] [SERVICE] kombinatsioonid viimase 5000 rea seast

LOG=/var/log/app/app.log

tail -n 5000 "$LOG" 2>/dev/null \
  | grep -oE '\[(INFO|WARN|ERROR)\] \[[a-z]+\]' \
  | sort -u \
  | awk '
    BEGIN { printf "[" }
    NR > 1 { printf "," }
    {
      sev = $1; svc = $2
      gsub(/[\[\]]/, "", sev)
      gsub(/[\[\]]/, "", svc)
      printf "{\"{#SEVERITY}\":\"%s\",\"{#SERVICE}\":\"%s\"}", sev, svc
    }
    END { print "]" }
  '
EOF
chmod +x zabbix/config/discover-services.sh
```

### 6.2 Restart agent ja testi

```bash
docker restart zabbix-agent
sleep 10
docker exec zabbix-server zabbix_get -s zabbix-agent -k applog.discovery
```

**Oodatud vastus:** JSON, mis näeb välja umbes nii:

```json
[{"{#SEVERITY}":"ERROR","{#SERVICE}":"auth"},{"{#SEVERITY}":"ERROR","{#SERVICE}":"payment"},{"{#SEVERITY}":"INFO","{#SERVICE}":"api"},...]
```

15 objekti ümber, sõltuvalt sellest palju log on kasvanud.

💡 **Selles on LLD võlu:** Zabbix näeb selle JSON-i ja saab aru "aa, meil on 15 asja, teeme 15 item'i".

### 6.3 Loo Discovery Rule

*Data collection* → *Hosts* → `docker-agent` → *Discovery rules* → *Create discovery rule*

| Väli | Väärtus |
|------|---------|
| Name | `Log services discovery` |
| Type | `Zabbix agent` |
| Key | `applog.discovery` |
| Update interval | `2m` |

*Add*.

### 6.4 Loo Item Prototype

Sama reegli sees, *Item prototypes* tab → *Create item prototype*

| Väli | Väärtus |
|------|---------|
| Name | `{#SEVERITY} count for {#SERVICE}` |
| Type | `Zabbix agent` |
| Key | `applog.count[{#SEVERITY},{#SERVICE}]` |
| Type of information | `Numeric (unsigned)` |
| Update interval | `30s` |

*Add*.

💡 **Mis just juhtus:** sa andsid Zabbixile **malli**. Iga avastatud `{#SEVERITY}`+`{#SERVICE}` paari kohta loob Zabbix ise item'i. 15 paari → 15 item'i.

### 6.5 Loo Trigger Prototype

Sama reegli sees, *Trigger prototypes* tab → *Create trigger prototype*

| Väli | Väärtus |
|------|---------|
| Name | `Too many {#SEVERITY} in {#SERVICE} (>20)` |
| Severity | `Warning` |
| Expression | `last(/docker-agent/applog.count[{#SEVERITY},{#SERVICE}])>20` |

*Add*.

### 6.6 Oota ja vaata võlu

⏱️ **Oota 2-3 min.**

*Data collection* → *Hosts* → `docker-agent` → *Items* → scrolli lõppu.

Peaksid nägema umbes 15 uut item'i automaatselt loodud:

- `ERROR count for payment`
- `ERROR count for auth`
- `WARN count for payment`
- `INFO count for api`
- ...

*Monitoring* → *Latest data* → filter `docker-agent` → scroll. Iga teenus-tase paari kohta on andmed.

### 6.7 Testi — lisa uus teenus

Nüüd tõestame et LLD on dünaamiline. Lisa logisse uus teenus, mida varem ei olnud:

```bash
docker exec log-generator sh -c '
for i in $(seq 1 50); do
  echo "$(date -Iseconds) [ERROR] [shipping] Package_lost_$i" >> /var/log/app/app.log
done'
```

⏱️ **Oota 2-3 min** (discovery interval + processing delay).

*Items* listis peaks ilmuma:

- `ERROR count for shipping`

Zabbix avastas ise. Sa ei teinud midagi.

🎉 **See on LLD:** ühe reegliga katsid tänase ja homse kasvu. Päris elus — kui täna on 5 mikroteenust ja järgmisel aastal 50, sinu monitooring ei vaja ühtegi muudatust.

---

## Osa 7: Action + teavitus (30 min)

> **Loengust:** Trigger tuvastab, Action reageerib. Ilma Action'ita istub probleem UI-s — keegi peab ekraani vaatama. Action saadab e-kirja, Slack-sõnumi, loeb piletisüsteemis, käivitab skripti.

Teeme Slack webhook teavituse.

### 7.1 Slack webhook URL

**Koolitaja annab:** klassi jaoks on loodud Slack workspace ja kanal `#alerts-<sinu-nimi>`. Webhook URL on kujul:

```
https://hooks.slack.com/services/XXX/YYY/ZZZ
```

Kirjuta oma URL siia: `__________________`

(Kui Slack pole saadaval, koolitaja annab emaili SMTP seadistuse juhised. Samm-sammult loogika sama.)

### 7.2 Seadista Media Type

*Alerts* → *Media types* → otsi `Slack`.

Zabbix 7.0-l on Slack media type sisseehitatud. Kliki nimel → *Parameters*:

| Parameter | Value |
|-----------|-------|
| `bot_token` | (jäta, me kasutame webhook'i) |
| `slack_mode` | `alarm` |
| `channel` | `#alerts-<sinu-nimi>` |

**Võimalik alternatiiv (lihtsam):** loo uus media type tüübiga *Webhook*, script lükkab JSON-payload'i webhook URL-ile. Vt `zabbix/config/slack-webhook.js` (kui koolitaja on selle ettevalmis pannud).

*Update*. Ülemisel ribal vali **Enabled**.

### 7.3 Lisa teavitus oma kasutajale

*Users* → *Users* → `Admin` → *Media* tab → *Add*

| Väli | Väärtus |
|------|---------|
| Type | `Slack` |
| Send to | `#alerts-<sinu-nimi>` |
| When active | `1-7,00:00-24:00` |
| Use if severity | märgi kõik |

*Add* → *Update*.

### 7.4 Loo Action

*Alerts* → *Actions* → *Trigger actions* → *Create action*

**Action** tab:
- Name: `Send Slack on any trigger`
- Conditions: (tühjaks — rakendub kõikidele trigger'itele) VÕI lisa `Severity >= Warning` kui tahad ainult kõrge severity

**Operations** tab:
- Operations → *Add*
- Send to users: `Admin`
- Send only to: `Slack`
- *Add*

**Recovery operations** tab:
- *Add* sama konfiguratsiooniga — see saadab ka resolved teate

*Add* (all all).

### 7.5 Testi

Tekita error-torm nagu osa 5-s:

```bash
docker exec log-generator sh -c '
for i in $(seq 1 100); do
  echo "$(date -Iseconds) [ERROR] [payment] Spam_$i" >> /var/log/app/app.log
done'
```

⏱️ **Oota 1-2 min.**

Slack kanalis peaks ilmuma sõnum. Täpne formaat sõltub media type template'ist.

🎉 **Pipeline on nüüd täis:** `log-generator` kirjutab → UserParameter loeb → item salvestab → trigger tuvastab → action saadab → inimene saab teada. See on **päris monitoring**.

---

## ✅ Lõpukontroll

Enne lõpetamist veendu:

- [ ] `docker compose ps` — 5 konteinerit Up
- [ ] Zabbix UI töötab `http://192.168.35.12X:8080`, parool vahetatud
- [ ] `docker-agent` host roheline, Latest data täis
- [ ] `mon-target` host roheline, Latest data täis
- [ ] `applog.errors[payment]` item olemas, graafikul andmed
- [ ] Custom trigger `Too many payment errors` on nähtud Firing olekus
- [ ] Discovery rule lõi vähemalt 10 item'i automaatselt
- [ ] Slack sõnum jõudis kohale (või email)

---

## 🚀 Lisaülesanded

### HTTP Agent — monitoori ilma agendita

`mon-target-web` peal on Nginx stub_status `:8080`. Loome Zabbixis item mis küsib HTTP-ga ilma agendita.

1. *Create host* `nginx-web`, **ei lisa** interface'i (HTTP Agent ei vaja)
2. *Items* → *Create item*:
   - Type: `HTTP agent`
   - Key: `nginx.stub_status`
   - URL: `http://192.168.35.141:8080/stub_status`
   - Type of info: `Text`
3. *Preprocessing* tab → *Add*:
   - Type: `Regular expression`
   - Parameters: `Active connections: (\d+)` / `\1`
4. Change item type of info to `Numeric (unsigned)`
5. Oota → näed active connections numbrit

### Multi-severity trigger

Muuda osa 6 trigger prototype'i nii, et severity sõltub `{#SEVERITY}`-st:

- Kui avastati `ERROR` → trigger severity `High`
- Kui `WARN` → `Warning`
- Kui `INFO` → ära loo trigger'it

Vihje: LLD filter + mitu trigger prototype'i.

### Grafana datasource

Installi Grafana-Zabbix plugin oma päev 1 Grafanasse. Ühine dashboard, mis näitab Prometheuse ja Zabbixi andmeid korraga.

```bash
# Vaata päev 1 Grafana
docker exec -it <päev1-grafana> grafana-cli plugins install alexanderzobnin-zabbix-app
```

---

## Veaotsing

| Probleem | Lahendus |
|----------|----------|
| Zabbix web ei lae | Oota MySQL healthcheck valmis — `docker compose logs mysql` |
| Host ZBX punane | `docker logs zabbix-agent`, kontrolli `ZBX_SERVER_HOST` |
| `zabbix_get` timeout | Port 10050 kinni, või agent alla (`docker ps`) |
| `ZBX_NOTSUPPORTED` | UserParameter'is süntaksi viga, vaata `docker exec zabbix-agent cat /etc/zabbix/zabbix_agentd.d/applog.conf` |
| Discovery ei loo item'eid | Oota 2x discovery interval. `grep -i "discover" /var/log/zabbix/zabbix_server.log` pole meil, vaata `docker logs zabbix-server` |
| Trigger ei käivitu | Oota `for:` aeg. Kontrolli expression Latest data väärtuse vastu. |
| Slack ei saabu | *Reports* → *Audit log* → kas Action käivitus? Media type → *Test* |
| Log fail tühi | `docker ps` — kas log-generator jookseb? `docker logs log-generator` |
| Stack jookseb aeglaselt | RAM (`free -h`) — kui < 500MB vaba, peata päev 1 Grafana |

---

## 📚 Allikad

| Allikas | URL |
|---------|-----|
| Zabbix 7.0 dokumentatsioon | https://www.zabbix.com/documentation/7.0/en/ |
| UserParameter juhend | https://www.zabbix.com/documentation/7.0/en/manual/config/items/userparameters |
| Low-Level Discovery | https://www.zabbix.com/documentation/7.0/en/manual/discovery/low_level_discovery |
| Zabbix Docker images | https://hub.docker.com/u/zabbix |
| Zabbix 7.0 → Grafana plugin | https://grafana.com/grafana/plugins/alexanderzobnin-zabbix-app/ |
| `zabbix_get` juhend | https://www.zabbix.com/documentation/7.0/en/manpages/zabbix_get |
| Custom LLD näited | https://sbcode.net/zabbix/custom-lld/ |

**Versioonid (testitud, aprill 2026):**

- Zabbix: `7.0.6` (LTS)
- MySQL: `8.0`
- Docker Compose: v2.x
