# Päev 5: Tempo + OpenTelemetry — Labor

**Kestus:** ~4 tundi (klassis Osad 1–4, ülejäänu kodus)
**Tase:** kesktase
**Eeldused:** Päev 1 (Docker Compose, Prometheus, Grafana datasource'id). Päev 2 (Loki, LogQL). Hajutatud jälgimise mõisted (span, trace, OTLP, context propagation) — loe enne labi [Päev 5 loeng](../../materials/lectures/paev5-loeng.md).
**VM:** sinu VM (`ssh <eesnimi>@192.168.35.12X` klassivõrgust või `192.168.100.12X` VPN-ist)

---

## Miks see labor

Päev 1 mõõtsid (Prometheus), päev 2 logisid (Loki). Mõlemad ütlevad, *et* midagi on valesti — aga kui päring läbib mitut teenust, ei ütle kumbki, *kus* aeg kulus. Täna lisad kolmanda samba: jäljed. Paned püsti Tempo, suunad demo-rakenduse jäljed OTel Collectori kaudu sisse, ja kõige lõpuks liigud Grafanas ühe probleemi puhul mõõdikult logile ja jäljele — see on terve LGTM-stack koos.

See lab **ehitab eelmisele peale**, ei alusta nullist. Lisad Tempo ja Collectori samasse Grafana-ökosüsteemi, mida oled kursuse vältel kasvatanud.

!!! note "Miks Tempo siin riistvaral töötab, InfluxDB 3 ei töötanud"
    Päev 4 ei saanud kasutada InfluxDB 3, sest lab-serveri CPU (Sandy Bridge) ei toeta AVX2 käsustikku. Tempo, OTel Collector ja Alloy on **Go-binaarid** — nad ei nõua AVX2 ja käivituvad sellel riistvaral. Kontseptsioonid on identsed pilve-Tempoga.

---

## 🎯 Õpiväljundid

**Teadmised:**

1. Selgitab, miks Tempo ei indekseeri trace'i sisu ja kuhu jäljed salvestuvad.
2. Kirjeldab OTel Collectori rolli rakenduse ja backend'i vahel.
3. Eristab kolme samba (metrics, logs, traces) ja teab, millal kumbki vastab.

**Oskused:**

4. Seab Tempo + OTel Collectori Docker Compose'iga olemasolevasse stacki.
5. Saadab jäljed OTLP kaudu ja leiab need Grafanas üles.
6. Loeb trace'i: leiab pikima span'i ja ütleb, kus aeg kulus.
7. Seob trace'i logiga (korrelatsioon metric → log → trace).

---

## Labi struktuur

Klassis jõuad Osadeni 1–4 (Tempo püsti, jäljed sees, trace Grafanas, korrelatsioon). Osad 5–6 ja lisaülesanded jäävad koju.

| Osa | Teema | Mida sa mõistad lõpus |
|-----|-------|------------------------|
| 1 | Tempo üles, Grafana datasource | Jälgede-backend elab, miks ID-põhine otsing |
| 2 | OTel Collector + esimene trace | Collector kui vahekiht, OTLP sisse |
| 3 | Demo-rakendus → päris jäljed | Span'ide puu, kus aeg kulub |
| 4 | Korrelatsioon: trace ↔ log | Üks uurimisteekond kolme signaali peale |
| 5 | TraceQL — päring jälgede peal (kodus) | Otsing kestuse/teenuse järgi |
| 6 | Metric → trace exemplar (kodus) | Graafikult otse trace'i |

Töökaust: `~/paev5`. Tempo on Grafana ökosüsteemi osa — kui sul on päev 1/2 Grafana stack alles, võid lisada teenused sinna; selguse huvises teeme siin eraldi kausta ja ühendame Grafana datasource'idena.

---

## Eeltöö

Pane eelmised rasked stack'id maha ja loo töökaust:

```bash
cd ~/paev4 2>/dev/null && docker compose down 2>/dev/null
free -h
mkdir -p ~/paev5/config && cd ~/paev5
```

Vaba mälu võiks olla ≥2 GB.

!!! warning "Kui `docker pull` jääb toppama"
    Sama IPv6-probleem mis varasematel päevadel:
    ```bash
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
    sudo systemctl restart docker
    ```

---

## Osa 1 · Tempo üles + Grafana datasource

> **Miks:** Tempo on jälgede-backend. Erinevalt logidest või mõõdikutest ei indekseeri ta sisu — jäljed lähevad otse ketta (objektisalvestus pilves, kohalik fail siin), otsing käib peamiselt `trace_id` järgi. See teeb salvestuse odavaks. Esmalt paneme Tempo püsti üksinda ja kontrollime, et ta elab, enne kui andmeid sisse saadame.

### 1.1 Tempo konfiguratsioon — minimaalne

Loo `~/paev5/config/tempo.yml`. Alustame väikseimast töötavast konfist: võta OTLP vastu, hoia lokaalsel kettal.

```yaml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        http:
          endpoint: 0.0.0.0:4318
        grpc:
          endpoint: 0.0.0.0:4317

storage:
  trace:
    backend: local
    local:
      path: /var/tempo/blocks
    wal:
      path: /var/tempo/wal
```

Kolm osa: **distributor** võtab jäljed vastu (OTLP üle HTTP 4318 ja gRPC 4317); **storage** paneb need lokaalsele kettale; **server** annab Tempo enda API pordi 3200.

### 1.2 Tempo teenus

Loo `~/paev5/docker-compose.yml`:

```yaml
services:
  tempo:
    image: grafana/tempo:2.6.1
    container_name: tempo
    command: ["-config.file=/etc/tempo.yml"]
    ports:
      - "3200:3200"
      - "4317:4317"
      - "4318:4318"
    volumes:
      - ./config/tempo.yml:/etc/tempo.yml:ro
      - tempo-data:/var/tempo
    restart: unless-stopped

volumes:
  tempo-data:
```

Käivita ja kontrolli:

```bash
cd ~/paev5
docker compose up -d tempo
sleep 10
curl -s http://localhost:3200/ready
```

Vastus `ready`. Tempo elab.

!!! tip "Kui `ready` asemel tuleb tühi vastus või refused"
    Tempo alles käivitub — oota veel ~10 s. Kui jääb püsima: `docker compose logs tempo`. Tüüpiline viga on konfis vale taane (YAML on tundlik) — kontrolli `protocols:` ploki struktuuri.

### 1.3 Lisa Tempo Grafanasse

Vajad Grafanat. Lisa `docker-compose.yml`-i `services:` alla (enne `volumes:`):

```yaml
  grafana:
    image: grafana/grafana:11.1.0
    container_name: grafana-tempo
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=monitoring2026
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Admin
    volumes:
      - grafana-data:/var/lib/grafana
    restart: unless-stopped
```

Lisa `volumes:` alla ka `grafana-data:`. Käivita:

```bash
docker compose up -d grafana
```

Ava brauseris `http://<sinu-VM-IP>:3000` (admin / `monitoring2026`). Mine *Connections → Data sources → Add data source → Tempo*. URL: `http://tempo:3200`. *Save & test* → roheline.

💭 **Mõtle:** Loki (päev 2) indekseeris ainult silte, Tempo ei indekseeri trace'i sisu üldse. Mõlemad panevad raske osa odavasse salvestusse. Miks see disainivalik sobib just logidele ja jälgedele, aga mitte näiteks pangatehingute andmebaasile?

---

## Osa 2 · OTel Collector + esimene trace

> **Miks:** rakendus ei saada üldjuhul otse backend'ile, vaid **Collectorile** — vahekihile, mis võtab OTLP vastu, töötleb ja saadab edasi. See tähendab, et backend'i saab vahetada Collectori konfist, rakendust puutumata. Enne demo-rakendust saadame ühe käsitsi-trace'i, et näha toru tööd.

### 2.1 Collectori konfiguratsioon

Loo `~/paev5/config/otel-collector.yml`:

```yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
      grpc:
        endpoint: 0.0.0.0:4317

exporters:
  otlp/tempo:
    endpoint: tempo:4317
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [otlp/tempo]
```

Loe ülevalt alla: **receiver** võtab rakenduselt OTLP vastu; **exporter** saadab Tempole (gRPC 4317, TLS-ita siselabis); **pipeline** seob need. Praegu ei töötle midagi vahepeal — lihtsaim võimalik toru.

### 2.2 Collector compose'i

!!! warning "Pordikonflikt — loe enne lisamist"
    Tempo kuulab juba 4317/4318 host-masinal. Kui Collector publiceerib samad pordid hostile, tekib konflikt. Lahendus: Collector ja Tempo on **samas Docker-võrgus** ja räägivad konteineri-nimede kaudu — Collector ei pea host-porti üldse avama Tempo poole. Avame Collectorile ainult **sissetuleva** pordi (rakendus → collector), nihutatuna, et Tempoga mitte põrkuda.

Lisa `services:` alla:

```yaml
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.117.0
    container_name: otel-collector
    command: ["--config=/etc/otel-collector.yml"]
    ports:
      - "14318:4318"   # rakendus saadab siia (host 14318 → konteiner 4318)
    volumes:
      - ./config/otel-collector.yml:/etc/otel-collector.yml:ro
    depends_on:
      - tempo
    restart: unless-stopped
```

!!! warning "Kasuta versiooni 0.117.0, mitte 0.116.0"
    Collectori image `0.116.0` on katki — konteiner kukub `exec /otelcol-contrib: no such file or directory` veaga (upstream bug, parandatud 0.117.0-s). Kui kopeerid compose'i mujalt vana versiooniga, vaheta tag `0.117.0`-ks.

```bash
docker compose up -d otel-collector
docker compose logs otel-collector | tail -10
```

Otsi logist `Everything is ready. Begin running and processing data.`. Kontrolli ka, et konteiner tegelikult jääb püsti, mitte ei ole restart-loopis:

```bash
docker compose ps
```

`otel-collector` peab olema `Up`, **mitte** `Restarting`.

### 2.3 Saada üks trace käsitsi

Saada üks minimaalne OTLP-trace Collectorile `curl`-iga (host-port 14318):

```bash
curl -s -X POST http://localhost:14318/v1/traces \
  -H "Content-Type: application/json" \
  -d '{
    "resourceSpans": [{
      "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "kasitsi-test"}}]},
      "scopeSpans": [{
        "spans": [{
          "traceId": "5b8aa5a2d2c872e8321cf37308d69df2",
          "spanId": "051581bf3cb55c13",
          "name": "minu-esimene-span",
          "startTimeUnixNano": "1700000000000000000",
          "endTimeUnixNano": "1700000000500000000",
          "kind": 2
        }]
      }]
    }]
  }'
```

Grafanas mine *Explore* → datasource **Tempo** → otsi `trace_id` järgi: kleebi `5b8aa5a2d2c872e8321cf37308d69df2`. Näed üht span'i nimega `minu-esimene-span`, teenus `kasitsi-test`.

!!! tip "Kui trace'i ei leia"
    Kontrolli: 1) Collectori logis pole eksportimise viga (`docker compose logs otel-collector`); 2) Tempo võtab vastu (`docker compose logs tempo` — ei tohi olla `connection refused`); 3) Grafanas vali Query type **TraceQL** või **Search**, mitte tühi. Andmete jõudmine võtab ~10 s.

