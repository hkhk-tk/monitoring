# Päev 4: TICK Stack — InfluxDB 3 Core, Telegraf ja aegread (labor)

**Kestus:** ~4 tundi (klassitöö umbes 2.5 h, ülejäänu kodused lisaülesanded)

**Tase:** kesktase

**Eeldused:** Päev 1 (Docker Compose, Prometheus pull-mudel, Grafana). Aegrida-mõiste, line protocol ja andmemudel (tag/field/timestamp) — loe enne labi [Päev 4 loeng](../../materials/lectures/paev4-loeng.md). SQL `SELECT`, `WHERE`, `GROUP BY` põhialused.
**VM:** sinu VM (`ssh <eesnimi>@192.168.35.12X` klassivõrgust või `192.168.100.12X` VPN-ist)

---

## Miks see labor

Päev 1 kasutasid Prometheust — pull-mudel, mõõdikud, PromQL. See töötab suurepäraselt serverite ja konteinerite jaoks. Aga kui andmeid tuleb teistmoodi — tuhanded sensorid, igaüks saadab väärtuse iga sekund, miljoneid punkte päevas — siis on vaja **spetsialiseeritud aegreade andmebaasi**. Loengus nägid, miks ja kuidas TICK arenes. Täna paned selle ise püsti.

Sellest labist tuled välja viie oskusega:

1. **InfluxDB 3 Core** püsti, token-autentimisega, üks andmebaas loodud.
2. **Line protocol** — kirjutad esimese punkti käsitsi ja näed toorvormingut.
3. **SQL aegridade peal** — päring nii käsurealt kui Exploreri UI-st.
4. **Telegraf** kogub su VM-i süsteemimeetrikaid automaatselt InfluxDB-sse.
5. **Dual-output** — sama agent saadab andmed kahte sihtkohta korraga (tootmismuster).

Erinevalt päev 3 ELK-klastrist on TICK kerge — InfluxDB 3 Core + Explorer + Telegraf mahuvad 4 GB VM-i mängleva kergusega.

---

## 🎯 Õpiväljundid

**Teadmised:**

1. Selgitab, miks aegread vajavad eraldi andmebaasi (mitte PostgreSQL-i) — meenuta loengut.
2. Loeb ja kirjutab line protocol rea: tabel, tag-set, field-set, ajatempel.
3. Põhjendab, mis on Telegrafi roll agendina ja millal eelistada teda `node_exporter`-ile.
4. Toob vähemalt kaks olukorda, kus eelistada InfluxDB-d, ja kaks, kus Prometheust.

**Oskused:**

5. Käivitab InfluxDB 3 Core Docker Compose'iga ja loob operator-tokeni + andmebaasi.
6. Kirjutab andmeid line protocol vormingus käsitsi ja päringustab SQL-iga.
7. Seadistab Telegrafi koguma süsteemimeetrikaid ja saatma neid InfluxDB-sse.
8. Konfigureerib Telegrafi saatma sama voogu kahte sihtkohta (dual-output).

---

## Labi struktuur

Labor on seitsmes osas. Klassis jõuad tavaliselt osadeni 1–4 (põhi-stack püsti ja andmed voolavad); osa 5–7 ja lisaülesanded võivad jääda koju.

| Osa | Teema | ~aeg | Mida sa mõistad lõpus |
|-----|-------|------|------------------------|
| 1 | InfluxDB 3 Core üles + token + andmebaas | 15 min | Server elab, miks token, mis on database |
| 2 | Line protocol käsitsi + SQL päring | 15 min | Toorvorming, kuidas SQL aegridade peal töötab |
| 3 | Explorer UI | 10 min | Visuaalne haldus ja päring |
| 4 | Telegraf → süsteemimeetrikad | 20 min | Agent kogub, andmed voolavad automaatselt |
| 5 | SQL sügavamalt | 20 min | `DATE_BIN`, agregeerimine, tag-filter |
| 6 | Dual-output | 15 min | Sama agent, kaks sihtkohta — tootmismuster |
| 7 | MQTT sensor maitseproov | 25 min | Miks TSDB tööstuses ja IoT-s domineerib |

