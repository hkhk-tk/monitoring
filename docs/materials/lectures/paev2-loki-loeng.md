# Päev 2: Grafana LGTM stack ja Loki

**Kestus:** ~45 minutit iseseisvat lugemist  
**Eeldused:** [Päev 2: Zabbix](paev2-loeng.md) loetud, Prometheus ja Grafana põhitõed ([Päev 1](paev1-loeng.md))  
**Versioonid laboris:** Loki 3.7.1, Grafana 12.4.3, Alloy 1.15.1  
**Viited:** [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/) · [Grafana Alloy](https://grafana.com/docs/alloy/latest/) · [LogQL](https://grafana.com/docs/loki/latest/query/)

!!! abstract "TL;DR (kui sul on 5 minutit)"
    **5 asja, mis tasub päriselt meelde jätta:**

    - **LGTM = Logs (Loki) + Grafana + Traces (Tempo) + Metrics (Mimir)** — sama meeskonna 4 tööriista, tugevus integratsioonis.
    - **Loki indekseerib ainult silte, mitte logi sisu** — salvestus S3-l, 35–50% odavam kui ELK.
    - **Kardinaalsus on vaenlane** — ära kunagi pane trace_id'd, user_id'd ega IP-d sildiks. Kasuta Structured Metadata'd (Loki 3.0+).
    - **Monolithic ≤20 GB/päevas, Microservices 1 TB+.** SSD režiim on aegumas — ära alusta sellega.
    - **Agent: Alloy, mitte Promtail.** Helm-chart: `grafana/loki`, mitte `loki-stack` ega `loki-distributed`.

---

## Õpiväljundid

Pärast selle materjali läbitöötamist osaleja:

1. **Selgitab** LGTM-pinu komponentide rolli ja korrelatsiooni kolmikut (mõõdik → logi → jälg)
2. **Kirjeldab** Loki põhifilosoofiat — miks indekseeritakse ainult sildid, mitte sisu
3. **Mõistab** kardinaalsuse mõju jõudlusele ja oskab hoida silte madala kardinaalsusega
4. **Eristab** Loki paigaldusrežiime (Monolithic, Microservices) ja teab, milline on tänaseks soovitatud
5. **Nimetab** Loki peamised komponendid kirjutus- ja lugemisteel
6. **Põhjendab**, millal valida Loki ja millal ELK Stack
7. **Loeb** põhilisi LogQL päringuid ja eristab nelja parserit (pattern, json, logfmt, regexp)

---

## 1. Kust me pooleli jäime

Hommikul rääkisime Zabbixist — IT-maastiku vanast tööhobusest, mis on olnud tootmises 25+ aastat. Zabbix on arhitektuuriliselt monoliit: üks server, üks andmebaas, kõik ühes kastis. Töötab hästi **seadmete ja nende oleku** jälgimiseks.

Aga pilvepõhises maailmas — Kubernetes, mikroteenused, efemeersed konteinerid — see mudel murdub. Kui su pod elab 30 sekundit ja paiskab sel ajal välja 50 MB logisid, on vaja teistsugust lähenemist.

Päev 1-s nägime ka Grafanat, aga ainult kui **visualiseerimiskihti** — tööriista, mis küsib andmeid Prometheuselt ja joonistab graafikuid. Mainisin akronüümi **LGTM** ainult möödaminnes. Pärastlõunal kaevume sügavamale ja ehitame laboris selle pere logihaldustööriista — **Loki**.

---

## 2. LGTM-pinu — mis see on

**LGTM** tähistab neli Grafana Labsi projekti:

```text
L — Loki    — logid
G — Grafana — visualiseerimine ja UI (juba tuttav)
T — Tempo   — jäljed (traces), hajutatud jälgimine  → Päev 5
M — Mimir   — meetrikad, mastaapne Prometheus-ühilduv TSDB
```

Need neli on sama meeskonna toode sama filosoofiaga: **indekseeri vähem, salvesta odavalt, skaleeri horisontaalselt**. Tugevus tuleb integratsioonist — sellepärast ongi akronüüm "pinu", mitte "neli tööriista".

### 2.1 Korrelatsiooni kolmik — miks LGTM on rohkem kui neli tööriista

Klassikaline tõrkeotsing traditsioonilises infras käib nii: Zabbix näitab CPU 100%, SSH-id masinasse, teed `tail -f /var/log/...`, leiad veateateid aga ei tea, kas need on põhjus või tagajärg, helistad arendajale, tema otsib trace-ID'd eraldi logiaggregaatorist. Tund hiljem saad aru, mis juhtus.

LGTM-pinu lubab teistsugust töövoogu:

1. **Grafana** — vaatad dashboardi, näed anomaaliat mõõdikute graafikul (Mimir/Prometheus)
2. **Klõpsad ajavahemikul** → hüppad samasse aega **logidesse** (Loki) — näed veateadet koos trace-ID-ga
3. **Klõpsad trace-ID-l** → avaneb **jälituse vaade** (Tempo) — näed, millises mikroteenuses päring seiskus

Kõik ühes UI-s, ilma tabivahetuseta. **MTTR** (mean time to recovery) langeb oluliselt, sest sa ei pea kolmel tööriistal vahet tegema. See on LGTM-pinu päris väärtus — üksikud komponendid on vaid pooled sellest loost.

### 2.2 Mis on iga komponendi töö

**Loki** on logide salvestus ja otsing. Indekseerib ainult silte, mitte sisu. Salvestab S3-sse. **Täna põhiteema.**

**Grafana** on UI ja päringukeskus. Päev 1-st mäletad — ta ei salvesta ise andmeid, vaid kogub neid datasource'idest. LGTM-kontekstis on ta **ainus koht, kust kasutaja midagi näeb**.

**Tempo** on jälitussüsteem. Kui sinu süsteem on 20 mikroteenust, mis räägivad omavahel, võib üks kasutaja-päring käia läbi 15 teenuse. Tempo salvestab selle tee. Filosoofia sama nagu Lokil — ei indekseeri sisu, ainult trace-ID-d. **Päev 5.**

**Mimir** on "Prometheus steroididega". Üks Mimir-klaster hallab miljardeid aktiivseid aegridu, samas kui üksik Prometheus jookseb mõne miljoni peal kokku. Täielikult Prometheuse API-ühilduv — kõik PromQL-päringud töötavad edasi. Enterprise-keskkonnad, kes skaleerivad Prometheust üle mitme klastri, kasutavad Mimirit.

Iga neli saab kasutada **eraldi** — sa võid võtta ainult Loki ja jätta Prometheuse. Või võtta ainult Tempo OpenTelemetry-stack'i. Aga nende tugevus on **perekonnana**.

### 2.3 Self-hosted vs Grafana Cloud

Üks otsus, mida iga sysadmin peab kunagi tegema.

**Self-hosted** (ise Kubernetes-klastris):
- ✅ Andmed jäävad sinu infrastruktuuri (GDPR, tundlik info)
- ✅ Kulu kontrolli all — maksad infrastruktuuri eest
- ✅ Täielik paindlikkus
- ❌ Operatiivne vastutus on sinul
- ❌ Vajab kompetentsi (Kubernetes, Helm, storage, networking)

**Grafana Cloud** (hallatud):
- ✅ Paigaldus minutites, mitte nädalates
- ✅ Grafana Labs vastutab uptime'i eest
- ❌ Andmed nende pilves
- ❌ Kulu põhineb mahul — võib kiirelt kasvada

Eestis kohtad mõlemat. Bolt, Wise on enamasti self-hosted, kuna mastaap on suur. Väiksemad iduettevõtted lähevad sageli Grafana Cloud'iga ("lihtsalt töötab"). **Laboris täna on self-hosted** (Docker Compose), sest see annab arusaamise sellest, mis kapoti all toimub.

### 2.4 Üks oluline otsus tuleviku pärast — OpenTelemetry

**OpenTelemetry (OTel)** on CNCF-i standard, mis defineerib universaalse viisi, kuidas rakendused saadavad logisid, meetrikaid ja jälgi. Põhimõte: instrumenteerid rakenduse OTel-iga, kogutud andmed saad saata **ükskõik kuhu** — Datadog'i, New Relic'usse, Grafana Cloud'i, Lokisse.

Grafana Labs tegi targa valiku — nende uus agent **Grafana Alloy** (§10) toetab OTel-i natiivselt. Kui valid täna Grafana Cloud'i, aga aasta pärast otsustad migreerida self-hosted'ile või Datadog'ile, sa ei pea rakendusi muutma — ainult kollektori sihtpunkti.

**Sysadminina tähendab see:** vali alati OTel-ühilduv tööriist, kui valida on. See on kindlustuspoliis tuleviku vastu.

---

## 3. Loki — "Prometheus logide jaoks"

2018. aastal KubeConis, San Franciscos, tutvustab Tom Wilkie (Grafana Labs CTO) uut projekti. Tema kirjeldus jääb ajalukku:

> *"Loki: like Prometheus, but for logs."*

See pole turundushüüdlause — see on arhitektuuriline avaldus.

**Prometheus** kogub iga sihtmärgi kohta mõõdikuid, mis on määratletud **siltidega** (`job="api"`, `env="prod"`). Sildid on indekseeritud, väärtused on aegread.

**Loki** kogub iga allika kohta logiridu, mis on määratletud samasuguste **siltidega** (`app="nginx"`, `namespace="prod"`). Sildid on indekseeritud, logi sisu on lihtsalt tekst, kokku pakitud, objektisalvestuses.

Ehk — **Loki ei indekseeri midagi sellest, mis logireal sees on**. Ei kasutajanime, ei IP-d, ei veateksti. Ainult silte.

---

## 4. Miks indekseeritakse ainult silte

Traditsiooniline lähenemine (Elasticsearch, Splunk) töötab nii: tuleb logirida sisse → tõkestatud sõnadeks → iga sõna lisatakse pöördindeksisse → indeks kasvab hiiglaslikuks → hoitakse SSD-l → vajab palju RAM-i.

Kui sul on 10 TB logisid päevas, on Elasticsearchi indeks **15 TB** — suurem kui andmed ise.

Loki lähenemine:

```text
Logirida tuleb sisse
   ↓
Eraldatakse sildid: {app="nginx", env="prod"}
   ↓
Sildid lähevad indeksisse (väike — megabaidid, mitte terabaidid)
   ↓
Logi sisu pakitakse tükiks (~1 MB)
   ↓
Tükk salvestub S3-sse (~0.01 €/GB/kuus)
```

Salvestuskulu S3-s vs. kiire SSD klaster: erinevus on umbes **20×**. Meeskonnad, kes on ELK-lt Lokile üle läinud, raporteerivad logihalduse kulude langust **35–50%**. See pole väike number, kui monitoorimiseks on eelarvest 6-kohaline summa.

Aga kuidas sa siis otsid? Kui logi sisu pole indekseeritud, kuidas leiad "error"-rida?

Loki leiab päringu ajal kõigepealt **siltide järgi** õiged logivood (`{app="nginx"}`). Siis avab ta nende voogude tükid (mitte kogu logi) ja skannib neid paralleelselt — sama põhimõte nagu `grep`. Kuna tükke loetakse paralleelselt kümnetest querier-itest, on see kiire.

**Tingimus:** pead teadma siltide põhjal, kust otsida. Kui ütled Lokile "otsi 10 TB andmestikust sõna 'timeout'", ta ei rõõmusta. **Operatiivse silumise jaoks** (tead millise rakenduse logid) on see ideaalne. **Üldine forensika** ("otsi kõigest sõna X") paneb Loki kannatama — selleks on ELK parem.

---

## 5. Sildid ja logivood — arhitektuuri süda

Kui on üks kontseptsioon, mida peab Loki juures õigesti mõistma, siis on see see.

**Logivoog** (log stream) on logiridade rühm, millel on täpselt sama komplekt silte. Iga kord, kui mõni silt erineb, tekib **uus voog**.

```text
{app="frontend", env="dev"}   → voog #1
{app="frontend", env="prod"}  → voog #2
{app="backend",  env="prod"}  → voog #3
```

Iga voog on Loki jaoks eraldi üksus. Ta kirjutab neid eraldi, pakib eraldi, salvestab eraldi. See toimib, kui voogusid on mõistlikult palju. Miljonite puhul hakkab süsteem kiduma.

### Kuldreegel nr 1 — sildid on piiratud hulgast

Kõik sildid peavad olema **piiratud väärtuste hulgast** — ette teada ja väike.

| Sildi tüüp | Näide | Unikaalseid väärtusi | Sildiks? |
|------------|-------|---------------------|----------|
| Keskkond | `env=dev/staging/prod` | 3 | ✅ jah |
| Klaster | `cluster=eu-west/us-east` | 5–10 | ✅ jah |
| Rakendus | `app=nginx/api/db/...` | ~20 | ✅ jah |
| Logitase | `level=info/warn/error` | 3–5 | ⚠️ sõltub |
| IP-aadress | `src_ip=1.2.3.4` | **∞** | ❌ **EI KUNAGI** |
| Kasutaja ID | `user_id=12345` | **∞** | ❌ **EI KUNAGI** |
| Trace ID | `trace_id=abc123...` | **∞** | ❌ **EI KUNAGI** |

Kui paned IP-aadressi sildiks, tekitab iga unikaalne IP uue voo. 10 000 kasutajat → 10 000 voogu. 100 000 → 100 000. Indeks paisub, Loki aeglustub.

---

## 6. Kardinaalsus — Loki tähtsaim piirang

**Kardinaalsus** = unikaalsete sildikombinatsioonide arv. See on number, mida Loki administraator peab teadma ja jälgima.

Meenuta §5-st — iga voog salvestatakse eraldi tükkideks. Ideaalne tüki suurus on ~1 MB pakitult. Kui tükk täitub, kirjutab Loki selle S3-sse.

Mis juhtub, kui sul on 10 000 voogu, millest igaüks toodab vaid mõne kilobaidi logisid tunnis?

```text
10 000 voogu × 10 KB/tund → 100 MB/tund
                         → aga 10 000 väikest tükki!
```

Iga tükk on eraldi fail S3-s. Iga päring, mis peab neid puudutama, teeb 10 000 HTTP-kutset. Süsteem muutub aeglaseks fragmenteerituse tõttu, **isegi kui andmete maht on tagasihoidlik**.

**Praktilised piirid:**

| Logide maht päevas | Mõistlik voogude arv | Hoiatuslävi |
|--------------------|---------------------|-------------|
| <100 GB | kuni 10 000 | 20 000 |
| 1 TB | kuni 10 000 | 50 000 |
| 10 TB+ | kuni 100 000 | 200 000 |

**Kuldreegel nr 2:** sildid on 5–8 voo kohta, tehniline piirang on 15. Iga lisasilt mitmekordistab potentsiaalselt voogude arvu.

---

## 7. Structured Metadata — Loki 3.0 vastus probleemile

"Aga mina tahan trace_id järgi otsida!" võib öelda arendaja. "Muidu pole kogu OpenTelemetry mõtet."

Kuni Loki 2.x-ni oli vastus: kasuta **filtrit, mitte silti**:

```logql
{app="api"} |= "trace_id=abc123"
```

See töötab, aga on aeglane — peab sisu skannima.

**Loki 3.0** (aprill 2024) tõi lahenduseks **Structured Metadata**. See on kolmas kategooria metaandmeid, mis elab **logirea kõrval, mitte indeksis**:

```text
┌─────────────────────────────────────────────────────────┐
│ INDEKS (sildid)                                         │
│ {app="api", env="prod"}                                 │
├─────────────────────────────────────────────────────────┤
│ STRUCTURED METADATA (kiire ligipääs, EI indekseerita)   │
│ trace_id=abc123, user_id=42, request_id=xyz             │
├─────────────────────────────────────────────────────────┤
│ LOGIREA SISU (pakitud, objektisalvestuses)              │
│ "2026-04-25 10:23:41 ERROR Payment failed: timeout"     │
└─────────────────────────────────────────────────────────┘
```

Structured Metadata on **otsitav ja kiire**, aga ei kasva indeksis. See tähendab: **kõrge kardinaalsusega andmed** (trace_id, user_id, request_id) lähevad nüüd siia, mitte siltidesse. Kardinaalsuse plahvatuse oht kaob.

**Kui kavandad Loki juurutust 2026. aastal — ära kunagi pane trace_id'd sildiks. Pane Structured Metadatasse.**

---

## 8. Paigaldusrežiimid

Loki saab paigaldada kolmel viisil. Üks neist on aegumas.

### Monolithic — kõik ühes protsessis

```text
┌──────────────────────────┐
│   Loki (üks binaarfail)  │
│  ┌────┐ ┌────┐ ┌──────┐ │
│  │Dist│ │Ingr│ │Query │ │
│  └────┘ └────┘ └──────┘ │
└──────────┬───────────────┘
           ▼
        ┌─────┐
        │ S3  │
        └─────┘
```

Üks protsess, kõik komponendid sees. Lihtne käivitada — üks Docker Compose, üks Helm-chart. **Sobib kuni 20 GB päevas** — väike-keskmine keskkond, arendus, testimine, koolitusruum.

**Meie laboris täna on just see.**

### Simple Scalable Deployment (SSD) — aegumas

Jagas töö kolmeks rolliks: `read`, `write`, `backend`. Oli vahepealne — suurem kui Monolithic, lihtsam kui täielik Microservices. Sobis keskkondadele kuni 1 TB päevas.

**2025. märts — Grafana Labs teatas** (David Allen): *"SSD režiimi keerukuse ja kasu suhe pole enam paigas. Uutel kasutajatel ei soovitata SSD-ga alustada."*

Ametlikult **eemaldatakse enne Loki 4.0**. Kui kohtad seda dokumentatsioonis või vanemas tutorialis — **hoia eemale**. Alusta Monolithicuga, kasva Microservices-iks.

### Microservices — tootmiskeskkonna standard

Iga komponent eraldi Kubernetes-deployment. Iga komponenti saab eraldi skaleerida — kirjutamiskoormus kasvab → lisad Ingestereid; päringuid tuleb rohkem → lisad Querier-eid.

Toetab **tsooniteadlikku replikatsiooni** — ingesterid jaotatakse eri Kubernetes-tsoonidesse, kui terve tsoon kukub, süsteem toimib edasi. Tootmiskriitilise süsteemi nõue.

**Soovitatud 1 TB+ päevas** või mujal, kus käideldavus on kriitiline.

---

## 9. Komponendid sügavamalt

Mikroteenuste režiimis näed kõiki komponente. Aga ka Monolithic-režiimis töötavad nad sama loogikaga — lihtsalt ühe protsessi sees.

### Kirjutustee

```text
Agent (Alloy) → Gateway (NGINX) → Distributor → Ingester → S3
```

**Distributor** on värav. Võtab vastu, valideerib, teeb rate limiting'ut, kontrollib tenant'it. Seejärel räsib logi sildid ja suunab õigele Ingesterile.

**Ingester** on süsteemi süda. Puhverdab logid mälus, pakib neid tükkidena kokku, replikeerib teistele Ingesteritele (tavaliselt 3 koopiat). Kui tükk saab valmis (~1 MB või aeg möödas), kirjutab selle S3-sse.

### Lugemistee

```text
Grafana → Gateway → Query Frontend → Query Scheduler → Querier → {Ingester RAM, S3}
```

**Query Frontend** tükeldab päringud — kui küsid viimase 24h andmeid, jagatakse 24-ks tunni-päringuks, mis käivad paralleelselt.

**Query Scheduler** haldab järjekorda — õiglane planeerimine, üks kasutaja ei saa süsteemi endale võtta.

**Querier** teeb tegeliku töö. Küsib andmeid nii Ingesteritest (viimased andmed veel mälus) kui S3-st (vanemad tükid), teeb deduplikatsiooni (sest tükid on replikeeritud), täidab LogQL päringu.

### Taustaprotsessid

**Compactor** — käib regulaarselt üle: liidab väiksed tükid suurteks, optimeerib indeksit, kustutab vanu andmeid säilituspoliitika järgi. Ilma selleta paisuks S3 täis killustatud faile.

**Ruler** — täidab alerti- ja recording-reegleid (nagu Prometheuses). Siin saad kirjutada: *"kui viimase 5 minuti jooksul on rohkem kui 100 level=error rida → saada hoiatus."*

---

## 10. Agent — Promtail on läinud, tule Alloy

Kuni 2024 oli Loki standardagent **Promtail** — lihtne binaar, mis lõi logifailid üles ja saatis Lokile. Aastaid lihtsalt-toimiv lahendus.

2024 teatas Grafana Labs, et **Promtail liigub feature-freeze olekusse** ja soovitatud on **Grafana Alloy**. Alloy on universaalne telemeetria-kollektor — üks agent kogub logisid, meetrikaid, jälgi. Põhineb OpenTelemetry Collectori komponentidel, pakub Grafana maailmas testitud konfiguratsiooni.

**Kui ehitad täna uut süsteemi — kasuta Alloy.** Kui sul on vana Promtail-deployment — töötab edasi, aga planeeri migratsiooni.

Laboris kasutame Alloy'd. Kerge (~30 MB RAM), konfiguratsioon sarnane HCL-ile (Terraformi tuttav süntaks).

---

## 11. HOIATUS — Helm-chart'ide džungel

Kui Google'ist otsid *"loki helm chart"*, leiad **kolm** erinevat nime. **Ainult üks on elus.**

| Chart | Staatus | Kasuta? |
|-------|---------|---------|
| `grafana/loki` | ✅ Ametlik, aktiivne, toetab Loki 3.0+ | **Jah — AINUS valik** |
| `grafana/loki-stack` | ⚠️ Deprecated | **Ei** |
| `grafana/loki-distributed` | ⚠️ Hooldamata, seisab 2.9.0 peal | **Ei** |

**Eriline hoiatus:** kui kasutad `values.yaml` genereerimiseks LLM-e (ChatGPT, Claude) — **kontrolli kriitiliselt**. Mudelite treeningandmed sisaldavad vanu tutoriale ja nad pakuvad sageli `loki-stack`-i näidiseid. Need ei tööta Loki 3.0+ maailmas.

---

## 12. LogQL — päringukeel lühidalt

LogQL on PromQL-i vend. Kui PromQL oskad, saad LogQL-iga 15 minutiga hakkama.

**Baaspäring — voo valik:**

```logql
{app="nginx", env="prod"}
```

Tagastab kõik sellise siltide komplektiga logiread.

**Tekstifilter — grep-stiil:**

```logql
{app="nginx"} |= "error"        # sisaldab "error"
{app="nginx"} != "healthcheck"  # EI sisalda
{app="nginx"} |~ "5[0-9]{2}"    # regex — HTTP 5xx koodid
```

**Parsimine (4 parserit):**

```logql
{app="nginx"} | json | status_code >= 500
{app="api"}   | logfmt | level = "error"
{app="java"}  | pattern `<_> [<level>] <_>` | level = "ERROR"
{app="legacy"} | regexp `level=(?P<lvl>\w+)` | lvl = "ERROR"
```

Neli parserit erinevateks logiformaatideks. Tänane laborilabor keskendub `pattern`-ile (vabatekst) ja `json`-ile. Valik:

| Logi välja näeb välja nagu | Parser |
|----------------------------|--------|
| `{"level":"error","user":"ann"}` | `json` |
| `level=error user=ann duration=42ms` | `logfmt` |
| `2026-04-25 10:23 ERROR user=ann` (vabatekst, stabiilne struktuur) | `pattern` |
| Täiesti ebastandardne | `regexp` |

**Meetrikud LogQL-ist** — siin läheb huvitavaks:

```logql
# Veaolukordade arv sekundis
rate({app="nginx"} |= "error" [5m])

# Viis suurimat 5xx-allikat viimase tunni jooksul
topk(5, sum by (app) (rate({env="prod"} |~ "5[0-9]{2}" [1h])))
```

Jah — logidest saab teha meetrikuid PromQL-sarnase süntaksiga. **Laboris käsitleme seda praktikas** (§3.4 `rate()` — logist metrika).

---

## 13. Loki vs ELK — millal kumba valida

Ei ole õiget ja valet tööriista. On sobiv ja sobimatu kontekstis.

| Kriteerium | Loki | ELK Stack |
|------------|------|-----------|
| Indekseerib | Ainult silte (~1% mahust) | Kogu teksti (~150% mahust) |
| Salvestuskulu | S3 — odav | SSD — kallis |
| RAM-vajadus | Madal | Kõrge |
| Täistekstiotsing | Aeglane (grep tükkidest) | Kiire (indeks olemas) |
| Operatiivne silumine | Ideaalne | Ülitugev |
| Ad-hoc forensika | Piiratud | Ülitugev |
| Turvaanalüüs | Alajääb | Domineerib (ES-SIEM) |
| Kubernetes-integratsioon | Natiivne | Töötab, vajab häälestust |
| TCO | **35–50% odavam** | Kallim |

**Vali Loki, kui:**

- Sul on juba Grafana ja/või Prometheus kasutuses — integratsioon sujuv
- Peamine kasutusviis on **operatiivne silumine** (tean rakendust, otsin põhjust)
- Eelarve on piiratud ja logihulk kasvab
- Kubernetes-keskkond — Loki on sinna sündinud

**Vali ELK, kui:**

- Teed **turvaforensikat** — vaja otsida suvalisi mustreid kogu andmekogus
- **Süvaanalüüs** on peamine — agregatsioonid, keerukad päringud
- Vajad **mitte-tehnilist UI-d** (Kibana on logide jaoks parem kui Grafana)
- Compliance nõuab täisteksti indekseerimist

Paljudes ettevõtetes leiab **mõlemad paralleelselt** — Loki igapäevaseks operatiivseks tööks, ELK turvatiimile. Täiesti mõistlik lähenemine.

---

## 14. Kokkuvõte

Enne laborisse minekut jäta meelde viis asja:

1. **LGTM = Loki + Grafana + Tempo + Mimir** — sama meeskond, sama filosoofia, tugevus integratsioonis (korrelatsiooni kolmik).

2. **Loki indekseerib ainult silte.** Logi sisu läheb objektisalvestusse. See on disainiotsus sügavate tagajärgedega — 35–50% odavam, aga täisteksti forensika on nõrgem.

3. **Kardinaalsus on vaenlane.** Ära kunagi pane trace_id'd, user_id'd ega IP-d sildiks. **Structured Metadata** (Loki 3.0+) on õige koht kõrge kardinaalsusega andmetele.

4. **Paigaldusrežiimid:** Monolithic ≤20 GB/päevas, Microservices 1 TB+. **SSD on suremas** — ära alusta sellega.

5. **Agent: Alloy, mitte Promtail. Helm-chart: `grafana/loki`, mitte `loki-stack`.**

Loki on noor ja areneb kiiresti — Bloom-filtrid (Loki 3.0), Structured Metadata, Alloy asendab Promtail'i. See, mis on täna "best practice", võib aastaga muutuda. **Ametlikud docs >> blogid >> LLM-ide vastused.**

**Järgmine samm:** [Labor: Loki](../../labs/02_zabbix_loki/loki_lab.md) — ehitame Loki + Alloy + Grafana stacki, teeme LogQL päringuid ja seome kokku Zabbix labori tulemustega.

---

## Enesekontrolli küsimused

<details>
<summary><strong>Küsimused + vastused (peida/ava)</strong></summary>

1. Kui Loki ei indekseeri logi sisu, kuidas ta siis "error"-rea leiab? Milline on sellise päringu jõudluse piirang?
2. Selgita, miks `trace_id` ei tohi olla Loki silt. Mis juhtub, kui sa ta siiski sildiks paned?
3. Mis on erinevus Structured Metadata ja siltide vahel? Millal kumba kasutada?
4. Sul on uus juurutus: ~50 GB logisid päevas, üks meeskond, Kubernetes. Millise paigaldusrežiimi valid?
5. Miks on SSD paigaldusrežiim aegumas?
6. Kirjuta LogQL päring: Nginx 5xx-vigade määr sekundis viimase 5 minuti jooksul, rakenduse järgi grupeeritud.
7. Millal eelistad Loki, millal ELK? Nimeta kaks konkreetset stsenaariumi kummagi jaoks.

??? note "Vastused (peida/ava)"
    1) Loki leiab "error"-rea kas täisteksti filtriga (`|= "error"`) või parseri + filtri abil. **Piirang:** kui filtreerid ainult sisu järgi, peab Loki rohkem andmeid skaneerima (aeglasem kui indeksipõhine label-filter). Seepärast pead alati esmalt kitsendama siltidega.

    2) `trace_id` on kõrge kardinaalsusega — peaaegu iga rea kohta unikaalne. Kui paned sildiks, tekib "stream explosion" — indeks paisub, päringud aeglustuvad, Loki hakkab uusi logisid tagasi lükkama. Kasuta **Structured Metadata'd** (Loki 3.0+).

    3) **Sildid** on indekseeritud, peavad olema madala kardinaalsusega, kasutatakse voogude valikuks. **Structured Metadata** on otsitav aga EI indekseeritud, sobib kõrge kardinaalsusega detailiks (trace_id, user_id). Sildid = dimensioonid, metadata = detailid.

    4) ~50 GB/päev, üks meeskond, K8s: **Monolithic** on piiripealne (~20 GB soovitus), aga 50 GB juures sobib ka Monolithic kui kasv on piiratud. Kui kasv ootuspärane, kavanda kohe Microservices Helm-chart'iga (`grafana/loki`).

    5) SSD režiimi keerukus vs kasu pole enam paigas — Monolithic on lihtsam alustamiseks, Microservices skaleerib paremini. SSD vahepealne roll pole enam õigustatud. Grafana Labs soovitab otse ühelt teisele.

    6) 
       ```logql
       sum by (app) (
         rate(
           {job="nginx"}
             | pattern `<_> <_> <_> <_> <_> <status> <_>`
             | status =~ "5.."
             [5m]
         )
       )
       ```

    7) **Loki:** operatiivne debug (tean rakendust, otsin põhjust), odavam logikiht, Grafana-integratsioon, Kubernetes. **ELK:** täisteksti/forensika, keerukamad otsingud, turvatiimi workflow, compliance mis nõuab täisteksti indekseerimist.

