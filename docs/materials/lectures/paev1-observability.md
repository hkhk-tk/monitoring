# Päev 1: Monitooring, logimine ja vaatlus

**Kestus:** ~35 minutit iseseisvat lugemist
**Eeldused:** Linux CLI põhitõed, võrgunduse alused
**Järgmine loeng:** [Prometheus ja Grafana](paev1-loeng.md)

---

## Õpiväljundid

Pärast selle materjali läbitöötamist osaleja:

1. **Põhjendab** monitooringu äririski-vähendamise rolli konkreetsete kuluhinnangute kaudu
2. **Eristab** tehniliselt kolme mõistet: logimine (sündmused), seire (mõõdikud ajas), vaatlus (suvaliste küsimuste uurimise võime)
3. **Kirjeldab** vaatluse kolme sammast (metrics, logs, traces) ja selgitab, millisele küsimusele iga sammas vastab
4. **Rakendab** USE, RED ja Four Golden Signals raamistikke õigetes kontekstides
5. **Selgitab** SLI, SLO, SLA hierarhiat ja error budget'i rolli tootmistarkvara töös
6. **Hindab** alert-disaini kvaliteeti kolme kriteeriumi järgi: actionability, symptom-based, runbook
7. **Paigutab** tööriistade maastiku (Prometheus, Zabbix, InfluxDB, Loki, ELK, Tempo) ühisele raamistikule ja teab, millal kumba valida

---

## 1. Miks monitooring on äririsk, mitte tehniline valik

Monitooringut käsitletakse tihti tehnilise kohustusena — "peame mõõtma, et saaksime debug-ida". See on kitsendav pilt. Tegelikkuses on monitooring kvantifitseeritav äririski vähendamise vahend.

### 1.1 Downtime'i maksumus

Reaalsed numbrid avalikust tööstusanalüüsist:

| Ettevõte / sektor | Downtime'i kulu | Allikas |
|-------------------|-----------------|---------|
| Amazon.com | ~$220 000 / minut (2023 hinnang) | Avalikud E-commerce analüüsid |
| Finantsteenused (keskmine) | $9 000 / minut | Gartner, 2022 |
| Kindlustus | $4 800 / minut | Gartner, 2022 |
| Tavaline SaaS ettevõte | $5 600 / minut (keskmine) | Gartner, 2022 |

Eesti kontekstis — Bolt, Wise, Pipedrive, Veriff on avalikult rääkinud, et panustavad iga aasta miljoneid eurosid observability infrastruktuuri. See pole valik — see on hinnale vajalikud kulutused.

### 1.2 Mean Time To Detect (MTTD) vs Mean Time To Resolve (MTTR)

Intsidendi elutsükli kaks võtmemõõdikut:

```
Intsident algab ───► Tuvastatakse ───► Lahendatakse
              ◄─MTTD─►              ◄────MTTR────►
```

- **MTTD** = kui kiiresti avastad probleemi
- **MTTR** = kui kiiresti selle lahendad

Hea observability **vähendab mõlemat**. Ilma seireta: MTTD = aeg, kuni esimene kasutaja helistab (tüüpiliselt 10-60 min).

**Tähtis järeldus:** kasutaja ei tohi olla su esimene monitooringuallikas. Kui helpdesk avastab probleeme enne su dashboardi — su observability on ebaõnnestunud.

---

## 2. Kolm mõistet: tehniline eristus

IT-spetsialistid kasutavad sõnu "logging", "monitoring", "observability" sageli sünonüümidena. Need ei ole sünonüümid. Neil on erinevad andmemudelid, kasutusjuhud ja tehnoloogiad.

### 2.1 Logimine — diskreetsete sündmuste jada

**Andmemudel:** ajajärjestusega tekstiline (või struktureeritud JSON) sündmuste jada.

```
2026-04-18T10:23:41.523Z INFO  auth      login        user_id=4821 ip=10.2.3.4
2026-04-18T10:23:45.014Z ERROR payment   timeout      tx_id=T-98321 db=primary-01 duration_ms=30000
2026-04-18T10:23:45.102Z WARN  payment   retry        tx_id=T-98321 attempt=2
2026-04-18T10:24:01.889Z FATAL payment   abort        tx_id=T-98321 reason="all retries failed"
```

