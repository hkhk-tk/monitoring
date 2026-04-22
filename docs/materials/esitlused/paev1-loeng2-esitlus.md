---
marp: true
theme: default
paginate: true
header: "Päev 1 · Loeng 2 · Prometheus + Grafana"
footer: "Haapsalu KHK · Monitooring ja jälgitavus · 2026"
---

<!--
KOMBINEERITUD ESITLUSE-SKRIPT — Loeng 2: Prometheus ja Grafana

See fail teenib kolme eesmärki:
  1. SLAIDID — saab renderdada Marp, Reveal.js või importida PowerPointi/Google Slidesi
  2. AUDIO — jutustaja tekst iga slaidi all sobib otse narratsiooniks (~45 min)
  3. VIDEO — visuaali-vihjed ütlevad, mida ekraanil näidata

NotebookLM kasutamine:
  Lae see fail sisse allikaks. NotebookLM suudab genereerida audio overview'd
  (podcast-stiilis dialoogi) või video overview'd.

Kestvused on ligikaudsed — kohanda vastavalt rühmale.
-->

# Prometheus ja Grafana

### Metrics-sammas praktikas

**Päev 1 · Loeng 2 · 45 minutit**

Maria Talvik · Haapsalu KHK · 18.04.2026

<!--
JUTUSTAJA (30 sek):
Tere tulemast teise loengusse. Kui esimene loeng andis raamistiku — kolm sammast,
USE, RED, SLI, SLO — siis see loeng läheb tehnilisse sügavusse. Keskendume
metrics-sambale ja konkreetselt Prometheus'ele ja Grafanale. 45 minutiga käime
läbi kõik, mida vajad laboris töötamiseks.

VISUAAL: pealkiri, Prometheus + Grafana logod
-->

---

## Õpiväljundid

1. **Selgitab** pull-mudeli põhjuseid ja piire
2. **Tõlgendab** aegrea andmemudelit ja label'ite kardinaalsust
3. **Eristab** 4 mõõdikutüüpi: counter, gauge, histogram, summary
4. **Kirjutab** PromQL päringuid (rate, agregeerimine, vektor-matching)
5. **Konfigureerib** alert-reeglid `for:` kestvusega
6. **Kavandab** Grafana dashboardi variables'iga
7. **Põhjendab** skaleerimisotsuseid — föderatsioon vs remote_write

<!--
JUTUSTAJA (30 sek):
Seitse konkreetset oskust. Kui kõik need on omandatud, oled valmis kirjutama
Prometheus'e konfiguratsiooni, kirjutama PromQL päringuid ja kavandama dashboarde.
Ehk kõike, mida vajad tüüpilises DevOps või SRE töös.

VISUAAL: nummerdatud loetelu
-->

---

## 1. Kontekst — miks Prometheus tekkis

**2012. SoundCloud.** Skaleerumisprobleem.

Vanad tööriistad (Nagios, Zabbix, Munin) ei sobinud mikroteenustele:

- Staatiline konfiguratsioon
- Push-mudel varjas vigu
- Dimensionaalsus puudus
- Jäigad päringukeeled

<!--
JUTUSTAJA (50 sek):
2012. aasta paiku seisis SoundCloud silmitsi skaleerumisprobleemiga. Monoliit-
rakenduselt liikumine mikroteenustesse tõi olukorra, kus vanad tööriistad lihtsalt
ei sobinud enam.

Nagios, Zabbix, Munin — neil oli kõigil mitu fundamentaalset probleemi.
Konfiguratsioon oli staatiline — iga sihtmärgist tuli manuaalselt teada anda.
Push-mudel varjas vigu — kui agent vaikis, polnud selge, mis on valesti.
Dimensionaalsus puudus — mõõdikud olid nimede tasandil, nagu "server1.cpu.idle".
Ja päringukeeled olid jäigad.

Julius Volz ja Matt Proud disainisid süsteemi, mis võttis vastu Google'i sisemise
tööriista Borgmon ideed.

VISUAAL: 4 probleemi listid, SoundCloud logo taustal
-->

