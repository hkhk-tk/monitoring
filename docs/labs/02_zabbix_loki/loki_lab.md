# Päev 2 osa 2: Loki — Labor

**Kestus:** 4 tundi
**Tase:** Keskaste
**VM:** sinu isiklik VM (nt `ssh kaarel@192.168.35.121`)

---

## 🎯 Õpiväljundid

Pärast selle labi läbimist õpilane:

**Teadmised:**

1. Selgitab Loki rolli LGTM stackis ja erinevust Elasticsearchist (indekseerimise lähenemine)
2. Eristab labelid ja logi sisu — ning miks see eristus on oluline
3. Kirjeldab Promtail → Loki → Grafana andmevoogu

**Oskused:**

4. Kirjutab põhilisi LogQL päringuid — filter, regex, label-filter
5. **Parsib struktureerimata logi `pattern` parseriga** ja ekstraheerib labelid
6. **Teisendab logi metrikaks** (`rate`, `count_over_time`, `sum by`) ja visualiseerib Grafana graafikul
7. **Seadistab log-based alert'i** mis käivitub mustri, mitte numbri põhjal
8. Navigeerib Grafana'as metric → log → vaate vahel (correlation)

---

## Meie keskkond

> **Loengust:** Loki indekseerib ainult labeleid, mitte kogu logi sisu. See teeb teda odavaks (disk, RAM) kuid samas sunnib planeerima labeleid hoolikalt. Elasticsearch indekseerib kõike → kiire otsing, kallis hoidla.

Sama infrastruktuur. Loki stack jookseb sinu VM-i peal kõrvuti (või asemel) Zabbix stackile.

| Masin | IP | Mis jookseb |
|-------|-----|-------------|
| **Sinu VM** | 192.168.35.12X | Docker — Loki stack (ehitad täna) |
| **mon-target** | 192.168.35.140 | Logi-generaator `/var/log/app/app.log` |
| **mon-target-web** | 192.168.35.141 | Nginx accesslog |

---

## Osa 1: LogQL simulator — brauseris, ilma Dockerita (15 min)

> **Loengust:** Enne Dockeri käivitamist — tutvume LogQL süntaksiga online tööriistas. See aitab süsteemipäringut tajuda enne, kui peame oma logisid selle alla seadma.

### 1.1 Ava simulator

Ava brauseris: <https://grafana.com/docs/loki/latest/query/analyzer/>

Näed kolme paneeli:
- **Example Log Lines** (vasakul) — näidislogid
- **Log Query** (keskel) — siia kirjutad LogQL
- **Log Query Results** (paremal) — vastus

### 1.2 Esimene filter — `|=` (sisaldab)

Vali paneelilt **logfmt** formaat. Kirjuta päring:

```logql
{job="analyze"} |= "error"
```

Vajuta **Run query**.

💡 **Mida näed?** Tulemuste paneelis on rohelised read (sobivad) ja hallid (ei sobi). Kliki rea peale — näed põhjendust.

### 1.3 Ekstraheeri labelid — `| logfmt`

Meie näidislogid on `key=value` formaadis. Parser `logfmt` ekstraheerib iga võtme labeliks.

```logql
{job="analyze"} | logfmt | level = "error"
```

Erinevus eelmisest — nüüd **parsisime** logi ja filtreerisime **väärtustatud labeli** järgi, mitte tekstiotsingu järgi.

### 1.4 JSON parser

Vali **json** näidisformaat. Kirjuta:

```logql
{job="analyze"} | json | status_code = "500"
```

### 1.5 Pattern parser — töö sellega

Vali **unstructured** formaat. Siin on logid mis ei ole JSON ega logfmt — vabatekst.

Kasuta `pattern` parseri süntaksit — defineeri mall, `<name>` on püütav, `<_>` on ignoreeritav:

```logql
{job="analyze"} | pattern `<_> <user> <_>`
```

Näed, et ekstraheeriti label `user`. Proovi filtreerida:

```logql
{job="analyze"} | pattern `<_> <user> <_>` | user =~ "kling.*"
```

🎉 **See ongi eesmärk** — paari tunni pärast teed sama enda logidega oma VM-is.

⚡ **Kiirkontroll — vasta:**

- Mis on erinevus `|=` ja `| json ... = "..."` vahel?
- Mis on `<_>` pattern-is?

---

## Osa 2: Loki + Promtail stack (30 min)

### 2.1 Puhasta eelmine stack

Päev 2 Zabbix stack võtab ära palju RAM-i. Peata see (volumes jäävad alles, kui tahad naasta):

