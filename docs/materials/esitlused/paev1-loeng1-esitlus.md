---
marp: true
theme: default
paginate: true
header: "Päev 1 · Loeng 1 · Observability"
footer: "Haapsalu KHK · Monitooring ja jälgitavus · 2026"
---

<!--
KOMBINEERITUD ESITLUSE-SKRIPT — Loeng 1: Monitooring, logimine, vaatlus

See fail teenib kolme eesmärki:
  1. SLAIDID — saab renderdada Marp, Reveal.js või importida PowerPointi/Google Slidesi
  2. AUDIO — jutustaja tekst iga slaidi all sobib otse narratsiooniks (~35 min)
  3. VIDEO — visuaali-vihjed ütlevad, mida ekraanil näidata

NotebookLM kasutamine:
  Lae see fail sisse allikaks. NotebookLM suudab genereerida:
    • Audio overview (dialoogne podcast kahe hääle vahel)
    • Video overview (slaidid + narratsioon, uus funktsioon 2025)
    • Õpijuhend, FAQ, ajajoon

Kestvused on ligikaudsed — kohanda vastavalt rühmale.
Klassis võib jätta mõne slaidi vahele ja minna laborisse varem.
-->

# Monitooring, logimine, vaatlus

### Kaasaegne IT-süsteemide monitooring ja jälgitavus

**Päev 1 · Loeng 1 · 30 minutit**

Maria Talvik · Haapsalu KHK · 18.04.2026

<!--
JUTUSTAJA (45 sek):
Tere ja tere tulemast meie monitooringu täienduskursuse esimesele loengule.
Enne kui me läheme Prometheuse ja Grafana tehnilisse süvitsi, peame paika panema
põhimõisted. Selle 30-minutilise loengu lõpuks tead, miks monitooring pole lihtsalt
tehniline kohustus vaid äririsk, mida saab mõõta eurodes ja minutites. Sa eristad
kolme mõistet, mida tavaliselt aetakse segamini — logimist, seiret ja vaatlust.
Ja sa tead, mis raamistikke kasutada, et vastata küsimusele "mida üldse jälgida".

VISUAAL: pealkiri + Haapsalu KHK logo + kuupäev
-->

---

## Õpiväljundid

Selle loengu lõpuks osaleja:

- **Põhjendab** monitooringu äririski-vähendamise rolli kulunumbrite kaudu
- **Eristab** logimist, seiret ja vaatlust tehniliselt
- **Kirjeldab** kolme sammast: metrics, logs, traces
- **Rakendab** USE, RED ja Four Golden Signals raamistikke
- **Selgitab** SLI, SLO, error budget'i hierarhiat
- **Hindab** alert-disaini kolme kriteeriumi järgi

<!--
JUTUSTAJA (30 sek):
Kuus konkreetset oskust, mida sa peaksid selle loengu lõpuks omama. Me ei käsitle
siin veel ühtegi tööriista detailselt — Prometheus tuleb järgmises loengus. See
loeng annab sulle raamistiku, mille abil iga tööriist — olgu see Prometheus,
Zabbix, või ELK — saab oma koha.

VISUAAL: loetelu ekraanil, iga punkt võib ilmuda järjest
-->

---

## 1. Miks monitooring on äririsk

Mitte tehniline kohustus. **Kvantifitseeritav risk.**

<!--
JUTUSTAJA (20 sek):
Alustame kõige olulisemaga — miks me siin üldse oleme. Monitooring pole tehniline
kohustus, mida insenerid peavad täitma, sest nii on kombeks. See on konkreetne
äririsk, mida saab rahas mõõta. Vaatame numbreid.

VISUAAL: üksainus suur pealkiri tumedal taustal, et rõhutada üleminekut
-->

---

## Downtime'i maksumus — reaalsed numbrid

| Ettevõte / sektor | Minutis | Allikas |
|-------------------|---------|---------|
| Amazon.com | ~$220 000 | 2023 hinnang |
| Finantsteenused | $9 000 | Gartner 2022 |
| Kindlustus | $4 800 | Gartner 2022 |
| Tüüpiline SaaS | $5 600 | Gartner 2022 |

