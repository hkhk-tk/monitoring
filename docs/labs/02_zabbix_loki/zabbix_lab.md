# Päev 2 · Labor: Zabbix

**Kestus:** ~2 tundi (pool päev 2 laborist)  
**Tase:** Keskaste  
**VM:** VM (nt `ssh <eesnimi>@192.168.35.12X`)  
**Eeldused:** [Päev 2: Zabbix loeng](../../materials/lectures/paev2-loeng.md) loetud. Päev 1 Docker Compose ja Grafana tuttav.

Labori teine pool — LogQL, Loki stack ja FINAAL — jätkub [Labor: Loki](loki_lab.md) lehel.

---

## 🎯 Õpiväljundid

**Teadmised:**

1. Eristab Zabbixi push-mudelit Prometheuse pull-mudelist ja põhjendab millal kumbagi kasutada
2. Kirjeldab Zabbixi andmemudelit: host → template → item → trigger → action

**Oskused:**

3. Ehitab Zabbix stack'i Docker Compose'iga teenus-teenuse haaval
4. Seadistab host'i, template'i ja jälgib trigger fire/resolve tsüklit
5. Loob HTTP Agent + Dependent item struktuuri ilma välise exporter'ita
6. Kirjutab UserParameter'i, discovery skripti ja honeypot-triggeri

---

## Eeltöö

Päev 1 stack maha (volumes jäävad alles juhuks kui tahad naasta):

```bash
cd ~/paev1 && docker compose down && cd ~
```

mon-target ja mon-target-web peale on `zabbix-agent` juba paigaldatud. Kontrolli:

```bash
nc -zv 192.168.35.140 10050 && nc -zv 192.168.35.141 10050
```

Mõlemad `succeeded`. Kui ei ole, ütle koolitajale.

---

Zabbix on neli komponenti: **MySQL** hoiab konfi ja ajalugu, **Server** töötleb ja arvutab trigger'id, **Web** on UI, **Agent** kogub mõõdikuid. Erinevalt Prometheusest (üks binaar) on Zabbix modulaarne — iga komponent eraldi konteineris.

Ehitame neid ükshaaval ja testime iga sammu eraldi.

---

## Osa 1 · Zabbix baas

```bash
mkdir -p ~/paev2/zabbix/config && cd ~/paev2/zabbix
```

### 1.1 Baas

Loo `docker-compose.yml`:

```yaml
services:
  # teenused lisanduvad siia

volumes:
  mysql-data:
```

`mysql-data` volume kohe alguses — ilma selleta kaotaks `docker compose down` kogu Zabbix konfi.

### 1.2 MySQL

Lisa `services:` alla:

```yaml
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
```

Testi ainult MySQL:

```bash
docker compose up -d mysql
docker compose ps
```

Oota kuni `Up (healthy)` — esmakäivitusel ~60s. Kontroll:

```bash
docker exec mysql mysql -uzabbix -pzabbix_pwd -e 'SHOW DATABASES;'
```

Pead nägema rida `zabbix`.

💡 **Kui `unhealthy`:** `docker compose logs mysql` — tavaline põhjus on RAM. `free -h` näitab.

### 1.3 Zabbix Server

Lisa `services:` alla MySQL-i järele:

```yaml
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
```

`DB_SERVER_HOST: mysql` — DNS-nimi, mitte IP. Docker bridge-võrgus konteinerid viitavad teineteisele nime kaudu.

```bash
docker compose up -d zabbix-server
docker compose logs -f zabbix-server
```

Oota rida `Zabbix Server started. Zabbix 7.0.6`. Ctrl+C.

```bash
docker exec mysql mysql -uzabbix -pzabbix_pwd zabbix -e 'SHOW TABLES;' | wc -l
```

~170 tabelit — Server lõi need ise.

---

## Osa 2 · Web + Agent

Baas töötab (MySQL + Server). Nüüd vajame kahte asja, et inimene saaks süsteemi kasutada — **Web UI** ja vähemalt ühe **Agent'i**, kes andmeid kogub.

### 2.1 Zabbix Web

Server oskab andmeid vastu võtta ja trigger'eid arvutada, aga tal pole oma veebiliidest. See on teadlik disain — frontend on eraldi konteiner (PHP + Nginx), mis räägib **otse andmebaasiga** (mitte serveriga). See võimaldab frontend'i skaleerida sõltumatult serverist.

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
```

```bash
docker compose up -d zabbix-web
```

Brauseris `http://192.168.35.12X:8080`. Login: `Admin` / `zabbix`. Vaheta kohe parool: üleval paremas nurgas ikoon → Users → Admin → Change password → `Monitor2026!`.

**Miks vaheta parool kohe:** `zabbix` on **avalikult teada** vaikeparool — iga turvakontroll lööb selle peale märgilist. Ainult localhost'is? Ikkagi vaheta — see harjutab õiget refleksi.

💡 **Kui "Database is not available":** MySQL pole veel healthy. Oota 30s, refresh.

### 2.2 Zabbix Agent

Server on olemas, aga kust ta andmeid saab? Agent on eraldi protsess, mis jookseb **igal masinal mida tahad jälgida** ja kogub süsteemi mõõdikuid (CPU, mälu, ketas, võrk). Mõte on lihtne: agent on käed-jalad, server on aju.

Eelmisest osast tuleb meelde, et Zabbix on modulaarne — server ise ei skanni masinat. See tundub esialgu liigne (Prometheus-es on üks binaar), aga annab paindlikkust: üks server jookseb 10–100–tuhanded agente paralleelselt.

