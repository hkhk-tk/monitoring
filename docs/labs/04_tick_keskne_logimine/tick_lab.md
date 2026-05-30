# Päev 4: TICK Stack — InfluxDB 2.7, Telegraf ja aegread

**Kestus:** ~4 tundi (klassis Osad 1–4, ülejäänu kodus)
**Tase:** kesktase
**Eeldused:** Päev 1 (Docker Compose, Prometheus pull-mudel, Grafana). Aegrida-mõiste, line protocol ja andmemudel (tag/field/timestamp) — loe enne labi [Päev 4 loeng](../../materials/lectures/paev4-loeng.md).
**VM:** sinu VM (`ssh <eesnimi>@192.168.35.12X` klassivõrgust või `192.168.100.12X` VPN-ist)

---

## Miks see labor

Päev 1 kasutasid Prometheust — pull-mudel, PromQL, suurepärane serverite ja konteinerite jaoks. Aga kui andmeid tuleb teistmoodi — tuhanded sensorid, igaüks väärtus iga sekund, miljoneid punkte päevas — vajad **spetsialiseeritud aegreade andmebaasi**. Loengus nägid, kuidas TICK arenes. Täna paned selle ise püsti ja näed, kuidas neli ajaloolise TICK-i komponenti on tänaseks **kaheks** koondunud.

!!! note "Miks InfluxDB 2.7, mitte 3?"
    Lab-serverite CPU (Xeon E5-2660, Sandy Bridge) ei toeta AVX2 käsustikku, mida InfluxDB 3 binäär nõuab — v3 ei käivitu sellel riistvaral. Kasutame **InfluxDB 2.7** (töötab igal CPU-l). Kontseptsioonid on identsed; päringukeel on **Flux** (SQL asemel), ja boonusena saame 2.7-ga näidata ka Chronograf'i ja Kapacitor'i rolli — mida v3 lab ei sisaldanud.

TICK on kerge — InfluxDB + Telegraf mahuvad 4 GB VM-i mängleva kergusega, kui päev 3 stack on maas.

---

## 🎯 Õpiväljundid

**Teadmised:**

1. Selgitab, miks aegread vajavad eraldi andmebaasi (mitte PostgreSQL-i) — meenuta loengut.
2. Loeb ja kirjutab line protocol rea: measurement, tag-set, field-set, ajatempel.
3. Põhjendab Telegrafi rolli agendina ja millal eelistada teda `node_exporter`-ile.
4. Selgitab, kuidas TICK-i neli komponenti (Telegraf-InfluxDB-Chronograf-Kapacitor) on 2.x-s kaheks koondunud.

**Oskused:**

5. Käivitab InfluxDB 2.7 Docker Compose'iga ja läbib seadistuse (org, bucket, token).
6. Kirjutab andmeid line protocol vormingus käsitsi ja päringustab Flux'iga UI-st.
7. Seadistab Telegrafi koguma süsteemimeetrikaid ja saatma neid InfluxDB-sse.
8. Loob Flux **task**'i (Kapacitor'i roll) ja **check**'i, mis hindab läve.

---

## Labi struktuur

Klassis jõuad Osadeni 1–4 (stack püsti, andmed voolavad, päringud UI-st). Osad 5–7 ja lisaülesanded jäävad koju.

| Osa | Teema | TICK | Mida sa mõistad lõpus |
|-----|-------|------|------------------------|
| 1 | InfluxDB 2.7 üles + seadistus | **I** | Server elab, org/bucket/token mudel |
| 2 | Line protocol käsitsi | **I** | Toorvorming, kuidas andmed sisse jõuavad |
| 3 | Data Explorer — päring + graafik | **C** | Chronograf'i roll, koondunud core'i |
| 4 | Telegraf → süsteemimeetrikad | **T** | Agent kogub automaatselt |
| 5 | Flux sügavamalt — aja-aknad | — | `aggregateWindow`, downsampling |
| 6 | Flux task + check (kodus) | **K** | Kapacitor'i roll, koondunud core'i |
| 7 | MQTT sensor (kodus) | — | Miks TSDB IoT-s domineerib |

Töökaust: `~/paev4`. TICK on eraldi ökosüsteem (mitte Grafana LGTM), seega uus kaust on õige.

---

## Eeltöö

Päev 3 ELK/OpenSearch võtab palju mälu. Pane maha ja loo töökaust:

```bash
cd ~/paev3/elk 2>/dev/null && docker compose down 2>/dev/null
cd ~/paev3/os  2>/dev/null && docker compose down 2>/dev/null
free -h
mkdir -p ~/paev4 && cd ~/paev4
```

Vaba mälu võiks olla ≥2 GB.

!!! warning "Kui `docker pull` jääb toppama (`Image ... Pulling` ei liigu)"
    VM-il pole töötavat IPv6 ühendust, aga Docker proovib seda. Lülita välja ja proovi uuesti:
    ```bash
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
    sudo systemctl restart docker
    ```

---

## Osa 1 · InfluxDB 2.7 üles (I)

> **Miks:** loengust tead, et aegread vajavad eraldi andmebaasi. InfluxDB on selle valdkonna tuntuim — andmed ketta peale ajatempli järgi optimeeritult, päring Flux'iga, ja **veebiliides sissehitatud** (vana eraldiseisev Chronograf on core'i sulandunud). Esmasel käivitusel pole midagi seadistatud — sa läbid ise onboardingu ja näed, kuidas tekivad **organisatsioon**, **bucket** (≈ andmebaas) ja **token**.

### 1.1 Baas — ainult InfluxDB

Loo `~/paev4/docker-compose.yml`:

```yaml
services:
  influxdb:
    image: influxdb:2.7
    container_name: influxdb
    ports:
      - "8086:8086"
    volumes:
      - influxdb-data:/var/lib/influxdb2

volumes:
  influxdb-data:
```

Käivita ja oota:

```bash
cd ~/paev4
docker compose up -d influxdb
sleep 10
curl -s http://localhost:8086/health
```

Vastuses on `"status":"pass"` — server elab. Pane tähele: **üks port (8086) annab nii API kui veebiliidese**. Vana TICK-i Chronograf jooksis eraldi konteinerina; 2.x-s on ta siin sees.

!!! tip "Kui health on tühi või Connection refused"
    Server alles käivitub — oota veel ~10 s. Kui jääb püsima: `docker compose logs influxdb`.

### 1.2 Seadistus UI-st — org, bucket, token

Ava brauserist `http://<sinu-VM-IP>:8086` (klassis `192.168.35.12X`, VPN-ist `192.168.100.12X`).

Esimene ekraan on **onboarding**. Täida:

- **Username:** `admin`
- **Password:** `Monitor2026!`
- **Organization:** `hkhk`
- **Bucket:** `mon`

Klõpsa **Continue**. Sa just lõid kolm asja, mis on InfluxDB 2.x andmemudeli alus:

- **Organisatsioon** (`hkhk`) — kõrgeim tase, eraldab meeskonnad/projektid.
- **Bucket** (`mon`) — siin andmed elavad; sisaldab ka retention-perioodi (kui kaua hoida). Vana 1.x "database + retention policy" on koondunud bucket'iks.
- **Operator token** — täisõigustega võti, tekkis automaatselt.

Mine **Load Data → API Tokens**, ava `admin's Token`, **Copy to Clipboard**. Salvesta shell-muutujasse (vajad seda Telegrafi jaoks):

```bash
export INFLUX_TOKEN="kleebi_token_siia"
```

!!! tip "Kui onboarding ekraani ei tule, vaid login"
    Server on juba seadistatud (nt taaskäivitasid). Logi sisse `admin / Monitor2026!`. Token leiad Load Data → API Tokens alt.

💭 **Mõtle:** org → bucket → token on hierarhia. Sinu praeguses tööl — kui mitu meeskonda kirjutaks samasse InfluxDB-sse, mis eraldaks nende andmed ja õigused? Miks on token bucket'i-tasemel piiratav?

---

## Osa 2 · Line protocol käsitsi (I)

> **Miks:** enne kui agent andmeid automaatselt saadab, kirjuta üks punkt **käsitsi**, et näha toorvormingut. Line protocol on tekstivorming, milles **kõik** InfluxDB-sse jõuab — Telegraf, curl, klient toodavad lõpuks sama. Näed seda korra, mõistad ülejäänut.

### 2.1 Üks punkt API kaudu

Line protocol struktuur (meenuta loengut): `measurement,tag-set field-set ajatempel`. Saada üks punkt v2 write-API-le:

```bash
curl "http://localhost:8086/api/v2/write?org=hkhk&bucket=mon&precision=s" \
  --header "Authorization: Token $INFLUX_TOKEN" \
  --data-raw 'cpu_manual,host=minu-vm,region=klass usage=42.0'
```