Töökaust: `~/paev4`. TICK on eraldi ökosüsteem (mitte Grafana LGTM), seega uus kaust on õige.

---

## Eeltöö

Päev 3 ELK/OpenSearch stack võtab palju mälu. Pane see maha:

```bash
cd ~/paev3/elk 2>/dev/null && docker compose down 2>/dev/null
cd ~/paev3/os  2>/dev/null && docker compose down 2>/dev/null
free -h
```

Vaba mälu võiks olla vähemalt 2 GB — TICK ei vaja rohkem. Loo töökaust:

```bash
mkdir -p ~/paev4 && cd ~/paev4
```

---

## Osa 1 · InfluxDB 3 Core üles

> **Miks:** loengust tead, et aegread vajavad eraldi andmebaasi. InfluxDB 3 Core on selle uus avatud lähtekoodiga versioon — andmed kettal Parquet-failidena, päring SQL-iga. Autentimine on **vaikimisi sees** — server ei tee midagi ilma tokenita. See on uus võrreldes vanade InfluxDB versioonidega ja sunnib sind kohe token-loogikaga tegelema.

### 1.1 Baas — ainult InfluxDB

Loo `~/paev4/docker-compose.yml`:

```yaml
services:
  influxdb3-core:
    image: influxdb:3-core
    container_name: influxdb3-core
    ports:
      - "8181:8181"
    command:
      - influxdb3
      - serve
      - --node-id=node0
      - --object-store=file
      - --data-dir=/var/lib/influxdb3/data
    volumes:
      - influxdb3-data:/var/lib/influxdb3/data

volumes:
  influxdb3-data:
```

Pane tähele `command:` plokki — `influxdb3 serve` vajab `--node-id` (selle server identifitseerib end nii) ja `--object-store=file` (andmed lokaalsele kettale, mitte S3-le). Käivita:

```bash
cd ~/paev4
docker compose up -d influxdb3-core
```

Oota ~15 sekundit ja testi:

```bash
curl http://localhost:8181/health
```

Vastuseks tuleb `OK` (server elab). Päringuid veel teha ei saa — pole tokenit.

!!! tip "Kui curl annab Connection refused"
    Server alles käivitub, oota veel umbes 10 sekundit. Kui jääb püsima, vaata `docker compose logs influxdb3-core`.

### 1.2 Operator token

Server ei tee midagi ilma autentimiseta. Esimene token, mille lood, on **operator token** — täisõigustega võti. Loo see konteineri seest:

```bash
docker exec influxdb3-core influxdb3 create token --admin
```

Väljund sisaldab pikka token-stringi (algab `apiv3_...`). **Kopeeri see kohe** — InfluxDB näitab tokenit ainult üks kord, hiljem ei saa seda kätte.

Salvesta token shell-muutujasse, et järgmised käsud oleksid lihtsamad:

```bash
export TOKEN="apiv3_...kleebi_oma_token_siia..."
```

!!! tip "Kui kaotad tokeni"
    Lihtsaim on `docker compose down -v` (kustutab andmed) ja alustad uuesti. Tootmises seda ei juhtu — token läheb saladuste-haldurisse.

### 1.3 Andmebaas

Loo andmebaas nimega `mon`:

```bash
docker exec influxdb3-core influxdb3 create database mon --token "$TOKEN"
```

Kontrolli:

```bash
docker exec influxdb3-core influxdb3 show databases --token "$TOKEN"
```

Nimekirjas on `mon`. InfluxDB 3-s on **database** ülemine tase (vanas 1.x oli see "database + retention policy", 2.x "bucket" — meenuta loengu andmemudeli tabelit).

??? question "Mõtle"
    Miks on token-autentimine vaikimisi sees mõistlik vaikeväärtus aegreade-andmebaasile, mis tihti kogub tundlikke sensori- või äriandmeid? Mis oleks risk, kui see oleks vaikimisi väljas?

---

## Osa 2 · Line protocol käsitsi + SQL

