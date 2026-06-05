# Päev 5: Hajutatud jälgimine — Zipkin, OpenTelemetry, Jaeger & Tempo, Alloy

**Kursus:** Kaasaegne IT-süsteemide monitooring ja jälgitavus
**Kestus:** ~45 minutit (loeng) + labor
**Tase:** Kesktase — eeldame, et tunned HTTP-päringuid, mikroteenuste arhitektuuri ja oled näinud Day 1 observability kolme sammast (metrics, logs, traces)

---

## 🎯 Õpiväljundid

Pärast seda loengut oskad:

- Selgitada, mis probleemi hajutatud jälgimine (distributed tracing) lahendab ja miks logid üksi ei piisa
- Kirjeldada trace'i, span'i ja context propagation'i mõisteid
- Põhjendada, miks Zipkin oli esimene ja mida B3 propagation tähendab
- Eristada OpenTelemetry rolli (standard) backend'ist (Jaeger, Tempo)
- Võrrelda Jaeger'it ja Grafana Tempo't salvestuse ja kasutuse järgi
- Selgitada, kuhu Grafana Alloy selles ahelas istub

---

## 1. Probleem, mille logid jätsid lahendamata

Day 1 nägime kolme sammast: metrics ütleb *kui palju*, logs ütleb *mis juhtus*, traces ütleb *kus*. Esimesed neli päeva tegelesime kahe esimesega — Prometheus, Zabbix, Loki, Elastic, TICK. Täna on kolmas sammas.

Kujuta ette tüüpilist 2026 arhitektuuri. Klient vajutab "Maksa" nuppu. See üks päring puudutab tegelikkuses kümneid teenuseid: API gateway → auth → kasutajaprofiil → ostukorv → hinnastamine → laoseis → maksevärav → kviitung → e-mail. Igaüks neist on eraldi konteiner, võib-olla eraldi serveris.

Nüüd läheb see päring aeglaseks — 8 sekundit. Sul on logid kõikidest teenustest. Aga logid on igaühes eraldi, oma ajatempliga, oma formaadis. Sa SSH-id ühte teenusesse, näed `INFO request handled`, lähed teise, näed `WARN slow query`. Aga **milline päring** oli aeglane? Kas see `slow query` kuulus üldse selle kliendi maksele, või kellegi teise samaaegsele päringule? Logid ei tea seda. Nad ei räägi omavahel.

```
Klient → [gateway] → [auth] → [profiil] → [ostukorv] → [hinnastamine] → [ladu] → [makse] → [e-mail]
            120ms     45ms      30ms        60ms          2400ms ⚠️       80ms     90ms      55ms
```

Distributed tracing lahendab täpselt selle: ta seob ühe päringu kõik sammud kokku ja näitab, **kus aeg kulus**. Ülal näeksid kohe, et hinnastamisteenus võttis 2,4 sekundit — sealt edasi kaevad. Üks pilk, mitte kaheksa SSH-sessiooni.

See pole teoreetiline. Üks inseneer kirjeldas 2026 märtsis, kuidas ta veetis neli tundi öösel kella 11 paiku, jälitades 30-sekundilist API-päringut, mis puudutas 12 teenust — logid ei öelnud midagi kasulikku, mõõdikud näitasid latentsust "kuskil" hinnastamise teel, aga "kuskil" ei ole tegevuskava, kui sinu valveteleon ei lõpeta värisemist.[^1]

### Trace, span ja context — kolm mõistet

Enne kui edasi läheme, kolm sõna, mida kogu ülejäänud loeng kasutab:

- **Span** — üks töölõik. "Auth-teenus kontrollis tokenit, kulus 45ms." Span'il on algus, kestus, nimi ja võib olla vanem-span.
- **Trace** — ühe päringu kõik span'id kokku, puuna. Üks `trace_id`, mille all on hierarhia: gateway on juur, tema all auth, selle all andmebaasipäring.
- **Context propagation** — see, kuidas `trace_id` liigub teenuselt teenusele. Kui gateway kutsub auth-teenust, peab ta `trace_id` kaasa andma — muidu auth loob uue trace'i ja ahel katkeb.

```
trace_id: 7f3a9b...
│
├─ span: GET /checkout          (gateway)      [████████████████] 2950ms
│   ├─ span: verify_token       (auth)         [█]                  45ms
│   ├─ span: load_cart          (ostukorv)     [██]                 60ms
│   ├─ span: calculate_price    (hinnastamine) [████████████]     2400ms ⚠️
│   │   └─ span: db_query        (postgres)     [███████████]      2350ms ⚠️
│   └─ span: charge_card        (makse)        [██]                 90ms
```

