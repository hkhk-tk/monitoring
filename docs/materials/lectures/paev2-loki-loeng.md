# Päev 2: Grafana LGTM stack ja Loki

**Kestus:** ~45 minutit iseseisvat lugemist  
**Eeldused:** [Päev 2: Zabbix](paev2-loeng.md) loetud, Prometheus ja Grafana põhitõed ([Päev 1](paev1-loeng.md))  
**Versioonid laboris:** Loki 3.3.0, Grafana 11.4.0, Alloy 1.5.0  
**Viited:** [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/) · [Grafana Alloy](https://grafana.com/docs/alloy/latest/) · [LogQL](https://grafana.com/docs/loki/latest/query/)

---

## Õpiväljundid

Pärast selle materjali läbitöötamist osaleja:

1. **Selgitab**, kuidas Grafana on arenenud visualiseerimistööriistast täielikuks vaadeldavuse platvormiks (LGTM)
2. **Kirjeldab** Loki põhifilosoofiat — miks indekseeritakse ainult sildid, mitte sisu
3. **Eristab** Loki paigaldusrežiime (Monolithic, SSD, Microservices) ja teab, milline on tänaseks soovitatud
4. **Mõistab** kardinaalsuse mõistet ja mõju Loki jõudlusele
5. **Nimetab** Loki peamised komponendid kirjutus- ja lugemisteel
6. **Põhjendab**, millal valida Loki ja millal ELK Stack
7. **Loeb** põhilisi LogQL päringuid ja eristab nelja parserit (pattern, json, logfmt, regexp)

---

## 1. Kust me pooleli jäime

Hommikul rääkisime Zabbixist — vanast heast tööhobusest, mis on olnud IT-maastikul ligi 25 aastat. Zabbix on monoliit: üks server, üks andmebaas, kõik ühes kastis. Töötab hästi seadmete ja nende oleku jälgimiseks.

Esimesel päeval nägime ka Grafanat, aga ainult kui "visualiseerimiskihti" — tööriistana, mis küsib andmeid Prometheuselt ja joonistab graafikuid. Mainisin põgusalt akronüümi **LGTM**: neli Grafana Labs'i projekti, mis moodustavad terve vaadeldavuse platvormi. Pärastlõunal kaevume sellest sügavamale ja ehitame töösse selle pere logihaldustööriista — **Loki**.

Miks see oluline on? Sest pilvepõhises maailmas — Kubernetes, mikroteenused, efemeersed konteinerid — Zabbixi monoliitne mudel murdub. Kui su pod elab 30 sekundit ja surub sel ajal välja 50 MB logisid, on vaja teistsugust süsteemi. Loki on ehitatud just selleks olukorraks.

---

## 2. LGTM-pinu — kogu perekond

Päev 1 loengus mainisin akronüümi möödaminnes. Paneme kirja, mis see täpselt tähendab:

```
L — Loki    — logid
G — Grafana — visualiseerimine ja UI (juba tuttav)
T — Tempo   — jäljed (traces), hajutatud jälgimine  → Päev 5
M — Mimir   — meetrikad, mastaapne Prometheus-ühilduv TSDB
```

Need neli on ehitanud sama meeskond (Grafana Labs, eesotsas CTO Tom Wilkie'ga) sama filosoofiaga: indekseeri vähem, salvesta odavalt, skaleeri horisontaalselt. Nende tugevus tuleb integratsioonist — sellepärast ongi akronüüm "pinu", mitte "neli tööriista".

### 2.1 Unified Observability — korrelatsiooni lugu

Meenuta päev 1 stsenaariumi: kell 18:00, Black Friday, süsteem katki. Traditsiooniline sysadmin teeb seda nii:

1. Zabbixis näeb, et mingi server on halb — CPU 100%
2. SSH-b sinna, hakkab `tail -f /var/log/...` jooksutama
3. Leiab ridade kaupa veateateid, aga ei tea, kas need on põhjus või tagajärg
4. Helistab arendajale, kes süveneb koodi, otsib trace-ID logist, üritab seda oma logiaggregaatorist üles leida
5. Üks tund hiljem keegi vast saab aru, mis juhtus

LGTM-pinu lubab järgmist: Grafanas vaatad dashboardi, näed anomaaliat meetrikute graafikul (Mimir), klõpsad sellel ajavahemikul → hüppad automaatselt samasse aega logidesse (Loki) → näed veateadet, millel on trace-ID → klõpsad sellel → avaneb jälituse vaade (Tempo), mis näitab täpselt, millises mikroteenuses päring seiskus.

See on **korrelatsiooni kolmik** — mõõdikult logisse, logist jälitusse. Kõik ühes UI-s, ilma tabivahetuseta. Inseneride keeles: **MTTR** (mean time to recovery) langeb oluliselt, sest pole enam tarvis kolmel tööriistal vahet teha.

Ilma selle integratsioonita ei erineks LGTM midagi neljast eraldi tööriistast. Just see, kuidas Grafana räägib Loki'ga ja Loki räägib Tempo'ga, ongi see, millest räägime tegelikult, kui ütleme "LGTM-pinu".

### 2.2 Mis on iga komponendi töö?

**Loki — logid.** Täna põhiteema. Indekseerib ainult silte, mitte sisu. Salvestab S3-tüüpi objektisalvestusse. 35–50% odavam kui ELK enamikes kasutuslugudes.

**Grafana — UI ja päringukeskus.** Juba tuttav. Päev 1-st mäletad — ei salvesta ise andmeid, kogub neid datasource-idest. LGTM-kontekstis on ta **ainus koht, kust kasutaja midagi näeb**. See on oluline arhitektuuriline valik — kõik muud komponendid on "päringuallikad".

**Tempo — jäljed.** Hajutatud jälgimine. Kui sinu süsteem on 20 mikroteenust, mis räägivad omavahel, siis üks kasutaja-päring võib käia läbi 15 teenuse. Tempo salvestab iga sellise päringu tee — kus ta oli, kui kaua, mis juhtus. Filosoofia sama nagu Lokil: ei indekseeri sisu, ainult trace-ID-d. Selle juurde jõuame päeval 5.

**Mimir — meetrikad.** "Prometheus steroididega." Üks Mimir-klaster suudab hallata **miljardeid aktiivseid aegridu**, samal ajal kui üksik Prometheus jookseb mõne miljoni peal kokku. Täielikult Prometheuse API-ühilduv, ehk kõik PromQL-päringud töötavad edasi. Enterprise-keskkonnad, mis tahavad Prometheust skaleerida üle mitme klastri ja regiooni, kasutavad Mimirit.

Iga neli saab kasutada **eraldi** — sa võid võtta ainult Loki ja jätta Mimirist Prometheuse. Või võtta ainult Tempo oma OpenTelemetry-stack'i. Need ei ole lukustatud kokku. Aga **nende tugevus on perekonnana**.

### 2.3 Enterprise-külg — mis sysadmin teadma peab

See osa on teile otseselt oluline — te tulete tootmiskeskkondadest, kus asjad peavad töötama tuhandele kasutajale, vastama compliance-nõuetele ja mitte kukkuma, kui üks tsoon ära kaob.

**Multi-tenancy.** LGTM-komponendid toetavad natiivselt mitme üürniku mudelit — sa saad ühes klastris hoida erinevate meeskondade või klientide andmed täielikult eraldi. Tenant-ID käib iga päringuga kaasas, indeks on eraldi, päring ühe tenandi andmetest ei saa eales teise omi näha. Kui haldad teenust, mis teenindab mitut osakonda või klienti, on see kriitiline.

**Skaleeritavus ja režiimid.** Tulen selle juurde Loki kontekstis tagasi (§8), aga põhimõte kehtib kogu LGTM-pinule: kuni väikese mahuni (paar GB päevas) töötab monoliitne paigaldus. Keskmise mahu puhul eralda kirjutus- ja lugemistee. Suure mahu puhul (1 TB+ päevas logisid, miljonid meetrikud) — **mikroteenuste režiim**, kus iga komponenti saab eraldi skaleerida. Tootmisstandard suurettevõtetes.

**Käideldavus ja SLA.** Grafana Cloud pakub 99.5–99.9% SLA-sid. Self-hosted puhul saad sama, kui ehitad süsteemi **zone-aware replication**-iga — komponendid jaotuvad eri Kubernetes-tsoonidesse, ja kui üks tsoon kukub, teised jätkavad. Replikatsioonifaktor 3 (iga andmeid hoiab 3 koopiat) on soovitus.

**Compliance.** Grafana Enterprise ja Cloud paketid on **SOC 2 Type II, GDPR, PCI-DSS** sertifitseeritud. Self-hosted puhul on compliance sinu õlgadel, aga võimalused on olemas — krüpteerimine andmete liikumisel ja puhkeolekus, audit-logid, RBAC kasutaja-tasemel.

**RBAC.** Rollipõhine juurdepääs — kes näeb milliseid dashboard'e, kes saab päringuid teha millistes datasource-ides, kes saab alerti muuta. Enterprise-versioonis on see palju detailsem kui OSS-is. Kui sinu firmas on auditinõue "iga dashboardi muudatus peab olema jälgitav kasutajani" — enterprise on ainus valik.

### 2.4 Self-hosted vs Grafana Cloud — otsustuspuu

See on otsus, mida iga sysadmin peab kunagi tegema.

**Self-hosted (te ise Kubernetes-klastris hoiate):**
- ✅ Andmed jäävad sinu infrastruktuuri. GDPR, saladuslik info, sise-eeskirjad — kõik puhas.
- ✅ Kulu kontrolli all — maksad ainult infrastruktuuri eest.
- ✅ Täielik paindlikkus — saad lugemistee tuunida, lisada plugin'e, muuta mida tahad.
- ❌ Kõik operatiivne vastutus on sinul. Ingester kukub keskööl — sina vastutad.
- ❌ Vajab kompetentsi — Kubernetes, Helm, storage, networking.

**Grafana Cloud (hallatud):**
- ✅ Paigalduseni minutid, mitte nädalad.
- ✅ Grafana Labs vastutab uptime'i eest.
- ✅ AI-lisaväärtus (sellest kohe).
- ❌ Andmed lähevad **nende pilve** — privaatsuskaalutlus.
- ❌ Kuluarvestus põhineb logi- ja mõõdikumahul — võib kiirelt kasvada ettearvamatult.
- ❌ Vendor lock-in risk. Aga see on väiksem kui konkurentidel, sest LGTM-komponendid on avatud lähtekoodiga, migreerud välja.

Eestis kohtad mõlemat. Bolt, Wise — enamasti self-hosted, kuna mastaap on suur ja kulu kriitiline. Väiksemad iduettevõtted lähevad sageli Grafana Cloud'iga, sest "lihtsalt töötab". Meie laboris täna — self-hosted (Docker Compose), sest see annab arusaamise sellest, mis kapoti all toimub.

### 2.5 AI ja LGTM — kus see tõesti aitab

Siin tuleb olla aus — 2024–2026 on iga tootja panustanud "AI"-märgi lisamisele oma toodetele. Osa neist on tõeline kasu, osa on pressi-esitlus. Teeme vahet.

**Grafana Assistant** — AI-abiline, mis aitab päringuid kirjutada. LogQL on küll lihtsam kui ElasticSearchi DSL, aga mitte tühi. Kui sa ei mäleta, kas filter on `|=` või `~=`, küsid Assistantilt loomuliku keelega, ta genereerib päringu. Tegelik kasu — on jah, ma proovisin. Eriti algajatele ja harva-kasutajatele.

**Adaptive Telemetry** — see on see, kus AI tõesti raha säästab. Süsteem analüüsib sinu mõõdikuid ja logisid ja tuvastab, mida **keegi kunagi ei vaata**. Pakub välja neid filtreerida. Grafana Labs lubab 35–50% säästu, mis on usutav — enamikus firmades kogutakse palju "igaks juhuks" andmeid, mis võtavad ruumi ja ei anna väärtust.

**Agentic AI / Automaatne RCA** (Root Cause Analysis) — siin ma olen kainem. Idee on, et AI-agendid uurivad intsidenti automaatselt, korreleerivad logisid-meetrikaid-jälgi ja pakuvad välja juurpõhjuse. Turundus lubab 90%+ MTTR vähendust. Praktikas — see on väga rakendusesõltuv. Lihtsate juhtumite puhul (disk täis, OOM-killer tuli) tõepoolest aitab. Keerukate hajutatud süsteemide bug-ide puhul jääb inimene siiski lahendajaks.

**Minu seisukoht sysadminina:** AI on hea **algataja** — saab probleemi üles, pakub hüpoteese, kitsendab ruumi. Inimene teeb lõpliku otsuse. Ära käsita AI-t kui võluvitsa. Käsita seda kui noorempraktikanti, kes on lugenud palju dokumentatsiooni ja suudab kiiresti otsida, aga kellel pole veel tootmiskeskkonna intuitsiooni.

### 2.6 OpenTelemetry ja vendor lock-in

Üks asi, mis enterprise-otsuses alati tuleb lauale, on **vendor lock-in** — kuidas tagada, et me ei jää ühe tarnija lõksu.

**OpenTelemetry (OTel)** on CNCF-i standard, mis defineerib universaalse viisi, kuidas rakendused saadavad logisid, meetrikaid ja jälgi. Põhimõte: rakenduses instrumenteerid OTel-iga, ja siis kogutud andmed saad saata **ükskõik kuhu** — Datadog'i, New Relic'usse, Grafana Cloud'i, Lokisse, kus iganes. Rakenduste poolel pole tarvis midagi muuta, kui tarnijat vahetad.

Grafana Labs tegi targa valiku — nende uus agent **Grafana Alloy** (millest §10 räägib) toetab natiivselt OTel-i. Ehk kui valid täna Grafana Cloud'i, aga aastaga otsustad migreerida self-hosted'ile või isegi Datadog'ile, su rakendusi muutma ei pea — ainult kollektori sihtpunkti.

Sysadminina tähendab see: **vali alati OTel-compatible tööriist**, kui valida on. See on sinu kindlustuspoliis tuleviku vastu.

### 2.7 Bloom-filtrid ja muud värskemad arengud

Enne kui Loki-spetsiifikasse sukeldume, mõned asjad, mis on LGTM-pinu juures viimase 12 kuu jooksul muutunud:

**Loki 3.0 (2024) tõi Bloom-filtrid.** See on andmestruktuur, mis võimaldab kiiresti vastata küsimusele "kas see väärtus on tüki sees?" ilma tüki avamiseta. Praktikas — kui otsid konkreetset trace-ID'd või kasutaja-ID'd, Bloom-filter ütleb ette ära, millistes tükkides seda üldse võiks olla. Skaneeritavate tükkide hulk väheneb drastiliselt. Tänase seisuga (aprill 2026) on see veel eksperimentaalne, aga 2026 lõpuks peaks olema standardne.

**Grafana Beyla (eBPF-põhine auto-instrumenteerimine).** See on eraldi lugu — Beyla kasutab Linux-tuuma eBPF-i, et **ilma koodi muutmata** koguda rakenduste meetrikaid ja jälgi. Installeerid Beyla sisse, pöörad ta rakenduse protsessi külge, ja saad automaatselt HTTP-päringute jälgi. Enterprise-keskkondades, kus rakendusi on sadu ja kõiki käsitsi instrumenteerida on ebarealistlik, see on murranguline.

**Frontend observability (RUM).** Real User Monitoring — sinu veebirakendus saadab brauserist telemeetriat selle kohta, mida päris kasutaja kogeb. LGTM toetab seda Grafana Faro komponendi kaudu. Enterprise-puhul sageli nõutav, sest "meie serverid on 99.9%-lised, aga kasutajad kurdavad ikka" probleemi lahendamiseks vajad sa **päris kasutaja** vaadet, mitte serveri vaadet.

---

## 3. Loki — "Prometheus logide jaoks"

Aitab ülevaatest, siseneme nüüd Loki'sse sügavamalt.

2018. aastal KubeConis, San Franciscos, tutvustab Tom Wilkie (Grafana Labs CTO, endine Weaveworks insener) uut projekti. Tema kirjeldus jääb ajalukku:

> *"Loki: like Prometheus, but for logs."*

See pole turundushüüdlause — see on arhitektuuriline avaldus. Vaatame, mida see praktikas tähendab.

**Prometheus** kogub iga sihtmärgi kohta mõõdikuid. Iga mõõdik on määratletud **siltidega** (`job="api"`, `env="prod"`). Sildid on indekseeritud, väärtused on aegrea andmed. Filtreerid siltidega, agregeerid väärtusi.

**Loki** kogub iga allika kohta logiridu. Iga logi on määratletud samasuguste **siltidega** (`app="nginx"`, `namespace="prod"`). Sildid on indekseeritud, logi sisu on... lihtsalt tekst, kokku pakitud, objektisalvestuses.

Ehk siis — Loki ei indekseeri midagi sellest, mis logireal sees on. Ei kasutajanime, ei IP-aadressi, ei veateksti. Ainult silte.

---

## 4. Miks indekseeritakse ainult silte

Traditsiooniline lähenemine (Elasticsearch, Splunk) töötab nii: tuleb logirida sisse → tõkestatud sõnadeks → iga sõna lisatakse pöördindeksisse → indeks kasvab hiiglaslikuks → hoitakse SSD-l → vajab palju RAM-i.

Kui sul on 10 TB logisid päevas, võib Elasticsearchi indeks olla 15 TB — indeks suurem kui andmed ise. Kalliks läheb see kiirete SSD-de, mälu ja shard-tuunimise oskusnõude tõttu.

Loki lähenemine:

```
Logirida tuleb sisse
   ↓
Eraldatakse sildid: {app="nginx", env="prod"}
   ↓
Sildid lähevad indeksisse (väike — megabaidid, mitte terabaidid)
   ↓
Logi sisu pakitakse tükiks (~1 MB)
   ↓
Tükk salvestub S3-sse (~0.01€ per GB/kuus)
```

Võrdluseks — salvestuskulu S3-s vs. kiire SSD klaster: erinevus on umbes **20x**. Meeskonnad, kes on ELK-lt Lokile üle läinud, raporteerivad logihalduse kulude langust **35–50%**. See pole väike number, kui sinu eelarvest on monitoorimisele pühendatud 6-kohalist summat.

Aga... kuidas sa siis otsid? Kui logi sisu pole indekseeritud, kuidas leiad "error"-rida?

Loki päringu ajal leiab ta kõigepealt siltide järgi õiged logivood (näiteks `{app="nginx"}`). Siis avab ta nende voogude tükid (mitte kogu logi) ja skannib neid paralleelselt — sama põhimõtte järgi nagu `grep`. Kuna tükke loetakse paralleelselt kümnetest querier-itest, on see kiire. Tingimus: pead teadma siltide põhjal, kust otsida. Kui ütled Lokile "otsi kogu minu 10 TB andmestikust sõna 'timeout'", ta ei rõõmusta.

Operatiivse silumise jaoks (sa tead, millise rakenduse logid sind huvitavad) on see ideaalne. Üldine forensika ("otsi kõigest sõna X") paneb Loki kannatama.

---

## 5. Sildid ja logivood — arhitektuuri süda

Kui on üks kontseptsioon, mida peab Loki juures õigesti mõistma, siis on see see.

**Logivoog** (log stream) on logiridade rühm, millel on täpselt sama komplekt silte. Iga kord, kui mõni silt erineb, tekib uus voog.

```
{app="frontend", env="dev"}       → voog #1
{app="frontend", env="prod"}      → voog #2
{app="backend",  env="prod"}      → voog #3
```

Iga voog on Loki jaoks eraldi üksus. Tema kirjutab neid eraldi, pakib eraldi, salvestab eraldi. See toimib, kui voogusid on mõistlikult palju. Aga kui neid on miljoneid, hakkab süsteem kiduma.

### Kuldreegel: piiratud väärtused

Kõik sildid, mida kasutad, peavad olema piiratud hulgaga (bounded) — väärtuste arv ette teada ja väike.

| Sildi tüüp | Näide | Unikaalseid väärtusi | Kas sildiks? |
|-----------|-------|---------------------|--------------|
| Keskkond | `env=dev/staging/prod` | 3 | ✅ jah |
| Klaster | `cluster=eu-west/us-east/ap-south` | 5–10 | ✅ jah |
| Rakendus | `app=nginx/api/db/...` | ~20 | ✅ jah |
| Logitase | `level=info/warn/error` | 3–5 | ⚠️ sõltub (vt all) |
| IP-aadress | `src_ip=1.2.3.4` | **∞** | ❌ **EI KUNAGI** |
| Kasutaja ID | `user_id=12345` | **∞** | ❌ **EI KUNAGI** |
| Trace ID | `trace_id=abc123...` | **∞** | ❌ **EI KUNAGI** |

Kui paned IP-aadressi sildiks, siis iga uus unikaalne IP loob uue logivoo. 10 000 kasutajaga süsteemis on sul 10 000 voogu. 100 000 kasutajaga — 100 000 voogu. Indeks paisub, Loki aeglustub.

---

## 6. Kardinaalsus — Loki tähtsaim piirang

**Kardinaalsus** = unikaalsete sildikombinatsioonide arv. See on number, mida Loki administraator peab teadma ja jälgima.

Meenuta eelmisest osast — iga voog salvestatakse eraldi tükkideks. Ideaalne tüki suurus on ~1 MB pakitult (umbes 5–10 MB teksti). Kui Loki tükk täitub, kirjutab ta selle S3-sse ja alustab uut.

Aga mis juhtub, kui sul on 10 000 voogu, millest igaüks toodab vaid mõne kilobaidi logisid tunnis?

```
10 000 voogu × 10 KB/tund → 100 MB/tund
                         → aga 10 000 väikest tükki!
```

Iga tükk on eraldi fail S3-s. Iga päring, mis peab neid puudutama, teeb 10 000 HTTP-kutset. Iga tükk võtab ka ingesteri mälu. Süsteem muutub aeglaseks fragmenteerituse tõttu, isegi kui andmete maht on tagasihoidlik.

### Praktilised piirid

| Logide maht päevas | Mõistlik voogude arv | Hoiatuslävi |
|-------------------|---------------------|-------------|
| Alla 100 GB | Kuni 10 000 | 20 000 |
| 1 TB | Kuni 10 000 | 50 000 |
| 10 TB+ | Kuni 100 000 | 200 000 |

100 000 voogu **ei ole eesmärk** — see on äärmine piir tohutute juurutuste jaoks. Tavaline tootmiskeskkond elab tuhandega-kahega täiesti õnnelikult.

### Kuldreegel nr 2: sildid on 10–15 voo kohta maksimaalselt

Tehniline piirang on 15 silti voo kohta, aga iga lisatud silt mitmekordistab potentsiaalselt voogude arvu. Reaalses tootmises on 5–8 silti piisav.

---

## 7. Structured Metadata — Loki 3.0 vastus probleemile

"Aga mina tahan trace_id järgi otsida!" võib öelda arendaja. "Muidu pole kogu OpenTelemetry asja mõtet."

Kuni Loki 2.x-ini oli vastus: kasuta filtrit, mitte silti. Sildid oleksid `{app="api"}` ja `trace_id` otsiksid LogQL-filtriga:

```logql
{app="api"} |= "trace_id=abc123"
```

See töötab, aga on aeglane — peab sisu skannima.

**Loki 3.0** (aprill 2024) tõi lahenduseks **Structured Metadata**. See on kolmas kategooria metaandmeid, mis elab **logirea kõrval, mitte indeksis**:

```
┌─────────────────────────────────────────────────────────┐
│ INDEKS (sildid)                                         │
│ {app="api", env="prod"}                                 │
├─────────────────────────────────────────────────────────┤
│ STRUCTURED METADATA (kiire ligipääs, ei indekseerita)   │
│ trace_id=abc123, user_id=42, request_id=xyz            │
├─────────────────────────────────────────────────────────┤
│ LOGIREA SISU (pakitud, objektisalvestuses)              │
│ "2026-04-25 10:23:41 ERROR Payment failed: timeout"     │
└─────────────────────────────────────────────────────────┘
```

Structured Metadata on otsitav ja kiire, aga ei kasva indeksis. See tähendab: **kõrge kardinaalsusega andmed** (trace_id, user_id, request_id) lähevad nüüd siia, mitte siltidesse. Kardinaalsuse plahvatuse oht kaob.

Kui kavandad Loki juurutust 2026. aastal — **ära kunagi pane trace_id'd sildiks**. Pane Structured Metadatasse.

---

## 8. Paigaldusrežiimid

Loki saab paigaldada kolmel viisil. Üks neist on hetkel aegumas.

### Monolithic — kõik ühes protsessis

```
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

Üks protsess, kõik komponendid sees. Lihtne käivitada — üks Docker Compose, üks Helm-chart. Sobib **kuni 20 GB päevas**, ehk väike-keskmine keskkond, arendus, testimine, koolitusruum.

Meie laboris kasutame täna just seda.

### Simple Scalable Deployment (SSD) — deprecated

See jagab töö kolmeks rolliks: `read`, `write`, `backend`. Oli mõeldud vahepealseks — suurem kui Monolithic, lihtsam kui täielik Microservices. Sobis keskkondadele mahuga kuni 1 TB päevas.

**Aga — 2025. märts — Grafana Labs teatas (David Allen):**

> *"SSD režiimi keerukuse ja kasu suhe pole enam paigas. Uutel kasutajatel ei soovitata SSD-ga alustada."*

Ametlikult on SSD režiim **aegumas** ja eemaldatakse enne Loki 4.0 versiooni. Kui sa kohtad seda dokumentatsioonis või vanemas tutorialis — hoia eemale. Alusta Monolithicuga, kasva Microservices-iks.

### Microservices — tootmiskeskkonna standard

Iga komponent eraldi Kubernetes-deployment. Iga komponenti saab eraldi skaleerida — kui kirjutamiskoormus kasvab, lisad Ingestereid; kui päringuid tuleb rohkem, lisad Querier-eid.

```
  ┌──────────┐    ┌──────────┐
  │Distributor│───│Distributor│─── ×3
  └────┬──────┘    └────┬─────┘
       ▼                ▼
  ┌──────────┐    ┌──────────┐    ┌──────────┐
  │ Ingester │    │ Ingester │    │ Ingester │ ×N
  └────┬─────┘    └────┬─────┘    └────┬─────┘
       │               │               │
       └───────────────┼───────────────┘
                       ▼
                    ┌─────┐
                    │ S3  │
                    └─────┘
                       ▲
       ┌───────────────┼───────────────┐
       │               │               │
  ┌────┴─────┐    ┌────┴─────┐    ┌────┴─────┐
  │ Querier  │    │ Querier  │    │ Querier  │ ×M
  └──────────┘    └──────────┘    └──────────┘
```

Toetab **tsooniteadlikku replikatsiooni** (zone-aware replication) — ingesterid jaotatakse eri Kubernetes-tsoonidesse, nii et kui terve tsoon kukub, süsteem toimib edasi. See on tootmiskriitilise süsteemi nõue.

Soovitatud **1 TB+ päevas** keskkondades või mujal, kus käideldavus on kriitiline.

---

## 9. Komponendid sügavamalt

Mikroteenuste režiimis näed sa kõiki komponente. Aga ka Monolithic-režiimis töötavad nad sama loogikaga — lihtsalt ühe protsessi sees.

### Kirjutustee (write path)

```
Agent (Alloy/Promtail) → Gateway (NGINX) → Distributor → Ingester → S3
```

**Distributor** on värav. Ta võtab vastu, valideerib, teeb rate limiting'ut, kontrollib tenant'it (multi-tenancy jaoks). Seejärel räsib logi sildid ja suunab `Hash Ring`-i järgi õigele Ingesterile.

**Ingester** on süsteemi süda. Ta puhverdab logid mälus, pakib neid tükkidena kokku, replikeerib teistele Ingesteritele (tavaliselt 3 koopiat). Kui tükk saab valmis (~1 MB, või aeg möödas), kirjutab ta selle S3-sse.

### Lugemistee (read path)

```
Grafana → Gateway → Query Frontend → Query Scheduler → Querier → {Ingester RAM, S3}
```

**Query Frontend** tükeldab päringud — kui küsid viimase 24h andmeid, jagatakse see 24-ks tunni-päringuks, mis käivad paralleelselt.

**Query Scheduler** haldab järjekorda. Õiglane planeerimine — üks kasutaja ei saa süsteemi endale võtta.

**Querier** teeb tegeliku töö. Ta küsib andmeid nii Ingesteritest (viimased andmed, veel mälus) kui S3-st (vanemad tükid), teeb deduplikatsiooni (sest tükid on replikeeritud), täidab LogQL-i päringu.

### Taustaprotsessid

**Compactor** on eriti oluline. Ta käib regulaarselt üle — liidab väiksed tükid suurteks, optimeerib indeksit, kustutab vanu andmeid vastavalt säilituspoliitikale (retention). Ilma selleta paisuks S3 täis killustatud faile.

**Ruler** täidab reegleid — alertimine ja recording rules (nagu Prometheuses). Siin saad kirjutada: *"kui viimase 5 minuti jooksul on rohkem kui 100 `level=error` rida — saada hoiatus."*

**Index Gateway** — vahekiht, mis vastutab indeksi lugemise eest. Vähendab S3-kutsete arvu.

---

## 10. Agent — Promtail on läinud, tule Alloy

Kuni 2024 oli Loki standardagent **Promtail** — lihtne binaar, mis lõi logifailid üles ja saatis Lokile. See oli aastaid lihtsalt-toimiv lahendus.

2024 teatas Grafana Labs, et Promtail liigub **feature-freeze** olekusse ja soovitatud on **Grafana Alloy**. Alloy on universaalne telemeetria-kollektor — üks agent kogub logisid, meetrikaid, jälgi. Põhineb OpenTelemetry Collectori komponentidel, aga pakub Grafana maailma poolt testitud konfiguratsiooni.

Kui ehitad täna uut süsteemi — kasuta **Alloy**. Kui sul on vana Promtail-deployment — töötab edasi, aga planeeri migratsiooni.

Laboris täna kasutame Alloy'd. See on kerge (u 30 MB RAM), konfiguratsioon sarnane HCL-ile (Terraformi tuttav süntaks).

---

## 11. HOIATUS — Helm-chart'ide džungel

Kui Google'ist otsid *"loki helm chart"*, leiad **kolm** erinevat nime. Ainult üks neist on elus. See on levinud komistuskivi ja põhjus, miks paljud Loki-tutorialid internetis on juba aegunud.

| Chart | Staatus | Kasuta? |
|-------|---------|---------|
| `grafana/loki` | ✅ Ametlik, aktiivne, toetab Loki 3.0+ | **Jah — AINUS valik** |
| `grafana/loki-stack` | ⚠️ Deprecated | **Ei** |
| `grafana/loki-distributed` | ⚠️ Hooldamata, seisab 2.9.0 peal | **Ei** |

Eriline hoiatus: kui kasutad ChatGPT-d või Claude'i (või mind, hehe) `values.yaml` genereerimiseks — **kontrolli kriitiliselt**. Mudelite treeningandmed sisaldavad vanu tutorialeid, ja nad pakuvad sageli `loki-stack`-i näidiseid. Need ei tööta Loki 3.0-ga.

---

## 12. LogQL — päringukeel lühidalt

LogQL on PromQL-i vend. Kui PromQL oskad, saad LogQL-iga 15 minutiga hakkama.

**Baaspäring — voo valik:**
```logql
{app="nginx", env="prod"}
```
See tagastab kõik sellise siltide komplektiga logiread.

**Tekstifilter — grep-stiil:**
```logql
{app="nginx"} |= "error"           # sisaldab "error"
{app="nginx"} != "healthcheck"     # EI sisalda
{app="nginx"} |~ "5[0-9]{2}"       # regex — HTTP 5xx koodid
```

**Parsimine ja labelite ekstraktimine:**
```logql
{app="nginx"} | json | status_code >= 500
```
Siin `| json` parsib JSON-vormingus logiread ja teeb kõigist väljadest kättesaadavad muutujad.

**Meetrikud LogQL-ist** — siin läheb huvitavaks:
```logql
# Veaolukordade arv minutis
rate({app="nginx"} |= "error" [1m])

# Viis suurimat 5xx-allikat viimase tunni jooksul
topk(5, sum by (app) (rate({env="prod"} |~ "5[0-9]{2}" [1h])))
```

Jah — logidest saab teha meetrikuid PromQL-sarnase süntaksiga. Laboris käsitleme seda praktikas.

---

## 13. Loki vs ELK — millal kumba valida

Ei ole õiget ja valet tööriista. On sobiv ja sobimatu kontekstis.

| Kriteerium | Loki | ELK Stack |
|-----------|------|-----------|
| **Indekseerib** | Ainult silte (~1% mahust) | Kogu teksti (~150% mahust) |
| **Salvestuskulu** | S3 — odav | SSD — kallis |
| **RAM-vajadus** | Madal | Kõrge |
| **Täistekstiotsing** | Aeglane (grep läbi tükkide) | Kiire (indeks on olemas) |
| **Operatiivne silumine** | Ideaalne | Ülitugev |
| **Ad-hoc forensika** | Piiratud | Ülitugev |
| **Turvaanalüüs** | Alajääb | Domineerib (ES-SIEM) |
| **Kubernetes-integreerumine** | Natiivne | Töötab, vajab häälestust |
| **TCO** | **35–50% odavam** | Kallis |

### Vali Loki, kui:

- Sul on juba Grafana ja/või Prometheus kasutuses — integratsioon on sujuv
- Sinu peamine kasutusviis on **operatiivne silumine** (tean rakendust, otsin põhjust)
- Eelarve on piiratud ja logihulk kasvab kiiresti
- Kubernetes-keskkond — Loki on sinna sündinud

### Vali ELK, kui:

- Teed **turvaforensikat** — vaja otsida suvalisi mustreid kogu andmekogus
- **Süvaanalüüs** on peamine kasutusviis — agregatsioonid, aggregations, complex queries
- Vajad **mitte-tehnilist UI-d** (Kibana on selles parem kui Grafana logide jaoks)
- Compliance nõuab täisteksti indekseerimist

Paljudes ettevõtetes leiab mõlemad paralleelselt — Loki igapäevaseks operatiivseks tööks, ELK turvatiimile. See on täiesti mõistlik lähenemine.

---

## 14. Grafana Cloud — üks lause

Kui sa ei taha ise LGTM-stack'i Kubernetes-klastris käimas hoida, pakub **Grafana Cloud** hallatud versiooni (tasuta tase — 50 GB logisid, 14-päevane säilitus). Meie laboris kasutame self-hosted, aga tasub teada, et valik on olemas.

---

## 15. Kokkuvõte

**LGTM = Logs + Grafana + Tempo + Mimir.** Grafana ei ole enam lihtsalt dashboard — see on platvorm.

**Loki indekseerib ainult silte.** Logi sisu läheb objektisalvestusse. See on disainiotsus, millel on sügavad tagajärjed.

**Kardinaalsus on vaenlane.** Ära kunagi pane IP-d, trace_id'd ega user_id'd sildiks. Kasuta **Structured Metadata** (Loki 3.0+).

**Paigaldusrežiimid:** Monolithic kuni 20 GB/päevas, Microservices 1 TB+. **SSD on suremas** — mitte alustada sellega.

**Helm-chart:** ainult `grafana/loki`. Teised on surnud või suremas.

**Agent:** täna on **Alloy**, mitte Promtail.

**Loki vs ELK:** operatiivne silumine → Loki. Forensika → ELK. Mõistlik kasutada mõlemat erinevate ülesannete jaoks.

**Järgmine samm:** [Labor: Loki](../../labs/02_zabbix_loki/loki_lab.md) — ehitame Loki + Alloy + Grafana stack'i, mis kogub logisid, teeme LogQL-i päringuid ja seome need kokku Zabbix labori tulemustega.

---

## Enesekontrolli küsimused

1. Kui Loki ei indekseeri logi sisu, kuidas ta siis "error"-rea leiab? Milline on sellise päringu jõudluse piirang?
2. Selgita, miks `trace_id` ei tohi olla Loki silt. Mis juhtub, kui sa ta siiski sildiks paned?
3. Mis on erinevus Structured Metadata ja siltide vahel? Millal kumba kasutada?
4. Sul on käsil uus juurutus: ~50 GB logisid päevas, üks meeskond, Kubernetes keskkond. Millist paigaldusrežiimi valid ja miks?
5. Miks on SSD paigaldusrežiim aegumas? Millest lähtus Grafana Labsi otsus?
6. Kirjuta LogQL päring, mis annab Nginx 5xx-vigade määra (error rate) sekundis viimase 5 minuti jooksul, rakenduspõhiste kaupa grupeeritult.
7. Millal eelistad Loki, millal ELK? Nimeta kaks konkreetset stsenaariumi kummagi jaoks.

---

## Allikad

### Ametlik dokumentatsioon

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

### Teooria ja kontekst

| Allikas | URL |
|---------|-----|
| Grafana ajalugu (Torkel Ödegaard) | https://grafana.com/about/team/torkel/ |
| KubeCon 2018 Loki tutvustus (Tom Wilkie) | https://www.youtube.com/results?search_query=loki+tom+wilkie+kubecon+2018 |
| Grafana Labs blog — Loki 3.0 | https://grafana.com/blog/2024/04/09/grafana-loki-3.0-release/ |
| "How we designed Loki" (Tom Wilkie) | https://grafana.com/blog/2018/12/12/loki-prometheus-inspired-open-source-logging-for-cloud-natives/ |
| Promtail → Alloy migratsioon | https://grafana.com/docs/alloy/latest/tasks/migrate/from-promtail/ |

### Praktiline

| Allikas | URL |
|---------|-----|
| Awesome Loki | https://github.com/grafana/loki/blob/main/docs/sources/community/getting-in-touch.md |
| LGTM demo (Docker Compose) | https://github.com/grafana/intro-to-mltp |
| Loki Canary | https://grafana.com/docs/loki/latest/operations/loki-canary/ |

**Versioonid (testitud, aprill 2026):**
- Loki: `grafana/loki:3.3.0`
- Grafana: `grafana/grafana:11.4.0`
- Alloy: `grafana/alloy:v1.5.0`

---

*Järgmine: [Labor: Loki](../../labs/02_zabbix_loki/loki_lab.md) — ehitame Loki + Alloy + Grafana stack'i, mis kogub logisid ja teeme LogQL-i päringuid.*