💭 **Mõtle:** sa saatsid trace'i Collectorile, mitte otse Tempole. Mis eelise annab see vahekiht, kui tahaksid homme jäljed Tempo asemel Jaegerisse saata? Mida muudaksid — rakendust või Collectori konfi?

---

## Osa 3 · Demo-rakendus → päris jäljed

> **Miks:** käsitsi-trace näitas toru, aga päris jälje juures on span'ide puu — mitu teenust, igaüks oma kestusega. Grafana pakub valmis demo-rakenduse (microservices-demo laadis), mis genereerib realistlikke jälgi. Vaatame, kuidas trace'ist loeb välja, kus aeg kulub.

### 3.1 Lihtne mitme-span'iga trace

Päris demo-rakendus (nt OpenTelemetry Demo) on raske meie VM-i jaoks. Genereerime mitme-span'iga jälje skriptiga, mis matkib teenuste ahelat. Loo `~/paev5/genereeri-trace.sh`:

```bash
cat > ~/paev5/genereeri-trace.sh << 'EOF'
#!/bin/bash
# Genereerib ühe trace'i kolme span'iga: api -> hinnastus -> andmebaas
TRACE=$(openssl rand -hex 16)
ROOT=$(openssl rand -hex 8)
CHILD=$(openssl rand -hex 8)
GRAND=$(openssl rand -hex 8)
NOW=$(date +%s)000000000

curl -s -X POST http://localhost:14318/v1/traces \
  -H "Content-Type: application/json" \
  -d "{
    \"resourceSpans\": [{
      \"resource\": {\"attributes\": [{\"key\": \"service.name\", \"value\": {\"stringValue\": \"api-varav\"}}]},
      \"scopeSpans\": [{\"spans\": [
        {\"traceId\": \"$TRACE\", \"spanId\": \"$ROOT\", \"name\": \"GET /checkout\", \"startTimeUnixNano\": \"$NOW\", \"endTimeUnixNano\": \"$(($NOW + 4000000000))\", \"kind\": 2},
        {\"traceId\": \"$TRACE\", \"spanId\": \"$CHILD\", \"parentSpanId\": \"$ROOT\", \"name\": \"hinnastus.arvuta\", \"startTimeUnixNano\": \"$(($NOW + 100000000))\", \"endTimeUnixNano\": \"$(($NOW + 3900000000))\", \"kind\": 2},
        {\"traceId\": \"$TRACE\", \"spanId\": \"$GRAND\", \"parentSpanId\": \"$CHILD\", \"name\": \"db.query hinnad\", \"startTimeUnixNano\": \"$(($NOW + 200000000))\", \"endTimeUnixNano\": \"$(($NOW + 3800000000))\", \"kind\": 3}
      ]}]
    }]
  }"
echo "Trace ID: $TRACE"
EOF
chmod +x ~/paev5/genereeri-trace.sh
~/paev5/genereeri-trace.sh
```

