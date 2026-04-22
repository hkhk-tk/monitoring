# Päev 2 · Zabbix + Loki

**Kestus:** ~4 tundi (klassis jõuad põhiosa, ülejäänu iseseisvalt)
**Tase:** Keskaste
**VM:** VM (nt `ssh <eesnimi>@192.168.35.12X`)
**Eeldused:** Päev 1 (Docker Compose, Grafana datasource, Prometheus pull-mudel, PromQL `rate()`).

---

## 🎯 Õpiväljundid

**Teadmised:**

1. Eristab Zabbixi push-mudelit Prometheuse pull-mudelist ja põhjendab millal kumbagi kasutada
2. Kirjeldab Zabbixi andmemudelit: host → template → item → trigger → action
3. Selgitab Loki rolli LGTM stackis ja labelite vs sisu indekseerimise erinevust
4. Eristab LogQL parserite kasutusolukordi (pattern, json, logfmt, regexp)

**Oskused:**

5. Ehitab Zabbix stacki Docker Compose'iga teenus-teenuse haaval
6. Seadistab host'i, template'i ja jälgib trigger fire/resolve tsüklit
7. Kirjutab UserParameter'i ja honeypot-triggeri
8. Ehitab Loki + Promtail stacki ja kirjutab LogQL päringuid
9. Parsib struktureerimata logi ja teisendab selle metrikaks (`rate()`, `count_over_time`)
10. Vaatab sama sündmust kahest vaatenurgast — Zabbix trigger + Loki graafik

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

# ZABBIX

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

### 2.1 Zabbix Web

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

💡 **Kui "Database is not available":** MySQL pole veel healthy. Oota 30s, refresh.

### 2.2 Zabbix Agent

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

```bash
docker compose up -d zabbix-agent
docker exec zabbix-server zabbix_get -s zabbix-agent -k agent.ping
```

Vastus `1` — agent elab.

### 2.3 Kontroll

```bash
docker compose ps
```

Neli teenust `Up`, MySQL `(healthy)`.

💭 **Mõtle:** Prometheus oli üks binaar + konfi-fail. Zabbix on neli komponenti + andmebaas. Miks nii keeruline? Mis on selle eelised võrreldes sinu töökogemusega?

---

## Osa 3 · Host, template, trigger, dashboard

### 3.1 docker-agent

*Data collection → Hosts → Create host*:

- Host name: `docker-agent`
- Host groups: `Linux servers`
- Interfaces → Add → Agent → DNS name `zabbix-agent`, Connect to **DNS**, port `10050`
- Templates → Select → `Linux by Zabbix agent`

Add. Oota 60s. *Hosts* lehel roheline ZBX.