</details>

---

## Allikad

??? note "Allikad (peida/ava)"
    **Ametlik dokumentatsioon**

    | Allikas | URL |
    |---------|-----|
    | Grafana Loki dokumentatsioon | https://grafana.com/docs/loki/latest/ |
    | Loki arhitektuur | https://grafana.com/docs/loki/latest/get-started/architecture/ |
    | Loki paigaldusrežiimid | https://grafana.com/docs/loki/latest/get-started/deployment-modes/ |
    | LogQL | https://grafana.com/docs/loki/latest/query/ |
    | Siltide parimad tavad | https://grafana.com/docs/loki/latest/get-started/labels/ |
    | Structured Metadata | https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/ |
    | Grafana Alloy | https://grafana.com/docs/alloy/latest/ |
    | Helm chart (ametlik) | https://github.com/grafana/loki/tree/main/production/helm/loki |

    **Teooria ja kontekst**

    | Allikas | URL |
    |---------|-----|
    | KubeCon 2018 Loki tutvustus (Tom Wilkie) | https://www.youtube.com/results?search_query=loki+tom+wilkie+kubecon+2018 |
    | Grafana Labs blog — Loki 3.0 | https://grafana.com/blog/2024/04/09/grafana-loki-3.0-release/ |
    | "How we designed Loki" (Tom Wilkie) | https://grafana.com/blog/2018/12/12/loki-prometheus-inspired-open-source-logging-for-cloud-natives/ |
    | Promtail → Alloy migratsioon | https://grafana.com/docs/alloy/latest/tasks/migrate/from-promtail/ |

    **Praktiline**

    | Allikas | URL |
    |---------|-----|
    | LGTM demo (Docker Compose) | https://github.com/grafana/intro-to-mltp |
    | Loki Canary | https://grafana.com/docs/loki/latest/operations/loki-canary/ |

    **Versioonid (testitud, aprill 2026):**

    - Loki: `grafana/loki:3.7.1`
    - Grafana: `grafana/grafana:12.4.3`
    - Alloy: `grafana/alloy:v1.15.1`

---

*Järgmine: [Labor: Loki](../../labs/02_zabbix_loki/loki_lab.md) — ehitame Loki + Alloy + Grafana stacki ja teeme LogQL-i päringuid.*

--8<-- "_snippets/abbr.md"