> **Miks:** enne kui agent andmeid automaatselt saadab, kirjuta üks punkt **käsitsi**, et näha toorvormingut. Line protocol on tekstivorming, milles kõik InfluxDB-sse jõuab — Telegraf, curl, klient, kõik toodavad lõpuks sama. Kui näed seda korra käsitsi, mõistad ülejäänut.

### 2.1 Üks punkt käsitsi

Line protocol struktuur (meenuta loengut): `tabel,tag-set field-set ajatempel`. Saada üks punkt HTTP API kaudu:

```bash
curl "http://localhost:8181/api/v3/write_lp?db=mon" \
  --header "Authorization: Bearer $TOKEN" \
  --data-raw 'cpu_manual,host=minu-vm,region=klass usage=42.0'
```

Lahti võetuna:

```
cpu_manual,host=minu-vm,region=klass usage=42.0
│          └── tag-set (indekseeritud)        └── field (väärtus)
└── tabel (measurement)
```

Ajatempli jätsime välja — InfluxDB paneb selle ise (praegune hetk). Saada veel paar punkti erinevate väärtustega:

```bash
curl "http://localhost:8181/api/v3/write_lp?db=mon" \
  --header "Authorization: Bearer $TOKEN" \
  --data-raw 'cpu_manual,host=minu-vm,region=klass usage=55.5
cpu_manual,host=minu-vm,region=klass usage=78.1
cpu_manual,host=teine-vm,region=klass usage=12.0'
```

Iga rida on üks punkt. Pane tähele: teine `host` (`teine-vm`) loob automaatselt uue seeria — tag'i muutus eraldab andmed.

!!! tip "Kui saad 400 Bad Request"
    Vaata, et tag-set ja field-set vahel oleks **tühik**, ja et `field` oleks `võti=väärtus` kujul. Line protocol on tühiku-tundlik.

### 2.2 SQL päring

InfluxDB 3 päringukeel on **SQL** (sama loogika, mis PostgreSQL-is). Päri kõik:

```bash
docker exec influxdb3-core influxdb3 query --database mon --token "$TOKEN" \
  "SELECT * FROM cpu_manual"
```

Näed nelja rida, igal `host`, `region`, `usage`, `time`. Proovi filtrit ja agregaati:

```bash
docker exec influxdb3-core influxdb3 query --database mon --token "$TOKEN" \
  "SELECT host, AVG(usage) FROM cpu_manual GROUP BY host"
```

`minu-vm` keskmine on kolme punkti keskmine, `teine-vm` üks punkt. See on tavaline SQL — `time` veerg lihtsalt tuleb iga tabeliga automaatselt kaasa.

??? question "Mõtle"
    Sa just kirjutasid SQL-i aegridade peal. Mille poolest erineb see Prometheuse PromQL-ist (päev 1)? Kumb tundub loomulikum andmebaasi-taustaga inimesele, kumb monitooringu-taustaga inimesele?

---

## Osa 3 · Explorer UI

> **Miks:** käsurida on hea, aga aegridade juures tahad sa graafikut näha. InfluxDB 3 Explorer on eraldi veebiliides — sama, mida InfluxData ametlikult 3.x ajastul kasutab (vana Chronograf on asendatud). Lisame ta samasse stacki.

### 3.1 Lisa Explorer compose'i

Lisa `docker-compose.yml`-i, `services:` alla (enne `volumes:` plokki):

```yaml
  explorer:
    image: influxdata/influxdb3-ui:1.8.0
    container_name: influxdb3-explorer
    ports:
      - "8888:8080"
    command: ["--mode=admin"]
    volumes:
      - explorer-db:/db
    depends_on:
      - influxdb3-core
```

Ja lisa `volumes:` plokki rida:

```yaml
  explorer-db:
```

Käivita ainult Explorer:

```bash
docker compose up -d explorer
```

`--mode=admin` annab täisõigused (kirjutamine + haldus); ilma selleta oleks Explorer read-only. Konteiner kuulab sees pordil 8080, me avaldame selle hostil pordina 8888.

### 3.2 Ühenda ja päri visuaalselt

Ava brauserist `http://<sinu-VM-IP>:8888` (klassivõrgus `192.168.35.12X`, VPN-ist `192.168.100.12X`).