💡 **Kui ZBX punane:** kontrolli et Host name = `docker-agent` (täpselt sama mis `ZBX_HOSTNAME` environment'is).

### 3.2 mon-target

Sama, aga interface on IP:

- Host name: `mon-target`
- Interface → Agent → IP `192.168.35.140`, Connect to **IP**, port `10050`
- Templates → `Linux by Zabbix agent`

Kontroll:

```bash
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k agent.ping
```

Peab tagastama `1`.

### 3.3 Trigger fire/resolve

`Linux by Zabbix agent` template sisaldab CPU triggerit. SSH mon-target'ile:

```bash
ssh <eesnimi>@192.168.35.140
sudo stress-ng --cpu 4 --timeout 180s &
```

*Monitoring → Problems* — 1-2 min pärast ilmub `High CPU utilization`. Peata (`sudo pkill stress-ng`) → trigger laheneb ise.

<details>
<summary>🔧 Edasijõudnule: kirjuta ise keerulisem trigger</summary>

Template'i triggerid kasutavad lihtsaid expression'eid. Proovi kirjutada oma:

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

`Linux by Zabbix agent` template tõi kaasa valmis dashboardi. Näed CPU, mälu, ketta graafikuid. Võrdle Grafanaga päevast 1 — Zabbixi dashboard tuleb template'iga automaatselt, Grafanas kirjutasid PromQL päringud ise.

💭 **Mõtle:** Zabbix template andis ~300 item'it ja ~50 trigger'it ühe klikiga. Prometheuses kirjutasid alert-reeglid YAML-i käsitsi. Kumb sobib paremini sinu töökeskkonda — template'd või "infrastructure as code"?

---

## Osa 4 · HTTP Agent + Dependent items

Päev 1 Prometheuses kasutasid `nginx-prometheus-exporter` konteinerit et Nginx stub_status andmeid koguda. Zabbix HTTP Agent teeb sama ilma välise exporter'ita — server küsib URL-i otse.

### 4.1 Host ilma agent'ita

Loo `nginx-web` host. Host group: loo uus `Applications`. **Interface'i ära lisa** — HTTP Agent teeb päringu otse URL-ile, agent'i pole vaja.

### 4.2 Master item

*Items → Create*:

- Name: `Nginx status raw`
- Type: **HTTP agent**
- Key: `nginx.status.raw`
- URL: `http://192.168.35.141:8080/stub_status`
- Type of information: **Text**
- Update interval: `30s`

Minut hiljem *Latest data* näitab stub_status teksti.

### 4.3 Dependent item

*Items → Create*:

- Name: `Active connections`
- Type: **Dependent item**
- Master item: `nginx-web: Nginx status raw`
- Key: `nginx.connections.active`
- Type of information: **Numeric (unsigned)**
- Preprocessing → Add → Regular expression: pattern `Active connections: (\d+)`, output `\1`

Tekita liiklust:

```bash
for i in {1..20}; do curl -s http://192.168.35.141:8080/ > /dev/null & done; wait
```

### 4.4 Tee ise

Loo dependent item `Requests total` — regex: `requests\s+\d+\s+(\d+)\s+\d+`. Üks HTTP päring annab kolm mõõdikut.

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

### 5.1 echo 42

```bash
echo 'UserParameter=minu.test, echo 42' > ~/paev2/zabbix/config/test.conf
docker restart zabbix-agent
sleep 5
docker exec zabbix-server zabbix_get -s zabbix-agent -k minu.test
```

Vastus: `42`.

### 5.2 Parameetrid

```bash
cat > ~/paev2/zabbix/config/test.conf <<'EOF'
UserParameter=minu.topelt[*], echo $(($1 * 2))
EOF
docker restart zabbix-agent && sleep 5
docker exec zabbix-server zabbix_get -s zabbix-agent -k "minu.topelt[5]"
docker exec zabbix-server zabbix_get -s zabbix-agent -k "minu.topelt[100]"
```

`[*]` → parameetrid lubatud. `$1` viitab esimesele.

### 5.3 Päris mõõdik — applog

mon-target'il kirjutab log-generator `/var/log/app/app.log`. SSH sinna:

```bash
ssh <eesnimi>@192.168.35.140
sudo tee /etc/zabbix/zabbix_agentd.d/applog.conf <<'EOF'
UserParameter=applog.errors[*], tail -n 1000 /var/log/app/app.log | grep -c "\[ERROR\] \[$1\]"
UserParameter=applog.count[*], tail -n 1000 /var/log/app/app.log | grep -c "\[$1\] \[$2\]"
EOF
sudo systemctl restart zabbix-agent
exit
```

Testi:

```bash
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k "applog.errors[payment]"
```

💡 **Kui `ZBX_NOTSUPPORTED`:** süntaksiviga konfis — `sudo cat /etc/zabbix/zabbix_agentd.d/applog.conf` ja kontrolli.

### 5.4 Item + trigger

mon-target host → *Items → Create*:

- Name: `Payment errors (last 1000 lines)`
- Type: Zabbix agent
- Key: `applog.errors[payment]`
- Type of information: Numeric (unsigned)
- Update interval: `30s`

*Data collection → Hosts → kliki `mon-target` real **Triggers** lingil (mitte host nimel!) → Create trigger*:

- Name: `Too many payment errors on {HOST.NAME}`
- Severity: Warning
- Expression: `last(/mon-target/applog.errors[payment])>10`

💡 **Trigger navigatsioon Zabbix 7.0:** trigger'i loomiseks mine host'i real "Triggers" lingile — paljud otsivad menüüst Alerts → Triggers, aga seal näeb ainult olemasolevaid.

### 5.5 Error-torm

```bash
ssh <eesnimi>@192.168.35.140 \
  'for i in $(seq 1 100); do echo "$(date -Iseconds) [ERROR] [payment] Spam_$i" | sudo tee -a /var/log/app/app.log > /dev/null; done'
```

1 min → *Problems* → trigger Firing.

### 5.6 Honeypot

UserParameter ei pea olema ainult jõudluse jaoks. Lihtne honeypot: ava port kuhu keegi ei peaks ühenduma.

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

Lisa UserParameter:

```bash
sudo tee -a /etc/zabbix/zabbix_agentd.d/applog.conf <<'EOF'
UserParameter=honeypot.hits, wc -l < /var/log/honeypot.log
EOF
sudo systemctl restart zabbix-agent
exit
```

Loo item (`honeypot.hits`, Numeric unsigned, 15s) ja trigger:

- Name: `Honeypot hit detected on {HOST.NAME}`
- Severity: **High**
- Expression: `last(/mon-target/honeypot.hits)>0`

Palud naabril:

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

*Data collection → Hosts → `docker-agent` → Macros* tab → *Add*:

| Macro | Value | Type |
|-------|-------|------|
| `{$APP.LOG.PATH}` | `/var/log/app/app.log` | Text |
| `{$APP.DB.PASSWORD}` | `secret_123` | **Secret text** |

**Secret text** peidab väärtuse UI-s ja audit-logis. Ava sama host'i Macros tab uuesti — Secret väärtust ei näe enam.

💭 **Mõtle:** UserParameter võimaldab mis tahes shell-käsku mõõdikuks muuta. Mis on selle turvarisk? Kuidas hallatakse sinu tööl paroole ja tokeneid monitooringu kontekstis — Vault, env-muutujad, failid?

---

# LOKI

Zabbix ütles "trigger Firing" — on probleem. Aga **mida** täpselt? Logid vastavad sellele. Lokiga tood logid Grafanasse — SSH + grep asemel LogQL päringud brauseris.

---

## Osa 6 · LogQL — brauseris ja päriselt

### 6.1 Simulator

Ava brauseris: <https://grafana.com/docs/loki/latest/query/analyzer/>

Vali **logfmt** formaat. Kirjuta:

```logql
{job="analyze"} |= "error"
```

Run query. Rohelised read sobivad, hallid ei sobi.

### 6.2 Ekstraheeri labelid

```logql
{job="analyze"} | logfmt | level = "error"
```

Erinevus — nüüd **parsisid** logi ja filtreerisid **labeli** järgi, mitte tekstiotsingu järgi.

### 6.3 Pattern parser

Vali **unstructured** formaat:

```logql
{job="analyze"} | pattern `<_> <user> <_>` | user =~ "kling.*"
```

`<_>` ignoreerib, `<user>` püüab labeli.

### 6.4 JSON

Vali **json** formaat:

```logql
{job="analyze"} | json | status_code = "500"
```

Neli parserit — `json`, `logfmt`, `pattern`, `regexp`. `pattern` on enim kasutatav kuna enamik logisid on vabatekst.

💭 **Mõtle:** Sinu töö logid — mis formaadis need on? Millist parserit kasutaksid?

---

## Osa 7 · Loki + Promtail stack

```bash
mkdir -p ~/paev2/loki/config && cd ~/paev2/loki
```

### 7.1 Loki konfiguratsioon

```bash
cat > config/loki-config.yml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  allow_structured_metadata: true
EOF
```

### 7.2 Loki teenus

Loo `docker-compose.yml`:

```yaml
services:
  loki:
    image: grafana/loki:3.2.1
    container_name: loki
    ports:
      - "3100:3100"
    volumes:
      - ./config/loki-config.yml:/etc/loki/local-config.yaml
      - loki-data:/loki
    command: -config.file=/etc/loki/local-config.yaml
    restart: unless-stopped

volumes:
  loki-data:
  grafana-data:
  app-logs:
  nginx-logs:
```

```bash
docker compose up -d loki
sleep 10
curl -s http://localhost:3100/ready
```

Vastus `ready`. Kui ei — `docker compose logs loki`.

### 7.3 Log-generator

Lisa `services:` alla:

```yaml
  log-generator:
    image: busybox:latest
    container_name: log-generator
    command:
      - sh
      - -c
      - |
        mkdir -p /var/log/app /var/log/nginx
        SERVICES="payment auth api database cache"
        LEVELS="INFO INFO INFO INFO INFO WARN ERROR"
        while true; do
          S=$$(echo $$SERVICES | tr " " "\n" | shuf -n1)
          L=$$(echo $$LEVELS | tr " " "\n" | shuf -n1)
          LATENCY=$$((RANDOM % 500))
          echo "$$(date -Iseconds) [$$L] [$$S] duration=$${LATENCY}ms trace_id=$$RANDOM" >> /var/log/app/app.log
          sleep 1
        done
    volumes:
      - app-logs:/var/log/app
    restart: unless-stopped
```

```bash
docker compose up -d log-generator
sleep 5
docker exec log-generator tail -3 /var/log/app/app.log
```

Näed ridu nagu `2026-04-25T10:23:41+03:00 [ERROR] [payment] duration=245ms trace_id=12345`.

### 7.4 Promtail

```bash
cat > config/promtail-config.yml << 'EOF'
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: applog
    static_configs:
      - targets:
          - localhost
        labels:
          job: applog
          __path__: /var/log/app/*.log
EOF
```

Lisa `services:` alla:

```yaml
  promtail:
    image: grafana/promtail:3.2.1
    container_name: promtail
    volumes:
      - ./config/promtail-config.yml:/etc/promtail/config.yml
      - app-logs:/var/log/app:ro
    command: -config.file=/etc/promtail/config.yml
    depends_on:
      - loki
    restart: unless-stopped
```

```bash
docker compose up -d promtail
sleep 10
docker compose logs promtail | tail -5
```

💡 **Kui "context deadline exceeded":** Loki pole veel ready. Oota 15s, `docker restart promtail`.

### 7.5 Grafana

Lisa `services:` alla:

```yaml
  grafana:
    image: grafana/grafana:11.1.0
    container_name: grafana-loki
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=monitoring2026
    volumes:
      - grafana-data:/var/lib/grafana
    restart: unless-stopped
```

```bash
docker compose up -d grafana-loki
```

Brauseris `http://192.168.35.12X:3000` (admin / `monitoring2026`).

*Connections → Data sources → Add → Loki* → URL: `http://loki:3100` → *Save & test* → roheline ✅.

### 7.6 Esimesed read

*Explore* → datasource: Loki → Code view:

```logql
{job="applog"}
```

Run query. Näed ridu tekkima.

💭 **Mõtle:** Promtail loeb faili nagu `tail -f`. Mis juhtub kui fail roteeritakse? Mis on positions-faili roll?

---

## Osa 8 · Pattern parser → rate() → dashboard

### 8.1 Pattern

Meie logirida: `2026-04-25T10:23:41+03:00 [ERROR] [payment] duration=245ms trace_id=12345`

```logql
{job="applog"} | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<_>`
```

Kliki rea peal — näed labeleid `level`, `service`, `duration`.

### 8.2 Filtreeri

```logql
{job="applog"} | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<_>` | level="ERROR" | service="payment"
```

Ainult payment error'id. Proovi ise: näita `api` teenuse logisid kus `duration > 300`.

### 8.3 Label disain — mis on label, mis on sisu?

Meie logis on: `level`, `service`, `duration`, `trace_id`. Pattern parser tegi neist kõigist labelid. Aga kas kõik peaksid olema labelid?

Mõtle:

| Väli | Unikaalseid väärtusi | Label? |
|------|---------------------|--------|
| `level` | 3 (INFO, WARN, ERROR) | ✅ Jah |
| `service` | 5 (payment, auth, api, database, cache) | ✅ Jah |
| `duration` | ~500 erinevat numbrit | ❌ Ei — liiga palju |
| `trace_id` | unikaalne iga rea kohta | ❌ Kindlasti ei |

**Reegel:** label'iks ainult asjad millest on kuni ~100 unikaalset väärtust. Kõik muu jääb sisusse ja otsitakse `|=` või parseri abil.

Mis juhtub kui teed `trace_id` label'iks? Proovi:

```logql
{job="applog"} | pattern `<_> [<_>] [<_>] <_> trace_id=<trace_id>`
```

Loki töötab — aga kujuta ette 10 000 unikaalset trace_id'd. See on 10 000 eraldi voogu. Loki indeks paisub, päringud aeglustuvad. Tootmises = raha ja aeg.

<details>
<summary>🔧 Edasijõudnule: Promtail pipeline stages</summary>

Tootmises ei parsi alati runtime'is. Promtail saab logisid **enne Loki saatmist** töödelda `pipeline_stages` abil:

```yaml
scrape_configs:
  - job_name: applog
    pipeline_stages:
      - regex:
          expression: '\[(?P<level>\w+)\] \[(?P<service>\w+)\]'
      - labels:
          level:
          service:
    static_configs:
      - targets: [localhost]
        labels:
          job: applog
          __path__: /var/log/app/*.log
```

Nüüd `level` ja `service` on **püsivad labelid** Lokis — filter `{level="ERROR"}` kasutab indeksit, mitte brute-force skaneerimist. `duration` ja `trace_id` jäävad sisusse.

See on tootmise vs labi erinevus. Labis parsime runtime'is (lihtsam setup), tootmises Promtail pipeline'is (kiiremad päringud).

</details>

### 8.4 rate() — logist metrika

```logql
sum by (service) (
  rate(
    {job="applog"}
      | pattern `<_> [<level>] [<service>] <_>`
      | level="ERROR"
      [5m]
  )
)
```

Vaheta Time series view — näed graafikut. Logist sai number — sama kontseptsioon mis PromQL `rate()`, aga allikas on tekst.

### 8.5 Dashboard

*Dashboards → New → Add visualization* → Loki datasource:

**Paneel 1:** `ERRORs per service` — eelmine päring, Time series.

**Paneel 2:**
```logql
sum by (level) (count_over_time({job="applog"} | pattern `<_> [<level>] [<_>] <_>` [1m]))
```
Bar chart — logimaht taseme järgi.

Salvesta: `App monitoring`.

### 8.6 FINAAL — sama sündmus, kaks vaatenurka

Nüüd on mõlemad stackid üleval. Tekita error-torm mon-target'il:

```bash
ssh <eesnimi>@192.168.35.140 \
  'for i in $(seq 1 200); do echo "$(date -Iseconds) [ERROR] [payment] Spam_$i" | sudo tee -a /var/log/app/app.log > /dev/null; done'
```

Ava kaks brauseri tabi:

1. **Zabbix:** `http://192.168.35.12X:8080` → *Monitoring → Problems* → `Too many payment errors` trigger **Firing**
2. **Loki Grafana:** `http://192.168.35.12X:3000` → Dashboard `App monitoring` → payment error spike graafikul

Sama sündmus, kaks perspektiivi. Zabbix ütleb **"on probleem"** (trigger). Loki näitab **"mis juhtus"** (logid + rate).

💭 **Lõpureflektsioon:** Sul on nüüd kolm tööriista — Prometheus (metrikad, pull), Zabbix (agent, push), Loki (logid). Millist probleemi oma tööst lahendaksid nendega esimesena? Kas näed olukorda kus kaks neist töötaksid kõrvuti?

---

## ✅ Lõpukontroll

**Zabbix:**

- [ ] `docker compose ps` (`~/paev2/zabbix/`) — 4 konteinerit Up
- [ ] docker-agent ja mon-target availability roheline
- [ ] Dashboard näitab mõlema host'i graafikuid
- [ ] nginx-web HTTP Agent item tagastab stub_status, dependent item numbri
- [ ] `zabbix_get -k "applog.errors[payment]"` tagastab numbri
- [ ] Payment errors trigger läks Firing ja lahenes
- [ ] Honeypot trigger Firing kui keegi ühendus port 2222-le

**Loki:**

- [ ] `docker compose ps` (`~/paev2/loki/`) — 4 konteinerit Up
- [ ] Grafana Loki datasource roheline
- [ ] Explore näitab `{job="applog"}` logisid
- [ ] Pattern parser ekstraheerib level, service, duration
- [ ] Dashboard `App monitoring` salvestatud, vähemalt 2 paneeli
- [ ] FINAAL: error-torm nähtav Zabbixi Problems lehel JA Loki graafikul

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

---

### Loki: Nginx accesslog + RED

Lisa `log-generator` konteinerisse nginx-stiilis accesslog genereerimine. Lisa Promtail konffi `job: nginx`. Ehita RED dashboard:
- `rate()` — päringuid sekundis
- `status =~ "5.."` — error rate
- `sum by (path)` — per path

### Log-based alert

Grafana → *Alerting → Alert rules → New* → Loki query `rate({job="applog"} | pattern ... | level="ERROR" | service="payment" [2m])` → threshold > 0.1 → Contact point: Discord.

### Correlation — metric → log

Dashboard paneelis *Data links → Add link* mis viib Explore vaatesse sama teenuse Loki logidele. Ühe klikiga graafikult logidesse.

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


??? note "Loki: retention, multi-tenancy ja S3 storage"

    Tootmises ei hoia logisid lõputult kohalikul kettal.

    **Retention (logide eluiga):**

    `loki-config.yml`:

    ```yaml
    limits_config:
      retention_period: 168h    # 7 päeva

    compactor:
      working_directory: /loki/compactor
      retention_enabled: true
      delete_request_store: filesystem
    ```

    **Multi-tenancy (mitme meeskonna logid eraldi):**

    `loki-config.yml`:

    ```yaml
    auth_enabled: true
    ```

    Promtail saadab `X-Scope-OrgID` header'i:

    ```yaml
    clients:
      - url: http://loki:3100/loki/api/v1/push
        tenant_id: team-backend
    ```

    Grafana datasource'is: HTTP Headers → `X-Scope-OrgID: team-backend`.

    Iga meeskond näeb ainult oma logisid.

    **S3/MinIO storage (tootmises):**

    ```yaml
    common:
      storage:
        s3:
          endpoint: minio:9000
          bucketnames: loki-chunks
          access_key_id: minioadmin
          secret_access_key: minioadmin
          insecure: true
          s3forcepathstyle: true
    ```

    **Loe edasi:**

    - [Loki retention](https://grafana.com/docs/loki/latest/operations/storage/retention/)
    - [Multi-tenancy](https://grafana.com/docs/loki/latest/operations/multi-tenancy/)
    - [S3 storage](https://grafana.com/docs/loki/latest/storage/)

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
| Loki "no labels found" | `{job="applog"}` — peab vastama Promtail config'ile |
| Loki "too many streams" | Label on liiga unikaalne (trace_id). Eemalda. |
| Promtail deadline exceeded | Loki pole ready — `docker restart promtail` |
| Grafana Loki datasource punane | URL peab olema `http://loki:3100`, mitte `localhost` |
| rate() tagastab 0 | Time range liiga kitsas — vaheta "Last 15 min" |
| Mõlemad stackid aeglased | `free -h` — 4GB piir. Peata üks ajutiselt kui vaja. |

---

## 📚 Allikad

| Allikas | URL |
|---------|-----|
| Zabbix 7.0 manuaal | [zabbix.com/documentation/7.0](https://www.zabbix.com/documentation/7.0/en/manual) |
| UserParameters | [zabbix.com/.../userparameters](https://www.zabbix.com/documentation/7.0/en/manual/config/items/userparameters) |
| Low-Level Discovery | [zabbix.com/.../low_level_discovery](https://www.zabbix.com/documentation/7.0/en/manual/discovery/low_level_discovery) |
| HTTP Agent | [zabbix.com/.../http](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/http) |
| Loki dokumentatsioon | [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/) |
| LogQL spetsifikatsioon | [grafana.com/.../query](https://grafana.com/docs/loki/latest/query/) |
| Pattern parser | [grafana.com/.../pattern](https://grafana.com/docs/loki/latest/query/log_queries/#pattern) |
| LogQL simulator | [grafana.com/.../analyzer](https://grafana.com/docs/loki/latest/query/analyzer/) |
| Discord integration | [zabbix.com/integrations/discord](https://www.zabbix.com/integrations/discord) |

**Versioonid:** Zabbix 7.0.6 LTS, MySQL 8.0, Loki 3.2.1, Promtail 3.2.1, Grafana 11.1.0.