---

## Prometheus täna

- **2015:** 1.0 avalikult
- **2016:** CNCF teine graduated projekt pärast Kubernetese
- **2024 nov:** 3.0 — esimene suur väljalase 7 aasta järel
- **Laboris:** Prometheus 3.x

**Kasutajad:** Bolt, Wise, Pipedrive, Uber, Airbnb, Twitter, tuhanded teised

<!--
JUTUSTAJA (40 sek):
Prometheus ajalugu lühidalt. 1.0 tuli 2015. aastal avalikult. 2016-l liitus CNCF-iga
Kubernetese järel teisena. 2024. aasta novembris ilmus versioon 3.0 — esimene
suur väljalase seitsme aasta jooksul. Meie laboris kasutame just 3.x seeriat.

Täna kasutab Prometheust kogu tööstus — Bolt, Wise, Pipedrive ja Eesti tööturul
on see kõige levinum monitooringu-oskus, mis CV-s hinnatud.

VISUAAL: ajajoon + ettevõtete logod
-->

---

## Kus Prometheus EI SOBI

| Mida vajad | Mida kasutada |
|------------|---------------|
| Pikaajaline (aastad) säilitus | Thanos, Mimir, VictoriaMetrics |
| Logihaldus | Loki, ELK, Splunk |
| Distribueeritud tracing | Tempo, Jaeger |
| 100% täpsusega arveldus | Event log + OLAP |
| Reaalajas (<1s) | Kafka + Flink |

**Ootuste kalibreerimine hoiab ära pettumused.**

<!--
JUTUSTAJA (45 sek):
Võrdselt oluline kui see, mida Prometheus teeb — see, mida ta EI tee. Ootuste
kalibreerimine hoiab ära hilised pettumused.

Prometheus ei ole pikaajaline salvestus. Vaikimisi 15 päeva, maksimaalselt mõned
kuud. Aastate jaoks vajad Thanos't või Mimir'it.

Ei ole logihaldus. Ainult mõõdikud. Logide jaoks Loki või ELK.

Ei ole distributed tracing. Ainult Prometheus ei näita päringu teekonda. Selleks
Tempo või Jaeger.

Ei ole 100% täpne arveldussüsteem. Pull-mudelis võib üksikud mõõtmised vahele jääda.

Ja ei ole reaalajas — alla sekundiline latentsus ei ole Prometheus'e tugevus.

Tootmiskeskkond kasutab mitut tööriista koos. Selle kursuse 5 päeva jooksul näed
kõiki neid klasse.

VISUAAL: võrdlustabel
-->

---

## 2. Arhitektuur — komponendid

**Prometheus Server** — scrape, storage, evaluate
**Exporter'id** — tõlkijad (node_exporter, mysqld_exporter, ...)
**Pushgateway** — ainult lühiajalistele batch-töödele
**AlertManager** — grupeerib, marsruutib, summutab alertid
**Grafana** — visualiseerimine (eraldi projekt)

<!--
JUTUSTAJA (60 sek):
Prometheus ei ole monoliitne rakendus — see on komponentide kogum.

Prometheus Server on süda. Ta teeb nelja asja — leiab sihtmärgid, tõmbab mõõdikud,
salvestab TSDB-sse ja hindab alert-reegleid.

Exporter'id on tõlkijad. Linux kernel ei räägi Prometheuse keelt. Node_exporter
loeb Linuxist CPU, mälu, ketta, võrgu andmed ja pakub neid Prometheuse formaadis.
Iga tehnoloogia jaoks on oma exporter — MySQL, PostgreSQL, Nginx, Redis.

Pushgateway on erijuhtum — ainult lühiajalistele batch-töödele. Cronjob, mis
käivitub 30 sekundiks, ei jõua Prometheuse scrape'i oodata. Tähtis — ei ole
üldine push-API.

AlertManager tegeleb alert-idega pärast nende tuvastamist. Grupeerib, marsruutib
õigetele inimestele, summutab hoolduse ajal.