Lahti võetuna:

```
cpu_manual,host=minu-vm,region=klass usage=42.0
│          └── tag-set (indekseeritud)        └── field (väärtus)
└── measurement (tabel)
```

Ajatempli jätsime välja — InfluxDB paneb praeguse hetke. Saada veel paar punkti:

```bash
curl "http://localhost:8086/api/v2/write?org=hkhk&bucket=mon&precision=s" \
  --header "Authorization: Token $INFLUX_TOKEN" \
  --data-raw 'cpu_manual,host=minu-vm,region=klass usage=55.5
cpu_manual,host=minu-vm,region=klass usage=78.1
cpu_manual,host=teine-vm,region=klass usage=12.0'
```

Iga rida on üks punkt. Teine `host` (`teine-vm`) loob uue seeria — tag'i muutus eraldab andmed.

!!! tip "Kui saad 400 Bad Request"
    Tag-set ja field-set vahel peab olema **tühik**; field on `võti=väärtus`. Line protocol on tühiku-tundlik. Kontrolli ka, et token on õige (`401` = vale/tühi token).

💭 **Mõtle:** sa lisasid `host` ja `region` tag'idena, `usage` field'ina. Miks on tag indekseeritud (kiire filter), aga field mitte? Mis juhtuks jõudlusega, kui paneksid `usage` väärtuse hoopis tag'iks?

---

## Osa 3 · Data Explorer — päring ja graafik (C)

> **Miks:** käsurida on hea, aga aegridade juures tahad graafikut. InfluxDB 2.x **Data Explorer** on see, mis vanas TICK-is oli eraldi tööriist **Chronograf** — nüüd ta core'i sisse. Eelis: visuaalne **Query Builder** ehitab päringu klikkides ja näitab, millise Flux-koodi see tekitas. Sa ei pea Flux'i peast teadma — ehitad, näed, siis loed.

### 3.1 Ehita päring klikkides

UI-s vali ülalt **Data Explorer** (graafiku-ikoon vasakus servas). Builder'is:

1. **FROM** → vali bucket `mon`.
2. **Filter** → `_measurement` = `cpu_manual`.
3. Vajuta **Submit** (paremal all).

Näed graafikut oma käsitsi-kirjutatud punktidest. Ülal saad lülitada **Graph ↔ Table** vaate vahel.

### 3.2 Vaata, mis Flux tekkis