Skript trükib `Trace ID: ...`. Kopeeri see.

### 3.2 Loe trace'i Grafanas

*Explore* → Tempo → otsi trace_id järgi. Näed kolme-tasemelist puud:

- `GET /checkout` (api-varav) — 4000 ms
- └ `hinnastus.arvuta` — 3800 ms
- &nbsp;&nbsp;└ `db.query hinnad` — 3600 ms

Kohe on näha: 4 sekundist kulus enamus andmebaasipäringule. Mitte api-väravas, mitte hinnastuse loogikas — `db.query`. Ilma jäljeta oleks see arvamine; jäljega on see üks pilk.

💭 **Mõtle:** trace näitas, et aeg kulus `db.query`-s. Mõõdik (Prometheus) oleks näidanud ainult „checkout 4s". Loki oleks näidanud vealogi, kui viga oleks. Mis on iga samba tugevus — millal vaatad esimesena mõõdikut, millal logi, millal jälge?

---

## Osa 4 · Korrelatsioon — trace ↔ log

> **Miks:** kolm signaali eraldi on kasulik, aga väärtus tuleb seosest. Kui logirida sisaldab `trace_id`, saad Grafanas logist otse trace'i hüpata. See on jälgitavuse tegelik lubadus: üks uurimisteekond sümptomilt põhjuseni.