Grafana on eraldi Grafana Labs'i projekt, mitte osa Prometheuse ökosüsteemist.
Tootmises kasutatakse peaaegu alati.

VISUAAL: arhitektuuri diagramm, iga komponenti võib kordamööda esile tõsta
-->

---

## Pull-mudel — disainivalik

```
  PUSH (Zabbix, Graphite)           PULL (Prometheus)

  Agent ─saadab─► Server            Server ─küsib─► Sihtmärk
```

| Aspekt | Pull eelis |
|--------|-----------|
| Agent vaikne | `up == 0` kohe nähtav |
| Debug | `curl /metrics` = mida Prometheus näeks |
| Firewall | Prometheus jõuab sihtmärgini |
| Kardinaalsus | Server määrab sageduse |

<!--
JUTUSTAJA (60 sek):
Push või pull — kumb on parem? Ei ole ühest vastust. Prometheus valib pull-i ja
see valik kannab konkreetseid tagajärgi.

Kõige olulisem operatiivne eelis — kui sihtmärk ei vasta, Prometheus näeb seda
kohe. `up` mõõdik läheb nulli. Alert käivitub. Push-mudelis võib agent lihtsalt
vaikida ja sa ei tea, kas agent on katki, võrk on maas või pole lihtsalt midagi
saata.

Debug on triviaalne. `curl http://server:9100/metrics` annab sama pildi mida
Prometheus scrape'imisel näeks. Sa saad terminalis kiiresti kontrollida, mis
mõõdikuid sihtmärk pakub.

Piirang — Prometheus peab firewall'ist läbi jõudma sihtmärgini. NAT-i taga
asuvatele sihtmärkidele on see keeruline.

VISUAAL: kaks nooltdiagrammi kõrvuti — push vs pull
-->

---

## 3. Aegrea andmemudel

```
http_requests_total{method="POST", status="201"} 1543 @1713436800
│                  │                              │     │
└── mõõdik         └── label'id                   │     └── ajatempel
                                                  └── väärtus
```

**Reegel:** erinev label'ite kombinatsioon = uus aegrida.

<!--
JUTUSTAJA (50 sek):
Prometheus'e andmemudel — iga aegrida identifitseeritakse mõõdiku nime ja
label'ite kombinatsiooni poolt.

Vaata seda näidet. Meil on mõõdik "http_requests_total", mis on POST-meetodiga
ja status-koodiga 201 saabunud 1543 päringut. Ajatempel näitab, millal.

Oluline — kui ükski label muutub, tekib uus aegrida. Seesama mõõdik, aga
method="GET" on täiesti eraldi aegrida.

See annab meile dimensionaalsuse — saame filtreerida ja agregeerida meelevaldsete
dimensioonide järgi ilma eeldefineeritud nimekirjata.

VISUAAL: sama näide ekraanil, koos visuaalse selgitusega
-->

---

## Label'id — võimsad, aga ohtlikud

**Kardinaalsus** = unikaalsete aegridade arv ühe mõõdiku kohta

| ✅ OK | ❌ EI |
|-------|------|
| method (5 väärtust) | user_id (miljonid) |
| status (40 väärtust) | email, IP |
| environment (3) | request_id |
| region (~10) | timestamp |

**Iga aegrida ≈ 3 kB RAM-i**

<!--
JUTUSTAJA (65 sek):
Label'id on Prometheus'e suurim tugevus — ja ka suurim oht.

Mõõdiku nime all saad hoida tuhandeid dimensioone. Aga mida rohkem unikaalseid
kombinatsioone, seda suurem kardinaalsus, seda suurem salvestuskulu.

Madal kardinaalsus on ok — method on 5 väärtust (GET, POST, PUT, DELETE, PATCH).
Status on umbes 40. Environment on 3 (dev, staging, prod). Regioone on ~10.

Aga user_id? Miljonid. Email? Miljonid. Request_id? Iga päring on eraldi ID.