```bash
cd ~/paev2
docker compose down
```

### 2.2 Uus töökaust

```bash
mkdir -p ~/paev2-loki/config
cd ~/paev2-loki
```

### 2.3 Loki konfiguratsioon

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

ruler:
  alertmanager_url: http://localhost:9093

limits_config:
  allow_structured_metadata: true
EOF
```

### 2.4 Promtail konfiguratsioon

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
  # Kõigi Docker konteinerite logid
  - job_name: docker
    static_configs:
      - targets:
          - localhost
        labels:
          job: docker
          __path__: /var/lib/docker/containers/*/*-json.log

  # App logi
  - job_name: applog
    static_configs:
      - targets:
          - localhost
        labels:
          job: applog
          __path__: /var/log/app/*.log

  # Nginx accesslog (simuleeritud)
  - job_name: nginx
    static_configs:
      - targets:
          - localhost
        labels:
          job: nginx
          __path__: /var/log/nginx/access.log
EOF
```

### 2.5 docker-compose.yml

```bash
cat > docker-compose.yml << 'EOF'
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

  promtail:
    image: grafana/promtail:3.2.1
    container_name: promtail
    volumes:
      - ./config/promtail-config.yml:/etc/promtail/config.yml
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - app-logs:/var/log/app:ro
      - nginx-logs:/var/log/nginx:ro
    command: -config.file=/etc/promtail/config.yml
    depends_on:
      - loki
    restart: unless-stopped

  grafana:
    image: grafana/grafana:11.1.0
    container_name: grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=monitoring2026
      - GF_AUTH_ANONYMOUS_ENABLED=false
      - GF_FEATURE_TOGGLES_ENABLE=traceqlEditor
    volumes:
      - grafana-data:/var/lib/grafana
    restart: unless-stopped

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
        METHODS="GET GET GET POST PUT DELETE"
        PATHS="/api/users /api/orders /api/products /health /login"
        STATUSES="200 200 200 200 200 301 400 404 500 503"
        while true; do
          # App log (structured-ish)
          S=$$(echo $$SERVICES | tr " " "\n" | shuf -n1)
          L=$$(echo $$LEVELS | tr " " "\n" | shuf -n1)
          LATENCY=$$((RANDOM % 500))
          echo "$$(date -Iseconds) [$$L] [$$S] duration=$${LATENCY}ms trace_id=$$RANDOM" >> /var/log/app/app.log

          # Nginx-like access log
          M=$$(echo $$METHODS | tr " " "\n" | shuf -n1)
          P=$$(echo $$PATHS | tr " " "\n" | shuf -n1)
          ST=$$(echo $$STATUSES | tr " " "\n" | shuf -n1)
          BYTES=$$((RANDOM % 10000))
          RT=$$(echo "scale=3; $$RANDOM/32768" | awk '{printf "%.3f\n", $$1/1}')
          echo "192.168.35.$$((RANDOM % 254 + 1)) - - [$$(date +%d/%b/%Y:%H:%M:%S)] \"$$M $$P HTTP/1.1\" $$ST $$BYTES \"-\" \"curl/7.68.0\" rt=$$RT" >> /var/log/nginx/access.log

          sleep 1
        done
    volumes:
      - app-logs:/var/log/app
      - nginx-logs:/var/log/nginx
    restart: unless-stopped

volumes:
  loki-data:
  grafana-data:
  app-logs:
  nginx-logs:
EOF
```

### 2.6 Käivita

```bash
docker compose up -d
sleep 30
docker compose ps
```

Kõik neli konteinerit peavad olema `Up`.

### 2.7 Grafana + Loki datasource

Ava: `http://192.168.35.12X:3000` (admin / `monitoring2026`)

1. Vasak menüü → *Connections* → *Data sources* → *Add data source*
2. Otsi *Loki*
3. URL: `http://loki:3100`
4. *Save & test* → roheline ✅

### 2.8 Esimesed read

Vasak menüü → *Explore*. Valige datasource Loki.

Logi otsuseke väli (Code view) → kirjuta:

```logql
{job="applog"}
```

**Run query**. Peaksid nägema ridu tekkima. Iga rida on `YYYY-MM-DDTHH:MM:SS+03:00 [LEVEL] [service] duration=123ms trace_id=45678`.

⚡ **Kiirkontroll:** Vaheta `{job="applog"}` → `{job="nginx"}`. Näed nginx-stiilis ridu (`192.168... GET /api/users HTTP/1.1 200`).

---