See puu ON trace. Ja `calculate_price` all olev `db_query` 2350ms — sealt sa nüüd tead, et probleem on andmebaasipäringus, mitte rakenduse loogikas. Logid poleks seda hierarhiat kunagi näidanud.

---

## 2. Teema 1 — Zipkin: kust kõik algas

Hajutatud jälgimine ei sündinud tühjale kohale. 2010. aastal avaldas Google teadusartikli **Dapper'i** kohta — nende sisemine süsteem, mis jälgis päringuid läbi tohutu mikroteenuste hulga.[^2] Dapper ise polnud kunagi avalik toode, aga artikkel pani aluse kõigele, mis järgnes.

Kaks aastat hiljem, 2012, avas Twitter lähtekoodi **Zipkinile** — esimene avatud lähtekoodiga hajutatud jälgimise projekt, otseselt Dapper'ist inspireeritud.[^3] Twitter ehitas selle, kuna nad uurisid jõudlusprobleeme, mis olid kuulsa "fail whale" taga — selle pildi, mida kasutajad nägid, kui Twitter alla läks. Nimi Zipkin tuleb türgi keelest "harpuun" — harpuun, mis tapab tõrked.[^4]

Zipkini ehitus oli lihtne ja on tänaseni õpetlik, sest kõik hilisemad süsteemid kordavad sama mustrit:

| Komponent | Roll |
|-----------|------|
| Tracer (teek rakenduses) | Loob span'e, mõõdab aega, saadab andmed |
| Collector | Võtab span'id vastu, valideerib |
| Storage | Salvestab — in-memory, MySQL, Cassandra või Elasticsearch |
| UI | Näitab trace'e puuna, otsing |

Zipkini suurim panus, mis elab tänaseni, on **B3 propagation** — formaat, kuidas trace'i context HTTP-päiseis liigub. Nimi B3 tuleb Twitteri algsest projektinimest "BigBrotherBird".[^5] Kui näed kuskil päist `X-B3-TraceId` või `X-B3-SpanId`, siis see on Zipkini pärand. Üheridaline variant näeb välja nii:

```
b3: {traceId}-{spanId}-{sampling}-{parentSpanId}
```

Kui sul on Istio service mesh, genereerib Envoy sidecar need päised automaatselt — aga sinu rakendus peab need sissetulevast päringust väljaminevasse edasi kandma, muidu näed üksikuid span'e, mitte seotud trace'e.[^6] See on praktikas hajutatud jälgimise sagedaseim viga: keegi unustas context'i edasi anda ja ahel laguneb tükkideks.

Zipkin oli pikalt ainus valik ja sai laialt kasutust. Aga tema valitsemine ei kestnud — järgmised mängijad olid ambitsioonikamad.

---

## 3. Teema 2 — OpenTelemetry: standard, mitte toode

Siin on koht, kus inimesed kõige sagedamini segadusse lähevad, nii et ütleme selgelt: **OpenTelemetry (OTel) ei ole jälgimise backend.** Sa ei "salvesta andmeid OpenTelemetrysse". OTel on standard ja tööriistakomplekt selle kohta, *kuidas* telemeetriat koguda ja edastada — ükskõik millisesse backendi.

Enne OTeli oli kaos. Igal tootel oli oma teek. Kui sa instrumenteeritsid oma rakenduse Zipkini teegiga, olid Zipkiniga abielus. Tahtsid vahetada? Kirjuta instrumenteerimine ümber. 2017 sündis kaks konkureerivat standardit — OpenTracing (CNCF) ja OpenCensus (Google) — ja lõpuks need ühinesid OpenTelemetryks.

OTelil on kolm osa, mida tasub eristada:

| Osa | Mida teeb |
|-----|-----------|
| **API** | Instrumenteerimine — span'ide loomine koodis |
| **SDK** | Andmete töötlemine ja eksport |
| **Collector** | Vendor-neutraalne proxy andmevoogudele, jõustab konventsioone (`http.method`, `db.system`) |

Praktikas tähendab see: sa instrumenteerid rakenduse **üks kord** OTeliga, ja saad andmed saata kuhu iganes — Tempo, Jaeger, Datadog, peaaegu kõik. Vendor lock-in kaob. Transport käib **OTLP** protokolli (OpenTelemetry Protocol) kaudu, mis on tänaseks de facto standard.

Üks tugevus, mida tasub teada: **auto-instrumentation**. Populaarsete raamistike puhul (Express, Flask, Spring, gRPC) saad jälgimise sisse minimaalse vaevaga — mõnikord paari minutiga, koodi puutumata. Käsitsi span'e lisad alles ärielloogika jaoks, kus auto-instrumentation ei tea, mis on oluline.