Esimesel avamisel küsib Explorer ühenduse andmeid:

- **Server URL:** `http://influxdb3-core:8181` — kasuta konteineri nime, mitte `localhost`, sest Explorer ja InfluxDB on samas Docker-võrgus.
- **Token:** sinu operator token (`$TOKEN` väärtus).
- **Database:** `mon`.

Pärast ühendamist vali `mon` andmebaas ja kirjuta sama SQL:

```sql
SELECT * FROM cpu_manual
```

Näed tabelit ja saad lülitada graafiku-vaatesse. Sama päring, mille tegid käsurealt, aga nüüd visuaalselt.

!!! tip "Kui Explorer ütleb connection failed"
    Kontrolli, et Server URL on `http://influxdb3-core:8181` (konteineri nimi), mitte `localhost:8181`. `localhost` viitaks Exploreri enda konteinerile, mitte InfluxDB-le.

??? question "Mõtle"
    Explorer on InfluxDB-spetsiifiline. Päev 1 kasutasid Grafanat, mis töötab paljude andmeallikate peal. Millal eelistaksid tööriista-spetsiifilist UI-d (Explorer) ja millal universaalset (Grafana)?

---

## Osa 4 · Telegraf — agent kogub automaatselt

> **Miks:** seni kirjutasid andmeid käsitsi. Päriselus teeb seda **agent**, mis jookseb taustal ja kogub pidevalt. Telegraf on TICK-ist kõige elavam tükk: ~300 input-pluginat, töötab ükskõik millise sihtkohaga. Kõige tähtsam — sama Telegraf, mida sa siin seadistad, töötab homme tööl ükskõik millise TSDB-ga.

### 4.1 Telegrafi config — baas

Loo `~/paev4/telegraf.conf`. Alusta minimaalsest: agent + üks input + output.

```toml
[agent]
  interval = "10s"
  hostname = "minu-vm"

# INPUT: kogub CPU mõõdikud
[[inputs.cpu]]
  percpu = false
  totalcpu = true

# OUTPUT: saadab InfluxDB 3 Core'i (v2-ühilduva API kaudu)
[[outputs.influxdb_v2]]
  urls = ["http://influxdb3-core:8181"]
  token = "${INFLUX_TOKEN}"
  organization = ""
  bucket = "mon"
```

Kaks asja, mida tasub mõista:

- **`outputs.influxdb_v2`** — InfluxDB 3 Core võtab vastu vana v2 write-API kaudu, seega kasutame `influxdb_v2` output-pluginat. `bucket` = andmebaasi nimi (`mon`), `organization` jääb tühjaks (Core ei kasuta seda).
- **`${INFLUX_TOKEN}`** — Telegraf loeb tokeni keskkonnamuutujast, et seda ei peaks faili kirjutama.

### 4.2 Lisa Telegraf compose'i

Lisa `services:` alla:

```yaml
  telegraf:
    image: telegraf:1.34
    container_name: telegraf
    environment:
      - INFLUX_TOKEN=${INFLUX_TOKEN}
    volumes:
      - ./telegraf.conf:/etc/telegraf/telegraf.conf:ro
    depends_on:
      - influxdb3-core
```

Telegraf loeb tokeni keskkonnast, mille me anname `docker compose`-le edasi. Ekspordi token muutuja, mida compose ootab:

```bash
export INFLUX_TOKEN="$TOKEN"
docker compose up -d telegraf
```

Vaata Telegrafi logi:

```bash
docker compose logs -f telegraf
```

Otsi rida nagu `Wrote batch of N metrics`. Kui see ilmub iga 10 sekundi tagant, voolavad andmed. Välju `Ctrl+C`.

!!! tip "Kui logis on unauthorized või 401"
    `INFLUX_TOKEN` ei jõudnud Telegrafini. Kontrolli, et eksportisid muutuja **enne** `docker compose up`, ja et see on sama token, millega lõid andmebaasi.

### 4.3 Päri Telegrafi andmeid

Telegraf lõi tabeli `cpu`. Päri seda:

```bash
docker exec influxdb3-core influxdb3 query --database mon --token "$TOKEN" \
  "SELECT time, usage_idle, usage_user FROM cpu ORDER BY time DESC LIMIT 5"
```

Näed viit viimast mõõtmist. `usage_idle` näitab jõudeoleku protsenti. Ava sama Exploreris graafikuna — näed CPU joont reaalajas kasvamas.

### 4.4 Lisa veel inpute

Nüüd, kui üks input töötab, lisa veel. Lisa `telegraf.conf`-i `inputs.cpu` järele:

```toml
[[inputs.mem]]

[[inputs.disk]]
  ignore_fs = ["tmpfs", "devtmpfs", "overlay"]
```

Rakenda muudatus (Telegraf loeb confi käivitusel):

```bash
docker compose restart telegraf
```

Päri uut tabelit:

```bash
docker exec influxdb3-core influxdb3 query --database mon --token "$TOKEN" \
  "SELECT time, used_percent FROM mem ORDER BY time DESC LIMIT 3"
```

Iga input loob oma tabeli (`cpu`, `mem`, `disk`). Sama agent, üks config, mitu mõõdiku-allikat.

??? question "Mõtle"
    Telegrafil on push-mudel (agent saadab ise andmed), Prometheusel pull-mudel (server tõmbab). Päev 1 nägid pull-i. Mis olukorras on push parem — näiteks kui sensorid on tulemüüri taga ega ole väljast kättesaadavad?

---

## Osa 5 · SQL sügavamalt

> **Miks:** aegridade juures on tavaline küsimus mitte "mis on väärtus", vaid "mis on keskmine 1-minutilistes akendes viimase tunni jooksul". Selleks on aja-aknad.

Telegraf on nüüd kogunud andmeid mõnda aega. Proovi neid päringuid (Explorer või käsurida).

**Aja-filter** — viimase 10 minuti andmed:

```sql
SELECT time, usage_user FROM cpu
WHERE time > now() - INTERVAL '10 minutes'
ORDER BY time DESC
```

**Aja-aknad `DATE_BIN`-iga** — keskmine CPU 1-minutilistes akendes:

```sql
SELECT
  DATE_BIN(INTERVAL '1 minute', time) AS minut,
  AVG(usage_user) AS keskmine_user
FROM cpu
WHERE time > now() - INTERVAL '30 minutes'
GROUP BY minut
ORDER BY minut DESC
```

`DATE_BIN` on InfluxDB 3 SQL-i viis aega "ämbritesse" jagada — see asendab vana InfluxQL-i `GROUP BY time(1m)`. Tulemus on downsampelitud rida iga minuti kohta.

**Maksimum ja miinimum**:

```sql
SELECT MAX(used_percent), MIN(used_percent) FROM mem
WHERE time > now() - INTERVAL '1 hour'
```

??? question "Mõtle"
    Miks on `DATE_BIN`-iga agregeerimine odavam ja kasulikum kui kõigi toorpunktide tagastamine, kui sul on graafik 24 tunni jagu andmeid?

---

## Osa 6 · Dual-output — tootmismuster

> **Miks:** see on Telegrafi kõige väärtuslikum oskus tööturul. Sama agent saadab samad andmed **kahte sihtkohta korraga**. Tootmises tähendab see, et saad TSDB-d vahetada ilma agente uuesti seadistamata, või saata sama voo nii reaalaja-andmebaasi kui pikaajalisse arhiivi.

Lisa `telegraf.conf`-i teine output `outputs.influxdb_v2` järele. Lihtsaim teine sihtkoht testimiseks on fail:

```toml
# Teine output: kirjuta samad andmed faili (tootmises oleks see nt teine TSDB)
[[outputs.file]]
  files = ["/tmp/telegraf-out.txt"]
  data_format = "influx"
```

Rakenda ja vaata:

```bash
docker compose restart telegraf
docker exec telegraf tail -5 /tmp/telegraf-out.txt
```

Näed samu mõõdikuid line protocol vormingus failis — **ja** samal ajal InfluxDB-s. Üks kogumine, kaks sihtkohta.