## Osa 3: LogQL alused (45 min)

> **Loengust:** Kaks etappi iga LogQL päringus — **label selector** `{...}` valib voo, **log pipeline** `| ...` filtreerib/parsib selle voo sees. Cardinality lõks: **ära pane labelitesse asju mis on unikaalsed** (user_id, trace_id, URL path). Kõik mis on unikaalne, kuulub sisusse.

### 3.1 Filter: sisaldab ja ei sisalda

```logql
{job="applog"} |= "ERROR"
{job="applog"} |= "ERROR" != "cache"
```

`|=` = sisaldab substring'i. `!=` = ei sisalda.

### 3.2 Regex — `|~` ja `!~`

```logql
{job="applog"} |~ "\\[WARN\\]|\\[ERROR\\]"
{job="nginx"} |~ "HTTP/1.1\" 5\\d\\d"
```

`|~` = sisaldab regex'i (RE2 süntaksiga).

### 3.3 Labels-esimene, filter-teine

**Halb:**

```logql
{job=~".+"} |= "payment"
```

See läheb läbi kõigi voogude — aeglane, koormab Loki.

**Hea:**

```logql
{job="applog"} |= "payment"
```

Label selector peab olema **nii kitsas kui võimalik**. Filter peale seda.

💡 **Cardinality lõks:** Ahvatlev oleks luua label `trace_id` iga trace jaoks. Aga trace'e on tuhandeid → tuhat unikaalset voogu → Loki muutub aeglaseks. **Label = midagi, millest pole rohkem kui ~100 unikaalset väärtust.**

Näiteid hea label-iks: `service` (5 väärtust), `level` (3 väärtust), `env` (2-3 väärtust).
Näiteid halva labeliks: `trace_id`, `user_id`, `request_id`, `path`.

### 3.4 Line filtering — ahelas

```logql
{job="applog"} |= "ERROR" |= "payment" != "test"
```

Iga `|=` / `!=` on järjekordne filter. Kõik peavad sobima.

⚡ **Kiirkontroll — kirjuta LogQL päring:**

- Näita ainult `WARN` ridu teenusest `auth`
- Näita ridu mis sisaldavad numbrilist duration > 3-kohaline (st 100ms+) — regex'iga

<details>
<summary>Vastused</summary>

```logql
{job="applog"} |= "[WARN]" |= "[auth]"
{job="applog"} |~ "duration=\\d{3,}ms"
```

</details>

---

## Osa 4: Pattern parser — parse strukturimata logi (50 min)

> **Loengust:** Logi read on **vabatekst**. Kuni sa ei parsi, ei saa küsida "mis on keskmine duration `payment` teenuses". Parser teisendab logi struktureerituks — labeliteks.

Loki pakub 4 parserit: `json`, `logfmt`, `regexp`, `pattern`. **Pattern** on tavaliselt parim strukturimata logi jaoks — kiire, loetav, piisavalt võimas.

### 4.1 Vaata logi formaati

```logql
{job="applog"}
```

Näide rida:
```
2026-04-25T10:23:41+03:00 [ERROR] [payment] duration=245ms trace_id=12345
```

Me tahame ekstraheerida: `level` (ERROR), `service` (payment), `duration` (245ms), `trace_id` (12345).

### 4.2 Esimene pattern

`pattern` parser võtab mall-stringi. `<name>` on captured label, `<_>` on ignored.

```logql
{job="applog"} | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<trace_id>`
```

Kliki mõnel real → avane näed et igaühel on nüüd labelid `level`, `service`, `duration`, `trace_id`.

### 4.3 Filtreeri parsed label järgi

```logql
{job="applog"} | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<trace_id>` | level="ERROR"
```

Nüüd võrdlus `|= "ERROR"` vs `| level="ERROR"`:

- `|= "ERROR"` otsib teksti `ERROR` kõikjalt reas — võib eksida, nt kui sõnumis on sõna "Error" teisel kohal
- `| level="ERROR"` kontrollib täpselt ekstraheeritud labelit — turvalisem

### 4.4 Keeruline filter

Leia `payment` teenuse `ERROR` read kus duration > 100:

```logql
{job="applog"}
  | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<_>`
  | level="ERROR"
  | service="payment"
  | duration > 100
```

💡 **Numbriline võrdlus töötab** kuigi duration parsitud tekstist — Loki teisendab automaatselt.

### 4.5 Line format — ilusamad read

Loki saab ka ümber formateerida kuidas logi näeb välja UI-s.

```logql
{job="applog"}
  | pattern `<ts> [<level>] [<service>] duration=<duration>ms trace_id=<trace_id>`
  | line_format "[{{.service}}] {{.level}} took {{.duration}}ms"