Selles osas seome Loki (kui sul on päev 2 stack alles) Tempoga. Kui Loki pole käes, loe see osa läbi ja tee kodus — kontseptsioon on tähtsam kui klikkimine.

### 4.1 Lisa Loki datasource'i trace-link

Grafanas *Connections → Data sources → Loki → Derived fields*. Lisa väli:

- **Name:** `trace_id`
- **Regex:** `trace_id=(\w+)`
- **Query:** `${__value.raw}`
- **Internal link:** datasource **Tempo**

See ütleb Grafanale: kui logireas on `trace_id=abc123`, tee sellest klõpsatav link, mis avab Tempos vastava trace'i.

### 4.2 Testi seost

Kui sul on logigeneraator (päev 2 `log-generator` tekitas ridu `trace_id=...`), ava *Explore* → Loki → `{job="applog"}`. Klõpsa real, kus on `trace_id`. Näed nüüd klõpsatavat **trace_id** välja → klõps → hüppad Tempo trace'i.

Kui logigeneraatorit pole, ava lihtsalt päev 3 trace Grafanas ja vaata, kuidas trace-vaates on iga span'i juures sildid, mille kaudu saaks tagasi logidesse liikuda.

💭 **Mõtle:** korrelatsioon töötab ainult siis, kui `trace_id` on **nii logis kui jäljes**. Mida see tähendab rakenduse instrumenteerimise jaoks — kes peab tagama, et logirida sisaldab sama `trace_id`-d, mis jälg? Miks on OTel siin abiks (meenuta loengut)?