<!--
JUTUSTAJA (50 sek):
Amazon.com-i üks minut seisakut maksab ligi veerand miljonit dollarit. See pole
hüpoteetiline — Amazon ise on neid numbreid avaldanud. Finantsteenuste valdkonnas
on minutikulu ligi 9000 dollarit, Gartneri 2022 aasta uuringu põhjal. Isegi
tüüpilise SaaS-ettevõtte jaoks läheb iga seisakuminutis ligi 5600 dollarit.

Eesti kontekstis — Bolt, Wise, Pipedrive, Veriff kõik panustavad igal aastal
miljoneid eurosid observability infrastruktuuri. Mitte sellepärast, et see on
lahe tehnoloogia. Sellepärast, et ilma selleta nad ei tööta.

VISUAAL: tabel ekraanil, võib lisada animeeritud $ märke
-->

---

## MTTD ja MTTR

```
Intsident algab ──► Tuvastatakse ──► Lahendatakse
           ◄─MTTD─►           ◄────MTTR────►
```

- **MTTD** = Mean Time To Detect — kui kiiresti avastad
- **MTTR** = Mean Time To Resolve — kui kiiresti lahendad

**Hea observability vähendab mõlemat.**

<!--
JUTUSTAJA (45 sek):
Intsidendil on kaks kriitilist ajaperioodi. MTTD — aeg, mille jooksul sa saad teada,
et probleem on. MTTR — aeg, mille jooksul sa selle lahendad. Hea observability
vähendab mõlemaid, aga eriti MTTD-d.

Kui su esimene monitooringuallikas on kasutaja, kes helistab helpdeskile — sinu
MTTD on tüüpiliselt 10-60 minutit. Iga minut on raha. Kui aga Prometheus alert
käivitub 90 sekundi jooksul, oled 95% lühendanud oma avastamisaega.

Reegel: kasutaja ei tohi olla su esimene monitooringuallikas.

VISUAAL: ajariba animeeritult — intsident algab vasakul, tuvastamine keskel,
lahendamine paremal. Näita, kuidas hea monitooring "võtab MTTD raami kitsamaks".
-->

---

## 2. Kolm mõistet, mida aetakse segamini

**Logimine ≠ Seire ≠ Vaatlus**

Erinevad andmemudelid. Erinevad tööriistad. Erinevad küsimused.

<!--
JUTUSTAJA (25 sek):
Nüüd läheme põhimõistete juurde. IT-spetsialistid kasutavad sõnu "logging",
"monitoring" ja "observability" tihti sünonüümidena. Need pole sünonüümid. Neil on
erinevad andmemudelid, erinevad tööriistad ja need vastavad erinevatele küsimustele.
Kui sa neid ei erista, teed vigaseid tööriista-valikuid.

VISUAAL: kolm võrdsuse läbi tõmmatud märki ekraanil
-->

---

## Logimine — sündmuste päevik

```
2026-04-18T10:23:41 INFO  auth    login    user=jaan ip=10.2.3.4
2026-04-18T10:23:45 ERROR payment timeout  tx=T-98321 db=primary-01
2026-04-18T10:24:01 FATAL payment abort    tx=T-98321 reason="retries failed"
```

**Küsimus:** mis täpselt juhtus, millal, kellega?

**Maht:** gigabaite päevas · **Vorming:** tekst või JSON · **Kulu:** kõrge otsingul

<!--
JUTUSTAJA (40 sek):
Logimine salvestab üksikuid sündmusi. Iga kord, kui midagi olulist juhtub —
kasutaja logib sisse, päring ebaõnnestub, teenus käivitub — kirjutatakse see üles
koos ajatempliga.

Logid vastavad küsimusele: "mis täpselt juhtus?" Konkreetne sündmus konkreetsel ajal.

Probleem logidega on maht. Moodne süsteem genereerib gigabaite logisid päevas.
Ilma tsentraliseeritud lahenduseta, nagu Loki või ELK, pead 50 serverisse ükshaaval
SSH-ga logima — see lihtsalt ei skaleeru.

VISUAAL: koodiplokk näitega + maht-ikoon (GB/päev)
-->

---

## Seire — mõõdikud ajas