```

### 4.6 Alternatiiv — `regexp` parser

`pattern` on kiire ja loetav, aga kui formaat on keerulisem, tuleb regex:

```logql
{job="applog"}
  | regexp `^(?P<ts>\S+) \[(?P<level>\w+)\] \[(?P<service>\w+)\] duration=(?P<duration>\d+)ms`
  | level="ERROR"
```

Võrdle — pattern (lihtne, 1 rida) vs regex (keerulisem, named groups). **Kasuta pattern'it kui võimalik.**

⚡ **Kiirkontroll:**

- Kirjuta päring mis näitab ainult `api` teenuse logisid kus duration > 300ms.
- Kasuta pattern parserit.

<details>
<summary>Vastus</summary>

```logql
{job="applog"}
  | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<_>`
  | service="api"
  | duration > 300
```

</details>

---

## Osa 5: rate() logist — logi kui metrika allikas (35 min)

> **Loengust:** Logid ei pea jääma logideks. Loki saab loendada read, arvutada rate'i, grupeerida labeliks — sama mis Prometheus PromQL. Allikas on lihtsalt erinev: logi, mitte `/metrics`.

### 5.1 `rate()` — mitu rida sekundis

```logql
rate({job="applog"} |= "ERROR" [5m])
```

Tulemuseks on **number sekundis** — mitu ERROR rida tuli viimase 5 minuti keskmisena.

Kliki **Time series** view ülal — näed graafikut ajas.

### 5.2 `count_over_time` — mitu viimase ajavahemikuga

```logql
count_over_time({job="applog"} |= "ERROR" [1m])
```

Sama kui rate, aga tagastab absoluutse arvu, mitte sekundi kohta.

### 5.3 `sum by` — grupeeri

Nüüd ühendame labelid + metrika. Mitu ERROR rida sekundis **iga teenuse kohta** eraldi:

```logql
sum by (service) (
  rate({job="applog"} [5m])
    |> pattern `<_> [<_>] [<service>] <_>`
)
```

Hmm, see süntaks pole päris — `|>` pole Loki's. Õige süntaks on:

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

Time series view'is näed eraldi jooni iga teenuse kohta.

### 5.4 Top 3 probleemset teenust

```logql
topk(3,
  sum by (service) (
    rate(
      {job="applog"}
        | pattern `<_> [<level>] [<service>] <_>`
        | level="ERROR"
        [5m]
    )
  )
)
```

### 5.5 Lisa Grafana dashboardile

Grafana → *Dashboards* → *New* → *Add visualization* → Loki datasource.

Paneel 1:
- Query: `sum by (service) (rate({job="applog"} | pattern <kleebi> | level="ERROR" [5m]))`
- Visualization: **Time series**
- Title: `ERRORs per service`

Paneel 2:
- Query: `sum by (level) (count_over_time({job="applog"} | pattern <kleebi> [1m]))`
- Visualization: **Bar chart**
- Title: `Log volume by level`

Salvesta dashboard: `App monitoring`.

🎉 **Sa teisendasid logid metrikateks graafikule** — sama tulemus nagu Prometheus'is, aga allikas oli logi fail.

---

## Osa 6: Nginx accesslog — RED metrikad (30 min)

> **Loengust:** RED meetod — Rate, Errors, Duration. See on klassikaline viis veebiteenust jälgida. Tavaliselt teeme seda `/metrics` endpoint'i pealt. Aga kui sul pole endpoint'i — saab sama logi pealt.

### 6.1 Vaata nginx logi

```logql
{job="nginx"}
```

Näide:
```
192.168.35.42 - - [25/Apr/2026:10:23:41] "GET /api/users HTTP/1.1" 200 4523 "-" "curl/7.68.0" rt=0.245
```

### 6.2 Pattern nginx formaadile

```logql
{job="nginx"} | pattern `<ip> <_> <_> [<ts>] "<method> <path> <_>" <status> <bytes> <_> <_> rt=<rt>`
```

### 6.3 Rate — päringuid sekundis

```logql
sum(rate({job="nginx"} [1m]))
```

Kogu liiklus.

Päringuid sekundis **per path**:

```logql
sum by (path) (
  rate(
    {job="nginx"}
      | pattern `<_> <_> <_> [<_>] "<_> <path> <_>" <_> <_> <_> <_> <_>`
      [1m]
  )
)
```