Kui paned user_id label-iks, on sinu aegridade arv võrdne kasutajate arvuga, korda
mõõdikute arv. 10 000 kasutajat × 100 mõõdikut = miljon aegrida. Kui iga aegrida
võtab 3 kilobaiti RAM-i, oled 3 GB ainult label'idega.

Kardinaalsuse plahvatus on Prometheus'e produktsiooni probleem #1. Print see tabel
välja.

VISUAAL: võrdlustabel, rohelised vs punased kirjed
-->

---

## 4. Mõõdikutüübid

- **Counter** — ainult kasvab (requests_total)
- **Gauge** — vabalt liikuv (memory_usage)
- **Histogram** — jaotus bucket'ites (latency)
- **Summary** — klient-pool protsentiilid (vana stiil)

<!--
JUTUSTAJA (45 sek):
Prometheus toetab nelja mõõdikutüüpi ja valik mõjutab, kuidas sa andmeid salvestad
ja milliseid PromQL operatsioone saad kasutada.

Counter on ainult kasvav. Päringute arv, vigade arv, baitide arv. Nullistub vaid
protsessi taaskäivitusel.

Gauge on vabalt liikuv. Mälu kasutus, aktiivsete kasutajate arv, temperatuur.

Histogram mõõdab jaotust bucket'ites — näiteks päringu kestuste jaotust.
Kasutatakse protsentiilide arvutamiseks.

Summary on vana stiil — protsentiile arvutatakse klient-poolel, aga piirang on,
et ei ole agregeeritav üle instanside.

Reegel — eelista histogrammi summary-le.

VISUAAL: 4 graafikut, näitamaks nende iseloomu
-->

---

## Counter vajab rate()

```promql
# VALE — absoluutarv, ei ütle midagi kasulikku
http_requests_total

# ÕIGE — päringuid sekundis, viimase 5 min keskmine
rate(http_requests_total[5m])
```

**Reegel:** aken peab olema ≥ 4× scrape_interval.

<!--
JUTUSTAJA (50 sek):
Counter on eriline — absoluutarv ise ei ütle midagi kasulikku. 1 543 892 päringut.
Okei. Mida see tähendab? Mitte midagi ilma kontekstita.

rate() funktsioon arvutab kasvukiiruse sekundis antud ajaakna jooksul.
rate(http_requests_total[5m]) ütleb: keskmine päringute arv sekundis viimase
5 minuti jooksul. See on kasulik.

Kriitiline reegel — ajaaken peab olema vähemalt 4 korda scrape_interval. 15-
sekundilise scrape'iga on [1m] minimaalselt toimiv, [5m] annab silutud graafiku.
Liiga kitsas aken tühi tulemus või mürarikas graafik.

VISUAAL: valesti ja õigesti päring koodiplokkidena
-->

---

## Histogram — protsentiilid

```promql
histogram_quantile(0.95,
  sum by(le, service) (
    rate(http_request_duration_seconds_bucket[5m])
  )
)
```

**Eelis:** agregeeritav üle instanside (10 serveri koond-p95).
**Kriitiline:** `le` peab säilima `by` klauslis.

<!--
JUTUSTAJA (55 sek):
Histogram'i võimsaim kasutus — protsentiilide arvutamine.

Tüüpiline näide — p95 latentsus teenuse kohta. See päring võib tunduda keeruline,
aga loed seestpoolt välja.

Sisemine rate näitab iga bucket'i kasvukiirust. sum by(le, service) agregeerib
üle instanside, säilitades bucket'i piiri ja teenuse nime. histogram_quantile
arvutab 95. protsentiili.

Tähtis — le peab säilima by klauslis. Kui unustad le, funktsioon ei tööta
õigesti, sest ta ei tea, milliste piiride vahel bucket'id on.

Histogram'i eelis summary ees — agregeeritav. 10 serveri koond-p95 on arvutatav.
Summary-ga ei ole see võimalik.

VISUAAL: koodiplokk, võib rõhutada le terminit
-->

---

## 5. PromQL — päringukeel

**Instant vektor** — ühel ajahetkel:
```promql
node_cpu_seconds_total{mode="idle"}
```