Kui aus olla, miks see kõik 2026 oluline on: Elasticu observability raport näitab, et **89% production-kasutajatest peab OpenTelemetry-vastavust kriitiliseks** vendori valikul.[^7] OTel on tänaseks teine kõige aktiivsem CNCF projekt, kohe Kubernetese järel.[^8] See pole enam "kas", vaid "kuidas". Kui ehitad täna uut jälgimist ja ei lähtu OTelist, ehitad legacy't.

```
                    ┌─────────────────────────────┐
   Rakendus ──OTel──┤  Collector  │  konventsioonid │──OTLP──┐
   (üks kord         └─────────────────────────────┘         │
    instrumenteeritud)                                       │
                                          ┌──────────────────┼──────────────┐
                                          ▼                  ▼              ▼
                                       Tempo             Jaeger         Datadog
                                    (vali backend, mitte vendor)
```

---

## 4. Teema 3 — Jaeger ja Grafana Tempo: kaks backend'i

Kui OTel kogub andmed, peab keegi need salvestama ja näitama. Kaks suurt avatud lähtekoodiga valikut on Jaeger ja Tempo.

### Jaeger — Uberi laps, nüüd OTeli peal

Uber alustas Jaegerit 2015 sisemise projektina, avas lähtekoodi 2016–2017 ja andis CNCF-ile.[^9] Nimi tuleb saksa keelest "kütt". Jaeger oli inspireeritud nii Dapper'ist kui Zipkinist ja pakkus tagasiühilduvust — Zipkini teekidega instrumenteeritud kood sai andmed otse Jaegeri backendi saata.

Tähtis 2026 fakt: **Jaeger v2 ehitati ümber OpenTelemetry Collectori raamistiku peale.**[^10] See tähendab, et Jaeger pole enam eraldiseisev asi — ta ON OTel Collector koos jälgimise-spetsiifiliste laiendustega. See on hea näide, kuidas OTel on kogu ökosüsteemi enda alla tõmmanud.

Jaeger toetab natiivselt mitut salvestust:

- **OpenSearch 1.0+** ja **Elasticsearch 7.x/8.x** — rikkalik otsing ja filtreerimine
- **Cassandra 4.0+** — optimeeritud suure kirjutusmahu jaoks

Jaegeri tugevus on **sampling** — nii head-based (otsustad päringu alguses, kas jälgid) kui tail-based (otsustad alles siis, kui trace on valmis — saad hoida ainult aeglasi või vigaseid). Tail-based on kallim, aga targem: salvestad ainult selle, mis sind huvitab.

### Tempo — Grafana vastus, object storage'i peal

Grafana Tempo läheneb teisiti. Tempo eesmärk on **odav suuremahuline salvestus**: ta paneb trace'id otse objektisalvestusse (S3, MinIO, GCS) ega vaja kallist indeksit nagu Elasticsearch. Sa otsid trace'e kas `trace_id` järgi otse, või **TraceQL** päringukeelega — see on Tempo oma keel, inspireeritud PromQL-ist ja LogQL-ist (mille Loki juures Day 2 nägime).

Tempo arendus on 2026 kiire. Versioon 2.10 (jaanuar 2026) tõi vParquet5 salvestusformaadi ja TraceQL täiendusi.[^11] Versioon 3.0 tõi uue arhitektuuri (koodnimi Project Rhythm), mis eraldab loe- ja kirjutustee teineteisest — varem võis üks halb päring mõlemad alla viia.[^12]

Tempo tugevaim müügiargument on **see, kuidas ta seob kolm sammast kokku**. Day 1 rääkisime, et observability mõte on andmete vahel liikuda. Tempoga see toimib: näed Grafanas mõõdikute graafikul latentsuse hüpet → klikid **exemplar'ile** (üks punkt graafikul, mis viitab konkreetsele trace'ile) → hüppad otse sellesse trace'i → ja sealt edasi logidesse sama `trace_id`-ga.[^13] Metric → trace → log, kolme klikiga, samas UI-s. See on terve LGTM-virna (Loki-Grafana-Tempo-Mimir) mõte.

### Kumb valida?

| | Jaeger | Tempo |
|---|--------|-------|
| Salvestus | OpenSearch / Elasticsearch / Cassandra | Objektisalvestus (S3, MinIO) |
| Indeks | Jah (kallim, rikkalik otsing) | Minimaalne (odav, `trace_id` + TraceQL) |
| Päringukeel | UI-otsing, filtrid | TraceQL |
| Tugevus | Võimas otsing, küps sampling | Odav skaala, LGTM-integratsioon |
| Vali kui | Vajad rikkalikku trace-otsingut | Oled juba Grafana ökosüsteemis |