### 6.4 Errors — 5xx rate

```logql
sum(rate(
  {job="nginx"}
    | pattern `<_> <_> <_> [<_>] "<_> <_> <_>" <status> <_> <_> <_> <_>`
    | status =~ "5.."
    [5m]
))
```

### 6.5 Dashboardile

Lisa dashboard'ile kolm paneeli:
- `Requests per second` — kogu rate
- `5xx errors per second` — error rate
- `Requests by path` — sum by (path)

🎉 **Sa ehitasid RED dashboardi pelgalt logist.** Mingeid eksportere ei olnud vaja.

---

## Osa 7: Log-based alert (30 min)

> **Loengust:** Prometheus alert käib numbrilt. Loki alert käib tekstilt — aga enne tuleb tekst **numbriks teisendada**. See on täpselt see samm mida me just tegime `rate()`-ga. Alert rule ütleb "kui see number on > X, käivitu".

### 7.1 Grafana Unified Alerting

Vasak menüü → *Alerting* → *Alert rules* → *+ New alert rule*.

| Väli | Väärtus |
|------|---------|
| Name | `Payment error rate too high` |
| Folder | Loo uus: `App alerts` |
| Evaluation group | Loo uus: `app`, interval `1m` |

**A query** (Grafana alerting käitub nii, et A on data query, B on treshold):

- Data source: Loki
- Query:
```logql
sum(rate(
  {job="applog"}
    | pattern `<_> [<level>] [<service>] <_>`
    | level="ERROR"
    | service="payment"
    [2m]
))
```

**Expression B** (threshold):

- Operation: `Threshold`
- Input: `A`
- Condition: `Is above 0.1` (st > 0.1 ERROR sekundis = > 6/min)

**Alert condition:** `B`

**Alert evaluation behavior:**
- Evaluate every `1m`
- For `2m`

**Labels:**
- `severity` = `warning`

### 7.2 Testi alert

Tekita error-torm:

```bash
docker exec log-generator sh -c '
for i in $(seq 1 100); do
  echo "$(date -Iseconds) [ERROR] [payment] Payment_failed duration=100ms trace_id=spam$i" >> /var/log/app/app.log
done'
```

⏱️ **Oota 2-3 min.**

*Alerting* → *Alert rules* — `Payment error rate too high` peaks minema **Firing** olekusse.

Pane tähele olekute progressi:
- `Normal` — kõik OK
- `Pending` — tingimus kehtib, aga `For:` aeg pole möödas
- `Firing` — käivitunud

### 7.3 Contact point

Alert ilma kontaktita ei tee midagi. Lisa üks.

*Alerting* → *Contact points* → *+ Add contact point*.

| Väli | Väärtus |
|------|---------|
| Name | `My Slack` |
| Integration | `Slack` |
| Webhook URL | (koolitaja annab, sama mis Zabbix osa 7) |

*Save contact point* → *Test*.

### 7.4 Ühenda alert contact'iga

*Alerting* → *Notification policies* → *New policy* → Labels `severity = warning` → Contact point `My Slack`.

🎉 **Alert pipeline lõpetatud:** logirida → parsing → rate → threshold → Slack. Ilma Prometheus'eta, ainult teksti põhjal.

---

## Osa 8: Correlation — üks klikk, 3 vaadet (15 min)

> **Loengust:** Grafana ei ole ainult graafik — ta on **ühenduslüli** tööriistade vahel. Dashboardi paneelis olevatel punktidel on "data links" mis viivad teise datasource'i, samale ajale, samale kontekstile.

### 8.1 Loo seos

Ava dashboard `App monitoring` (osa 5-st).

Paneel `ERRORs per service` → *Edit* → *Data links* → *+ Add link*:

| Väli | Väärtus |
|------|---------|
| Title | `Open logs for this service` |
| URL | `/explore?left=["now-1h","now","Loki",{"expr":"{job=\"applog\"} \| pattern \`<_> [<_>] [<service>] <_>\` \| service=\"${__series.name}\""}]` |

⚠️ **See URL on pikk ja keeruline.** Alternatiiv lihtsaim variant:

Paneel → *Edit* → *Options* tab → *Data links* → lisa link kus URL viib `/explore` ja `expr` parameeter teeb päringu. Tavaliselt kopeerid URL juba avatud Explore'ist ja modifitseerid.

### 8.2 Kasuta correlation'it

Dashboardil → kliki mõnel Time series joonel → *Open logs for this service*. Grafana avab Explore vaate Loki päringuga mis filtreerib samale teenusele, samale ajaperioodile.