**Edasijõudnutele:** asenda `outputs.file` teise päris-sihtkohaga. Kui sul on päev 1 Prometheuse stack veel olemas, proovi `outputs.prometheus_client` — siis sama Telegraf serveerib mõõdikuid ka Prometheusele scrape'imiseks. See on täpselt see muster, mida loeng kirjeldas: üks agent, InfluxDB + Prometheus korraga.

??? question "Mõtle"
    Sinu praeguses tööl — kui peaksid TSDB-d vahetama (nt InfluxDB → VictoriaMetrics), kui palju tööd oleks, kui kõik agendid kirjutavad otse ühte sihtkohta? Kuidas dual-output või marsruteerija (Vector, loeng) seda muudaks?

---

## Osa 7 · MQTT sensor — maitseproov

> **Miks:** siin on koht, kus TSDB-d päriselt domineerivad — tööstus, energia, nutimajad. Sensorid ei kõnele HTTP-d, nad kõnelevad **MQTT**-d (kerge sõnumiprotokoll). Telegrafil on MQTT input. Teeme väikese maitseproovi: üks MQTT broker, üks simuleeritud sensor, Telegraf kuulab.

### 7.1 Lisa Mosquitto broker

Lisa `docker-compose.yml`-i `services:` alla:

```yaml
  mosquitto:
    image: eclipse-mosquitto:2
    container_name: mosquitto
    ports:
      - "1883:1883"
    command: ["mosquitto", "-c", "/mosquitto-no-auth.conf"]
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

`topics` kasutab metamärki `+` — kuulab kõiki sensoreid (`sensorid/saal1/temperatuur`, `sensorid/saal2/temperatuur` jne). Rakenda:

```bash
docker compose restart telegraf
```

### 7.3 Simuleeri sensorit

Saada paar mõõtmist (kasutame Mosquitto enda klienti konteinerist):

```bash
docker exec mosquitto mosquitto_pub -t "sensorid/saal1/temperatuur" -m "21.5"
docker exec mosquitto mosquitto_pub -t "sensorid/saal1/temperatuur" -m "22.1"
docker exec mosquitto mosquitto_pub -t "sensorid/saal2/temperatuur" -m "19.8"
```

Päri:

```bash
docker exec influxdb3-core influxdb3 query --database mon --token "$TOKEN" \
  "SELECT * FROM temperatuur ORDER BY time DESC"
```

Näed sensori-temperatuure InfluxDB-s. Sama tööriist, mis kogus CPU-d, kogub nüüd sensori-andmeid — ainult input-plugin muutus.

??? question "Mõtle"
    Loengus nägid, et TICK-i sugu andmebaasid domineerivad tööstuses ja IoT-s. Pärast seda harjutust — miks on Telegraf + InfluxDB selle maailma jaoks loomulikum valik kui Prometheus + node_exporter?

---

## ✅ Lõpukontroll (tehnika + arusaamine)

**Tehniline (kontrollitav):**

- [ ] `docker compose ps` kaustas `~/paev4` näitab `influxdb3-core`, `explorer` ja `telegraf` olekus `Up`.
- [ ] `curl http://localhost:8181/health` vastab `OK`.
- [ ] `influxdb3 show databases` näitab andmebaasi `mon`.
- [ ] Kirjutasid käsitsi line protocol punkti ja nägid seda `SELECT * FROM cpu_manual` väljundis.
- [ ] Explorer UI ühendub `http://influxdb3-core:8181` peale ja näitab sinu andmeid graafikuna.
- [ ] Telegrafi logis on näha `Wrote batch of N metrics` iga ~10 s tagant.
- [ ] `SELECT ... FROM cpu` tagastab Telegrafi kogutud reaalseid mõõdikuid.
- [ ] (Osa 5) `DATE_BIN`-iga päring tagastab ühe rea minuti kohta, mitte kõiki toorpunkte.

**Arusaamine (vasta peast):**

- [ ] Suudad ühe lausega selgitada, miks aegread ei sobi tavalisse SQL-andmebaasi suure mahu juures.
- [ ] Oskad lugeda line protocol rida ja nimetada, kus on tabel, tag, field, ajatempel.
- [ ] Suudad nimetada kaks olukorda, kus eelistad Telegrafi `node_exporter`-ile, ja kaks vastupidi.
- [ ] Selgitad, mis vahe on push- (Telegraf) ja pull-mudelil (Prometheus) ning millal kumb sobib.