**Range vektor** — ajavahemiku kohta:
```promql
node_cpu_seconds_total{mode="idle"}[5m]
```

**rate() võtab range → tagastab instant**

<!--
JUTUSTAJA (50 sek):
PromQL on deklaratiivne keel aegrea andmete päringuteks. Erineb SQL-ist
fundamentaalselt — ta töötab vektoritega.

Instant vektor on väärtused ühel ajahetkel. Näiteks node_cpu_seconds_total mode=idle
annab iga (instance, CPU) paari jaoks hetke idle-sekundid.

Range vektor on väärtused ajavahemiku kohta. Nurksulg ja aeg — näiteks [5m]
tähendab viimase 5 minuti ajalugu.

Funktsioonid nagu rate() võtavad range vektori ja tagastavad instant vektori.
Seega rate(x[5m]) käitub nagu "andke mulle kasvukiirus viimase 5 minuti põhjal".

VISUAAL: kaks kasti — instant (üks väärtus per aegrida) vs range (väärtuste rida)
-->

---

## Filtreerimine ja agregeerimine

```promql
# Filter
http_requests_total{status=~"5.."}       # regex — kõik 5xx

# Agregeerimine
sum by(service) (rate(http_requests_total[5m]))
sum without(instance) (rate(http_requests_total[5m]))

# Top 5
topk(5, sum by(handler) (rate(http_requests_total[5m])))
```

<!--
JUTUSTAJA (55 sek):
Filtreerimine label'ite järgi on PromQL-i igapäevane ekspluatatsioon. Võrdusmärk
on täpne vaste, hüüumärk võrduse ees on "mitte võrdne", tilde-märk võrduse ees
on regex.

regex näiteks {status=~"5.."} tähendab — kõik status-väärtused, mis algavad
viiega ja on kolme-sümbolised. Ehk kõik 5xx-vead. 500, 502, 503 jne.

Agregeerimine — sum, avg, min, max, count, topk. by säilitab nimetatud label'id.
without eemaldab nimetatud label'id.

Top 5 kõige koormatum endpoint — topk(5, sum by(handler) (rate(...))). Sageli
kasutatud muster.

VISUAAL: kolm näidet koodiplokkidena
-->

---

## Klassikaline päring — CPU %

```promql
100 - (
  avg by(instance) (
    rate(node_cpu_seconds_total{mode="idle"}[5m])
  ) * 100
)
```

1. Counter iga (instance, cpu) kohta, idle mode
2. rate = idle-sekundit sekundis (0-1)
3. avg by(instance) = keskmine üle CPU-de
4. × 100 = idle protsent
5. 100 - ... = kasutus protsent

<!--
JUTUSTAJA (65 sek):
Selle päringu näed sa tõenäoliselt iga päev, kui töötad Prometheus'ega. Loe seda
läbi samm-sammult.

Alustame sisemisest osast. node_cpu_seconds_total mode="idle" on counter iga
(instance, cpu) paari jaoks — kui palju sekundit on see CPU olnud jõude.

rate() aknaga [5m] arvutab idle-sekunditat sekundis. See on 0 ja 1 vahel —
0 tähendab CPU täielikult hõivatud, 1 tähendab täielikult vaba.

avg by(instance) võtab keskmise üle kõigi CPU-de ühel masinal. Kui server-il on
4 CPU-d, arvutame nende keskmise.

Korrutamine 100-ga teisendab protsendiks. Nüüd meil on idle protsent.

Ja 100 miinus see annab kasutusprotsendi. CPU kasutus protsentides.

Print see välja, hoia laua peal, kasuta iga päev.

VISUAAL: päring, numbrid 1-5 kõrval iga sammule, joonistada alt üles
-->

---

## 6. Alerting

```yaml
groups:
  - name: node_health
    rules:
      - alert: HighCpuUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Kõrge CPU: {{ $labels.instance }}"
          runbook_url: "https://wiki.example.com/runbooks/high-cpu"
```

<!--
JUTUSTAJA (55 sek):
Alert-reegli anatoomia. Neli olulist välja.