See on **metric → log** tee. Ühe klikiga.

### 8.3 Ära näita veel — päev 5 teaser

Samamoodi tuleb päev 5 juurde **trace → log** tee. Tempo'ga. Selleks peab logi sisse märkima `trace_id` — mida meie log-generator juba teeb! Pane tähele logi:

```
2026-04-25T... [INFO] [payment] duration=123ms trace_id=45678
```

Päev 5-s kasutame seda `trace_id`-d, et logidest hüppada trace'i sisse ja vastupidi. Nüüd lihtsalt teadmiseks — sellepärast on seal.

---

## ✅ Lõpukontroll

- [ ] `docker compose ps` — 4 konteinerit Up
- [ ] Grafana Loki datasource roheline
- [ ] Explore näitab nii `applog` kui `nginx` logisid
- [ ] Oled parsinud app.log pattern parseriga ja näinud labeleid (level, service)
- [ ] Dashboard `App monitoring` on salvestatud, vähemalt 2 paneeli
- [ ] Alert `Payment error rate too high` nähtud Firing olekus
- [ ] Slack sõnum jõudis kohale
- [ ] Oled kasutanud data link'i dashboardilt Explore'i

---

## 🚀 Lisaülesanded

### Derived fields — trace_id klikkimiseks

Grafana Loki datasource konfis saab lisada *Derived fields*. Kui logirida sisaldab `trace_id=45678`, Grafana muudab numbri klikitavaks.

- *Connections* → *Data sources* → Loki → *Derived fields* → *Add*
- Name: `trace_id`
- Regex: `trace_id=(\w+)`
- URL: `http://localhost:3200/trace/${__value.raw}` (või lihtsalt `#${__value.raw}` testiks)

### Mitme-allika dashboard

Tee dashboard kus on:
- Paneel 1: Prometheus `rate(node_cpu_seconds_total[5m])` (päev 1 stack'ist)
- Paneel 2: Loki `rate({job="applog"} |= "ERROR" [5m])`
- Paneel 3: Mõlemad samas graafikus

### Loki ruler — alert ilma Grafana Unified Alerting'ita

Grafana Unified Alerting on mugav, aga päris Loki'l on oma alert engine — **ruler**. Konfiguratsioon on YAML-failides, sobib paremini GitOps'iga.

Vt: <https://grafana.com/docs/loki/latest/operations/recording-rules/>

### Oma rakendus

Vali üks asi oma tööelust. Kirjuta Promtail config mis selle logid scrapib. Tee Grafana paneel millel on mingi asjakohane näitaja.

---

## Veaotsing

| Probleem | Lahendus |
|----------|----------|
| Explore ei näita logisid | Oota 30 sek et Promtail jõuab esimesed read lugeda |
| `no labels found` | Kontrolli `{job="applog"}` — `job` peab vastama Promtail config'ile |
| Pattern ei parsi | Testi samm-sammult — lisa ühe `<label>` korraga |
| `too many streams` viga | Sa lõid label-i mis on liiga unikaalne (nt trace_id). Eemalda. |
| Rate tagastab 0 | Time range tagant (parem ülal) peab mahutama sobiva akna. Vaheta "Last 15 min". |
| Alert ei lähe Firing'iks | Oota `For:` aeg. Kontrolli Query tulemust Expression B threshold'i vastu. |
| Grafana ei näe Loki'd | URL peab olema `http://loki:3100` (DNS), mitte `localhost` |
| Nginx logi tühi | `docker exec log-generator ls /var/log/nginx/` — kas access.log seal? |

---

## 📚 Allikad

| Allikas | URL |
|---------|-----|
| Loki dokumentatsioon | https://grafana.com/docs/loki/latest/ |
| LogQL spetsifikatsioon | https://grafana.com/docs/loki/latest/query/ |
| LogQL online simulator | https://grafana.com/docs/loki/latest/query/analyzer/ |
| Pattern parser süntaks | https://grafana.com/docs/loki/latest/query/log_queries/#pattern |
| Promtail konfig | https://grafana.com/docs/loki/latest/send-data/promtail/configuration/ |
| Grafana Unified Alerting | https://grafana.com/docs/grafana/latest/alerting/ |
| LogQL näited (cheatsheet) | https://github.com/ruanbekker/cheatsheets/tree/master/loki/logql |

**Versioonid (testitud, aprill 2026):**

- Loki: `3.2.1`
- Promtail: `3.2.1`
- Grafana: `11.1.0`
