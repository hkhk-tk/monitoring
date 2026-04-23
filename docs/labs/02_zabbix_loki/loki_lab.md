# Päev 2 · Labor: Loki

**Kestus:** ~2 tundi (pool päev 2 laborist)  
**Tase:** Keskaste  
**VM:** Sama VM nagu Zabbix laboris (`ssh <eesnimi>@192.168.35.12X`)  
**Eeldused:** [Labor: Zabbix](zabbix_lab.md) läbitud (Zabbix stack, mon-target host, payment errors trigger). [Päev 2: Loki loeng](../../materials/lectures/paev2-loki-loeng.md) loetud.

Labor jätkab sealt, kus Zabbix osa lõppes — Zabbix stack jääb taustale, Loki stack lisandub kõrvale.

---

## 🎯 Õpiväljundid

**Teadmised:**

1. Selgitab Loki rolli LGTM stackis ja labelite vs sisu indekseerimise erinevust
2. Eristab LogQL parserite kasutusolukordi (pattern, json, logfmt, regexp)
3. Põhjendab label-disaini reegleid kardinaalsuse piiri kontekstis

**Oskused:**

4. Ehitab Loki + Alloy + Grafana stack'i Docker Compose'iga
5. Kirjutab LogQL päringuid ja parsib struktureerimata logi
6. Teisendab logi metrikaks (`rate()`, `count_over_time`) ja ehitab dashboard'i
7. Vaatab sama sündmust kahest vaatenurgast — Zabbix trigger + Loki graafik

---

## Eeltöö

Kontrolli et Zabbix stack on eelmisest osast üleval:

```bash
cd ~/paev2/zabbix && docker compose ps
```

Neli konteinerit `Up`. Kui ei, [mine tagasi Zabbix labi juurde](zabbix_lab.md).

---

Zabbix ütles "trigger Firing" — on probleem. Aga **mida** täpselt? Logid vastavad sellele. Lokiga tood logid Grafanasse — SSH + grep asemel LogQL päringud brauseris.

---

## Osa 6 · LogQL — brauseris ja päriselt

Enne oma stacki ehitamist prooviks LogQL-i Grafana ametlikul simulatoril. Eelis: tulemused on kohesed, ei pea ootama Loki käivitust. Harjutame 4 parserit (logfmt, pattern, json + filter `|=`) üksteise järel.

### 6.1 Simulator — täisteksti filter

Ava brauseris: <https://grafana.com/docs/loki/latest/query/analyzer/>

Vali **logfmt** formaat. Kirjuta:

```logql
{job="analyze"} |= "error"
```

Run query. Rohelised read sobivad, hallid ei sobi.

**Mis juhtus:** `{job="analyze"}` valib voog ja `|=` on täistekstifilter — sarnane `grep -i "error"`-iga. Lihtne ja kiire, aga **ei eristu** INFO-tasemega reast, kus sisus on sõna "error". Iga rida, kus esineb tähistring "error", võidab.

### 6.2 Ekstraheeri labelid (logfmt parser)

```logql
{job="analyze"} | logfmt | level = "error"
```

Erinevus — nüüd **parsisid** logi ja filtreerisid **labeli** järgi, mitte tekstiotsingu järgi.

**Miks see parem:** logfmt on vorming `level=error service=auth duration=42ms`. Parser teeb `level` järgi filtri semantiliselt — üle jääb ainult INFO-rida, kus sisus kogemata sõna "error". Filter on täpsem.

### 6.3 Pattern parser (struktureerimata tekst)

Vali **unstructured** formaat:

```logql
{job="analyze"} | pattern `<_> <user> <_>` | user =~ "kling.*"
```

`<_>` ignoreerib, `<user>` püüab labeli.

**Miks pattern oluline:** mitmed tootmises olevad logid **ei ole** logfmt ega JSON kujul. Apache access log, Nginx error log, Tomcat catalina.out — kõik vabas vormis. Pattern ütleb "selles kohas oota sõna, selles kohas ignore" ja teeb labelid struktureerimata stringist.