```
cpu_usage{host="web-01"} 45.2   @ 10:23:00
cpu_usage{host="web-01"} 47.1   @ 10:23:15
cpu_usage{host="web-01"} 89.1   @ 10:23:30   ← midagi juhtus
cpu_usage{host="web-01"} 44.2   @ 10:24:00   ← lahenes
```

**Küsimus:** kui palju? Kas normaalne?

**Maht:** megabaite · **Vorming:** aegread · **Kulu:** madal päringul

<!--
JUTUSTAJA (40 sek):
Seire on hoopis teistsugune. Siin ei salvesta me sündmusi, vaid numbreid ajas.
Iga 15 sekundi järel küsib Prometheus: mis on CPU kasutus, mis on mälu, mis on
päringute arv. Need numbrid moodustavad aegrea — väärtuste jada ajas.

Seire vastab küsimusele: "kui palju ressursi ma kasutan ja kas see on normaalne?"

Maht on palju väiksem kui logidel — megabaite, mitte gigabaite. Ja päringud on
kiired, sest andmebaas on sellise formaadi jaoks optimeeritud.

VISUAAL: graafik ajas näitab spike'i 10:23:30 juures, punane nool
-->

---

## Vaatlus — uurimise võime

**Monitoring** = "kas süsteem töötab?"

**Observability** = "**miks** süsteem on aeglane ja **kus täpselt**?"

> Monitoring on teadaolevate teadaolekute jaoks.
> Observability on tundmatute tundmatute jaoks.

<!--
JUTUSTAJA (55 sek):
Observability on midagi enamat kui lihtsalt logide ja mõõdikute kogumine. See on
võime vastata suvalisele küsimusele su süsteemi kohta, ilma et peaksid eelnevalt
teadma, mida mõõta.

Monitooring on teadaolevate teadaolekute jaoks — sa tead, et CPU võib olla probleem,
nii et sa paned üles CPU dashboardi. Aga observability on tundmatute tundmatute
jaoks — kasutaja kaebab aeglust pärast deploy-i, sa ei tea miks, aga sul on
vahendid, millega saad uurida.

Termini populariseerisid Charity Majors ja kaasautorid 2022. aasta raamatus
"Observability Engineering". See on tänapäeva tootmissüsteemi standard.

VISUAAL: kaks küsimusmärki — üks väike (monitoring), teine suur ja keerlev
(observability)
-->

---

## 3. Kolm sammast

```
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│   METRICS    │ │     LOGS     │ │    TRACES    │
│              │ │              │ │              │
│ Kui palju?   │ │ Mis juhtus?  │ │ Kus viibib?  │
│ Prometheus   │ │ Loki / ELK   │ │ Tempo/Jaeger │
└──────────────┘ └──────────────┘ └──────────────┘
```

<!--
JUTUSTAJA (35 sek):
Observability kolm sammast. Metrics vastab küsimusele "kui palju" — numbrid ajas.
Logs vastab küsimusele "mis juhtus" — üksikud sündmused. Traces vastab küsimusele
"kus täpselt viibib" — päringute teekond läbi mikroteenuste.

Kolm sammast, kolm erinevat küsimust. Täielik observability vajab kõiki kolme.
Selle kursuse viie päeva jooksul ehitame kõik kolm üles. Täna metrics-kihi.
Järgmisel nädalal logs-kihi. Päev viis traces.

VISUAAL: kolm kasti kõrvuti, võib hiirega rõhutada iga üks kordamööda
-->

---

## Kolm sammast — tehniline võrdlus

| | Metrics | Logs | Traces |
|---|---------|------|--------|
| **Andmetüüp** | Aegread | Sündmused | Päringuteekonnad |
| **Maht** | MB / päev | GB / päev | GB-TB / päev |
| **Säilitus** | 15 päeva - 1 aasta | 7-90 päeva | 1-7 päeva |
| **Päringu kiirus** | ms | sek | sek |

<!--
JUTUSTAJA (40 sek):
Tehniliselt on sammasd väga erinevad. Metrics on kõige odavam — megabaite päevas,
kiired päringud, pikk säilitus. Logs on keskklass — gigabaite päevas, aeglasemad
päringud. Traces on kõige ressursinõudlikum — võib olla terabaite päevas, ja
peamiselt seetõttu tehakse sampling'ut — st ei salvestata mitte iga päringut,
vaid osa neist.

