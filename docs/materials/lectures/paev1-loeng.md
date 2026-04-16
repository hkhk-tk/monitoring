# Päev 1: Prometheus ja Grafana

*Iseseisev lugemine enne labi*

**Eeldused:** [Observability loeng](paev1-observability.md) loetud  
**Dokumentatsioon:** [prometheus.io](https://prometheus.io) | [PromLabs Training](https://training.promlabs.com/)

---

## Õpiväljundid

Pärast seda loengut:

- Mõistad, miks Prometheus loodi ja milliseid probleeme see lahendab
- Oskad selgitada, kuidas Prometheus erineb traditsioonilistest seiretööriistadest
- Tead, millal Prometheus sobib ja millal mitte
- Mõistad aegrea andmemudelit ja label'ite tähtsust
- Oskad lugeda lihtsamaid PromQL päringuid
- Tead, kuidas hoiatused töötavad

---

## Sissejuhatus: Miks Me Seda Vajame?

Alustame küsimusega: miks me üldse vajame Prometheust? Kas pole Nagios, Zabbix ja teised tööriistad juba olemas?

### Mikroteenuste probleem

2010. aastatel hakkas toimuma suur muutus: monoliitrakendustest mikroteenustesse. Äkki pole teil enam 10 serverit, vaid 100 konteinerit. Need konteinerid tulevad ja lähevad automaatselt. Kubernetes skaleerib neid vastavalt koormusele.

Vana seire ei sobinud enam:
- Nagios: käsitsi konfigureerid iga serveri
- Zabbix: agendid peavad olema eelnevalt seadistatud
- Mõlemad: ei tea konteinerite dünaamilisest elust midagi

<img src="https://training.promlabs.com/static/prometheus-abstract-pipeline-fcb092ef3974c2ada13032abdec22c29.svg" alt="Prometheus pipeline" width="600">

*Prometheus töövoog: rakendused → scraping → TSDB → päringud → hoiatused. Allikas: [PromLabs Training](https://training.promlabs.com/)*

SoundCloud seisis 2012. aastal sama probleemi ees. Neil oli sadu mikroteenuseid, mis muutusid pidevalt. Julius Volz ja tema meeskond otsustasid luua midagi uut — Prometheus sündis. 2016. aastal sai sellest CNCF-i teine projekt pärast Kubernetes-t. Täna kasutavad Prometheust Bolt, Wise, Pipedrive, Twitter ja tuhanded teised.

---

## 1. Mis on Prometheus põhimõtteliselt?

Prometheus on avatud lähtekoodiga süsteemide seire ja hoiatuste tööriistakomplekt. Kolm asja teevad selle eriliseks.

**Prometheus KÜSIB ise — pull mudel**

Traditsiooniline seire: rakendus saadab andmeid serverile.
```
[Rakendus] --saadab--> [Seire server]
```

Prometheus: ise küsib regulaarselt.
```
[Prometheus] --küsib--> [Rakendus /metrics]
```

Miks see parem on? Prometheus otsustab ise, millal ja kui sageli koguda. Kui rakendus on maas, Prometheus näeb seda kohe — scrape ebaõnnestub.

**Kõik on aegread**

Iga mõõdik on aegrida — väärtuste jada ajas. Mitte lihtsalt "CPU on 45%", vaid "CPU oli 43%, siis 45%, siis 47%..." See võimaldab näha trende, ennustada probleeme, mõista mustreid.

**Võimas päringukeel PromQL**

Sa ei küsi "mis on CPU kasutus?". Sa küsid "kui palju on CPU kasutus kasvanud viimase 5 minuti jooksul, grupeerituna serveri järgi?" — ja saad vastuse sekunditega.

<img src="https://training.promlabs.com/static/d9e03d17f39f1bd2614a5162449e07c6/00d43/prometheus-graph-page-screenshot.png" alt="Prometheus UI" width="600">

*Prometheus UI — PromQL päringud ja graafikud. Allikas: [PromLabs Training](https://training.promlabs.com/)*

---

## 2. Mis Prometheus EI OLE

Enne sügavamale minekut — ootuste haldamine hoiab ära hilisemad pettumused.

**Prometheus ei ole pikaajaline salvestus.** Ta hoiab mõõdikuid vaikimisi 15 päeva. Aastate trendide jaoks vajad Thanos-t või Mimir-it.

**Prometheus ei ole logihaldussüsteem.** Ta on ainult mõõdikute jaoks. Logide analüüsiks kasuta ELK Stack-i või Loki-t — mõlemad tulevad järgmistel päevadel.

**Prometheus ei ole distributed tracing.** Jaeger ja Tempo näitavad päringu teekonda läbi mikroteenuste. Prometheus näitab kui kiiresti need teenused töötavad — aga mitte päringute teed. Tracing tuleb päeval 5.

Millal Prometheus sobib:
- Mikroteenused ja konteinerid
- Kubernetes
- Dünaamilised keskkonnad
- Kui fookus on numbrilistel mõõdikutel

Millal ei sobi:
- Kui vajad ainult logide otsingut
- Kui vajad aastaid ajaloolisi andmeid
- Kui vajad 100% täpsust arvelduse jaoks

---

## 3. Arhitektuur — kuidas see töötab

Prometheus ei ole üks programm — see on tööriistakomplekt mitmest komponendist.

<img src="https://training.promlabs.com/static/prometheus-architecture-a119718f561df181406e112e6174d907.svg" alt="Prometheus arhitektuur" width="600">

*Prometheus arhitektuur: server, exporterid, Pushgateway, AlertManager, visualiseerimine. Allikas: [PromLabs Training](https://training.promlabs.com/)*

**Prometheus Server** on süda. Ta kogub mõõdikuid HTTP GET päringuga `/metrics` endpoint'ilt, salvestab need aegrea andmebaasi (TSDB) ja hindab hoiatuste reegleid.

**Exporterid** on tõlkijad. Sinu Linux server ei tea mis on Prometheus. Nginx ei tea. MySQL ei tea. Exporter on väike programm, mis loeb süsteemi statistikat (näiteks Linuxi `/proc` kataloogist) ja pakub seda Prometheus-e formaadis `/metrics` endpoint'il. Node Exporter teeb seda Linuxi serveri jaoks — CPU, mälu, ketas, võrk.

**Pushgateway** on erijuht — lühiajaliste batch job'ide jaoks. Cronjob, mis töötab 30 sekundit ja lõpeb, ei jõua Prometheus-e scrape'imist oodata. Ta saadab mõõdikud Pushgateway'le, Prometheus loeb sealt.

**AlertManager** on intelligentne teavitaja. Prometheus tuvastab probleemi, AlertManager otsustab mida teha: grupeerib sarnased hoiatused üheks emailiks, suunab andmebaasi alertid DBA meeskonnale, summutab hoiatused plaanilise hoolduse ajal.

### Pull vs Push — miks see vahe on oluline

<img src="https://training.promlabs.com/static/prometheus-sd-architecture-122b09757f1dbd6ace435cd70fdb81c5.svg" alt="Service discovery" width="600">

*Service Discovery: Prometheus leiab sihtmärgid automaatselt. Allikas: [PromLabs Training](https://training.promlabs.com/)*

Push-mudelis (Zabbix, Nagios) saadab agent andmeid serverile. Kui agent vaikib, ei tea sa miks — kas agent on maas, võrk on katki, või pole lihtsalt midagi saata?

Pull-mudelis küsib Prometheus ise iga 15 sekundi järel. Kui sihtmärk ei vasta — Prometheus näeb seda kohe, `up` mõõdik läheb nulli ja alert käivitub. Lisaks saad sihtmärgi `/metrics` lehe lihtsalt brauseris avada ja näed täpselt mida Prometheus näeks — see teeb debugimise palju lihtsamaks.

---

## 4. Aegrea andmemudel

Kuidas Prometheus andmeid salvestab? See on kogu süsteemi võtmekontseptsioon.

Tavalises andmebaasis on read: kasutaja nimi, email, vanus. Prometheus-es on aegread — sama väärtus erinevatel aegadel:

```
cpu_usage 10:00 → 45%
cpu_usage 10:01 → 47%
cpu_usage 10:02 → 43%
cpu_usage 10:03 → 50%
```

Meid huvitab muutus ajas — kas CPU tõuseb? Kui kiiresti? Mis hetkel täpselt hakkas tõusma?

### Andmemudeli struktuur

Iga aegrida koosneb kolmest osast — mõõdiku nimest, label'itest ja väärtusest koos ajatempliga:

```
http_requests_total{method="GET", path="/api/users", status="200"} 1234 @14:23:45
```

<img src="https://training.promlabs.com/static/prometheus-data-model-7756d9169168839cd7145f4aaa7e39df.svg" alt="Andmemudeli struktuur" width="600">

*Andmemudel: metric name + labels = series identity. Allikas: [PromLabs Training](https://training.promlabs.com/)*

### Label'id — miks need on võimsad

Ilma label'ideta vajaksid eraldi mõõdiku iga kombinatsiooni jaoks: `server1_api_users_get_requests`, `server1_api_users_post_requests`... 3 serverit × 2 endpoint'i × 2 meetodit = 12 erinevat mõõdikut.

Label'itega on üks mõõdik `http_requests_total` ja filtreerid vajalikku:
```promql
http_requests_total{server="server1", method="GET"}
```

<img src="https://training.promlabs.com/static/prometheus-data-model-series-graph-379763ef781612bc7dddf098e32b0525.svg" alt="Aegrea graafikud" width="600">

*Üks mõõdik, erinevad label'i kombinatsioonid = mitu aegrida graafikul. Allikas: [PromLabs Training](https://training.promlabs.com/)*

**Kardnaalsuse ohumärk:** Ära kasuta label'ina midagi, millel on tuhandeid väärtusi — `user_id`, `email`, `session_id`. 3 serverit × 10 000 kasutajat = 30 000 aegrida, mis võib Prometheus-e maha võtta. Label'id peavad olema madala kardnaalsusega: `method` (4 väärtust), `status` (mõned väärtused), `server` (mõned väärtused).

### Neli mõõdikutüüpi

**Counter** ainult kasvab — päringute arv, vigade arv, töödeldud baidid. Nullistub ainult teenuse taaskäivitusel. Kasuta alati koos `rate()` funktsiooniga.

**Gauge** tõuseb ja langeb vabalt — CPU kasutus, mälu hulk, aktiivsete ühenduste arv. Kasuta otse, ilma `rate()`-ta.

**Histogram** mõõdab jaotust bucket'ites — vastuse ajad, päringu suurused. Kasuta `histogram_quantile()` funktsiooniga p95, p99 arvutamiseks.

**Summary** on sarnane histogram'ile aga arvutab protsentiilid kliendi poolel — vähem paindlik, eelistada histogram'i.

---

## 5. Mõõdikute formaat `/metrics` endpoint'il

Prometheus kasutab lihtsat tekstiformaati — inimloetav, lihtne parsida:

```
# HELP http_requests_total The total number of HTTP requests.
# TYPE http_requests_total counter
http_requests_total{method="GET",path="/api/users",status="200"} 1234
http_requests_total{method="POST",path="/api/users",status="201"} 567

# HELP node_memory_MemAvailable_bytes Memory information field MemAvailable.
# TYPE node_memory_MemAvailable_bytes gauge
node_memory_MemAvailable_bytes 2147483648
```

`# HELP` rida on inimestele — kirjeldab mida mõõdik tähendab. `# TYPE` rida on Prometheus-ele — ütleb kas tegemist on counter, gauge, histogram või summary-ga.

Sa saad seda ise kontrollida:
```bash
curl http://localhost:9100/metrics | head -20
```

See on täpselt see, mida Prometheus iga 15 sekundi järel sihtmärkidelt saab.

---

## 6. PromQL — päringukeel lühidalt

PromQL on spetsiaalselt aegrea andmete jaoks loodud keel. Erineb SQL-ist fundamentaalselt.

<img src="https://training.promlabs.com/static/prometheus-architecture-promql-c17cab57350af33a41588d9a1f37b4f6.svg" alt="PromQL arhitektuuris" width="600">

*PromQL: päringud TSDB vastu → tulemused visualiseerimiseks ja hoiatusteks. Allikas: [PromLabs Training](https://training.promlabs.com/)*

**Filtreerimine label'ite järgi:**
```promql
# Kõik HTTP päringud
http_requests_total

# Ainult GET päringud
http_requests_total{method="GET"}

# Kõik peale GET
http_requests_total{method!="GET"}

# Regex — kõik 5xx vastused
http_requests_total{status=~"5.."}
```

**`rate()` — kõige olulisem funktsioon:**

Counter väärtus ise ei ütle midagi kasulikku — 1 234 567 päringut alates käivitusest. `rate()` arvutab kasvu kiiruse sekundis:

```promql
# VALE — absoluutarv, kasvab pidevalt
http_requests_total

# ÕIGE — päringuid sekundis viimase 5 minuti põhjal
rate(http_requests_total[5m])
```

`[5m]` on ajavahemik — Prometheus vaatab viimase 5 minuti andmeid. Mida laiem aken, seda silutum graafik.

**Agregeerimine:**
```promql
# Kõigi serverite päringud kokku
sum(rate(http_requests_total[5m]))

# Grupeeritud meetodi järgi
sum by(method) (rate(http_requests_total[5m]))

# CPU kasutus % per server
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

---

## 7. Hoiatused — automaatne reaktsioon

Prometheus hindab reegleid regulaarselt. Kui tingimus kehtib, käivitub hoiatus:

```yaml
- alert: HighCPUUsage
  expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
  for: 2m
  labels:
    severity: warning
  annotations:
    summary: "Kõrge CPU: {{ $labels.instance }}"
```

`for: 2m` on kriitiline — tingimus peab kehtima katkematult 2 minutit enne hoiatuse saatmist. See väldib valehoiatusi mööduvate spike'ide peale.

AlertManager võtab hoiatused vastu ja otsustab mida teha:
- **Grupeerib** — 10 serverit on maas → 1 teade, mitte 10
- **Suunab** — andmebaasi alertid DBA meeskonnale, kriitilised kõigile
- **Summutab** — planeeritud hooldus, 2 tundi vaikust

---

## 8. Grafana — miks eraldi tööriist?

Prometheus-el on oma lihtne UI päringute tegemiseks. Aga see on arendaja tööriist.

Grafana on visualiseerimisplatvorm, mis ühendab erinevaid andmeallikaid. Oluline: **Grafana ise ei kogu andmeid** — ta küsib neid Prometheus-elt (või Loki-lt, Elasticsearch-ist jne) ja kuvab graafikutena.

See tähendab, et ühel Grafana dashboardil saad näidata mõõdikuid Prometheus-est, logisid Loki-st ja trace-e Tempo-st — kõik koos, täielik observability pilt.

**Visualiseerimistüübid:**

| Tüüp | Millal kasutada |
|------|----------------|
| Time series | Trendid ajas — CPU, võrguliiklus |
| Stat | Üks hetkenumber — aktiivsed serverid |
| Gauge | Protsent poolringina — ketta täituvus |
| Bar gauge | Võrdlus — top 5 koormatum server |

**Variables** teevad dashboardi dünaamiliseks — kasutaja valib dropdown-ist serveri ja kõik paneelid uuenevad automaatselt. **Thresholds** värvivad väärtused automaatselt: alla 70% roheline, 70-90% kollane, üle 90% punane.

---

## Kokkuvõte

Prometheus lahendab dünaamiliste keskkondade monitooringu probleemi pull-mudeliga, aegrea andmebaasiga ja võimsa PromQL päringkeelega. Grafana lisab visualiseerimiskihi. AlertManager tegeleb intelligentse teavitamisega.

**Meeles pidada:**
- Counter vajab `rate()` — ilma selleta on arv kasutu
- Label'id on võimsad aga hoia kardnaalsus madalal
- `for:` alertireeglites väldib valehoiatusi
- Grafana ei kogu andmeid — ta ainult küsib neid

Laboris ehitad täna töötava Prometheus + Grafana + Alertmanager stacki ja näed kõiki neid kontseptsioone praktikas.

---

## Allikad

| Allikas | Miks lugeda |
|---------|-------------|
| [Prometheus dokumentatsioon](https://prometheus.io/docs/introduction/overview/) | Ametlik allikas, alati ajakohane |
| [PromLabs Training](https://training.promlabs.com/) | Julius Volz (Prometheus looja) tasuta kursused |
| [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/) | Prindi välja, hoia laua peal |
| [Prometheus metric types](https://prometheus.io/docs/concepts/metric_types/) | Counter, Gauge, Histogram, Summary |
| [PromQL querying basics](https://prometheus.io/docs/prometheus/latest/querying/basics/) | rate(), sum(), avg() — ametlik seletus |
| [Awesome Prometheus alerts](https://samber.github.io/awesome-prometheus-alerts/) | Valmis alertireeglid tootmiseks |
| [Node Exporter Full (ID 1860)](https://grafana.com/grafana/dashboards/1860) | Professionaalne dashboard näide |
| [AlertManager dokumentatsioon](https://prometheus.io/docs/alerting/latest/alertmanager/) | Routing, grouping, silencing |
| [Google SRE raamat — peatükk 6](https://sre.google/sre-book/monitoring-distributed-systems/) | Four Golden Signals, tööstusstandard |