---

## 🚀 Lisaülesanded (kellel veel aega)

**A. Grafana InfluxDB peal.** Kui sul on päev 1 Grafana stack veel alles, lisa InfluxDB 3 datasource (SQL/FlightSQL) ja ehita CPU dashboard. Sama Grafana, mis töötas Prometheuse peal, töötab ka TSDB peal — see on LGTM-põhimõte praktikas.

**B. Docker input.** Lisa `[[inputs.docker]]` Telegrafi confi (mount `/var/run/docker.sock`). Nüüd jälgib Telegraf su konteinerite ressursikasutust — sama VM, uus mõõdikute allikas.

**C. Retention.** Explorer 1.8 oskab andmebaasile retention-perioodi seada. Sea `mon` andmebaasile 7-päevane retention ja mõtle, miks aegridade puhul on automaatne vanade andmete kustutamine olulisem kui tavalises andmebaasis.

**D. Cardinality katse.** Kirjuta line protocol punkte, kus iga punkt on uue unikaalse `host` tag-väärtusega (nt `host=vm-1`, `host=vm-2` ... `host=vm-1000`). See kasvatab cardinality't. Mõtle, miks see on TSDB suurim peavalu (meenuta loengut).

---

## Veaotsing

| Probleem | Kontroll | Lahendus |
|---|---|---|
| `curl localhost:8181/health` → Connection refused | `docker compose ps` | Server alles käivitub või ei tööta. `docker compose logs influxdb3-core`. |
| `create token` ei anna tokenit | `docker compose logs influxdb3-core` | Server pole valmis. Oota ja proovi uuesti. |
| Kõik käsud → `401 unauthorized` | `echo $TOKEN` | `$TOKEN` on tühi või vale. Loo uus token või kontrolli muutujat. |
| Telegraf logis `401`/`unauthorized` | `docker exec telegraf env \| grep INFLUX` | `INFLUX_TOKEN` ei jõudnud konteinerisse. Ekspordi muutuja ja `docker compose up -d telegraf` uuesti. |
| Telegraf `connection refused` InfluxDB-le | `urls` confis | Peab olema `http://influxdb3-core:8181` (konteineri nimi), mitte `localhost`. |
| Explorer "connection failed" | Server URL UI-s | Kasuta `http://influxdb3-core:8181`, mitte `localhost:8181`. |
| `400 Bad Request` line protocol kirjutamisel | rea süntaks | Tag-set ja field-set vahel peab olema tühik; field on `võti=väärtus`. |
| SQL päring → tabelit ei leita | `influxdb3 query "SELECT table_name FROM information_schema.tables"` | Andmeid pole veel kirjutatud või tabeli nimi vale. |

---

## 📚 Allikad

| Allikas | URL | Miks oluline |
|---|---|---|
| InfluxDB 3 Core docs | <https://docs.influxdata.com/influxdb3/core/> | Ametlik seadistus- ja CLI-viide. |
| InfluxDB 3 Core — Get started | <https://docs.influxdata.com/influxdb3/core/get-started/> | Setup, write, query samm-sammult. |
| Line protocol viide | <https://docs.influxdata.com/influxdb3/core/reference/line-protocol/> | Toorvormingu täpne süntaks. |
| InfluxDB 3 Explorer docs | <https://docs.influxdata.com/influxdb3/explorer/> | UI seadistus ja kasutus. |
| Telegraf docs + pluginad | <https://docs.influxdata.com/telegraf/v1/> | ~300 input/output plugina viide. |
| Telegraf InfluxDB 3 output | <https://docs.influxdata.com/influxdb3/core/write-data/use-telegraf/> | `influxdb_v2` output InfluxDB 3-le. |
| SQL viide (InfluxDB 3) | <https://docs.influxdata.com/influxdb3/core/reference/sql/> | `DATE_BIN`, agregaadid, aja-funktsioonid. |

--8<-- "_snippets/abbr.md"