**Vastav küsimus:** mis täpselt juhtus, millal, kellega?

**Tehnilised omadused:**

- **Maht:** kõrge (gigabaite päevas ühe süsteemi kohta)
- **Struktuur:** vahelduv — traditsiooniline kas vabatekst (syslog) või struktureeritud JSON
- **Indekseerimine:** full-text search (Elasticsearch, Splunk) või metadata-põhine (Loki)
- **Säilitusaeg:** tüüpiliselt 7-90 päeva, regulatiivsetel põhjustel kuni aastad
- **Päringu kulu:** kõrge — täistekstiotsing suure andmehulga peal

**Log-tasemed** võimaldavad filtreerida müra vs olulist: `TRACE < DEBUG < INFO < WARN < ERROR < FATAL`. Tootmiskeskkonnas hoitakse tavaliselt `INFO` või kõrgem.

**Levinud probleem:** tsentraliseerimise puudumine. 50 serverisse ükshaaval SSH-ga sisselogimine logide kogumiseks ei skaleeru. Selle probleemi jaoks on keskne logimissüsteem (Loki, ELK, Graylog) — käsitleme päeva 2 ja päeva 3 jooksul.

### 2.2 Seire — mõõdikud aegreadadena

**Andmemudel:** arvulised väärtused ajas, iga mõõdik kui aegrida.

```
cpu_usage{host="web-01"}       45.2   @ 10:23:00
cpu_usage{host="web-01"}       47.1   @ 10:23:15
cpu_usage{host="web-01"}       89.1   @ 10:23:30   ← spike
cpu_usage{host="web-01"}       44.2   @ 10:24:00
```

**Vastav küsimus:** kui palju ressurssi kasutan? Kas see on normaalne?

**Tehnilised omadused:**