See mõjutab otseselt, kui kaua sa andmeid säilitad — metrics aasta, logs kuu,
traces nädal. Ja päringute hind on vastavalt.

VISUAAL: tabel, võib värvikoodidega markeerida "odav" (roheline) kuni "kallis" (punane)
-->

---

## Kasutaja kaebab aeglast lehte

| Sammas | Annab vastuse |
|--------|---------------|
| **Metrics** | Andmebaasi CPU 100%, p99 = 4.2s |
| **Logs** | Täistabeli skaneerimised iga sekund |
| **Traces** | Konkreetne päring viibib DB-s 4.5s/5s, SQL: `SELECT users.* WHERE email LIKE '%@'` |

<!--
JUTUSTAJA (50 sek):
Võtame praktilise näite. Kasutaja kaebab, et leht on aeglane. Kuidas sa uurid?

Metrics näitab, et andmebaasi CPU on 100% ja p99 latentsus on 4.2 sekundit.
Aga sa ei tea miks.

Logs ütleb, et andmebaas teeb täistabeli skaneerimisi iga sekund. Juba parem.

Traces näitab konkreetset päringut — see viibib andmebaasi-operatsioonis täpselt
4.5 sekundit 5-st. Ja võimaldab näha ka SQL-päringut — `SELECT users.* WHERE email
LIKE '%@'`. Puudub indeks. Seal see on.

Ilma trace-iteta teaksid, et **midagi** on aeglane. Trace'idega tead, **mis täpselt**
ja **miks**.

VISUAAL: tabel, kusjuures iga rea juures on "✗" → "?" → "✓" mis näitab info
täpsuse paranemist sammaste kaupa
-->

---

## 4. Mida üldse jälgida — kolm raamistikku

**USE** → infrastruktuurile

**RED** → teenustele

**Four Golden Signals** → kasutajakogemusele

<!--
JUTUSTAJA (25 sek):
Tuhandete potentsiaalsete mõõdikute hulgast — mida valida? Kolm raamistikku annavad
struktuuri. USE infrastruktuurile — serveritele, ketastele, võrgule. RED teenustele —
API-dele, mikroteenustele. Ja Google'i Four Golden Signals kasutajakogemusele
tervikuna. Me kasutame korraga kõiki kolme.

VISUAAL: kolm akronüümi ekraanile ilmuvad järjest
-->

---

## USE — Brendan Gregg, Netflix

Iga ressursi kohta:

- **U**tilization — hõivatuse %
- **S**aturation — järjekorras ootajad
- **E**rrors — vead

| | CPU | Mälu | Ketas | Võrk |
|---|---|---|---|---|
| **U** | CPU % | RAM % | I/O % | Bandwidth % |
| **S** | Load avg | Swap | I/O queue | Dropped pkts |
| **E** | — | OOM kills | Disk errors | IF errors |

<!--
JUTUSTAJA (50 sek):
USE meetod tuleb Brendan Greggilt, Netflix'i ja hiljem Intel'i inseneri poolt.
Iga ressursi kohta — CPU, mälu, ketas, võrk — küsid kolm küsimust.

Esiteks, kui suur osa ressursist on hõivatud? See on Utilization.

Teiseks, kas miski ootab järjekorras? See on Saturation. Näiteks CPU 80% võib olla
okei, kui load average on madal. Aga kui load average on 20 ja CPU-sid on 4 —
meil on 16 protsessi järjekorras ja see on probleem.

Kolmandaks, kas ressurss tagastab vigu? Mälu puhul näiteks out-of-memory killid.

See tabel on klassika. Print see välja ja hoia laua peal.

VISUAAL: 4x3 tabel, võib rõhutada ühte rida korraga
-->

---

## RED — Tom Wilkie, Grafana Labs

Iga teenuse kohta:

- **R**ate — päringud sekundis
- **E**rrors — veaprotsent
- **D**uration — p95, p99 kestvus

> Bolt jälgib sõidupäringute RED-mõõdikuid reaalajas.
> Langus Rate-is = midagi on valesti.

<!--
JUTUSTAJA (45 sek):
RED meetod on Tom Wilkie, Grafana Labs'i praeguse tehnikadirektori töö. See on
spetsiifiliselt mikroteenuste jaoks.