---

## Osa 5 · TraceQL — päring jälgede peal (kodus)

> **Miks:** trace_id järgi otsimine eeldab, et ID on teada. Päriselus tahad otsida „kõik checkout-päringud üle 2 sekundi". Selleks on TraceQL — Tempo päringukeel, sarnane LogQL-ile.

Grafanas *Explore* → Tempo → Query type **TraceQL**. Proovi:

```traceql
{ duration > 2s }
```

Tagastab jäljed, mis kestsid üle 2 sekundi. Lisa teenuse filter:

```traceql
{ resource.service.name = "api-varav" && duration > 2s }
```

Genereeri paar trace'i juurde (`~/paev5/genereeri-trace.sh`) ja vaata, kuidas päring neid leiab.

💭 **Mõtle:** TraceQL `{ duration > 2s }` leiab aeglased päringud ilma ID-d teadmata. Kuidas seostub see SLO-ga (loeng)? Kui SLO on „99% alla 300 ms", millise TraceQL-päringuga leiaksid SLO-d rikkuvad jäljed?

---

## Osa 6 · Metric → trace exemplar (kodus)

> **Miks:** exemplar on mõõdiku külge kinnitatud näidis-`trace_id`. Latentsuse-graafikul on punkt, mis viitab konkreetsele aeglasele trace'ile — klõpsad graafikul ja hüppad otse selle päringu jäljele. See sulgeb ringi: mõõdik (kus piik) → trace (miks piik).

See nõuab rakendust, mis emiteerib exemplar'eid (OTel SDK teeb seda automaatselt). Loe Grafana dokumentatsioonist exemplars-toe kohta ja proovi `intro-to-mltp` demoga, kui tahad terve LGTM-i ühes konteineris näha:

- <https://github.com/grafana/intro-to-mltp>

💭 **Mõtle:** exemplar viib mõõdikult jäljele. Korrelatsioon (Osa 4) viis logilt jäljele. Mõlemad sulgevad ringi. Kui sul oleks tööl üks asi, mille saaksid seadistada — exemplar (metric→trace) või trace↔log link — kumb annaks rohkem väärtust ja miks?

---

## ✅ Lõpukontroll (enesekontroll, verifitseeritav)

**Tehniline:**

- [ ] `curl -s http://localhost:3200/ready` tagastab `ready`.
- [ ] `docker compose ps` näitab `tempo`, `otel-collector`, `grafana` olekus `Up` (otel-collector **mitte** `Restarting`).
- [ ] Grafana Tempo datasource *Save & test* on roheline.
- [ ] Käsitsi saadetud trace (`kasitsi-test`) on Grafanas trace_id järgi leitav.
- [ ] `genereeri-trace.sh` trace näitab Grafanas kolme-tasemelist span'ide puud.
- [ ] Trace-vaates näed, et pikim span on `db.query hinnad`.

**Arusaamine (vasta peast):**

- [ ] Selgitad ühe lausega, miks Tempo ei indekseeri trace'i sisu.
- [ ] Nimetad kolme samba küsimused: metric (kas?), log (mis?), trace (kus?).
- [ ] Selgitad, miks rakendus saadab Collectorile, mitte otse Tempole.
- [ ] Selgitad, mis peab logis ja jäljes ühine olema, et korrelatsioon töötaks.

---

## 🚀 Lisaülesanded (kellel aega)

**A. Processor Collectorisse.** Lisa Collectori pipeline'i `batch` processor (`processors: batch:` ja lisa pipeline'i). Vaata logist, kuidas jäljed nüüd partiidena lähevad — see vähendab koormust, nagu loeng mainis.