- **Maht:** madal-keskmine (megabaite, mitte gigabaite ühe süsteemi kohta)
- **Struktuur:** range (nimi + label'id + float + ajatempel)
- **Säilitusaeg:** tüüpiliselt 15 päeva kuni 1 aasta
- **Päringu kulu:** madal — aegrea andmebaasid on selleks optimeeritud

**Dimensioonid label'ite kaudu.** Moodne seire (Prometheus, InfluxDB, OpenMetrics) ei ole lihtsalt `server1.cpu.idle` tüüpi nimed, vaid mitmedimensiooniline andmemudel:

```
http_requests_total{service="auth", method="POST", status="500", region="eu-north-1"}
```

See võimaldab hiljem filtreerida ja agregeerida meelevaldsete dimensioonide järgi ilma eeldefineeritud agregaatide nimekirjata.

### 2.3 Vaatlus — uurimise võime

Observability ei ole logide, mõõdikute ega trace'ide kogumine — see on **võime vastata suvalisele küsimusele süsteemi seisundi kohta, ilma et peaks ette teadma, mida mõõta**.

Termini populariseerisid Charity Majors ja meeskond [Observability Engineering (O'Reilly, 2022)](https://www.oreilly.com/library/view/observability-engineering/9781492076438/) raamatus. Võtmetäh­tsusega mõtted:

- **Monitooring on teadaolevate teadaolekute kohta** — panid üles dashboardi "CPU kasutus", sest tead, et CPU võib probleem olla
- **Observability on teadaolevate tundmatute ja tundmatute tundmatute kohta** — kasutajad kaebavad aeglust pärast deploy-i, sa ei tea miks; observability võimaldab uurida

Praktiline näide — kasutaja kaebab aeglast lehte:

| Sammas | Annab vastuse |
|--------|---------------|
| **Metrics** | Andmebaasi CPU on 100%, vastamisaeg p99 = 4.2s |
| **Logs** | Täistabeli skaneerimised iga sekund, konkreetne SQL-päring |
| **Traces** | Konkreetne päring viibib andmebaasi-operatsioonis 4.5s 5-st, raam `SELECT users.* WHERE email LIKE '%@'` |

Ilma trace'ita tead, et **midagi** on aeglane. Trace'iga tead, **mis täpselt** ja **miks**.

---

## 3. Kolm sammast — tehniline võrdlus

| Aspekt | Metrics | Logs | Traces |
|--------|---------|------|--------|
| **Andmetüüp** | Arvulised aegread | Sündmused / tekst | Päringute teekonnad |
| **Kardinaalsus** | Madal (10-1000 unikaali) | Keskmine-kõrge | Väga kõrge (iga päring ise) |
| **Mahu suurusjärk** | MB / päev | GB / päev | GB-TB / päev |
| **Säilitus** | 15 päeva - 1 aasta | 7-90 päeva | 1-7 päeva (sampling) |
| **Päringu kiirus** | Millisekundid | Sekundid | Sekundid |
| **Tüüpiline tööriist** | Prometheus, InfluxDB | Loki, Elasticsearch | Tempo, Jaeger |
| **Päringukeel** | PromQL, Flux, InfluxQL | LogQL, KQL, SPL | TraceQL |

### 3.1 Millist sammast millal kasutada

Praktiline reegel jõudlusintsidentide uurimiseks:

```
1. METRICS — kas midagi on valesti? (dashboardide pilk, 10 sekundit)
     ↓ jah
2. LOGS    — mis juhtus selles ajavahemikus? (Loki/ELK otsing, 1-2 minutit)
     ↓ vaja sügavamale
3. TRACES  — mis täpselt aeglustub ja kus? (Tempo, 30 sekundit kuni mitu minutit)
```

Metrikult alustamine on odav ja kiire. Trace'ide vaatamine **esimese** sammuna on raiskamine — sul on miljoneid trace'e ja sa ei tea, mida otsida.

### 3.2 Korrelatsioon sammaste vahel

Moodne observability ühendab sammaste vahel. **Exemplars** (näidisjuhud) on Prometheus-e ja OpenTelemetry funktsioon, mis seob mõõdiku andmepunkti konkreetse trace'iga:

```
http_request_duration_seconds_bucket{le="5.0", ...} 42 # {trace_id="abc123"} 4.8
```

Grafanas näed graafikul latentsuse spike'i, klikkad sellel ja jõuad otse probleemse trace'ini. See on tänapäevase observability stackide (LGTM — Loki, Grafana, Tempo, Mimir) põhijoon.

---

## 4. Mida üldse jälgida: raamistikud

Tuhandete potentsiaalsete mõõdikute hulgast — mida valida? Kolm peamist raamistikku annavad struktuuri.

### 4.1 USE meetod — ressurssidele

Brendan Gregg (endine Netflix, nüüd Intel) formuleeris USE meetodi süsteemiressursside analüüsiks. Iga ressursi kohta kolm küsimust:

- **Utilization** — kui suur osa ressursist on hõivatud
- **Saturation** — kas midagi ootab järjekorras (lisatöö, mida ressurss ei jõua teha)
- **Errors** — kas ressurss tagastab vigu

```
       CPU             Mälu           Ketas              Võrk
U   CPU kasutus %    RAM kasutus %   I/O aeg %         Bandwidth %
S   Load average     Swap aktiivsus  I/O järjekord     Dropped packets
E   (CPU-l tavaliselt puuduvad)  OOM killide arv   Disk errors    Interface errors
```

**Ametlik allikas:** [brendangregg.com/usemethod.html](https://www.brendangregg.com/usemethod.html)

**Millal kasutada:** infrastruktuuri mõõdikud (hostid, virtuaalmasinad, konteinerid).

### 4.2 RED meetod — teenustele

Tom Wilkie (Grafana Labs CTO) formuleeris RED meetodi mikroteenuste jaoks:

- **Rate** — päringute arv sekundis
- **Errors** — ebaõnnestunud päringute arv sekundis või protsent
- **Duration** — päringu kestvuse jaotus (eriti p95, p99 protsentiilid)

**Ametlik allikas:** [The RED Method (Grafana blog)](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)

**Millal kasutada:** teenuste, API-de, microservice-de mõõdikud.

Bolt, Wise ja paljud teised ettevõtted seirevad reaalajas RED-mõõdikuid iga oma mikroteenuse kohta. Langus Rate-is on kõige varasem indikatsioon, et midagi on valesti.

### 4.3 Four Golden Signals — Google'i SRE kogumik

[Google SRE raamat](https://sre.google/sre-book/monitoring-distributed-systems/) defineerib neli signaali, mis kokku katavad enamiku tootmisprobleemidest:

| Signaal | Mida mõõdab | Tüüpiline mõõdik |
|---------|-------------|------------------|
| **Latency** | Kui kiiresti teenus vastab | p50, p95, p99 kestvus |
| **Traffic** | Koormuse tase | Requests / sec |
| **Errors** | Ebaõnnestunute osakaal | Error rate % |
| **Saturation** | Kui lähedal on ressurss piirile | Queue depth, utilization |

**Neljas signaal — saturation — on olulisim ennetamiseks.** Latentsus ja vead on sümptomid, mis ilmuvad pärast saturatsiooni. Kui jälgid ainult latency-t, alusted probleemi lahendamist alles siis, kui on hilja.

### 4.4 Kuidas valida

Praktikas kasutad korraga mitut raamistikku:

```
Infrastruktuuri kiht    →  USE      (nodeid, diske, võrku)
Teenuste kiht            →  RED      (iga mikroteenuse jaoks)
Terviktasandi SLO       →  4GS      (kasutaja kogemus: latency + errors)
```

---

## 5. SLI, SLO, SLA — tootmissüsteemi keel

SRE praktika toob kolm akronüümi, mis on olulised arusaama seire **eesmärgi** tasandil.

### 5.1 Definitsioonid

**SLI — Service Level Indicator:** konkreetne, mõõdetav jõudluse näitaja.
*Näide:* "HTTP päringu edukus" = `2xx+3xx / kogusumma`.

**SLO — Service Level Objective:** sihtväärtus SLI-le teatud ajavahemikus.
*Näide:* "99.9% edukus viimase 30 päeva jooksul."

**SLA — Service Level Agreement:** lepinguline kohustus SLO-de täitmiseks koos hüvitiste mehhanismiga.
*Näide:* "Kui teenuse kättesaadavus kuus langeb alla 99.5%, kompenseerime 10% kuutasust."

### 5.2 Error Budget — operatsiooniline tarkus

Kui SLO on 99.9% kuus, tähendab see **lubatud "eelarve" vigu**: 0.1% × 30 päeva × 24h = ~43 minutit downtime'i kuus.

**Error budget-i kasutamine:**

- **Budget alles** → meeskond saab võtta riske (uued release'id, eksperimendid)
- **Budget otsas** → kõik deploy-d peatatakse, fookus stabiilsusel

See on formaalne mehhanism, mis tasakaalustab arenduskiirust ja töökindlust. Ilma error budget-ita kipub organisatsioon joondunud ühe äärmusega (kas "0 downtime mingi hinnaga", mis peatab innovatsiooni, või "liigume kiiresti, hoolime vähem", mis tekitab intsidente).

### 5.3 SLI valik — kasutaja vaatest

Halb SLI: "CPU kasutus < 80%". See on tehniline implementatsioonidetail, mitte kasutajale oluline.

Hea SLI: "95% API-päringutest vastatakse <200ms". See peegeldab otseselt kasutaja kogemust.

**Reegel:** defineeri SLI-d kasutajale nähtavate näitajate põhjal, mitte sisemiste ressursside põhjal.

---

## 6. Alert-disain — kaks põhilist eksimist

Alertimine on see, kus monitooring läheb inimese sekkumiseks. Halvasti disainitud alertid põhjustavad kahte probleemi.

### 6.1 Alert fatigue

Kui 80% alert-itest on valehäired või infomürae, meeskond kaotab reageerimisvõime. Kõigile alert-itele. See pole hüpoteetiline — on dokumenteeritud intsidente, kus olulised alert-id on ignoreeritud kuuliinide valehäirete taustal.

**Reegel:** iga alert peab olema **actionable**. Kui saad teate ja sul ei ole selget järgmist sammu, see on vale alert.

### 6.2 Sümptom vs põhjus

Halb: alert "CPU on 90%". See on implementatsioonidetail.
Hea: alert "API latentsus p95 > 2 sekundit". See mõjutab kasutajat.

Sümptompõhised alertid tegelevad probleemiga, mida on **tegelikult** vaja lahendada. Põhjuspõhised alertid tekitavad müra, sest paljud "põhjused" ei mõjuta kasutajat.

### 6.3 Kvaliteedikriteeriumid

Hea alert-i tunnused:

1. **Actionable** — selge, mida teha
2. **Symptom-based** — mõjutab kasutajat
3. **Runbook** — viit juhendile lahendamiseks
4. **Severity hierarhia** — `critical` (äratab öösel), `warning` (hommikuks Slack), `info` (ainult dashboardil)
5. **`for:` kestvus** — väldib mööduvaid spike'e (vähemalt 1 min, tüüpiliselt 5 min)

Google SRE raamatu peatükk 6 on selle vallas viidatuim allikas: [sre.google/sre-book/monitoring-distributed-systems](https://sre.google/sre-book/monitoring-distributed-systems/).

---

## 7. Monitoring vs Observability — tehniline eristus

Need mõisted ei ole sünonüümid. Tehniline erinevus:

### 7.1 Monitooring — eeldefineeritud

```
Tead ette, mida tahad mõõta → seadistad dashboardi → vaatad, kas piir ületatud
```

- Dashboardid mõõdikutega
- Eelseadistatud alert-reeglid
- Püstitatud eeldustest lähtuvad

Sobib: stabiilsed süsteemid, kus failure mode'd on teada.

### 7.2 Observability — eksploratiivne

```
Kasutaja kaebab → sa ei tea miks → uurid andmeid → leiad põhjuse
```

- Kõrge kardinaalsusega andmed (iga päring eraldi)
- Meelevaldsed ad-hoc päringud
- Struktureeritud logid + distributed tracing + metrics koos

Sobib: keerulised distribueeritud süsteemid, kus failure mode'id on ettenägematud.

### 7.3 Praktikas

Moodne tootmiskeskkond vajab mõlemat. Ei saa tugineda ainult dashboardidele (sest ei oska kõike ette näha) ega ainult eksploratiivsele (sest iga kasutaja kaebus ei vääri 30-minutilist uurimist).

Mõtlemiseks: SoundCloud ja Netflix avaldasid 2017-2020 paiku, et nende "dashboardide vaatamise" aeg on suhteliselt väheoluline, rohkem väärtust tuleb ad-hoc päringute tööriistadelt (Honeycomb stiilis, high-cardinality).

---

## 8. Tööriistade maastik

Selle kursuse viie päeva jooksul puutud kokku järgmiste tööriistadega. Siin on võrdlustabel, millal millist eelistada.

### 8.1 Metrics-kihi tööriistad

| Tööriist | Tugevused | Nõrkused | Sobib kui |
|----------|-----------|----------|-----------|
| **Prometheus** | Pull-mudel, PromQL, CNCF standard | Staatiline retention, vertikaalne skaleerumine | Kubernetes, dünaamilised keskkonnad |
| **Zabbix** | Mature, suur template-kogumik, klassikaline seire | Jäigem andmemudel, vähem cloud-native | Suur infrastruktuur, legacy süsteemid |
| **InfluxDB** | Optimeeritud suure kirjutussageduse jaoks, IoT sobivus | Vähem CNCF-ökosüsteem | IoT, Industry 4.0, kõrge sagedusega sensorid |
| **VictoriaMetrics** | Kõrge ressursitõhusus, Prometheus-ühilduv | Väiksem ökosüsteem | Kui Prometheus läheb liiga kalliks |

### 8.2 Logs-kihi tööriistad

| Tööriist | Tugevused | Nõrkused | Sobib kui |
|----------|-----------|----------|-----------|
| **Loki** | Odav (label-indeksid), integreerub Grafanaga | Täistekstiotsing kehvem kui ELK | Kubernetes-keskkond, kus kasutad juba Grafanat |
| **ELK Stack** | Võimas täistekstiotsing, suur ökosüsteem | Kallis (mälu, CPU), keeruline hallata | Keerulised otsinguid vajavad analüüsid |
| **OpenSearch** | AWS fork ELK-st, sama API | Uuem projekt, väiksem kogukond | Kui Elastic litsents on probleem |
| **Graylog** | Kesktee ELK ja Loki vahel | Väiksem turuosa | Mid-market ettevõtted |
| **Splunk** | Enterprise, ML-funktsioonid | Väga kallis | Suured organisatsioonid, valgusaasta eelarve |

### 8.3 Traces-kihi tööriistad

| Tööriist | Tugevused | Nõrkused | Sobib kui |
|----------|-----------|----------|-----------|
| **Tempo** | Object storage, odav; integreerub Grafanaga | Ei tee sampling-otsuseid | LGTM stack |
| **Jaeger** | Mature, CNCF, OpenTracing/OTel ühilduv | Eraldi UI (mitte Grafana) | Kui juba Jaeger kogukonnaga |
| **Zipkin** | Kerge, lihtne setup | Vähem funktsioone kui Jaeger | Algus-tasemel tracing |

### 8.4 Instrumentatsiooni standard: OpenTelemetry

Viimastel aastatel on turule tulnud **OpenTelemetry (OTel)** — CNCF projekt, mis ühtlustab kõikide sammaste instrumentatsiooni ühe standardi alla. Enne OTel-i:

- Prometheus klient-teegid mõõdikute jaoks
- Eraldi logimisraamistik logidele
- OpenTracing/Zipkin trace-ide jaoks

OTel-iga: **üks SDK kolmele sambale**, vendor-neutraalne. OTLP (OpenTelemetry Protocol) on edastuse standard. Võid rakenduses kasutada OTel-i, mõõdikud liiguvad Prometheusesse, logid Lokisse, trace-id Tempo-sse — **ilma et rakenduse kood peaks seda teadma**.

**Päev 5 käsitleb OTel-i detailselt.**

---

## 9. Intsidentide haldamine

Hoolimata parimast observability-st juhtuvad intsidendid. Nende käsitlemise küpsus eristab tootmiskõlblikke organisatsioone amatöörlikest.

### 9.1 Intsidenti elutsükkel

```
Tuvastamine → Klassifitseerimine → Mobiliseerimine → Uurimine → Lahendamine → Postmortem
```

- **Tuvastamine** (MTTD) — monitooringust, kasutajalt, automaatteste kaudu
- **Klassifitseerimine** — severity (P0/P1/P2), mõju (kui palju kasutajaid)
- **Mobiliseerimine** — kes teeb mida, kellele eskaleerin
- **Uurimine** — observability tools, runbook'id
- **Lahendamine** — rollback, hotfix, manuaalne parandus
- **Postmortem** — miks see juhtus, kuidas vältida tulevikus

### 9.2 Blameless postmortem

SRE kultuuris kehtib põhimõte: **vead on protsessi/süsteemi, mitte inimese süü.** Postmortem ei küsi "kes tegi vea?", vaid "millised tingimused võimaldasid vea tekkimist ja kuidas süsteemi parandada?"

Blameless-i põhjendus on praktiline: kui kaasalused kardavad süüdistamist, nad varjavad infot. Varjatud info takistab õppimist. Õppimata jäetakse sama viga kordama.

### 9.3 Postmortem dokumendi struktuur

Tüüpiline struktuur (Google SRE raamatust):

1. **Kokkuvõte** — mis juhtus, kestus, mõju
2. **Ajaliinid** — sündmuste kronoloogia
3. **Mõju mõõtmine** — kasutajate arv, rahaline mõju, SLO rikkumised
4. **Juurpõhjus** — tehniline analüüs
5. **Parandusmeetmed** — konkreetsed tegevused koos omanike ja tähtaegadega
6. **Õppimuskohad** — mida see intsident meile ütleb

Avalikke postmortemeid tasub lugeda õppetundide jaoks: [postmortems GitHub kollektsioon](https://github.com/danluu/post-mortems).

---

## 10. Regulatiivne kontekst

Monitooring pole ainult tehniline valik — on ka seadusandlikke nõudeid.

### 10.1 GDPR (General Data Protection Regulation)

Euroopa Liidu andmekaitsemäärus kehtib igale organisatsioonile, kes töötleb ELi kodanike andmeid.

Nõuded, mis puudutavad monitooringut:

- **Audit-logid** — kõik juurdepääsud isikuandmetele tuleb logida
- **Kustutamise nõue** — kasutaja taotlusel tuleb tema andmed kustutada, sh logidest
- **Teavitamiskohustus** — andmelekkest tuleb teavitada 72 tunni jooksul
- **Trahvid** — kuni 4% aasta ülemaailmsest käibest

**Tehniline tagajärg:** kui logid sisaldavad PII-d (isikuandmeid), peab neid käsitlema regulatiivselt (säilitusaeg, juurdepääsukontroll, kustutamise võimalus). Mõned ettevõtted eraldavad audit-logid ja operatsioonilogid just seetõttu, et vältida operatsioonilogide sattumist regulatiivsesse raamistikku.

### 10.2 NIS2 ja muud

- **NIS2** (2023) — ELi küberturvalisuse direktiiv kriitiliste taristute jaoks
- **DORA** (Digital Operational Resilience Act, 2025) — finantssektori töökindluse nõuded
- **Sektoripõhised** — PCI-DSS (maksekaardid), HIPAA (USA tervishoid)

Kõik nõuavad üksikasjalikku logimist ja observability-t. Finantsiliste teenuste arhitekt peab kujundama süsteemid, mis suudavad taastada täieliku audit-ahela iga tehingu kohta.

---

## 11. Tulevikutrendid (2026)

### 11.1 OpenTelemetry konsolideerumine

OTel on de facto standard uute projektide jaoks. Vanad süsteemid migreeruvad järk-järgult. Prognoos: 2027-2028 paiku on OTel dominantne instrumentatsiooni standard.

### 11.2 eBPF-põhine observability

[eBPF (extended Berkeley Packet Filter)](https://ebpf.io/) lubab Linuxi kerneli-tasemel koguda observability-andmeid **ilma rakenduse muutmiseta**. Tööriistad nagu [Cilium Hubble](https://cilium.io/), [Pixie](https://px.dev/), [Parca](https://www.parca.dev/) toovad "zero-instrumentation" observability.

Eelis: ei pea iga rakendust instrumenteerima, andmed tulevad kerneli-tasandilt.
Piirang: vaid Linuxi (mitte Windows / macOS), vajab õige sügavaid kerneli teadmisi.

### 11.3 AI-abiline analüüs

Suuri mudelid anomaalia-tuvastuseks, alert-gruppimiseks, juurpõhjuste pakkumiseks. Kogu selle kursuse viimane päev vaatleb 2026 trende põhjalikumalt.

### 11.4 FinOps + observability

Cloud-kulude jälgimine kui observability distsipliin. Tööriistad nagu Kubecost, OpenCost viivad infrastruktuuri kulumõõdikud sama dashboardile jõudluse mõõdikutega.

---

## 12. Kokkuvõte

**Peamised mõisted, mida pead meelde jätma:**

- **Monitooring on äririsk** — kvantifitseeritud downtime-kuludes
- **Kolm mõistet pole sünonüümid** — logimine (sündmused), seire (mõõdikud), vaatlus (uurimise võime)
- **Kolm sammast** — metrics (kui palju?), logs (mis juhtus?), traces (kus aeglustub?)
- **USE infrastruktuurile, RED teenustele, 4GS kasutajale**
- **SLI → SLO → error budget** — raamistik kiiruse ja stabiilsuse tasakaalustamiseks
- **Alert'id peavad olema actionable ja symptom-based** — muidu tekib alert fatigue
- **Monitoring ja observability täiendavad teineteist** — mitte kas-kas
- **OpenTelemetry on tulevik** — vendor-neutraalne instrumentatsioon

**Järgmine samm:** [Loeng 2 — Prometheus ja Grafana](paev1-loeng.md) — kuidas metrics-sammas praktikas töötab.

---

## Enesekontrolli küsimused

1. Mis on MTTD ja MTTR? Kuidas observability mõjutab kumbagi?
2. Selgita tehnilist erinevust logimise ja seire vahel. Mis andmetüüpi kumbki kasutab?
3. Millal kasutad USE meetodit ja millal RED meetodit? Too konkreetne näide mõlemast.
4. Mis on error budget? Kuidas see mõjutab arendusprotsessi?
5. Miks peaksid alert-id olema symptom-based, mitte cause-based? Too näide halvast ja heast alert-ist.
6. Kasutaja kaebab aeglast lehte. Millises järjekorras vaatled kolme sammast? Miks just selles järjekorras?
7. Millal eelistad Lokit ELK-le? Millal vastupidi?
8. Mida toob OpenTelemetry juurde võrreldes traditsioonilise instrumentatsiooniga?

---

## Viited ja süvendatud lugemine

### Põhiteosed

| Allikas | Miks lugeda |
|---------|-------------|
| [Google SRE raamat](https://sre.google/sre-book/table-of-contents/) | Tasuta, valdkonnas standardsereferents. Peatükk 6 eriti oluline |
| [Google SRE Workbook](https://sre.google/workbook/table-of-contents/) | Teise raamatu praktiline jätk |
| [Observability Engineering](https://www.oreilly.com/library/view/observability-engineering/9781492076438/) | Charity Majors jt — moodne observability filosoofia |
| [Seeking SRE](https://www.oreilly.com/library/view/seeking-sre/9781491978856/) | David Blank-Edelman, intervjuud tööstuse liidritelt |

### Metoodikad

| Allikas | Miks lugeda |
|---------|-------------|
| [Brendan Gregg — USE Method](https://www.brendangregg.com/usemethod.html) | Ametlik allikas, Netflix / Oracle / Intel |
| [Tom Wilkie — RED Method](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/) | Grafana Labs CTO |
| [Four Golden Signals](https://sre.google/sre-book/monitoring-distributed-systems/) | Google SRE raamatu peatükk 6 |
| [Service Level Objectives](https://sre.google/sre-book/service-level-objectives/) | Google SRE raamatu peatükk 4 — SLI/SLO/SLA formaalselt |
| [Postmortem Culture](https://sre.google/sre-book/postmortem-culture/) | Google SRE raamatu peatükk 15 |

### CNCF ja standardid

| Allikas | Miks lugeda |
|---------|-------------|
| [CNCF Observability Whitepaper](https://github.com/cncf/tag-observability/blob/main/whitepaper.md) | Cloud Native Computing Foundation ametlik seisukoht |
| [CNCF Landscape](https://landscape.cncf.io/guide#observability-and-analysis) | Kõikide observability-tööriistade kaart |
| [OpenTelemetry](https://opentelemetry.io/docs/) | Moodne instrumentatsiooni standard |
| [OpenMetrics spec](https://openmetrics.io/) | Exposition format standard |

### Praktiline

| Allikas | Miks lugeda |
|---------|-------------|
| [post-mortems (Dan Luu GitHub)](https://github.com/danluu/post-mortems) | Avalike intsidentide kollektsioon |
| [observability.dev](https://observability.dev/) | Praktiliste näidete kogumik |
| [Honeycomb blog](https://www.honeycomb.io/blog) | High-cardinality observability perspektiiv |
| [Grafana Labs blog](https://grafana.com/blog/) | Praktilised juhendid |

### Eesti kontekst

Mitmed Eesti ettevõtted on avalikult rääkinud oma observability praktikatest — Bolt, Wise (Transferwise), Pipedrive, Veriff. Otsi nende inseneri-blogidest või tehnoloogiakonverentside ettekannetest (nt TalTech-i konverentsid, Devclub.eu).