expr on PromQL-väljend. Kui see tagastab tühja vektori, tingimus ei kehti. Kui
tagastab vähemalt ühe rea, iga sellest rea label'ite kombinatsioon on aktiivne
alert.

for on kestvus, mille jooksul expr peab katkematult tõene olema enne, kui alert
läheb firing-olekusse. See on kriitiline — ilma for-ita saad alert'i iga
15-sekundilise spike peale.

labels on staatilised label'id, mida lisatakse alert'ile. AlertManager kasutab
neid marsruutimiseks — severity critical läheb pageri, warning Slacki.

annotations on inimloetavad väljad. summary ja runbook_url on elementaarsed.

VISUAAL: YAML ekraanil, võib iga välja värviga esile tõsta
-->

---

## Alert-i elutsükkel

```
Inactive → (expr kehtib) → Pending → (for aeg täis) → Firing
                ↓                          ↓
          expr ei kehti           expr ei kehti
                ↓                          ↓
            Inactive                  Inactive
```

**for: väldib valehäireid mööduvate spike'ide korral.**

<!--
JUTUSTAJA (40 sek):
Alert'il on kolm olekut. Inactive — tingimus ei kehti. Pending — tingimus kehtib,
aga for-aeg pole veel täis. Firing — for-aeg täis, alert aktiivne.

Näiteks kui for on 2 minutit ja CPU ületab 80% 90 sekundiks, aga siis langeb —
alert jääb Pending olekusse ja ei käivitu. See on see, mida sa tahad — väldid
valehäireid mööduvate spike'ide korral.

Ainult kui tingimus kehtib katkematult 2 minutit, alert läheb Firing olekusse ja
AlertManager saab teate.

VISUAAL: state diagram, värvidega markeerida iga olekut
-->

---

## 7. AlertManager

- **Deduplicate** — sama alert mitmest Prometheusest
- **Group** — 10 alert'i kokku üks teade
- **Route** — DB → DBA meeskonnale, võrk → võrgumeeskonnale
- **Silence** — planeeritud hooldus
- **Inhibit** — kui DC on maas, ära saada igat alert'i

<!--
JUTUSTAJA (55 sek):
AlertManager on eraldi protsess. Ta tegeleb kõigega pärast alert'i tuvastamist.

Viis põhifunktsiooni. Deduplicate — kui sama alert tuleb mitmest Prometheuse
instantsist, AlertManager saadab ainult ühe teate.

Group — 10 seotud alert'i grupitatakse üheks kokkuvõttev teateks. Kui korraga
läheb maha 10 serverit, sa ei taha 10 emaili, vaid ühte.

Route — AlertManager marsruutib alert'id label'ite põhjal. Andmebaasi-alert'id
DBA meeskonnale, võrgu-alert'id võrgumeeskonnale, kriitilised kõigile.

Silence — planeeritud hoolduse ajaks saad alert'id 2 tunniks vaikima panna.

Inhibit — kui on juba käimas kriitiline intsident nagu DatacenterDown, siis
kõik sellest sõltuvad alert'id summutatakse automaatselt. Ei taha saada 100
teenuse alert'e, kui tead juba, et DC on maas.

VISUAAL: 5 funktsiooni, ikoonidega
-->

---

## 8. Grafana — visualiseerimine

**Eraldi projekt.** Ei kogu andmeid ise — küsib andmeallikatelt.

```
[Andmeallikas] → [Query] → [Transform] → [Visualization]
   Prometheus      PromQL    kombineerimine  graafik
```