**B. Service graph.** Tempo oskab span'idest teenuste-graafi tuletada. Uuri Tempo `metrics_generator` konfi ja vaata, kuidas Grafana joonistab teenuste sõltuvused automaatselt.

**C. Terve LGTM ühes.** Kui VM-il on mälu, proovi `intro-to-mltp` demo — Loki + Grafana + Tempo + Mimir + demo-rakendus ühes compose'is. Näed kõiki kolme sammast päris korrelatsiooniga.

**D. Retention.** Sea Tempo konfis `compactor` block_retention lühikeseks (nt `1h`) ja vaata, kuidas vanad jäljed kustuvad. Mõtle, miks jälgede retention on tavaliselt lühem kui mõõdikute oma.

**E. Rain küpsetab rabarberikooki (lõbus, terve LGTM ühe näitega).** Trace ei pea olema API-päring. Mõtle igale protsessile, millel on järjestikused etapid — koogi tegemine sobib täpselt. Rain teeb rabarberikooki: span'id ahelas `osta_rabarber` → `tee_tainas` → `sega_taidis` → `kupseta` → `jahuta`. Genereeri koogi-trace ja vaata Grafanas, milline samm on pikim (vihje: ahi).

Loo `~/paev5/koogi-trace.sh`:

```bash
cat > ~/paev5/koogi-trace.sh << 'EOF'
#!/bin/bash
# Rain küpsetab rabarberikooki — üks trace, viis span'i ahelas.
# Iga uus kook saab veidi erineva küpsetusaja (mõni kõrbeb).
TRACE=$(openssl rand -hex 16)
S1=$(openssl rand -hex 8); S2=$(openssl rand -hex 8); S3=$(openssl rand -hex 8)
S4=$(openssl rand -hex 8); S5=$(openssl rand -hex 8)
NOW=$(date +%s)000000000
MIN=60000000000   # üks minut nanosekundites

# küpsetusaeg 40-55 min (juhuslik) — üle 50 = kõrbenud
BAKE=$(( (40 + RANDOM % 16) ))

curl -s -X POST http://localhost:14318/v1/traces \
  -H "Content-Type: application/json" \
  -d "{
    \"resourceSpans\": [{
      \"resource\": {\"attributes\": [{\"key\": \"service.name\", \"value\": {\"stringValue\": \"rain-kook\"}}]},
      \"scopeSpans\": [{\"spans\": [
        {\"traceId\": \"$TRACE\", \"spanId\": \"$S1\", \"name\": \"osta_rabarber\", \"startTimeUnixNano\": \"$NOW\", \"endTimeUnixNano\": \"$(($NOW + 5*$MIN))\", \"kind\": 2},
        {\"traceId\": \"$TRACE\", \"spanId\": \"$S2\", \"parentSpanId\": \"$S1\", \"name\": \"tee_tainas\", \"startTimeUnixNano\": \"$(($NOW + 5*$MIN))\", \"endTimeUnixNano\": \"$(($NOW + 20*$MIN))\", \"kind\": 2},
        {\"traceId\": \"$TRACE\", \"spanId\": \"$S3\", \"parentSpanId\": \"$S2\", \"name\": \"sega_taidis\", \"startTimeUnixNano\": \"$(($NOW + 20*$MIN))\", \"endTimeUnixNano\": \"$(($NOW + 30*$MIN))\", \"kind\": 2},
        {\"traceId\": \"$TRACE\", \"spanId\": \"$S4\", \"parentSpanId\": \"$S3\", \"name\": \"kupseta\", \"startTimeUnixNano\": \"$(($NOW + 30*$MIN))\", \"endTimeUnixNano\": \"$(($NOW + (30+$BAKE)*$MIN))\", \"kind\": 2},
        {\"traceId\": \"$TRACE\", \"spanId\": \"$S5\", \"parentSpanId\": \"$S4\", \"name\": \"jahuta\", \"startTimeUnixNano\": \"$(($NOW + (30+$BAKE)*$MIN))\", \"endTimeUnixNano\": \"$(($NOW + (45+$BAKE)*$MIN))\", \"kind\": 2}
      ]}]
    }]
  }"
echo "Kook valmis. Trace ID: $TRACE (kupsetusaeg ${BAKE} min)"
EOF
chmod +x ~/paev5/koogi-trace.sh
```