```yaml
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
      - ./config:/etc/zabbix/zabbix_agentd.d:ro
    restart: unless-stopped
```

`ZBX_HOSTNAME` **peab** ühtima sellega, mida kasutad UI-s host-i loomisel. Kui ei vasta — Server viskab andmed ära.

**Miks see reegel olemas:** Zabbix agent saadab andmeid serverile koos enda nimega. Server kontrollib — kas mul on sõlm nimega `docker-agent`? Kui jah, salvesta. Kui ei, ignoreeri (et kogemata teise firma agent ei pumpaks andmeid). See on **esimene tüüpiline viga** uutel Zabbix'i kasutajatel — konfis on nimi A, UI-s host nimega B, andmeid pole kunagi.

```bash
docker compose up -d zabbix-agent
docker exec zabbix-server zabbix_get -s zabbix-agent -k agent.ping
```

Vastus `1` — agent elab.

### 2.3 Kontroll

Enne kui liigume host'ide ja trigger'ite juurde, kontrollime et baas on tõesti stabiilne.

```bash
docker compose ps
```

Neli teenust `Up`, MySQL `(healthy)`. Kui mõni on restarting või exited, vaata selle konteineri logi (`docker compose logs <nimi>`) enne edasi minekut.

💭 **Mõtle:** Prometheus oli üks binaar + konfi-fail. Zabbix on neli komponenti + andmebaas. Miks nii keeruline? Mis on selle eelised võrreldes sinu töökogemusega?

---

## Osa 3 · Host, template, trigger, dashboard

Süsteem on üleval, agent elab. Aga Zabbix ei tea veel, et me tahame midagi jälgida. Päev 2 loengu 4 kontseptsiooni tulevad siin päriseks: **Host** (mida jälgida), **Template** (millist komplekti mõõdikuid rakendame), **Trigger** (millal häirima hakata), **Dashboard** (kuidas näha).

### 3.1 docker-agent

Esimesena lisame iseenda Zabbix agent'i kui host'i. See on kõige lihtsam — Docker Compose võrgus konteinerid näevad üksteist DNS-nimega (`zabbix-agent` on teenuse nimi compose-failis).

*Data collection → Hosts → Create host*:

- Host name: `docker-agent`
- Host groups: `Linux servers`
- Interfaces → Add → Agent → DNS name `zabbix-agent`, Connect to **DNS**, port `10050`
- Templates → Select → `Linux by Zabbix agent`

**Miks Connect to DNS, mitte IP**: Docker bridge-võrgus konteinerite IP-d muutuvad iga restart'iga. DNS-nimi on stabiilne — Docker sisene DNS lahendab selle automaatselt.

**Miks template `Linux by Zabbix agent`**: üks kliki ja saad ~300 valmismeetrikut (CPU, mälu, ketas, võrk, protsessid, filesystem) + ~50 valmist trigger'it. Ilma template'ita peaksid iga item'i ise looma — 2 päeva tööd.

Add. Oota 60s. *Hosts* lehel roheline ZBX.