**Mitu andmeallikat samas dashboardis:**
Prometheus (mõõdikud) + Loki (logid) + Tempo (trace'id) koos

<!--
JUTUSTAJA (60 sek):
Grafana on eraldi projekt, Grafana Labs'i toode, mitte osa Prometheuse
ökosüsteemist.

Oluline — Grafana ei kogu andmeid ise. Ta küsib neid andmeallikatelt. Prometheus,
Loki, Tempo, InfluxDB, SQL-andmebaasid — iga andmeallika kohta on plugin.

Dashboardi andmevoog on kolm-etapiline. Päring läheb andmeallikale, saadud andmeid
saab vajadusel transformida, ja lõpuks visualiseeritakse.

Kõige olulisem Grafana tugevus — mitu andmeallikat samas dashboardis. Saad
paneelis 1 Prometheus mõõdikud, paneelis 2 Loki logid, paneelis 3 Tempo trace'id.
Kolme samba vaade ühes kohas.

VISUAAL: dashboardi visuaal, 3 paneeli erinevate ikoonidega
-->

---

## Dashboard, Panel, Variable

- **Dashboard** — konteiner, JSON Git-is
- **Panel** — üks visualiseering (PromQL + graafik)
- **Variable** — `$instance` dropdown, kõik paneelid filtreeruvad automaatselt
- **Annotation** — deploy-märgid, intsidentide algused

<!--
JUTUSTAJA (50 sek):
Grafana põhimõisted. Dashboard on konteiner paneelide ja muutujate jaoks. See on
JSON-fail, mida saad Git-iga versioneerida.

Panel on üks visualiseering. Näiteks CPU graafik on üks paneel. Mälu graafik on
teine.

Variable muudab dashboardi dünaamiliseks. Defineerid $instance muutuja — näiteks
label_values päringuga tõmbad nimekirja serveritest. Kasutaja valib dropdown'ist
ühe serveri, ja kõik paneelid filtreeruvad selle põhjal.

Annotation on ajaline märge. Näiteks iga deploy lisab annotation'i, mis kuvatakse
kõigil paneelidel vertikaaljoonena. Nii näed kohe, millal see deploy toimus, mis
eelnes intsidendile.

VISUAAL: Grafana ekraanipilt, iga mõiste markeeritud noolega
-->

---

## Visualiseeringute valik

| Tüüp | Millal |
|------|--------|
| Time series | Trendid ajas |
| Stat | Üks hetkenumber |
| Gauge | Protsent piiriga |
| Bar gauge | Võrdlus kategooriate vahel |
| Table | Mitmedimensiooniline detail |
| Heatmap | Jaotus ajas (latentsus) |
| Logs | Loki logid |
| Trace | Tempo trace'id |

<!--
JUTUSTAJA (40 sek):
Grafana pakub üle 25 visualiseeringutüübi. Igapäevases kasutuses on peamiselt
need 8.

Time series — trendid ajas, nagu CPU graafik. Stat — üks hetkenumber, aktiivsed
kasutajad. Gauge — protsent piiri lähenemisega, ketta täituvus. Bar gauge —
võrdlus kategooriate vahel, top 5 endpointi.

Table detailseks vaateks. Heatmap latentsuse jaotuseks. Logs ja Trace spetsialist-
paneelid.

Labris täna ehitame dashboard'i kasutades neid kõiki.

VISUAAL: tabel + pisi-pildikesed iga visualiseeringutüübi juures
-->

---

## 9. Skaleerimine

| Aegridade arv | Lahendus |
|---------------|----------|
| <1M, 15 päeva | Üks Prometheus |
| 1-10M, 1 aasta | Prometheus + remote_write → Thanos/Mimir |
| >10M, multi-tenancy | Natiivne Mimir/Cortex |

<!--
JUTUSTAJA (55 sek):
Ühe Prometheuse piirid — umbes 1 miljon aktiivset aegrida ja 15 päeva retention.
See katab enamiku väikseid ja keskmisi süsteeme.

Kui lähed suuremaks — 1 kuni 10 miljonit aegrida, või tahad aasta säilitust —
lisa remote_write. See saadab andmed paralleelselt ekstern-salvestussüsteemi
nagu Thanos või Mimir. Need kasutavad object storage-t nagu S3 pikaajaliseks
säilitamiseks — palju odavam kui lokaalne ketas.

Kui lähed veel suuremaks — üle 10 miljoni aegrida, vajad multi-tenancy-t — siis
on natiivsed lahendused nagu Mimir või Cortex õiged. Need on horisontaalselt
skaleeruvad algusest peale.

Meie labris aga piisab ühest Prometheusest — laboris töötab iga osaleja üks VM
ja pakub ~100 aegrida.

VISUAAL: tabel + skaleerimise diagram
-->

---

## Föderatsioon vs remote_write

**Föderatsioon** — üks Prometheus scrape'ib teist, ainult agregeeritud
```yaml
- job_name: 'federate'
  metrics_path: '/federate'
  params: {'match[]': ['{job="critical"}']}
```

**remote_write** — kogu andmevoog eksternsüsteemi
```yaml
remote_write:
  - url: "https://mimir.example.com/api/v1/push"
```

<!--
JUTUSTAJA (50 sek):
Kaks skaleerimismustrit, millega kohtad.

Föderatsioon — üks Prometheus scrape'ib teist. Klassikaline kasutus — iga
datacentri Prometheus scrape'ib kohalikku infrastruktuuri, ja tsentraalne
Prometheus scrape'ib datacentrite Prometheus-eid, aga ainult agregeeritud
mõõdikuid.

remote_write — kogu andmevoog saadetakse paralleelselt ekstern-salvestussüsteemi.
Prometheus kirjutab jätkuvalt kohalikku TSDB-sse, aga saadab kõike ka Thanosele
või Mimirile.

Reegel — föderatsioon kui tahad konsolideerida mõõdikuid hierarhiliselt.
remote_write kui tahad pikaajalist säilitamist või horisontaalset skaleerimist.

VISUAAL: kaks diagrammi kõrvuti — föderatsioon vs remote_write
-->

---

## 10. Kokkuvõte — 8 reeglit

1. Pull-mudel → `up` mõõdik esmane diagnostika
2. Label'id madala kardinaalsusega (< 10)
3. Counter vajab `rate()`
4. `rate()` aken ≥ 4× scrape interval
5. Histogram > Summary (agregeeritav)
6. `for:` alert-reeglites → väldib valehäireid
7. Recording rules keeruliste päringute jaoks
8. Grafana ei salvesta — küsib ainult

<!--
JUTUSTAJA (40 sek):
Kaheksa reeglit, mida meelde jätta. Kui rakendad neid, väldid 90% levinumatest
Prometheuse vigadest.

Pull-mudel ja up mõõdik — esmane diagnostika. Label'id madala kardinaalsusega.
Counter vajab rate(). rate() aken peab olema vähemalt 4 korda scrape interval.
Histogram on summary-st parem, sest agregeeritav. for alert-reeglites väldib
valehäireid. Recording rules kiirendavad keerulisi päringuid. Grafana ei salvesta
andmeid — ta küsib neid Prometheusest.

VISUAAL: nummerdatud loetelu, ikoonid või värvid igal punktil
-->

---

## Järgmine — LABOR

**Ehitad täna:**

- Prometheus + Grafana + Alertmanager Docker Compose'iga
- 3 target'it UP
- PromQL päringud kolmelt serverilt
- Grafana dashboard 4 paneeliga
- Alert, mis käivitub Pending → Firing

**~4 tundi praktikat**

<!--
JUTUSTAJA (30 sek):
Ja nüüd läheme praktikasse. Neli tundi kätega tööd. Selle aja jooksul ehitad
töötava monitooringu-stack'i, kirjutad esimesed PromQL päringud, ehitad dashboardi
ja näed alerti Firing olekus.

Pausi peame vahele. Lõuna kell 12:30. Lähme.

VISUAAL: "LABOR" suur tekst, sümbolid Docker'i, Prometheus'e, Grafana logodega
-->

---

## Küsimused?

📧 maria.talvik@haapsalu.kutsehariduskeskus.ee

📚 Labori juhend: `docs/labs/01_prometheus_grafana/lab.md`

<!--
JUTUSTAJA (10 sek):
Küsimused enne laborisse minemist? Labri juhend on repos või MkDocs saidil.
Lähme.

VISUAAL: kontaktid
-->