2026 üldsoovitus uutele deploymentidele: instrumenteeri OTel SDK-ga, kogu OTel Collectoriga, salvesta Tempos või Jaegeris.[^14] Valik sõltub sellest, kas oled Grafana-maailmas (→ Tempo) või vajad sügavat otsingut (→ Jaeger).

---

## 5. Teema 4 — Grafana Alloy: kogur ahela alguses

Viimane tükk. Day 2 Loki juures mainisime, et logiagent on tänapäeval **Alloy**, mitte vana Promtail. Alloy roll hajutatud jälgimises on sama loogiline: ta on **üks agent, mis kogub kõike** — metrics, logs ja traces — ja saadab edasi õigesse backendi.

Mõtle Alloyle kui universaalsele kogurile. Varem oli sul Promtail logidele, eraldi OTel Collector trace'idele, eraldi exporter mõõdikutele. Alloy ühendab need: ta võtab vastu OTLP trace'e (täpselt sama protokoll, mida OTel SDK saadab), võib teha teel sampling'ut või rikastamist, ja edastab Tempole. Samal ajal korjab ta logisid Lokile ja mõõdikuid Prometheusele/Mimirile.

```
                  ┌─────────────────────────────────────┐
   Rakendus ─OTLP─┤              GRAFANA ALLOY            │
   (OTel SDK)     │  vastuvõtt → töötlus → marsruutimine │
                  └──┬──────────────┬──────────────┬─────┘
                     │ traces       │ logs         │ metrics
                     ▼              ▼              ▼
                   Tempo          Loki          Mimir/Prometheus
                     └──────────────┴──────────────┘
                              Grafana (üks UI)
```

Praktikas tähendab see laboris üht teenust seadistada, mitte kolme. Alloy võtab OTLP sisse, sa ütled talle kuhu trace'id saata, ja kogu LGTM-virn on koos. See on põhjus, miks me Day 5 laboris just Alloyt kasutame — see on liim, mis hoiab kolm sammast ühe konfiguratsioonifaili sees.

---

## 6. Kuhu hajutatud jälgimine 2026 liigub

Lühike pilk horisondile, sest see mõjutab, mida tööl näed:

**Trace pole enam waterfall-pilt, vaid root-cause mootor.** 2026 ei defineeri jälgimistööriistu enam nende võime järgi joonistada ilusaid diagramme, vaid võime järgi võimaldada kiiret root cause analüüsi ja automaatset trace triage'i.[^15] Vaatamine on lahendatud — nüüd on küsimus, kui kiiresti jõuad põhjuseni.

**AI-põhine trace triage tõuseb.** Dynatrace, Datadog ja teised reklaamivad AI-põhist root cause analüüsi, mis toob probleemi esile proaktiivselt.[^16] Ole siin kainest peast sysadmin: turundus lubab "automaatset põhjustuvastust", praktikas aitab see lihtsate juhtumite puhul (üks teenus selgelt aeglane), keeruliste hajutatud bug-ide puhul jääb inimene lahendajaks.

**eBPF zero-code instrumentation.** Kerneli tasandil jälgimine ilma rakenduse koodi puutumata — tõusev kõrvalsuund, eriti Kubernetese keskkonnas.

---

## 7. Kokkuvõte — mis on täna tähtis

**Trace seob ühe päringu kõik sammud kokku.** Logid ja mõõdikud üksi ei näita, kus aeg hajutatud süsteemis kulus — trace näitab.

**Trace = span'ide puu, ühe `trace_id` all.** Context propagation kannab `trace_id` teenuselt teenusele; kui see katkeb, lagunevad ka trace'id tükkideks.

**Zipkin oli esimene (2012), Dapper'ist (2010) inspireeritud.** Tema pärand elab B3 propagation päiseis (`X-B3-TraceId`).

**OpenTelemetry on standard, mitte backend.** Instrumenteeri üks kord OTeliga, saada OTLP kaudu kuhu iganes. 2026 de facto, 89% peab seda kriitiliseks.

**Jaeger vs Tempo = otsing vs odav skaala.** Jaeger (OpenSearch/Cassandra, rikkalik otsing) vs Tempo (objektisalvestus, TraceQL, LGTM-integratsioon). Jaeger v2 istub nüüd OTel Collectori peal.

**Tempo seob kolm sammast.** Metric → exemplar → trace → log, sama `trace_id`, sama UI. See on LGTM mõte.

**Alloy on üks kogur kõigele.** OTLP sisse, traces Tempole + logs Lokile + metrics Mimirile, üks konfiguratsioon.