Klõpsa **Script Editor** (builder'i kõrval). Näed Flux'i, mille builder genereeris — umbes:

```flux
from(bucket: "mon")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "cpu_manual")
```

Loe rida-realt: `from` valib bucket'i, `range` aja-akna, `filter` measurement'i. Flux on **torujada** — iga `|>` annab andmed järgmisele sammule (nagu Unix pipe). See on Flux'i põhimõte.

Proovi muuta `range(start: -1h)` → `range(start: -10m)` ja **Submit**. Vaade kitseneb.

!!! tip "Kui graafik on tühi"
    Aja-aken on liiga kitsas või andmed vanemad. Suurenda `range` (nt `-24h`), või kontrolli paremalt ülalt ajavahemiku valijat.

!!! info "InfluxQL (SQL-tunne) — valikuline"
    Kui eelistad SQL-laadset süntaksit, InfluxDB 2.x toetab vana **InfluxQL**-i v1-compat API kaudu (`/query` endpoint). Flux on aga 2.x natiivne keel ja Data Explorer töötab Flux'iga — selles labis kasutame Flux'i.

💭 **Mõtle:** Data Explorer on InfluxDB-spetsiifiline. Päev 1 kasutasid Grafanat, mis töötab paljude allikate peal. Millal eelistaksid tööriista-omast UI-d (Data Explorer) ja millal universaalset (Grafana)?

---

## Osa 4 · Telegraf — agent kogub automaatselt (T)

> **Miks:** seni kirjutasid käsitsi. Päriselus teeb seda **agent** taustal. Telegraf on TICK-i kõige elavam tükk: ~300 input-pluginat, töötab ükskõik millise sihtkohaga. Kõige tähtsam — sama Telegraf, mida siin seadistad, töötab tööl ükskõik millise TSDB-ga.

### 4.1 Telegrafi config — baas

Loo `~/paev4/telegraf.conf`. Alusta minimaalsest: agent + üks input + output.

```toml
[agent]
  interval = "10s"
  hostname = "minu-vm"

# INPUT: CPU mõõdikud
[[inputs.cpu]]
  percpu = false
  totalcpu = true

# OUTPUT: InfluxDB 2.7
[[outputs.influxdb_v2]]
  urls = ["http://influxdb:8086"]
  token = "${INFLUX_TOKEN}"
  organization = "hkhk"
  bucket = "mon"
```

Kaks asja: **`outputs.influxdb_v2`** kirjutab v2 API kaudu (`organization` = `hkhk`, `bucket` = `mon`); **`${INFLUX_TOKEN}`** loetakse keskkonnamuutujast, et seda ei peaks faili kirjutama.

### 4.2 Lisa Telegraf compose'i

Lisa `docker-compose.yml`-i `services:` alla (enne `volumes:`):

```yaml
  telegraf:
    image: telegraf:1.34
    container_name: telegraf
    environment:
      - INFLUX_TOKEN=${INFLUX_TOKEN}
    volumes:
      - ./telegraf.conf:/etc/telegraf/telegraf.conf:ro
    depends_on:
      - influxdb
```

Telegraf loeb tokeni keskkonnast, mille `docker compose` edasi annab. Token on juba eksporditud (Osa 1.2) — kontrolli ja käivita:

```bash
echo $INFLUX_TOKEN   # ei tohi olla tühi
docker compose up -d telegraf
docker compose logs -f telegraf
```

Otsi rida `Wrote batch of N metrics`. Kui see ilmub iga ~10 s tagant, andmed voolavad. Välju `Ctrl+C`.

!!! tip "Kui logis on `unauthorized` / `401`"
    `INFLUX_TOKEN` ei jõudnud Telegrafini. Kontrolli `echo $INFLUX_TOKEN` (eksporti **enne** `docker compose up`), ja et `organization`/`bucket` confis on `hkhk`/`mon`.

!!! tip "Kui `connection refused` InfluxDB-le"
    `urls` peab olema `http://influxdb:8086` (konteineri nimi), mitte `localhost` — Telegraf ja InfluxDB on samas Docker-võrgus.

### 4.3 Näe Telegrafi andmeid Data Explorer'is

Mine UI Data Explorer'isse, vali bucket `mon`, filter `_measurement` = `cpu`. Näed reaalset CPU joont, mis kasvab iga 10 s. Telegraf lõi measurement'i `cpu` automaatselt.

### 4.4 Lisa veel inpute

Lisa `telegraf.conf`-i `inputs.cpu` järele:

```toml
[[inputs.mem]]

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "overlay"]
```

Rakenda (Telegraf loeb confi käivitusel):

```bash
docker compose restart telegraf
```

Data Explorer'is on nüüd ka measurement'id `mem` ja `disk`. Üks agent, üks config, mitu allikat.

💭 **Mõtle:** Telegrafil on push-mudel (agent saadab), Prometheusel pull (server tõmbab). Mis olukorras on push parem — näiteks kui sensorid on tulemüüri taga ega ole väljast kättesaadavad?

---

## Osa 5 · Flux sügavamalt — aja-aknad (kodus)

> **Miks:** aegridade juures on tavaline küsimus mitte "mis on väärtus", vaid "mis on keskmine 1-minutilistes akendes viimase tunni jooksul". Flux teeb seda `aggregateWindow`-iga.

Data Explorer **Script Editor**'is proovi (kirjuta Flux otse):

**Aja-aknad** — keskmine CPU 1-minutilistes ämbrites:

```flux
from(bucket: "mon")
  |> range(start: -30m)
  |> filter(fn: (r) => r._measurement == "cpu" and r._field == "usage_user")
  |> aggregateWindow(every: 1m, fn: mean)
```

`aggregateWindow(every: 1m, fn: mean)` jagab aja 1-minutilisteks akendeks ja võtab igast keskmise — see on **downsampling**, asendab vana InfluxQL `GROUP BY time(1m)`.

Proovi `fn: max` või `fn: min` asemel `mean`. Vaata, kuidas joon muutub.

💭 **Mõtle:** miks on `aggregateWindow`-iga agregeerimine odavam ja kasulikum kui kõigi toorpunktide tagastamine, kui graafikul on 24 tunni jagu andmeid?

---

## Osa 6 · Flux task + check — Kapacitor'i roll (kodus, K)

> **Miks:** vana TICK-i **K** oli **Kapacitor** — eraldi mootor, mis töötles andmeid (downsampling) ja saatis häireid. InfluxDB 2.x-s on see core'i sees: **task** = ajastatud Flux-skript, **check** = läve-hindaja. Siin näed, kuidas neli komponenti on kaheks koondunud.

### 6.1 Task — ajastatud downsampling

UI-s **Tasks → Create Task**. Anna nimi `cpu-1m-keskmine`, intervall `1m`, ja skript:

```flux
option task = {name: "cpu-1m-keskmine", every: 1m}

from(bucket: "mon")
  |> range(start: -2m)
  |> filter(fn: (r) => r._measurement == "cpu" and r._field == "usage_user")
  |> aggregateWindow(every: 1m, fn: mean)
  |> to(bucket: "mon", org: "hkhk")
```

See jookseb iga minut, arvutab keskmise ja kirjutab tagasi. **See on täpselt see, mida Kapacitor tegi** — ainult nüüd InfluxDB enda sees.

### 6.2 Check — läve-häire

UI-s **Alerts → Checks → Create → Threshold Check**. Vali measurement `cpu`, field `usage_user`, ja sea läve: **CRIT kui value > 80**. Salvesta.

Koorma VM-i, et näha häiret:

```bash
yes > /dev/null &   # tekitab 100% CPU
# oota ~1 min, vaata Alerts → Alert History
kill %1             # peata koormus
```

💭 **Mõtle:** vana TICK vajas Kapacitor'it eraldi konteinerina. Mis on eelis, et task ja check on nüüd InfluxDB enda sees? Mis võiks olla puudus (vrd Prometheus + Alertmanager eraldatus)?

---

## Osa 7 · MQTT sensor (kodus)

> **Miks:** siin TSDB-d päriselt domineerivad — tööstus, energia, nutimajad. Sensorid ei kõnele HTTP-d, vaid **MQTT**-d. Telegrafil on MQTT input. Väike maitseproov: üks broker, üks sensor, Telegraf kuulab.

### 7.1 Mosquitto broker

Broker vajab konfi, mis lubab anonüümset ühendust. Loo `~/paev4/mosquitto.conf`:

```
listener 1883 0.0.0.0
allow_anonymous true
```

Lisa `docker-compose.yml`-i `services:` alla:

```yaml
  mosquitto:
    image: eclipse-mosquitto:2
    container_name: mosquitto
    ports:
      - "1883:1883"
    volumes:
      - ./mosquitto.conf:/mosquitto/config/mosquitto.conf:ro
```

```bash
docker compose up -d mosquitto
```

### 7.2 Telegraf MQTT input

Lisa `telegraf.conf`-i:

```toml
[[inputs.mqtt_consumer]]
  servers = ["tcp://mosquitto:1883"]
  topics = ["sensorid/+/temperatuur"]
  data_format = "value"
  data_type = "float"
  name_override = "temperatuur"
```

`+` on metamärk — kuulab kõiki sensoreid (`sensorid/saal1/temperatuur` jne). Rakenda:

```bash
docker compose restart telegraf
```

### 7.3 Simuleeri sensorit

```bash
docker exec mosquitto mosquitto_pub -t "sensorid/saal1/temperatuur" -m "21.5"
docker exec mosquitto mosquitto_pub -t "sensorid/saal2/temperatuur" -m "19.8"
```

Data Explorer'is filter `_measurement` = `temperatuur` — näed sensori-temperatuure. Sama agent, mis kogus CPU-d, kogub nüüd sensoreid; ainult input-plugin muutus.

💭 **Mõtle:** miks on Telegraf + InfluxDB IoT maailma jaoks loomulikum valik kui Prometheus + node_exporter?

---

## ✅ Lõpukontroll (enesekontroll, verifitseeritav)

**Tehniline:**

- [ ] `docker compose ps` kaustas `~/paev4` näitab `influxdb` ja `telegraf` olekus `Up`.
- [ ] `curl -s http://localhost:8086/health` sisaldab `"status":"pass"`.
- [ ] UI onboarding tehtud: org `hkhk`, bucket `mon`, sisselogimine `admin / Monitor2026!` töötab.
- [ ] Kirjutasid käsitsi line protocol punkti ja näed seda Data Explorer'is (`_measurement = cpu_manual`).
- [ ] Telegrafi logis on `Wrote batch of N metrics` iga ~10 s tagant.
- [ ] Data Explorer näitab measurement'e `cpu`, `mem`, `disk` reaalsete väärtustega.
- [ ] (Osa 5) `aggregateWindow`-iga päring tagastab ühe punkti minuti kohta, mitte kõiki toorpunkte.

**Arusaamine (vasta peast):**

- [ ] Selgitad ühe lausega, miks aegread ei sobi tavalisse SQL-andmebaasi suure mahu juures.
- [ ] Loed line protocol rea ja nimetad measurement'i, tag'i, field'i, ajatempli.
- [ ] Nimetad, kus on TICK-i C ja K tänases InfluxDB 2.x-s (Data Explorer + Tasks/Checks).
- [ ] Selgitad push (Telegraf) vs pull (Prometheus) ja millal kumb sobib.

---

## 🚀 Lisaülesanded (kellel aega)

**A. Grafana InfluxDB peal.** Kui päev 1 Grafana stack on alles, lisa InfluxDB datasource (Flux) ja ehita CPU dashboard. Sama Grafana, mis töötas Prometheuse peal, töötab ka TSDB peal — LGTM-põhimõte praktikas.

**B. Docker input.** Lisa `[[inputs.docker]]` (mount `/var/run/docker.sock`). Telegraf jälgib nüüd su konteinerite ressursse — sama VM, uus allikas.

**C. Retention.** Sea `mon` bucket'ile 7-päevane retention (UI: Load Data → Buckets → mon → Settings). Mõtle, miks aegridade puhul on automaatne vanade andmete kustutamine olulisem kui tavalises andmebaasis.

**D. Cardinality katse.** Kirjuta line protocol punkte unikaalse `host` tag'iga (`host=vm-1` ... `host=vm-1000`). See kasvatab cardinality't — mõtle, miks see on TSDB suurim peavalu (meenuta loengut).

---

## Veaotsing

| Probleem | Kontroll | Lahendus |
|---|---|---|
| `docker pull` jääb toppama | — | IPv6 välja (vt Eeltöö hoiatus), `docker compose` uuesti. |
| `curl :8086/health` tühi / refused | `docker compose ps` | Server alles käivitub või maas. `docker compose logs influxdb`. |
| Onboarding asemel login-ekraan | — | Juba seadistatud. Logi `admin / Monitor2026!`. Token: Load Data → API Tokens. |
| Kõik käsud → `401 unauthorized` | `echo $INFLUX_TOKEN` | Token tühi/vale. Kopeeri uuesti UI-st (Load Data → API Tokens). |
| `400 Bad Request` line protocol kirjutamisel | rea süntaks | Tag-set ja field-set vahel tühik; field on `võti=väärtus`. |
| Telegraf logis `401` | `docker exec telegraf env \| grep INFLUX` | `INFLUX_TOKEN` ei jõudnud konteinerisse. Eksporti ja `docker compose up -d telegraf` uuesti. |
| Telegraf `connection refused` | `urls` confis | Peab olema `http://influxdb:8086` (konteineri nimi), mitte `localhost`. |
| Data Explorer graafik tühi | aja-aken | Suurenda `range` (nt `-24h`) või kontrolli paremalt ülalt ajavahemikku. |

---

## 📚 Allikad

| Allikas | URL | Miks oluline |
|---|---|---|
| InfluxDB 2.7 docs | <https://docs.influxdata.com/influxdb/v2/> | Ametlik seadistus- ja CLI-viide. |
| Get started (2.x) | <https://docs.influxdata.com/influxdb/v2/get-started/> | Setup, write, query samm-sammult. |
| Line protocol | <https://docs.influxdata.com/influxdb/v2/reference/syntax/line-protocol/> | Toorvormingu täpne süntaks. |
| Flux põhialused | <https://docs.influxdata.com/flux/v0/get-started/> | `from`, `range`, `filter`, `aggregateWindow`. |
| Telegraf docs + pluginad | <https://docs.influxdata.com/telegraf/v1/> | ~300 input/output plugina viide. |
| Tasks (Kapacitor'i roll) | <https://docs.influxdata.com/influxdb/v2/process-data/> | Ajastatud Flux-skriptid. |
| Checks & alerts | <https://docs.influxdata.com/influxdb/v2/monitor-alert/> | Läve-häired UI-st. |

--8<-- "_snippets/abbr.md"