### 6.4 JSON parser

Vali **json** formaat:

```logql
{job="analyze"} | json | status_code = "500"
```

**Miks parser valida sobiv logiformaadiga:** kui logi on JSON, parseri `| json` paneb iga välja otse labeliks — nested `.user.id` kuulub `user_id` labelina. Vale parser (`logfmt` JSON-iga) ei suuda struktureerida — tulemus on pettumus.

Neli parserit — `json`, `logfmt`, `pattern`, `regexp`. `pattern` on enim kasutatav kuna enamik logisid on vabatekst. `regexp` on viimane samuraide valik — töötab alati, aga on aeglasem ja veaohtlikum kui pattern.

💭 **Mõtle:** Sinu töö logid — mis formaadis need on? Millist parserit kasutaksid?

---

## Osa 7 · Loki + Alloy stack

Nüüd ehitame oma stacki. Sama lähenemine mis Zabbix labis — kiht-kihi haaval, iga kiht testitud eraldi enne järgmise lisamist. Stack koosneb 4 komponendist: **Loki** (kirjutab ja otsib logisid), **log-generator** (tekitab test-logi), **Alloy** (loeb logifaili ja saadab Lokisse), **Grafana** (UI).

```bash
mkdir -p ~/paev2/loki/config && cd ~/paev2/loki
```