---

## Allikad

### Ametlik dokumentatsioon
| Allikas | URL |
|---------|-----|
| OpenTelemetry docs | https://opentelemetry.io/docs/ |
| Grafana Tempo docs | https://grafana.com/docs/tempo/latest/ |
| Jaeger docs | https://www.jaegertracing.io/docs/ |
| Zipkin | https://zipkin.io/ |
| Grafana Alloy docs | https://grafana.com/docs/alloy/latest/ |
| B3 propagation spec | https://github.com/openzipkin/b3-propagation |

### Teooria ja ajalugu
| Allikas | URL |
|---------|-----|
| Google Dapper paper (2010) | https://research.google/pubs/pub36356/ |
| A History of Distributed Tracing | https://devops.com/a-history-of-distributed-tracing/ |
| Distributed Tracing, Past and Future | https://www.spectrocloud.com/blog/distributed-tracing-past-and-future |

### Praktiline ja trendid
| Allikas | URL |
|---------|-----|
| Tempo 3.0 release | https://grafana.com/blog/tempo-3-0-release-all-the-latest-features/ |
| Microservices Observability 2026 | https://dasroot.net/posts/2026/03/microservices-observability-distributed-tracing-logging-2026/ |
| OpenTelemetry & Distributed Tracing 2026 | https://www.javacodegeeks.com/2026/02/observability-beyond-monitoring-opentelemetry-and-distributed-tracing.html |

**Versioonid (testitud, juuni 2026):**
- Grafana Tempo: `grafana/tempo:3.0`
- Grafana Alloy: viimane stabiilne
- OpenTelemetry Collector: OTLP standard
- Jaeger: v2 (OTel Collectori peal)

[^1]: Odendaal, A. (2026). *Distributed Tracing with OpenTelemetry: A Complete Guide.* https://andrewodendaal.com/distributed-tracing-opentelemetry-complete-guide/
[^2]: Sigelman, B. et al. (2010). *Dapper, a Large-Scale Distributed Systems Tracing Infrastructure.* Google Research.
[^3]: DevOps.com (2022). *A History of Distributed Tracing.* https://devops.com/a-history-of-distributed-tracing/
[^4]: Apache Software Foundation. *Zipkin Proposal (INCUBATOR).* https://cwiki.apache.org/confluence/display/incubator/ZipkinProposal
[^5]: Loffay, P. (2021). *Five years evolution of open-source distributed tracing.* https://ploffay.medium.com/five-years-evolution-of-open-source-distributed-tracing-ec1c5a5dd1ac
[^6]: OneUptime (2026). *How to Integrate Zipkin with Istio for Distributed Tracing.* https://oneuptime.com/blog/post/2026-02-24-how-to-integrate-zipkin-with-istio-for-distributed-tracing/view
[^7]: Java Code Geeks (2026). *Observability Beyond Monitoring: OpenTelemetry and Distributed Tracing.* https://www.javacodegeeks.com/2026/02/observability-beyond-monitoring-opentelemetry-and-distributed-tracing.html
[^8]: daily.dev (2026). *Observability for Developers: OpenTelemetry, Distributed Tracing, and Modern Monitoring.* https://daily.dev/blog/observability-developers-opentelemetry-distributed-tracing-monitoring
[^9]: Spectro Cloud (2023). *Distributed Tracing, a Survey of Past and Future.* https://www.spectrocloud.com/blog/distributed-tracing-past-and-future
[^10]: Techjockey (2026). *Best 9 Distributed Tracing tools.* https://www.techjockey.com/blog/top-distributed-tracing-tools
[^11]: Grafana Labs (2026). *Tempo 2.10 release.* https://grafana.com/blog/tempo-2-10-release-all-the-latest-features/
[^12]: Grafana Labs (2026). *Tempo 3.0 release.* https://grafana.com/blog/tempo-3-0-release-all-the-latest-features/
[^13]: daily.dev (2026). *Observability for Developers.* https://daily.dev/blog/observability-developers-opentelemetry-distributed-tracing-monitoring
[^14]: Odendaal, A. (2026). *Distributed Tracing with OpenTelemetry: A Complete Guide.*
[^15]: dasroot.net (2026). *Microservices Observability: Distributed Tracing and Logging in 2026.* https://dasroot.net/posts/2026/03/microservices-observability-distributed-tracing-logging-2026/
[^16]: Techjockey (2026). *Best 9 Distributed Tracing tools.*

---

*Järgmine: Day 5 labor — Alloy + Tempo + OTel demo rakendusega, trace puu Grafanas, exemplar metric → trace → log.*