💡 **Kui ZBX punane:** kontrolli et Host name = `docker-agent` (täpselt sama mis `ZBX_HOSTNAME` environment'is).

### 3.2 mon-target

Nüüd lisame **päris** masina — mon-target. See on eraldi VM, kus Zabbix agent jookseb systemd teenusena. Erinevalt docker-agent'ist ei ole ta sama Docker-võrgu sees, seega DNS-nimi ei tööta.

Sama, aga interface on IP:

- Host name: `mon-target`
- Interface → Agent → IP `192.168.35.140`, Connect to **IP**, port `10050`
- Templates → `Linux by Zabbix agent`

**Millal IP, millal DNS**: kui masin on püsiv infrastruktuur (VM, server), IP on mõistlik. Konteinerid või dünaamiliselt muutuvad keskkonnad (Kubernetes) → DNS või discovery. IP on lihtsam, aga nõuab et masin selle IP ka järjepidevalt hoiaks (static DHCP lease või static IP).

Kontroll:

```bash
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k agent.ping
```

Peab tagastama `1`. Kui töötab serverist käsitsi, töötab ka UI kaudu — see on kiire sanity check enne kui UI-s 1 min ootad.

### 3.3 Trigger fire/resolve

Millal trigger töötab? Vaatame seda praktikas. `Linux by Zabbix agent` template sisaldab järgmist trigger'it:

```
avg(/mon-target/system.cpu.util,5m) > 90
```

Tõlgiksime: "kui CPU kasutus keskmiselt viimased 5 minutit on üle 90%, löö häiret". Selline keskmistatud trigger jätab lühikesed spike-id ignoreerituks — üks sekund 95% CPU ei ole probleem, aga 5 minutit järjest on.

SSH mon-target'ile ja tekita koormust:

```bash
ssh <eesnimi>@192.168.35.140
sudo stress-ng --cpu 4 --timeout 180s &
```

`stress-ng --cpu 4` paneb 4 protsessorit 100% koormuse alla 3 minutiks. Kuna trigger nõuab 5 minutit keskmist, jookseme tahtlikult üle lävendi, aga mitte nii kaua et trigger Firing muutub.

*Monitoring → Problems* — 1-2 min pärast ilmub `High CPU utilization`. Peata (`sudo pkill stress-ng`) → trigger laheneb ise.

**Miks see oluline**: sellisel kujul töötab **iga** Zabbix trigger — olek liigub `Inactive → Pending → Firing → Inactive` vastavalt tingimuse täitumisele. "Pending" on automaatne "for" kestus — ei löö kohe tulekahju, ootab et tingimus püsib. Kui kunagi ütled "miks mu alerti ei tuletatud", vaata esmalt seda oleku ajalugu.

<details>
<summary>🔧 Edasijõudnule: kirjuta ise keerulisem trigger</summary>

Template'i trigger-id kasutavad lihtsaid expression'eid. Proovi kirjutada oma:

*Data collection → Hosts → kliki `mon-target` real **Triggers** lingil → Create trigger*:

- Name: `Memory usage critical on {HOST.NAME}`
- Severity: **High**
- Kliki **Expression → Add** → Expression builder:
  - Item: `mon-target: Available memory`
  - Function: `last()`
  - Result: `< 100M`

Või kirjuta expression käsitsi:

```
last(/mon-target/vm.memory.size[available]) < 100000000
```

Keerulisem variant — **keskmistamine aja peale** (vähendab false positive'e):

```
avg(/mon-target/system.cpu.util[,idle],5m) < 20
```

See käivitub ainult kui CPU idle on keskmiselt alla 20% viimase 5 minuti jooksul — mitte iga spike peale.

Expression builder aitab, aga päris Zabbixi admin kirjutab expression'id käsitsi. [Docs / trigger expressions](https://www.zabbix.com/documentation/7.0/en/manual/config/triggers/expression).

</details>

### 3.4 Dashboard

*Monitoring → Dashboards → Global view*

`Linux by Zabbix agent` template tõi kaasa valmis dashboardi. Näed CPU, mälu, ketta graafikuid ilma ühtki PromQL'i kirjutamata. Võrdle Grafanaga päevast 1 — Zabbixi dashboard tuleb template'iga automaatselt, Grafanas kirjutasid PromQL päringud ise.

**Mis see tähendab praktikas**: Zabbix on "monitoring out of the box". Lisa host, lisa template, jookse. Grafana + Prometheus nõuab rohkem ettevalmistustes käsitööd, aga on **versioonitud** (PromQL YAML-is + Grafana dashboards JSON-is). Mõlemal on kohad, millal sobib.

💭 **Mõtle:** Zabbix template andis ~300 item'it ja ~50 trigger'it ühe klikiga. Prometheuses kirjutasid alert-reeglid YAML-i käsitsi. Kumb sobib paremini sinu töökeskkonda — template'd või "infrastructure as code"?

---

## Osa 4 · HTTP Agent + Dependent items

Päev 1 Prometheuses kasutasid `nginx-prometheus-exporter` konteinerit et Nginx stub_status andmeid koguda. Zabbix HTTP Agent teeb sama ilma välise exporter'ita — server küsib URL-i otse.

**Miks see oluline:** iga exporter-konteiner on üks rohkem asi, mida hoida üleval (logid, uuendused, konflikte, failure mode'd). Kui suudad küsida otse (HTTP API, SNMP, JMX), säästad end sellest üleliigsest kihist. Selle osa eesmärk on näha **master + dependent** mustrit — üks HTTP päring annab mitu mõõdikut.

### 4.1 Host ilma agent'ita

Loo `nginx-web` host. Host group: loo uus `Applications`. **Interface'i ära lisa** — HTTP Agent teeb päringu otse URL-ile, agent'i pole vaja.

**Miks ilma interface'ita**: Zabbixis on interface "kuidas server mõõdetava objektiga ühenduse saab" (tavaliselt agent'i kaudu). HTTP Agent tüüpi item küsib URL-i otse, ei vaja välise protsessi (agent) vahenduses. See on sama muster mida Prometheus kasutab (pull HTTP → scrape).

### 4.2 Master item

Esimene item küsib **kogu** stub_status väljundit korraga. See on "master" — hiljem ehitame sellest mitu "dependent" item'it, kes kasutavad sama toorandmeid.

*Items → Create*:

- Name: `Nginx status raw`
- Type: **HTTP agent**
- Key: `nginx.status.raw`
- URL: `http://192.168.35.141:8080/stub_status`
- Type of information: **Text**
- Update interval: `30s`

**Miks Text, mitte Numeric**: stub_status väljund on mitmerealine tekst, mõne numbrilise väärtusega. Numeric ei sobi. Master item hoiab **toorandmeid**, dependent item'id parseerivad numbri välja.

Minut hiljem *Latest data* näitab stub_status teksti.

### 4.3 Dependent item

Nüüd ekstraheerime ühe konkreetse numbri master item'i väljundist.

*Items → Create*:

- Name: `Active connections`
- Type: **Dependent item**
- Master item: `nginx-web: Nginx status raw`
- Key: `nginx.connections.active`
- Type of information: **Numeric (unsigned)**
- Preprocessing → Add → Regular expression: pattern `Active connections: (\d+)`, output `\1`

**Miks master + dependent**: stub_status annab kogu infot ühe HTTP päringuga — active connections, reading, writing, waiting, handled requests jne. Kui teeksid iga numbri jaoks eraldi HTTP päringu, tekiks 5 päringut 30s kohta (Nginx pool = koormus, võrgus = latency). Master küsib ühe korra, dependent'id parsivad sealt erinevaid numbreid. Üks päring → viis mõõdikut.

Tekita liiklust:

```bash
for i in {1..20}; do curl -s http://192.168.35.141:8080/ > /dev/null & done; wait
```

### 4.4 Tee ise

Loo dependent item `Requests total` — regex: `requests\s+\d+\s+(\d+)\s+\d+`. Üks HTTP päring annab kolm mõõdikut (active connections, requests total + mida veel ise ekstraheerida soovid).

See on iseseisev harjutus — külge vaadatakse regex'i ja master item'i väljundit. Kui regex ei tule kohe välja, kliki master item'ile *Test* nuppu — Zabbix näitab väljundit ja saad regex'i jooksvalt testida.

<details>
<summary>🔧 Edasijõudnule: JSONPath preprocessing</summary>

Regex töötab stub_status jaoks, aga kui monitoorid JSON API-t (nt `/api/health`), on JSONPath mugavam:

Loo item:
- Type: **HTTP agent**
- URL: mingi JSON endpoint (nt `http://192.168.35.141:8080/api/status` kui olemas)
- Type of information: **Text**

Dependent item:
- Preprocessing → **JSONPath**: `$.connections.active`

JSONPath on nagu XPath, aga JSON-ile. Regex'ist selgem, vähem vigu. [Docs / preprocessing](https://www.zabbix.com/documentation/7.0/en/manual/config/items/preprocessing).

</details>

💭 **Mõtle:** Prometheus vajab nginx-exporter konteinerit. Zabbix HTTP Agent küsib otse. Mida see tähendab halduse ja sõltuvuste poolest?

---

## Osa 5 · UserParameter + honeypot

UserParameter on shell-käsk mida agent käivitab, kui server küsib võtmega. Üks rida ja sul on uus mõõdik. [Docs](https://www.zabbix.com/documentation/7.0/en/manual/config/items/userparameters).

**Miks see on oluline:** template'id katavad ~300 standard-mõõdikut, aga iga organisatsioon vajab **oma mõõdikuid** — ärilogide veaarvud, küsimuste järjekord, licence'i expiration, tarkvaraversioon. Ilma UserParameter'ita peaksid need tulema HTTP exporter'ist või eraldi teenusest. UserParameter teeb selle ühe rea konfiga.

### 5.1 echo 42 — minimaalne UserParameter

Esimesena teeme kõige lihtsama võimaliku UserParameter'i — konstant 42. See aitab aru saada, mis on "võti" ja mis on "väärtus", enne kui läheme keerulisemate peale.

```bash
echo 'UserParameter=minu.test, echo 42' > ~/paev2/zabbix/config/test.conf
docker restart zabbix-agent
sleep 5
docker exec zabbix-server zabbix_get -s zabbix-agent -k minu.test
```

Vastus: `42`.

**Mis just juhtus:** kirjutasid agent'i config'i faili, mille mount on `./config:/etc/zabbix/zabbix_agentd.d:ro`. Konfig ütleb: kui server küsib võtit `minu.test`, käivita `echo 42` ja tagasta väljund. Võti `minu.test` on suvaline string — sa ise valid konventsiooni (tavaliselt `rakendus.alam-mõõdik`).

### 5.2 Parameetrid võtmes

Võtmed on dünaamilised — võid anda talle argumente nurksulgudes. See võimaldab ühe UserParameter'iga kirjutada "malli" ja siis küsida konkreetseid järgi.

```bash
cat > ~/paev2/zabbix/config/test.conf <<'EOF'
UserParameter=minu.topelt[*], echo $(($1 * 2))
EOF
docker restart zabbix-agent && sleep 5
docker exec zabbix-server zabbix_get -s zabbix-agent -k "minu.topelt[5]"
docker exec zabbix-server zabbix_get -s zabbix-agent -k "minu.topelt[100]"
```

Esimene päring annab `10`, teine `200`. `[*]` võtme definitsioonis tähendab "lubatud on mistahes parameetrid", `$1` viitab esimesele parameetrile, `$2` teisele jne.

**Miks see on oluline:** hiljem kirjutame `applog.errors[payment]`, `applog.errors[auth]`, `applog.errors[api]` — üks UserParameter, aga Zabbixis on kolm eraldi item'it. Ilma parameetriteta peaks iga teenuse jaoks eraldi UserParameter'i kirjutama.

### 5.3 Päris mõõdik — applog

Nüüd kirjutame midagi kasulikku. mon-target'il jookseb log-generator, mis lisab `/var/log/app/app.log` failile ridu kujul `2026-04-25T10:23:41 [ERROR] [payment] ...`. Tahame teada: mitu `ERROR` rida on teenusest `payment` viimases 1000 reas.

**Lahendus `tail + grep`** on shell-klassika — `tail -n 1000` annab faili viimased 1000 rida, `grep -c` loendab mustrile vastavad read. Cron'is teeks sama. UserParameter teeb sellest Zabbix item'i.

SSH mon-target'ile:

```bash
ssh <eesnimi>@192.168.35.140
sudo tee /etc/zabbix/zabbix_agentd.d/applog.conf <<'EOF'
UserParameter=applog.errors[*], tail -n 1000 /var/log/app/app.log | grep -c "\[ERROR\] \[$1\]"
UserParameter=applog.count[*], tail -n 1000 /var/log/app/app.log | grep -c "\[$1\] \[$2\]"
EOF
sudo systemctl restart zabbix-agent
exit
```

Kaks UserParameter'it — üks spetsialiseeritud "errors" (ainult ERROR tase), teine üldine "count" (kasutaja annab mõlemad). Mõlemad kasutavad parameetritega võtmeid. Zabbix agent jookseb mon-target'il juba eelinstallitult.

Testi, et agent tagastab päris numbri:

```bash
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k "applog.errors[payment]"
```

Pead nägema numbri (võib-olla 0 kui õnneks pole praegu payment-ERROR'eid voolus).

!!! warning "Piirang: `tail -n 1000`"
    See käsk loeb ainult viimased 1000 rida. Kui logi kasvab kiiresti, võib reaalne veaarv olla palju suurem kui see, mida näed. Tootmises eelistatakse [Log monitoring](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/log_items) item-tüüpi, mis hoiab positsiooni ja loeb ainult uued read. UserParameter + grep on lihtsam, aga vaid demo-kvaliteedis.

💡 **Kui `ZBX_NOTSUPPORTED`:** süntaksiviga konfis — `sudo cat /etc/zabbix/zabbix_agentd.d/applog.conf` ja kontrolli.

### 5.4 Item ja trigger — andmed nähtavaks UI-s

Agent tagastab numbri, aga Zabbix ei **salvesta** seda veel — pole item'it. Item ütleb Zabbixile "hakka seda võtit regulaarselt küsima ja salvestama". Trigger ütleb "ja kui väärtus käib üle lävendi, tekita probleem".

mon-target host → *Items → Create*:

- Name: `Payment errors (last 1000 lines)`
- Type: Zabbix agent
- Key: `applog.errors[payment]`
- Type of information: Numeric (unsigned)
- Update interval: `30s`

**Miks 30 sekundit**: logi kasvab ~1 rida sekundis, 30s annab õige kompromissi reaktsioonikiiruse ja serveri koormuse vahel. Iga sekund oleks üleliigne, iga 5 minut oleks aeglasem kui märkate.

*Data collection → Hosts → kliki `mon-target` real **Triggers** lingil (mitte host nimel!) → Create trigger*:

- Name: `Too many payment errors on {HOST.NAME}`
- Severity: Warning
- Expression: `last(/mon-target/applog.errors[payment])>10`

**Miks `last() > 10`**: item'i väärtus on `tail -n 1000 | grep -c ERROR payment`. Kui viimase 1000 rea hulgas on üle 10 payment-ERROR'i, midagi on tegelikult katki. `{HOST.NAME}` on Zabbixi **makro** — trigger'i kirjeldusse paigutatakse automaatselt vastav host'i nimi (siin `mon-target`). Sama trigger töötab teise host'iga, kui linkida uuesti.

💡 **Trigger navigatsioon Zabbix 7.0:** trigger'i loomiseks mine host'i real "Triggers" lingile — paljud otsivad menüüst Alerts → Triggers, aga seal näeb ainult olemasolevaid.

### 5.5 Error-torm — testi, et trigger elab

Produktsioon on kvaliteetne ainult siis, kui sa oled testinud, et probleemi tekkimisel see ka välja lööb. Tekita künstlik error-torm mon-target'i logifaili ja vaata, mitu sekundit hiljem Zabbix seda märkab.

```bash
ssh <eesnimi>@192.168.35.140 \
  'for i in $(seq 1 100); do echo "$(date -Iseconds) [ERROR] [payment] Spam_$i" | sudo tee -a /var/log/app/app.log > /dev/null; done'
```

See tekitab 100 ERROR rida pärast viimase 1000 rea hulka. Nii on kindel, et `grep -c` annab väärtuse üle 10. Umbes 1 min pärast (update interval + server-side processing) *Problems* lehel trigger **Firing**. Kui lakkad logikirjadeid lisamast, vead liiguvad aknast välja ja trigger laheneb ise.

### 5.6 Honeypot — UserParameter turbe-kontekstis

UserParameter ei pea olema ainult jõudluse jaoks. Lihtsaim honeypot on avatud port kuhu keegi "õiges" ei peaks ühenduma — tulemüüri taga teenuste, ainult ründaja skannib. Iga ühendus on turvasignaal.

```bash
ssh <eesnimi>@192.168.35.140
sudo tee /usr/local/bin/honeypot-listen.sh <<'EOF'
#!/bin/bash
while true; do
  nc -lnp 2222 < /dev/null 2>/dev/null && echo "$(date -Iseconds) HIT" >> /var/log/honeypot.log
done
EOF
sudo chmod +x /usr/local/bin/honeypot-listen.sh
sudo touch /var/log/honeypot.log
nohup sudo /usr/local/bin/honeypot-listen.sh &
```

Skript avab pordi 2222 ja iga ühenduse kohta kirjutab rea `HIT` faili. Kui keegi seda porti skannib, tekib rida. Mingit teenust seal õieti ei jookse — port on mõeldud "lõksuks".

Lisa UserParameter, mis loendab HIT-e:

```bash
sudo tee -a /etc/zabbix/zabbix_agentd.d/applog.conf <<'EOF'
UserParameter=honeypot.hits, wc -l < /var/log/honeypot.log
EOF
sudo systemctl restart zabbix-agent
exit
```

See UserParameter on **ilma parameetrita** — lihtsalt loendab rida honeypoti logis.

Loo item (`honeypot.hits`, Numeric unsigned, 15s) ja trigger:

- Name: `Honeypot hit detected on {HOST.NAME}`
- Severity: **High**
- Expression: `last(/mon-target/honeypot.hits)>0`

**Miks `High`**: `Warning` päev 2 payment-error'itel — need juhtuvad mingi määra, tavaline müra. Honeypot hit on **definitsiooni järgi** anomaalia — ei tohiks kunagi juhtuda. `last() > 0` ja `High` ütleb "iga üks löök ongi probleem".

Testi üks ühendus (palu naabril seda teha või ise testi VM-ist):

```bash
nc -zv 192.168.35.140 2222
```

1 min → trigger **Firing**.

<details>
<summary>🔧 Edasijõudnule: honeypot mitme pordiga + IP logimine</summary>

Üks port on demo. Tootmises kuulad mitut porti ja logid ühenduse IP:

```bash
# Logib ühenduse koos IP-ga
UserParameter=honeypot.connections, grep -c "HIT" /var/log/honeypot.log
UserParameter=honeypot.last_ip, tail -1 /var/log/honeypot.log | awk '{print $NF}'
```

Või kasuta `iptables` logimist ilma kuulajata:

```bash
sudo iptables -A INPUT -p tcp --dport 2222 -j LOG --log-prefix "HONEYPOT: "
UserParameter=honeypot.iptables, grep -c "HONEYPOT:" /var/log/messages
```

See on rohkem turvameeskonnale — aga näitab kui laiendatav UserParameter on.

</details>

### 5.7 User macros — tundlik info item'ides

Enne kui edasi — üks tähtis küsimus: Osa 5.3 konfis olid paroolid ja teed kõvakodeeritud. Tootmises nii ei tee.

**Miks see on probleem**: kui kirjutad konfis `-u root -p Monitor2026!`, on parool nüüd agent'i konfis kettal, audit-logis, git'is (kui kommittid), backup'is. See on 4+ kohta, kust parool saab lekkida. User macros lahendab selle — väärtused Zabbix'i UI-s, krüpteeritud serveris, item kasutab makro-nime.

*Data collection → Hosts → `docker-agent` → Macros* tab → *Add*:

| Macro | Value | Type |
|-------|-------|------|
| `{$APP.LOG.PATH}` | `/var/log/app/app.log` | Text |
| `{$APP.DB.PASSWORD}` | `secret_123` | **Secret text** |

Item'is kasuta võtit nagu `applog.errors[{$APP.SERVICE}]` — Zabbix asendab makro enne agentile saatmist. **Secret text** peidab väärtuse UI-s ja audit-logis. Ava sama host'i Macros tab uuesti — Secret väärtust ei näe enam.

💭 **Mõtle:** UserParameter võimaldab mis tahes shell-käsku mõõdikuks muuta. Mis on selle turvarisk? Kuidas hallatakse sinu tööl paroole ja tokeneid monitooringu kontekstis — Vault, env-muutujad, failid?

---

## ✅ Lõpukontroll (Zabbix pool)

- [ ] `docker compose ps` (`~/paev2/zabbix/`) — 4 konteinerit Up
- [ ] docker-agent ja mon-target availability roheline
- [ ] Dashboard näitab mõlema host'i graafikuid
- [ ] nginx-web HTTP Agent item tagastab stub_status, dependent item numbri
- [ ] `zabbix_get -k "applog.errors[payment]"` tagastab numbri
- [ ] Payment errors trigger läks Firing ja lahenes
- [ ] Honeypot trigger Firing kui keegi ühendus port 2222-le

**Jätka:** [Labor: Loki](loki_lab.md) — logide stack, LogQL, FINAAL.

---

## 🚀 Lisaülesanded

### LLD + oma template

`applog.errors[payment]` tegid käsitsi. Aga teenuseid on 5, tasemeid 3 = 15 kombinatsiooni. LLD avastab need automaatselt.

Discovery skript mon-target'il:

```bash
ssh <eesnimi>@192.168.35.140
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

Testi: `docker exec zabbix-server zabbix_get -s 192.168.35.140 -k applog.discovery` → valiidne JSON.

Loo template `App Log Monitoring` → Discovery rule (`applog.discovery`, 2m) → Item prototype (`applog.count[{#SEVERITY},{#SERVICE}]`) → Trigger prototype → Filter: ainult ERROR ja WARN.

Lisa template mon-target host'ile. 2-3 min → ~10 uut item'it tekib automaatselt.

### Discord teavitused

*Alerts → Media types → Discord* → lisa webhook URL → *Users → Admin → Media → Discord* → *Actions → Create action* (severity ≥ Warning, send to Admin via Discord, + recovery operation).

Testi error-tormiga — sõnum peaks tulema Discord kanalisse.

### Trigger hysteresis

Problem: `last() > 10`. Recovery: `last() < 5`. Väldib kõikumist piiri ümber.

---

## 🏢 Enterprise lisateemad

Järgnevad teemad on mõeldud tootmiskeskkondade jaoks. Igaüks on iseseisev — vali mis on sinu tööle kõige relevantam.

??? note "Zabbix HA — kõrgkäideldavus Docker Compose'is"

    Alates Zabbix 6.0 on natiivne HA sisseehitatud — ei vaja Pacemaker'it ega Corosync'i. Kaks (või enam) Zabbix Server'it jagavad sama MySQL-i, üks on aktiivne, teised standby.

    **Lisa docker-compose'i teine server:**

    ```yaml
      zabbix-server-2:
        image: zabbix/zabbix-server-mysql:ubuntu-7.0.6
        container_name: zabbix-server-2
        depends_on:
          mysql:
            condition: service_healthy
        environment:
          DB_SERVER_HOST: mysql
          MYSQL_DATABASE: zabbix
          MYSQL_USER: zabbix
          MYSQL_PASSWORD: zabbix_pwd
          ZBX_SERVER_NAME: zabbix-server-2
          TZ: Europe/Tallinn
        restart: unless-stopped
    ```

    `zabbix_server.conf` mõlemas serveris:

    ```
    HANodeName=zabbix-server-1    # või -2
    NodeAddress=zabbix-server:10051
    ```

    **Testi failover:**

    ```bash
    docker compose up -d zabbix-server-2
    # Vaata Reports → System information → HA cluster → 2 sõlme
    docker stop zabbix-server
    # ~30s → zabbix-server-2 võtab üle (active)
    docker start zabbix-server
    # server-1 läheb standby
    ```

    Tootmises: andmebaasikiht vajab samuti HA-d (PostgreSQL + Patroni või MariaDB + Galera). See on eraldi projekt, mitte labi teema.

    **Loe edasi:**

    - [Zabbix HA dokumentatsioon](https://www.zabbix.com/documentation/7.0/en/manual/concepts/server/ha)
    - [HA runtime commands](https://www.zabbix.com/documentation/7.0/en/manual/concepts/server/ha#runtime-commands)


??? note "Zabbix Proxy — monitooring üle WAN-i"

    Kui sul on filiaalid, DMZ või pilveinfra, ei saa agent'id alati otse serveriga rääkida. Proxy kogub andmeid lokaalselt ja edastab serverile.

    ```
    [Filiaal A]                    [Peakontor]
    Agent → Proxy-A ──── WAN ────→ Zabbix Server
    Agent →                        ↑
                                   MySQL
    [Filiaal B]
    Agent → Proxy-B ──── WAN ────→
    ```

    **Lisa docker-compose'i:**

    ```yaml
      zabbix-proxy:
        image: zabbix/zabbix-proxy-sqlite3:ubuntu-7.0.6
        container_name: zabbix-proxy
        environment:
          ZBX_PROXYMODE: 0                    # 0=active, 1=passive
          ZBX_HOSTNAME: proxy-local
          ZBX_SERVER_HOST: zabbix-server
          TZ: Europe/Tallinn
        ports:
          - "10061:10051"
        restart: unless-stopped
    ```

    UI-s: *Administration → Proxies → Create proxy* → Name: `proxy-local`, Mode: Active.

    Host'i lisamisel: *Monitored by proxy → proxy-local*.

    **Zabbix 7.0 proxy groups:** mitu proxy't ühes grupis — kui üks kukub, teised võtavad host'id üle automaatselt.

    **Loe edasi:**

    - [Proxy dokumentatsioon](https://www.zabbix.com/documentation/7.0/en/manual/distributed_monitoring/proxies)
    - [Proxy groups (7.0)](https://www.zabbix.com/documentation/7.0/en/manual/distributed_monitoring/proxy_groups)


??? note "SNMP monitooring — võrguseadmed ja kaamerad"

    Switchi, ruuteri, kaamera, printeri peal agent'it ei installi. Need räägivad SNMP-d.

    **Lisa host SNMP interface'iga:**

    *Data collection → Hosts → Create host*:

    - Host name: `switch-01`
    - Interfaces → Add → **SNMP** → IP: `192.168.35.1`, port `161`
    - SNMP version: `SNMPv2`
    - SNMP community: `public`
    - Templates → `Net Cisco IOS by SNMP` (või `Generic by SNMP`)

    Template toob kaasa interface'ide avastamise (LLD), liikluse graafikud, uptime, error counterid.

    **Testi ilma päris seadmeta — snmpsim:**

    ```bash
    docker run -d --name snmpsim -p 161:161/udp xeemetric/snmp-simulator
    ```

    Nüüd lisa Zabbix host'i IP `192.168.35.12X` (sinu VM), port 161.

    **OID-de uurimine:**

    ```bash
    docker exec zabbix-server snmpwalk -v2c -c public 192.168.35.12X .1.3.6.1.2.1.1
    ```

    **Loe edasi:**

    - [SNMP monitooring Zabbixis](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/snmp)
    - [SNMP OID tree](http://www.oid-info.com/cgi-bin/display?tree=.1.3.6.1.2.1)
    - [Community templates (SNMP)](https://github.com/zabbix/community-templates/tree/main/Network_Devices)


??? note "Agent ↔ Server PSK krüpteerimine"

    Tootmises ei saada agent andmeid selgetekstis. TLS-PSK on lihtsaim viis krüpteerida.

    **Genereeri PSK:**

    ```bash
    openssl rand -hex 32 > /tmp/zabbix_agent.psk
    cat /tmp/zabbix_agent.psk
    ```

    **Agent konfis** (`zabbix_agentd.conf` või environment):

    ```
    TLSConnect=psk
    TLSAccept=psk
    TLSPSKIdentity=PSK-agent-01
    TLSPSKFile=/etc/zabbix/zabbix_agent.psk
    ```

    **UI-s host'il:** *Encryption* tab → PSK → Identity: `PSK-agent-01` → PSK: (kleebi hex string).

    Nüüd `zabbix_get` ilma PSK-ta ei tööta:

    ```bash
    # Ebaõnnestub — krüpteerimata
    docker exec zabbix-server zabbix_get -s zabbix-agent -k agent.ping

    # Töötab — PSK-ga
    docker exec zabbix-server zabbix_get -s zabbix-agent -k agent.ping \
      --tls-connect psk --tls-psk-identity "PSK-agent-01" --tls-psk-file /tmp/agent.psk
    ```

    **Loe edasi:**

    - [Encryption dokumentatsioon](https://www.zabbix.com/documentation/7.0/en/manual/encryption)
    - [PSK vs Certificate](https://www.zabbix.com/documentation/7.0/en/manual/encryption/using_pre_shared_keys)


??? note "Zabbix API + Ansible automatiseerimine"

    2000 host'i käsitsi lisamine on mõttetu. Zabbix JSON-RPC API + Ansible collection teeb selle minutitega.

    **API näide — host'ide nimekiri:**

    ```bash
    curl -s -X POST http://192.168.35.12X:8080/api_jsonrpc.php \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "method": "host.get",
        "params": {"output": ["host", "status"]},
        "auth": "TOKEN",
        "id": 1
      }'
    ```

    **Token saamine:**

    ```bash
    curl -s -X POST http://192.168.35.12X:8080/api_jsonrpc.php \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "method": "user.login",
        "params": {"username": "Admin", "password": "Monitor2026!"},
        "id": 1
      }' | python3 -c "import sys,json; print(json.load(sys.stdin)['result'])"
    ```

    **Ansible collection:**

    ```bash
    pip install zabbix-api --break-system-packages
    ansible-galaxy collection install community.zabbix
    ```

    ```yaml
    # playbook: add-hosts.yml
    - hosts: localhost
      collections:
        - community.zabbix
      tasks:
        - name: Lisa host Zabbixisse
          community.zabbix.zabbix_host:
            server_url: "http://192.168.35.12X:8080"
            login_user: Admin
            login_password: Monitor2026!
            host_name: "server-{{ item }}"
            host_groups:
              - Linux servers
            link_templates:
              - Linux by Zabbix agent
            interfaces:
              - type: agent
                main: 1
                ip: "192.168.35.{{ item }}"
          loop: "{{ range(140, 145) | list }}"
    ```

    **Loe edasi:**

    - [Zabbix API dokumentatsioon](https://www.zabbix.com/documentation/7.0/en/manual/api)
    - [Ansible Zabbix collection](https://docs.ansible.com/ansible/latest/collections/community/zabbix/)


??? note "Audit log + SLA raportid (compliance)"

    Eesti Pank, GDPR, NIS2 — kes mida muutis ja mis on uptime?

    **Audit log:**

    *Reports → Audit log* — iga muudatus on logitud: kes, millal, mida. Filter: Resource type, Action, User.

    API kaudu eksporditav — saad regulaarselt CSV-sse tõmmata.

    **SLA (Zabbix 7.0 sisseehitatud):**

    *Services → SLA* → *Create SLA*:

    - Name: `Production servers 99.9%`
    - SLO: `99.9`
    - Schedule: `24x7`
    - Service tags: `env` = `production`

    *Services → Services* → Loo teenuse puu:

    ```
    Production
    ├── Web tier (mon-target-web)
    └── App tier (mon-target)
    ```

    *Reports → SLA report* näitab uptime % iga perioodi kohta.

    **Maintenance windows** — et planeeritud hooldus ei rikuks SLA-d:

    *Data collection → Maintenance → Create*:

    - Type: `With data collection` (kogub andmeid aga ei teavita)
    - Active since/till: hoolduse aeg
    - Hosts: vali host'id

    **Loe edasi:**

    - [SLA dokumentatsioon](https://www.zabbix.com/documentation/7.0/en/manual/it_services/sla)
    - [Audit log](https://www.zabbix.com/documentation/7.0/en/manual/web_interface/frontend_sections/reports/audit)
    - [Maintenance](https://www.zabbix.com/documentation/7.0/en/manual/maintenance)

---

## Veaotsing

| Probleem | Esimene kontroll |
|----------|------------------|
| MySQL unhealthy | `free -h` — kas RAM piisab? `docker compose logs mysql` |
| ZBX availability punane | Host name peab = `ZBX_HOSTNAME`. DNS vs IP — kontrolli |
| zabbix-web restartub | MySQL pole veel healthy — oota |
| ZBX_NOTSUPPORTED | UserParameter süntaksiviga — `sudo cat /etc/zabbix/zabbix_agentd.d/applog.conf` |
| Trigger ei Firing | Latest data — kas väärtus tegelikult ületab künnise? |
| HTTP Agent timeout | `curl -v http://192.168.35.141:8080/stub_status` otse |

---

## 📚 Allikad

| Allikas | URL |
|---------|-----|
| Zabbix 7.0 manuaal | [zabbix.com/documentation/7.0](https://www.zabbix.com/documentation/7.0/en/manual) |
| UserParameters | [zabbix.com/.../userparameters](https://www.zabbix.com/documentation/7.0/en/manual/config/items/userparameters) |
| Low-Level Discovery | [zabbix.com/.../low_level_discovery](https://www.zabbix.com/documentation/7.0/en/manual/discovery/low_level_discovery) |
| HTTP Agent | [zabbix.com/.../http](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/http) |
| Discord integration | [zabbix.com/integrations/discord](https://www.zabbix.com/integrations/discord) |

**Versioonid:** Zabbix 7.0.6 LTS, MySQL 8.0, Zabbix agent 2 (7.0+).