Tee Rainile mitu kooki (igaüks juhusliku küpsetusajaga):

```bash
for i in 1 2 3 4 5 6 7 8; do ~/paev5/koogi-trace.sh; sleep 1; done
```

**Trace.** Grafanas *Explore* → Tempo → Search → service `rain-kook`. Ava üks kook — span-puu näitab, et `kupseta` on alati pikim. Sama loogika mis `db.query` Osas 3, ainult maitsvam.

**Metric — mitu kooki Rain tegi.** Tempo `metrics_generator` toodab span'idest automaatselt mõõdikud (span count, kestus). Tee TraceQL-päring, mis loeb koogid kokku, ja vaata trace'ide arvu — see ongi „mitu kooki Rain tegi" mõõdikuna.

**TraceQL — leia kõrbenud koogid.** SLO: kook ei tohi olla ahjus üle 50 minuti. Leia rikkujad:

```traceql
{ name = "kupseta" && duration > 50m }
```

Iga tagastatud trace on kõrbenud kook. See on täpselt sama muster mis tootmises „leia SLO-d rikkuvad päringud" — ainult et siin on tagajärg söögikõlbmatu kook, mitte vihane klient.

💭 **Mõtle:** kui Rain tahaks alarmi „liiga palju kõrbenud kooke viimase tunni jooksul", siis kas seda ehitaks trace'i, mõõdiku või logi peale? Seosta loengu SLO/veaeelarve mõttega — mis oleks „koogi-SLO" ja „koogi-veaeelarve"?

---

## Veaotsing

| Probleem | Kontroll | Lahendus |
|---|---|---|
| `docker pull` jääb toppama | — | IPv6 välja (vt Eeltöö), `docker compose` uuesti. |
| `:3200/ready` tühi / refused | `docker compose ps` | Tempo alles käivitub või konfis YAML-viga. `docker compose logs tempo`. |
| Collector `Restarting`, logis `exec /otelcol-contrib: no such file` | `docker compose ps` | Image-versioon katki. Kasuta `0.117.0`, mitte `0.116.0`. |
| Collector ei käivitu (muu viga) | `docker compose logs otel-collector` | Konfis taane/struktuur vale. Kontrolli `receivers`/`exporters`/`service` plokid. |
| Trace ei jõua Tempole | Collectori logi | `connection refused tempo:4317` → Tempo pole valmis. Oota, `docker compose restart otel-collector`. |
| Grafanas trace_id ei leia | Query type | Vali **TraceQL** või **Search**, mitte tühi. Andmed jõuavad ~10 s. |
| Pordikonflikt 4317/4318 | `docker compose ps` | Collector kasutab host-porti 14318 (mitte 4318) — vt Osa 2.2 hoiatus. |
| `container is marked for removal` | `docker compose ps` | Pooleli koristus. `docker rm -f tempo otel-collector grafana-tempo; docker container prune -f`, siis uuesti. |
| Grafana datasource refused | URL | Tempo URL peab olema `http://tempo:3200` (konteineri nimi), mitte `localhost`. |

---

## 📚 Allikad

| Allikas | URL | Miks oluline |
|---|---|---|
| Grafana Tempo docs | <https://grafana.com/docs/tempo/latest/> | Konfiguratsioon, salvestus, retention. |
| Tempo getting started | <https://grafana.com/docs/tempo/latest/getting-started/> | Tempo + Collector + Grafana koos. |
| OpenTelemetry Collector | <https://opentelemetry.io/docs/collector/> | Receiver/processor/exporter mudel. |
| OTLP spetsifikatsioon | <https://opentelemetry.io/docs/specs/otlp/> | Trace-vorming, mida `curl`-iga saatsid. |
| TraceQL | <https://grafana.com/docs/tempo/latest/traceql/> | Päringukeel jälgede peal. |
| Grafana intro-to-mltp | <https://github.com/grafana/intro-to-mltp> | Terve LGTM demo korrelatsiooniga. |

--8<-- "_snippets/abbr.md"