!!! info "Agent valik — Alloy"
    Kasutame tänavust ametlikku soovitust — **Grafana Alloy**. Promtail, mis Loki pärinud 2018 aastast, on tänaseks **feature-freeze** olekus (vt Loki loeng §10). Alloy on universaalne telemeetria-kollektor: sama agent saab koguda logid (Lokile), mõõdikud (Prometheusele/Mimirile), traces (Tempo'le) ja OpenTelemetry-ühilduvatele backendidele. Selle laboris hoiame selle lihtsa kujul — ainult logide osa.

### 7.1 Loki konfiguratsioon

Esmalt kirjutame Loki enda konfi. Loki vajab teadmisi: kuhu salvestada (filesystem, S3), millise skeemi versiooniga (v13 on praegune), kas autentimine on olemas. Laboris kasutame kõige lihtsamat varianti — lokaalne filesystem, auth väljas, single-node.

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

**Mida see konfig ütleb:**
- `auth_enabled: false` — single-tenant, kogu Loki on üks "nimi"
- `common.storage.filesystem` — logi-trükid (chunks) salvestatakse `/loki/chunks` kausta, mis on konteineri volume
- `schema v13` — praegune stabiilne skeem (aprill 2026). Vanemates tutorialides näed `v11` või `boltdb-shipper` — need on vananenud
- `allow_structured_metadata: true` — Loki 3.x feature (structured metadata), lubatud tootmises.

Tootmises oleks S3 asemel filesystem, auth sisse lülitatud, replikatsioonifaktor >1.

### 7.2 Loki teenus

Loo `docker-compose.yml`:

```yaml
services:
  loki:
    image: grafana/loki:3.3.0
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

**Miks nimelised volumes, mitte bind mounts:** `loki-data` on Docker volume — need elavad Dockeri hallatavas asukohas ja säilivad `docker compose down` järel. Kui kasutaksid `./data:/loki`, satuksid logid sinu paev2 kausta, mis võib kasvada mahuliselt ja juhuslikult saada git'i pandud.

Käivita ja testi:

```bash
docker compose up -d loki
sleep 10
curl -s http://localhost:3100/ready
```

Vastus `ready`. Kui ei — `docker compose logs loki`. Loki tagastab `ready` alles siis, kui sisemine initsialiseerimine on läbi (TSDB indeksid, ring konsensus ka single-node puhul). Tavaliselt 5-10s.

### 7.3 Log-generator

Loki töötab, aga meil pole logisid. Lisame sisupakkuja — konteiner, mis 1x sekundis kirjutab juhusliku logirea applog-faili. Faili jälgib hiljem Alloy.

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
          S=$(echo $SERVICES | tr " " "\n" | shuf -n1)
          L=$(echo $LEVELS | tr " " "\n" | shuf -n1)
          LATENCY=$((RANDOM % 500))
          echo "$(date -Iseconds) [$L] [$S] duration=${LATENCY}ms trace_id=$RANDOM" >> /var/log/app/app.log
          sleep 1
        done
    volumes:
      - app-logs:/var/log/app
    restart: unless-stopped
```

**Miks LEVELS nii:** `INFO INFO INFO INFO INFO WARN ERROR` — 5 INFO, 1 WARN, 1 ERROR. See simuleerib reaalset distributsiooni: enamik logisid on informatiivsed, WARN'ureid vähem, ERROR'eid kriitiliselt vähe. Iga sekundi `shuf -n1` valib tõenäosusega 5/7 INFO.

```bash
docker compose up -d log-generator
sleep 5
docker exec log-generator tail -3 /var/log/app/app.log
```

Näed ridu nagu `2026-04-25T10:23:41+03:00 [ERROR] [payment] duration=245ms trace_id=12345`.

### 7.4 Alloy

Loki ja logid on valmis, aga keegi peab logid Lokisse saatma. **Alloy** on see "keegi" — agent, mis jookseb logide peremees-masinal, loeb logifaile (sarnaselt `tail -f`-ile) ja saadab ridade Loki HTTP API-sse.

Alloy konfig on **HCL-sarnane** (Terraform-stiilis plokid), mitte YAML. See on Grafana Labs'i valik — plokki saab kirjutada iga komponendi jaoks ja siduda neid `forward_to` viidetega.

```bash
cat > config/config.alloy << 'EOF'
local.file_match "applog" {
  path_targets = [
    {
      __path__ = "/var/log/app/*.log",
      job      = "applog",
    },
  ]
}

loki.source.file "applog" {
  targets    = local.file_match.applog.targets
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
EOF
```

**Konfiguratsiooni plokid ("components"):**

- `local.file_match "applog"` — määrab glob-mustri failidele (`/var/log/app/*.log`) ja staatilised labelid (`job="applog"`). Sisuline vaste Promtail'i `scrape_configs.static_configs`-le.
- `loki.source.file "applog"` — komponent, mis tegelikult faile **loeb**. Kõik hallatakse iseseisvalt: positsiooni-mälu (et restart'i korral õigest kohast jätkata), failide rotatsiooni tuvastus, uute failide avastamine.
- `loki.write "default"` — kuhu read saadetakse. Sisuline vaste Promtail'i `clients.url`-le.
- `forward_to` — sidumine: `loki.source.file.applog` järgnev on `loki.write.default.receiver`. Nii saab ühest allikast suunata mitmele backendile paralleelselt.

**Miks see on parem kui Promtail'i YAML:** plokid on **komponeeritavad**. Saad lisada logi-modifikaatori (nt JSON-parsimise) kesk teed, lisada teise `loki.write` alternatiivsele Lokile, saata sama logid ka OpenTelemetry collector'ile — ilma et peaks kogu konfi ümber kirjutama. Promtail'i `pipeline_stages` on järjestikune nagu konveier; Alloy on graaf.

Lisa `services:` alla:

```yaml
  alloy:
    image: grafana/alloy:v1.5.0
    container_name: alloy
    volumes:
      - ./config/config.alloy:/etc/alloy/config.alloy
      - app-logs:/var/log/app:ro
    command:
      - run
      - /etc/alloy/config.alloy
      - --server.http.listen-addr=0.0.0.0:12345
    ports:
      - "12345:12345"
    depends_on:
      - loki
    restart: unless-stopped
```

**Miks `app-logs:/var/log/app:ro`:** Alloy jagab log-generator'i volume'i, aga **read-only** (`:ro`). Alloy peab ainult lugema faili, mitte muutma. Kui kogemata kirjutaks, läheb positsioonide-andmestik sassi.

**Port 12345** on Alloy enda UI ja debug endpoint. Brauseris `http://192.168.35.12X:12345` näeb komponentide graafi, aktiivseid voolusid, vigade logi. See on Alloy oluline eelis — konfi silumine on visuaalne.

```bash
docker compose up -d alloy
sleep 10
docker compose logs alloy | tail -5
```

Alloy logis peab olema `component "loki.source.file.applog" started` ja mitte ühtki `error` rida.

💡 **Kui "connection refused" Loki'sse:** Loki pole veel ready. Oota 15s, `docker restart alloy`. Alloy on sallivam kui Promtail — jätkab oma komponentide käivitamist ja proovib hiljem Loki'le saata.

### 7.5 Grafana

Lõpuks UI. Grafana, tuttav päev 1-st, aga seekord **uus instants** (port 3000, eraldi konteiner `grafana-loki`). See hoiab päev 1 Prometheus-Grafana sõltumatuna.

Lisa `services:` alla:

```yaml
  grafana:
    image: grafana/grafana:11.4.0
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

**Miks URL on `http://loki:3100`, mitte `localhost:3100`:** Grafana jookseb konteineris. Konteineri jaoks `localhost` on Grafana ise. Loki on eraldi konteiner — jõuame Docker-võrgu DNS-nimega `loki`. See on **levinuim esimene eksitus** Loki datasource'i seadistamisel.

### 7.6 Esimesed read

*Explore* → datasource: Loki → Code view:

```logql
{job="applog"}
```

Run query. Näed ridu tekkima.

**Mis just juhtus ahelas:** log-generator kirjutas rea applog-faili → Alloy märkas (positsioonide-andmestik) → Alloy saatis rea HTTP POST-iga Lokisse → Loki salvestas chunk'i + indeksi `job="applog"` → Grafana küsis LogQL-iga seda voogu → sa näed tulemust. Kogu teekond on 1-3 sekundit.

💡 **Nõuanne:** nüüd on hea hetk avada Alloy debug UI (`http://192.168.35.12X:12345`) ja vaadata komponentide graafi — näed kõiki kolme plokki omavahel seotuna. See aitab hiljem tootmises silumisel.

💭 **Mõtle:** Alloy loeb faili nagu `tail -f`. Mis juhtub kui fail roteeritakse? Mis on positsioonide-andmestiku roll?

---

## Osa 8 · Pattern parser → rate() → dashboard

Nüüd kui stack on üleval ja LogQL alus on olemas, teeme üht päris kasulikku asja — teisendame logid metrikaks, et saaks graafikul jooksu jälgida. See on Loki võtmehetk: ilma Lokita oleks sul vaja **kahte** süsteemi (logi + metrika); Lokiga saad ühe logi-andmest teha metrika lennult.

### 8.1 Pattern — struktuuri lisamine

Meie logirida: `2026-04-25T10:23:41+03:00 [ERROR] [payment] duration=245ms trace_id=12345`

```logql
{job="applog"} | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<_>`
```

Kliki rea peal — näed labeleid `level`, `service`, `duration`.

**Mis just juhtus:** Loki polnud enne teadnud, et `[ERROR]` on midagi erilist — see oli lihtsalt osa sõnelisest sisust. Pattern parser määras struktuuri: esimene vaba väljend on aeg (`<_>` = ignoreeri), kaks nurksulu sees on level ja service, `duration=Xms` osa annab numbrilise kestuse. Pärast seda päringut võid neid väärtusi filtrisse panna ja agregeerida.

### 8.2 Filtreeri pattern'i tulemusi

```logql
{job="applog"} | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<_>` | level="ERROR" | service="payment"
```

Ainult payment error'id. Lisafiltrit saab lihtsalt täiendada — `| duration > 300` annab aeglased. Proovi ise: näita `api` teenuse logisid kus `duration > 300`.

**Märka:** enne `| pattern` filtreeris Loki **tekstisõnu**. Pärast `| pattern` filtreerib **struktureeritud väärtusi**. See on sama hetk, mis päev 1 Prometheus'es oli "eraldi label'id per dimensioon" — üleminek tekstist andmestruktuurile.

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

**Miks reegel nii range on:** iga unikaalne label'ite kombinatsioon tekitab Lokis **eraldi voogu (stream)**. 3 level × 5 service = 15 voogu — normaalne. 3 level × 5 service × 10 000 trace_id = 150 000 voogu — kardinaalsuse plahvatus. Loki indeks kasvab, päringud muutuvad aeglasemaks, Loki võib keelduda uusi logisid vastu võtma. Loeng §6 selgitab seda sügavamalt.

Mis juhtub kui teed `trace_id` label'iks? Proovi:

```logql
{job="applog"} | pattern `<_> [<_>] [<_>] <_> trace_id=<trace_id>`
```

Loki töötab — aga kujuta ette 10 000 unikaalset trace_id'd. See on 10 000 eraldi voogu. Loki indeks paisub, päringud aeglustuvad. Tootmises = raha ja aeg.

<details>
<summary>🔧 Edasijõudnule: Alloy `stage.regex` ja `stage.labels` komponendid</summary>

Tootmises ei parsi alati runtime'is LogQL'is. Alloy saab logisid **enne Loki saatmist** töödelda `loki.process` komponendis:

```hcl
loki.source.file "applog" {
  targets    = local.file_match.applog.targets
  forward_to = [loki.process.applog.receiver]
}

loki.process "applog" {
  forward_to = [loki.write.default.receiver]

  stage.regex {
    expression = `\[(?P<level>\w+)\] \[(?P<service>\w+)\]`
  }

  stage.labels {
    values = {
      level   = "",
      service = "",
    }
  }
}
```

Käguke: `loki.source.file` edastab `loki.process`-ile, see omakorda `loki.write`-ile. Regex leiab level ja service, labels-stage paneb need Loki labeliteks.

Nüüd `level` ja `service` on **püsivad labelid** Lokis — filter `{level="ERROR"}` kasutab indeksit, mitte brute-force skaneerimist. `duration` ja `trace_id` jäävad sisusse.

See on tootmise vs labi erinevus. Labis parsime runtime'is (lihtsam setup), tootmises Alloy `loki.process`-is (kiiremad päringud).

</details>

### 8.4 rate() — logist metrika

Siiamaani vaatasime logisid kui ridu (vaatlus). Nüüd teisendame nad **numbriks ajas** — logist saab metrika, nagu Prometheus annaks.

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

**Mis täpselt toimub:**

1. `{job="applog"}` — valib kõik applog voogud
2. `| pattern ...` — parsib read, teeb `level`, `service` labeleiks
3. `| level="ERROR"` — filtreerib ainult ERROR read
4. `[5m]` — "viimase 5 minuti" aken (range vector)
5. `rate(...)` — loendab read sekundis selles aknas
6. `sum by (service)` — grupeerib teenuste kaupa

**Miks see võimas:** sama loogika kui Prometheus'e `rate(http_requests_total[5m])` — aga allikas on **logirida**, mitte counter. Kui rakendus ei eksporteeri mõõdikut, aga logib "FAILED transaction" rida, saad Loki'ga sellest ikka trendi teha. See on palju vaheteenuseid (legacy rakendused), mida ei saa instrumenteerida.

### 8.5 Dashboard

Nüüd kui üks päring töötab, paneme ta dashboardile. Grafanas on muster alati sama: *loo dashboard → lisa paneel → päring → vali visualiseering*.

*Dashboards → New → Add visualization* → Loki datasource:

**Paneel 1:** `ERRORs per service` — eelmine päring, Time series.

**Paneel 2:**
```logql
sum by (level) (count_over_time({job="applog"} | pattern `<_> [<level>] [<_>] <_>` [1m]))
```
Bar chart — logimaht taseme järgi.

**Erinevus `rate()` ja `count_over_time()` vahel:**
- `rate()` — ridu sekundis (keskmistatud sujuvaks graafikuks)
- `count_over_time()` — ridude **koguarv** aknas (kasulik bar chart'ile, mis näitab "mitu ERROR-rida oli viimase minutiga")

Salvesta: `App monitoring`.

### 8.6 FINAAL — sama sündmus, kaks vaatenurka

Nüüd on mõlemad stackid üleval. Tekita error-torm mon-target'il:

```bash
ssh <eesnimi>@192.168.35.140 \
  'for i in $(seq 1 200); do echo "$(date -Iseconds) [ERROR] [payment] Spam_$i" | sudo tee -a /var/log/app/app.log > /dev/null; done'
```

Ava kaks brauseri tabi:

1. **Zabbix:** `http://192.168.35.12X:8080` → *Monitoring → Problems* → `Too many payment errors` trigger **Firing** (see oli [Zabbix labori osa 5.4](zabbix_lab.md#54-item-trigger))
2. **Loki Grafana:** `http://192.168.35.12X:3000` → Dashboard `App monitoring` → payment error spike graafikul

Sama sündmus, kaks perspektiivi. Zabbix ütleb **"on probleem"** (trigger). Loki näitab **"mis juhtus"** (logid + rate).

💭 **Lõpureflektsioon:** Sul on nüüd kolm tööriista — Prometheus (metrikad, pull), Zabbix (agent, push), Loki (logid). Millist probleemi oma tööst lahendaksid nendega esimesena? Kas näed olukorda kus kaks neist töötaksid kõrvuti?

---

## ✅ Lõpukontroll (Loki pool)

- [ ] `docker compose ps` (`~/paev2/loki/`) — 4 konteinerit Up (loki, log-generator, alloy, grafana-loki)
- [ ] Grafana Loki datasource roheline
- [ ] Explore näitab `{job="applog"}` logisid
- [ ] Alloy debug UI (`http://192.168.35.12X:12345`) näitab `loki.source.file.applog` → `loki.write.default` graafi
- [ ] Pattern parser ekstraheerib level, service, duration
- [ ] Dashboard `App monitoring` salvestatud, vähemalt 2 paneeli
- [ ] **FINAAL:** error-torm nähtav Zabbixi Problems lehel JA Loki graafikul

---

## 🚀 Lisaülesanded

### Loki: Nginx accesslog + RED

Lisa `log-generator` konteinerisse nginx-stiilis accesslog genereerimine. Lisa teine `local.file_match` ja `loki.source.file` komponent Alloy konfi `job="nginx"` jaoks. Ehita RED dashboard:

- `rate()` — päringuid sekundis
- `status =~ "5.."` — error rate
- `sum by (path)` — per path

### Log-based alert

Grafana → *Alerting → Alert rules → New* → Loki query `rate({job="applog"} | pattern ... | level="ERROR" | service="payment" [2m])` → threshold > 0.1 → Contact point: Discord.

### Correlation — metric → log

Dashboard paneelis *Data links → Add link* mis viib Explore vaatesse sama teenuse Loki logidele. Ühe klikiga graafikult logidesse.

### Multi-source Alloy — üks agent, kaks allikat

Alloy võimas pool tuleb välja, kui lisada **teine** logiallikas üldse ilma uut konteinerit käivitamata. Loo teine `local.file_match` komponent (nt nginx accesslog jaoks) ja suuna see samale `loki.write.default`-ile, kui ka eraldi `loki.write.nginx`-ile. Üks konfifail, kaks logi-voolu, võimalus mitut backend'i paralleelselt toita.

---

## 🏢 Enterprise lisateemad

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

    Alloy saadab `X-Scope-OrgID` header'i `loki.write` komponendis:

    ```hcl
    loki.write "team_backend" {
      endpoint {
        url = "http://loki:3100/loki/api/v1/push"
        headers = {
          "X-Scope-OrgID" = "team-backend",
        }
      }
    }
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


??? note "Alloy: OpenTelemetry, traces ja mõõdikud samas agendis"

    Laboris kasutasime Alloy'd ainult logide jaoks. Alloy oskab kolme sammast (logid, mõõdikud, traces) korraga. Näited:

    **Mõõdikud Prometheusele (Prometheus asendaja):**

    ```hcl
    prometheus.scrape "node" {
      targets = [
        {__address__ = "mon-target:9100"},
      ]
      forward_to = [prometheus.remote_write.default.receiver]
    }

    prometheus.remote_write "default" {
      endpoint {
        url = "http://prometheus:9090/api/v1/write"
      }
    }
    ```

    **OTel traces vastuvõtt ja Tempo suunamine:**

    ```hcl
    otelcol.receiver.otlp "default" {
      grpc { endpoint = "0.0.0.0:4317" }
      http { endpoint = "0.0.0.0:4318" }

      output {
        traces = [otelcol.exporter.otlp.tempo.input]
      }
    }

    otelcol.exporter.otlp "tempo" {
      client {
        endpoint = "tempo:4317"
        tls { insecure = true }
      }
    }
    ```

    Üks agent ehitab kogu LGTM pinu kirjutuspoole. Kolm eraldi agenti (Promtail + node_exporter + otel-collector) asendunud ühe Alloy konteineriga.

    **Loe edasi:**

    - [Alloy kõik komponendid](https://grafana.com/docs/alloy/latest/reference/components/)
    - [OpenTelemetry Alloy's](https://grafana.com/docs/alloy/latest/collect/opentelemetry-to-lgtm-stack/)
    - [Migration from Promtail](https://grafana.com/docs/alloy/latest/tasks/migrate/from-promtail/)

---

## Veaotsing

| Probleem | Esimene kontroll |
|----------|------------------|
| Loki "no labels found" | `{job="applog"}` — peab vastama Alloy config'ile |
| Loki "too many streams" | Label on liiga unikaalne (trace_id). Eemalda. |
| Alloy "connection refused" | Loki pole ready — `docker restart alloy` |
| Alloy komponendid "unhealthy" | Ava debug UI port 12345 — komponendi võib näidata veateksti |
| Grafana Loki datasource punane | URL peab olema `http://loki:3100`, mitte `localhost` |
| rate() tagastab 0 | Time range liiga kitsas — vaheta "Last 15 min" |
| Mõlemad stackid aeglased | `free -h` — 4GB piir. Peata üks ajutiselt kui vaja. |
| Alloy ei loe logifaile | `docker logs alloy` — permission? `app-logs:/var/log/app:ro` mount OK? |

---

## 📚 Allikad

| Allikas | URL |
|---------|-----|
| Loki dokumentatsioon | [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/) |
| LogQL spetsifikatsioon | [grafana.com/.../query](https://grafana.com/docs/loki/latest/query/) |
| Pattern parser | [grafana.com/.../pattern](https://grafana.com/docs/loki/latest/query/log_queries/#pattern) |
| LogQL simulator | [grafana.com/.../analyzer](https://grafana.com/docs/loki/latest/query/analyzer/) |
| Grafana Alloy | [grafana.com/docs/alloy](https://grafana.com/docs/alloy/latest/) |
| Siltide parimad tavad | [grafana.com/.../labels](https://grafana.com/docs/loki/latest/get-started/labels/) |

**Versioonid:** Loki 3.3.0, Alloy 1.5.0, Grafana 11.4.0.