Rate — kui palju päringuid sekundis teenus saab. Errors — kui suur osa ebaõnnestub.
Duration — kui kauaks teenus vastab, eriti kõrged protsentiilid nagu p95 ja p99.

Praktiline näide: Bolt jälgib sõidupäringute RED-mõõdikuid reaalajas. Kui Rate
langeb järsku öösel kell 2, kui see tavaliselt ei lange — on midagi valesti.
See on tihti kõige varasem signaal, enne kui veateated tulevad.

VISUAAL: kolm akronüümi + tsitaat Boltist
-->

---

## Four Golden Signals — Google SRE

| Signaal | Mõõdab |
|---------|--------|
| **Latency** | Kui kiiresti vastab |
| **Traffic** | Koormuse tase |
| **Errors** | Ebaõnnestumiste osakaal |
| **Saturation** | Kui lähedal ressursi piirile |

**Saturation on olulisim ennetamiseks.**

<!--
JUTUSTAJA (50 sek):
Google'i SRE raamat, mis on tasuta veebis, defineerib Four Golden Signals — neli
signaali, mis kokku katavad enamiku tootmisprobleemidest.

Latency, Traffic, Errors, Saturation. Neli signaali.

Saturation on olulisim ennetamiseks. Miks? Sest latency ja vead on sümptomid.
Need ilmuvad alles pärast saturatsiooni. Kui jälgid ainult latency-t, alustad
reageerimist alles siis, kui on juba hilja.

Kui sa mäletad ainult nelja asja sellest loengust — jäta need neli meelde.

VISUAAL: 4 signaali ringina, Saturation esile tõstetud
-->

---

## 5. SLI, SLO, SLA — tootmise keel

- **SLI** — Service Level Indicator (näitaja)
- **SLO** — Service Level Objective (sihtväärtus)
- **SLA** — Service Level Agreement (leping)

```
SLI: API päringu edukus = 2xx+3xx / kokku
SLO: 99.9% edukus 30 päeva jooksul
SLA: alla 99.5% → 10% kuutasust tagasi
```

<!--
JUTUSTAJA (45 sek):
Nüüd tootmisterminoloogiasse. Kolm akronüümi, mida inglise keeles kutsutakse
SLI, SLO, SLA.

SLI on Service Level Indicator — konkreetne mõõdetav näitaja. Näiteks:
"API päringu edukus on 2xx ja 3xx vastuste osakaal kõigist vastustest."

SLO on Service Level Objective — sihtväärtus SLI-le. Näiteks 99,9% edukus viimase
30 päeva jooksul.

SLA on Service Level Agreement — lepinguline kohustus. See on see, mida sa kliendile
lubad. Kui SLA on rikutud, saad kliendi raha tagasi anda.

VISUAAL: pyramiid — SLI all, SLO keskel, SLA tipus
-->

---

## Error budget — tootmise tarkus

**99.9% kuus = 43 minutit downtime'i lubatud**

- Budget alles → meeskond saab riskida (uued release'id)
- Budget otsas → kõik deploy-d peatatud, fookus stabiilsusele

**Tasakaalustab kiirust ja stabiilsust.**

<!--
JUTUSTAJA (55 sek):
Kui SLO on 99,9% kuus, tähendab see lubatud eelarvet vigu — 0,1% 30 päevast on
umbes 43 minutit seisakut kuus. See on sinu error budget.

Mõte on lihtne. Kui eelarve on veel alles, meeskond saab võtta riske. Uued
release'id, eksperimendid, riskantsed muudatused — kõik on okei.

Aga kui eelarve on otsas — kõik deploy-d peatatakse. Kogu meeskond fookuseerub
stabiilsusele, kuni eelarve taastub.

See on formaalne mehhanism, mis tasakaalustab arenduskiirust ja töökindlust.
Ilma selleta kipuvad meeskonnad minna kas äärmusesse "liigume kiiresti, hoolime
vähem" või "null downtime kui ainus prioriteet."

VISUAAL: progress bar 43 minutiga, millega saab "tarbida"
-->

---

## 6. Alert-disain — kaks põhilist eksimist

### Alert fatigue

Kui 80% alert-itest on müra → meeskond ignoreerib **kõiki**.

### Sümptom vs põhjus

- ❌ "CPU on 90%" — implementatsioonidetail
- ✅ "API latentsus p95 > 2s" — mõjutab kasutajat

<!--
JUTUSTAJA (55 sek):
Alert'imine on koht, kus monitooring läheb inimeste sekkumiseks. Kaks põhilist
viga, mida tehakse.

Esimene — alert fatigue. Kui 80% alert-itest on valehäired või müra, meeskond
kaotab reageerimisvõime kõigile alert-itele. See pole teoreetiline — on
dokumenteeritud intsidente, kus tõeline alert on ignoreeritud, sest 10 000
eelmist olid müra.

Teine viga — põhjusepõhine alertimine. "CPU on 90%" on süsteemi sisedetail.
Kas see mõjutab kasutajat? Võib-olla jah, võib-olla ei. Hea alert on
sümptomipõhine — "API latentsus p95 on 2 sekundit" — see mõjutab kasutajat
otseselt, ja kui see kehtib, pead tegutsema.

VISUAAL: punase X-iga "halb alert" ja rohelise linnukesega "hea alert"
-->

---

## Hea alert'i kriteeriumid

1. **Actionable** — tean, mida teha
2. **Symptom-based** — mõjutab kasutajat
3. **Runbook** — viit lahendamise juhendile
4. **Severity hierarhia** — critical / warning / info
5. **`for:` kestvus** — väldib mööduvaid spike'e

<!--
JUTUSTAJA (40 sek):
Kui sa disainid alert'i, kontrolli viis asja.

Esiteks — actionable. Kui saad teate ja sul ei ole selget järgmist sammu — see on
vale alert.

Teiseks — symptom-based. Mõjutab kasutajat.

Kolmandaks — runbook. Igal alert-il peaks olema link wikile, kus on kirjas, mida teha.

Neljandaks — severity hierarhia. Critical äratab öösel. Warning läheb hommikul
Slack'i. Info kuvatakse ainult dashboardil.

Viiendaks — for-kestvus. Alert ei pea käivituma iga 15-sekundilise spike'i peale.
Pane 5 minutit, vähemalt 1 minut.

VISUAAL: checklist, rohelised linnukesed, kui kriteerium on täidetud
-->

---

## 7. Monitoring vs Observability

|  | Monitoring | Observability |
|--|-----------|---------------|
| Tüüp | Eeldefineeritud | Eksploratiivne |
| Küsimused | Teadaolevad | Tundmatud |
| Sobib | Stabiilsed süsteemid | Keerulised distribueeritud |
| Tööriistad | Dashboardid, alertid | High-cardinality, traces |

**Moodne tootmine vajab mõlemat.**

<!--
JUTUSTAJA (45 sek):
Need mõisted pole sünonüümid. Monitoring on eeldefineeritud — tead ette, mida tahad
mõõta, seadistad dashboardid ja alertid. Sobib stabiilsetele süsteemidele, kus
failure mode'd on teada.

Observability on eksploratiivne. Kui kasutaja kaebab aeglast lehte ja sa pead
uurima, mis toimub — see on observability töövaldkond. Vajab high-cardinality
andmeid, nagu trace'id, kus iga päring on oma andmepunkt.

Moodne tootmiskeskkond vajab mõlemat. Ei saa tugineda ainult dashboardidele — ei
oska kõike ette näha. Ei saa tugineda ainult ekspressiivsele — iga kasutaja
kaebus ei vääri 30-minutilist uurimist.

VISUAAL: dashboard vs detektiiv lupiga — kaks erinevat tööriista erinevatele
olukordadele
-->

---

## 8. Tööriistade maastik — metrics

| Tööriist | Sobib kui |
|----------|-----------|
| **Prometheus** | Kubernetes, dünaamilised keskkonnad |
| **Zabbix** | Suur infrastruktuur, legacy |
| **InfluxDB** | IoT, kõrge kirjutussagedus |
| **VictoriaMetrics** | Kui Prometheus läheb liiga kalliks |

<!--
JUTUSTAJA (35 sek):
Metrics-kihi tööriistad. Prometheus on tänane standard dünaamilistele
keskkondadele, nagu Kubernetes. Zabbix on klassikaline — suur template'ide kogumik,
sobib legacy-süsteemidele. InfluxDB on IoT ja kõrge sagedusega sensorite jaoks —
Tesla tootmisliin, Bolti GPS-koordinaadid. VictoriaMetrics on ressursitõhusam
alternatiiv Prometheusele, kui skaala läheb suureks.

Mina kasutan selles kursuses Prometheust, sest see on Eesti tööturul kõige
nõutum oskus.

VISUAAL: 4 tööriista logo, Prometheus esile tõstetud
-->

---

## Tööriistade maastik — logs

| Tööriist | Sobib kui |
|----------|-----------|
| **Loki** | K8s, kasutad Grafanat |
| **ELK Stack** | Keerulised otsingud, suur maht |
| **OpenSearch** | AWS kontekst, Elastic litsentsi probleem |
| **Splunk** | Enterprise, suur eelarve |

<!--
JUTUSTAJA (35 sek):
Logs-kiht. Loki on odav ja integreerub Grafanaga — sobib Kubernetese kontekstile.
ELK Stack on võimas täistekstiotsing — mahukas, keerukam hallata, aga võimas.
OpenSearch on AWS fork ELK-st, sama API, sest Elastic muutis litsentsi.
Splunk on enterprise, kallis, aga ML-funktsioonidega.

Päeval 2 vaatame Loki. Päeval 3 ELK.

VISUAAL: 4 tööriista logo
-->

---

## Tööriistade maastik — traces

| Tööriist | Sobib kui |
|----------|-----------|
| **Tempo** | LGTM stack, Grafana |
| **Jaeger** | CNCF, mature |
| **Zipkin** | Algus-tasemel |

**OpenTelemetry** = ühtne instrumentatsiooni standard kõigile kolmele

<!--
JUTUSTAJA (40 sek):
Traces-kiht. Tempo on Grafana Labs'i toode, kasutab object storage'it, odav.
Jaeger on mature CNCF projekt. Zipkin on lihtsam, algus-taseme jaoks.

Ja kõige olulisem — OpenTelemetry. See on CNCF projekt, mis ühtlustab kõikide
sammaste instrumentatsiooni ühe standardi alla. Sa instrumenteerid oma rakendust
üks kord OpenTelemetry SDK-ga, ja mõõdikud lähevad Prometheusesse, logid Lokisse,
trace'id Tempo-sse. Rakendus ei pea seda teadma.

Päev 5 käsitleb OpenTelemetry detailselt.

VISUAAL: OpenTelemetry logo suurelt + 3 arrow'ga 3-le tööriistale
-->

---

## 9. Intsidentide haldamine

```
Tuvastamine → Klassifitseerimine → Mobiliseerimine → Uurimine → Lahendamine → Postmortem
```

**Blameless postmortem** — vead on süsteemi, mitte inimese süü.

<!--
JUTUSTAJA (45 sek):
Hoolimata parimast observability-st juhtuvad intsidendid. See, kuidas meeskond
neid käsitleb, eristab tootmiskõlblikke organisatsioone amatöörlikest.

Intsidendi elutsükkel on kuueetapiline — tuvastamine, klassifitseerimine,
mobiliseerimine, uurimine, lahendamine, postmortem.

Postmortem on viimane ja üks olulisemaid etappe. SRE kultuuris on see alati
blameless — süüdistatamata. Vead on protsessi ja süsteemi süü, mitte inimese süü.

Põhjus on praktiline. Kui inimesed kardavad süüdistamist, nad varjavad infot.
Varjatud info takistab õppimist. Õppimata jäetakse sama viga kordama.

VISUAAL: 6-etapiline flowchart
-->

---

## 10. Regulatiivne kontekst

- **GDPR** — PII logides, 72h teavitamiskohustus
- **NIS2** — küberturvalisus kriitilistele taristutele
- **DORA** — finantssektori töökindlus (2025)
- **PCI-DSS, HIPAA** — sektoripõhine

**Trahvid:** kuni 4% aasta käibest (GDPR)

<!--
JUTUSTAJA (45 sek):
Monitooring pole ainult tehniline valik. On seadusandlikke nõudeid.

GDPR kehtib igale Euroopa kodaniku andmeid töötlevale organisatsioonile. Kui su
logid sisaldavad isikuandmeid, pead neid käsitlema regulatiivselt. Kustutamise
nõue, audit-logid, andmelekkest teavitamine 72 tunni jooksul. Trahvid ulatuvad
4%-ni aasta käibest.

Lisaks GDPR-ile — NIS2 kriitilistele taristutele, DORA finantssektorile,
PCI-DSS maksekaartidele. Kõik nõuavad üksikasjalikku logimist ja observability-t.

Kui arendad finantstarkvara, pead süsteemid kujundama nii, et suudad taastada
täieliku audit-ahela iga tehingu kohta.

VISUAAL: 4 regulatsiooni logo/ikooni
-->

---

## 11. Tulevikutrendid 2026

- **OpenTelemetry** konsolideerumine
- **eBPF-põhine observability** — zero-instrumentation
- **AI-abiline analüüs** — anomaalia tuvastus, alert grupitamine
- **FinOps** + observability — cloud-kulude jälgimine

<!--
JUTUSTAJA (50 sek):
Kus on valdkond minemas? Neli peamist trendi.

Esiteks, OpenTelemetry konsolideerumine. See on de facto standard uute projektide
jaoks. Vanad süsteemid migreeruvad. Prognoos — 2027-2028 on OTel dominantne.

Teiseks, eBPF. See on Linuxi kerneli-tasandi tehnoloogia, mis lubab koguda
observability-andmeid ilma rakenduse muutmiseta. Tööriistad nagu Cilium Hubble
ja Pixie toovad "zero-instrumentation" observability.

Kolmandaks, AI-abiline analüüs. Suurte mudelite kasutamine anomaalia
tuvastuseks ja juurpõhjuste pakkumiseks.

Neljandaks, FinOps. Cloud-kulude jälgimine kui observability distsipliin.
Tööriistad nagu Kubecost viivad kulumõõdikud samale dashboardile jõudlusega.

Kursuse viimane päev käsitleb neid trende põhjalikumalt.

VISUAAL: 4 trendi ikoonidega
-->

---

## Kokkuvõte — mida meelde jätta

- **Monitooring = äririsk**, kvantifitseeritud
- **Kolm mõistet** erinevad tehniliselt
- **Kolm sammast**: metrics, logs, traces
- **USE / RED / 4GS** — raamistikud mida jälgida
- **SLI → SLO → error budget**
- **Alert'id peavad olema actionable ja symptom-based**
- **Monitoring + observability koos**
- **OpenTelemetry on tulevik**

<!--
JUTUSTAJA (35 sek):
Kokkuvõtteks — kaheksa asja, mida meelde jätta.

Monitooring on äririsk, mitte tehniline kohustus. Logimine, seire ja vaatlus on
tehniliselt erinevad. Kolm sammast on metrics, logs, traces. USE infrastruktuurile,
RED teenustele, Four Golden Signals kasutajale. SLI, SLO, error budget on
tootmise keel. Alert'id peavad olema actionable ja symptom-based. Monitoring ja
observability täiendavad teineteist. Ja OpenTelemetry on tulevik.

VISUAAL: kõik 8 punkti listena, võiksid ilmuda järjest
-->

---

## Järgmine

**Loeng 2: Prometheus ja Grafana**

Kuidas metrics-sammas praktikas töötab
Pull-mudel, PromQL, alertid, dashboardid

**~45 minutit**

<!--
JUTUSTAJA (15 sek):
Järgmine — teine loeng selle päeva kohta. Prometheus ja Grafana, metrics-sammas
praktikas. Lähme 45 minutiks sügavuti.

VISUAAL: üleminek järgmisele teemale
-->

---

## Küsimused?

📧 maria.talvik@haapsalu.kutsehariduskeskus.ee

📚 [docs.haapsalu-kutsehariduskeskus.github.io/monitoring-taienduskoolitus](https://haapsalu-kutsehariduskeskus.github.io/monitoring-taienduskoolitus/)

<!--
JUTUSTAJA (10 sek):
Küsimused enne labori juurde liikumist? Tagasiside — kirjuta mulle otse, olen
siin kõik 5 päeva. Aitäh kuulamast.

VISUAAL: kontaktid
-->
