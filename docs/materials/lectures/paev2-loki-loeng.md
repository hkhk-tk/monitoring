---
tags:
  - Loki
  - Logid
  - LGTM
  - Day2
---

# Päev 2: Loki — logid Grafana maailmas

**Kursus:** Kaasaegne IT-süsteemide monitooring ja jälgitavus
**Kestus:** ~45 minutit lugemist
**Eeldused:** Päev 1 (Prometheus + Grafana), Zabbix loeng ja labor hommikul

---

## Õpiväljundid

Pärast seda loengut oskad:

- **Selgitada**, miks logid ei mahu enam Zabbixisse
- **Kirjeldada** LGTM stacki lühidalt ja öelda, kuhu Loki selles sobitub
- **Seletada** põhimõtet "label on sildi järgi, sisu on pakitud"
- **Selgitada** kardinaalsust ühe lausega ja põhjendada, miks trace_id EI tohi olla label
- **Nimetada** LogQL-i neli parserit ja öelda, millist millal kasutada
- **Kirjeldada** Alloy rolli ja miks Promtail enam ei ole soovituslik

---

## 1. Miks logid ei mahu Zabbixisse

Hommikul ehitasid Zabbixi. Ta ütleb sulle "payment teenuses on liiga palju vigu" — trigger läheb tulele, sulle tuleb teade.

Nüüd küsimus: **mis on see viga täpselt?** Mis päringud kukkusid? Mis klient? Mis ajal täpselt algas? Mis error message? Mis stack trace?

Zabbix ei ütle. Ta loeb ainult numbri — "ERROR-ridu viimase 1000 rea hulgas" — aga ei näita ridu endid. Selleks, et vigu päriselt näha, pead SSH-ga minema serverisse, leidma õige logifaili, ja tegema `grep ERROR /var/log/app/app.log`.

See töötab, kuni sul on **üks** server. Kui neid on **50** (erinevad mikroteenused, koopiad, keskkonnad), siis on iga kord vaja:

- Teada, kuhu SSH-da (millises serveris see teenus just praegu jookseb?)
- Teada, mis failis logid on (iga rakendus kirjutab enda kohta)
- Olla SSH-võime kõigis (production-is ei pruugi sul lihtsalt õigusi olla)
- Otsida mitmest failist paralleelselt

See on raiskamine. Ja just sellepärast on olemas **tsentraalsed logisüsteemid** — kõik rakendused saadavad oma logid ühte kohta, sa otsid brauserist, filtreerid keskkonna ja teenuse järgi, ja leiad selle, mida otsid sekundites.

Suur mängija on **Elasticsearch / ELK** — olemas juba 2010-st, tugev otsing, aga kallis. Terabaiti logisid päevas → kümneid tuhandeid eurosid kuus, sest Elasticsearch indekseerib kogu logi teksti. Uuem konkurent on **Loki** — Grafana Labs-i tööriist, mis läheneb teistmoodi ja on oluliselt odavam. Täna õpime teda.

---

## 2. Loki koht LGTM pildis

Kursuse Grafana Stack readeri juures nägid **LGTM** akronüümi: **L**oki + **G**rafana + **T**empo + **M**imir. Korda kiirelt, mis on kes:

- **Grafana** — UI, visualiseerija
- **Mimir** — mõõdikud (Prometheus-ühilduv, skaleeruv)
- **Loki** — logid
- **Tempo** — trace'id (distributed tracing)

Kõik neli on **Grafana Labs-i** tehtud, kõik **avatud lähtekoodiga**, kõik on üles ehitatud samale filosoofiale: indekseeri vähe, salvesta odavalt objektimälus (S3), skaleeru horisontaalselt.

Loki koht selles pildis on konkreetne: **ta on logiosa.** Ta võtab logiridu sisse, salvestab need, ja Grafana UI kaudu saad neid päringuda. Ta ei joonista graafikuid ise — selle teeb Grafana. Ta ei kogu logisid ise — selle teeb **Alloy** (agent, millest §7).

Kui ehitad LGTM stacki laupäeval, siis sul on kolm konteinerit: **Loki** (logisalv), **Alloy** (logide kogumise agent), **Grafana** (UI). Zabbix on eraldi, oma logikas. Kaks erinevat maailma samal päeval — traditsiooniline seiremaailm (Zabbix) ja cloud-native observability-maailm (LGTM). Mõlemal on oma koht tootmises.

!!! tip "Loe ka"
    Laiem pilt LGTM stackist on [Grafana Stack — LGTM ülevaade](../../resources/grafana-stack.md) readeris. Soovitan selle enne laborit kiirelt läbi vaadata.

---

## 3. Loki põhiidee: "nagu Prometheus, aga logidele"

Kui hakata Lokit kirjeldama, on üks kõige lühem lause selle kohta Tom Wilkie (Loki autor) sõnastus 2018. aastast:

> "Like Prometheus, but for logs."

See tähendab konkreetset disainivalikut. Prometheus töötab nii: mõõdikud on **sildistatud** (nt `up{job="api", env="prod"}`), sildid on indekseeritud, väärtus ise on lihtsalt number. Sildid teevad otsingu kiireks.

Loki teeb sama asja logidega. Iga logirida tuleb koos **siltidega** (`app="nginx"`, `env="prod"`, `host="mon-target"`). Sildid lähevad indeksisse. **Logirea sisu ise aga EI lähe indeksisse** — ta pakitakse kokku ja salvestatakse objektimällu (S3, MinIO) tavalise failina.

See on Loki **fundamentaalne erinevus Elasticsearchist**. Elasticsearch indekseerib **kogu teksti** — iga sõna igas logireas läheb hiiglaslikku indeksisse. Otsing on kiire ("otsi sõna `database` miljardist logireast sekundis"), aga indeks kasvab suuremaks kui andmed ise. Salvestus on SSD-l, maksab kuus palju raha.

Loki indeks on **megabaidid**, mitte terabaidid, sest sildid on vähesed. Kogu mahukas logitekst on odavas objektimälus (S3 gigabait = sent kuus). Hind on selles, et otsing **sisu järgi** on aeglasem — Loki peab esmalt filtreerima sildi järgi, siis läbi teksti skännima. Aga kui sa otsid targalt (esmalt kitsenda rakenduse sildiga, siis otsi veateadet), toimib see täiesti kiirelt.

Praktikas: organisatsioonid, kes on Elasticsearchilt Lokile üle läinud, teatavad **35-50% logimiskulu vähenemisest**. See on suur arv.

---

## 4. Labelid ja logivood — mõiste, mis teeb või murrab

Siin on Loki **kõige tähtsam mõiste**. Kui sa selle valesti teed, Loki ei tööta. Kui sa selle õigesti teed, Loki lendab.

### Mis on logivoog (log stream)

Iga logirida Lokis kuulub **logivoogu**. Logivoog on ridade kogum, millel on **täpselt samad sildid**.

Näiteks need kolm rida:

```
{app="nginx", env="prod"} "GET /api/users 200"
{app="nginx", env="prod"} "GET /api/orders 500"
{app="nginx", env="prod"} "POST /api/login 200"
```

...on **kõik samas logivoos**, sest nende siltide komplekt on sama: `app="nginx", env="prod"`.

Aga kui ühel real oleks `env="dev"` asemel, oleks see **teine logivoog**. Iga unikaalne siltide kombinatsioon = üks logivoog.

### Kardinaalsus — logivoogude arv

**Kardinaalsus** on lihtsalt sõna "mitu erinevat logivoogu sul on". Kui sa jälgid 5 rakendust 3 keskkonnas, on sul kardinaalsus 5 × 3 = 15 logivoogu. See on OK.

Loki tunneb end hästi kuni **umbes 100 000 logivooni**. Sealt edasi hakkab indeks paisuma, päringud aeglustuvad, kirjutamine hakkab pidurdama. See on Loki disainipiirang — ta on tehtud **vähesteks, suurteks vooludeks**, mitte miljonist pisikesteks.

### Kus asi valesti läheb

Kujuta ette, et paned sildiks `trace_id`:

```
{app="api", trace_id="abc123"}
{app="api", trace_id="def456"}
{app="api", trace_id="ghi789"}
...
```

Iga päring genereerib uue `trace_id`, iga uus `trace_id` loob **uue logivoo**. Kui su rakendus teeb päevas 1 miljon päringut, on sul päevas 1 miljon logivoogu. Loki sureb.

Sama juhtub, kui paned sildiks:
- IP-aadressi (iga uus klient = uus voog)
- Kasutaja ID (iga kasutaja = uus voog)
- Ajatempli (iga sekund = uus voog)
- Pordi numbri (iga ühendus = uus voog)

### Reegel

Lihtne reegel pähe panemiseks: **silt kirjeldab, KUST logi tuleb. Logi sisu läheb logiritta.**

Head sildid kirjeldavad allikat ja on stabiilsed:
- `app` (nginx, api, payment-service)
- `env` (dev, staging, prod)
- `host` või `instance`
- `namespace` (Kubernetes)
- `region`

Halvad sildid on dünaamilised, piiramatud:
- `trace_id`, `request_id`, `session_id`
- `user_id`, `email`, `ip`
- `order_id`, `transaction_id`

Kui vajad neid dünaamilisi välju **otsinguks**, siis Loki 3.0-st (2024) on olemas lahendus: **Structured Metadata**. See on kolmas kiht (sildid-indeksis — metadata-otsitav-ent-indekseerimata — logi sisu-pakitud). Trace_id ja kasutaja_id lähevad sinna. Aga see on detail, mis laboris ei puutu kõigi osadesse — pane praegu kirja ainult reegel: **trace_id EI TOHI olla label**.

---

## 5. LogQL — päringukeel, mis meenutab PromQL-i

Kui Grafana UI-s hakkad Lokist logisid küsima, kirjutad **LogQL** päringu. See keel on tehtud sarnaseks PromQL-iga, mida kasutasid eile Prometheuses.

### Lihtne näide

```logql
{app="nginx", env="prod"}
```

Loe: "anna mulle kõik logivood, kus `app` on `nginx` ja `env` on `prod`". Tulemus on logiread. See on kõige lihtsam LogQL — ainult siltide filter.

### Filter sõne järgi

```logql
{app="nginx", env="prod"} |= "error"
```

Lisaks sildifiltrile kitsendame tulemusi ridadeni, mis sisaldavad sõna "error". `|=` tähendab "sisaldab". Muud filtrid: `!=` (ei sisalda), `|~` (regex).

### Parserid — neli tükki

Siiani me vaatasime logisid **tavalise tekstina**. Aga sageli on logid **struktureeritud** — JSON, logfmt, või mingi muu kindel muster. Parser lahkab logi osadeks ja annab sulle väljad, mida saad filtreerida eraldi.

**JSON parser.** Kui logi on `{"level":"error","user":"ann","duration":42}`:

```logql
{app="api"} | json | level = "error" and duration > 100
```

JSON parser muudab välja `level` ja `duration` filtreeritavaks. See on kõige puhtam, sest JSON-struktuur on selge.

**Logfmt parser.** Kui logi on `level=error user=ann duration=42ms`:

```logql
{app="api"} | logfmt | level = "error"
```

Logfmt on Go-maailma standard (võti=väärtus paarid). Palju Go-rakendusi logib selles formaadis.

**Pattern parser.** Kui logi on vabatekst **stabiilse struktuuriga** (nt `2026-04-25 10:23 ERROR user=ann request failed`):

```logql
{app="api"} | pattern `<_> <_> <level> <_>` | level = "ERROR"
```

`<_>` tähendab "ignoreeri", `<level>` tähendab "võta siit välja ja nimeta level-iks". Pattern on kõige praktilisem tootmises, sest enamik vanemaid rakendusi logivad vabateksti, aga stabiilse mustriga.

**Regexp parser.** Täiesti ebastandardne tekst, kus pattern ei tööta. See on viimane valik — aeglasem ja vigaderohke.

### Parseri valik ühe lausega

| Logi formaat | Parser |
|--------------|--------|
| `{"level":"error"}` | `json` |
| `level=error duration=42ms` | `logfmt` |
| Vabatekst stabiilse struktuuriga | `pattern` |
| Täiesti ebastandardne | `regexp` |
| Ainult ühekordne kiire otsing | `|=` |

Laboris teed osas 1 kõik neli harjutust Grafana ametlikul simulaatoril — enne kui oma Lokit üldse püsti paned. See on targalt nii, sest parseri intuitsiooni on parem arendada ilma infrastruktuuri pärast muretsedes.

---

## 6. Logidest metrika — üks huvitav hüpe

Siin tuleb üks asi, mida Loki teeb ja mida Elasticsearch lihtsalt ei oska. LogQL lubab sul **logidest teha mõõdikuid** — see tähendab, et logiridadest saad tavalise PromQL-stiilis numbri, mida saad panna Grafana graafikule või Zabbixi stiilis häire külge.

Näide. Kujutame, et Nginx logib iga päringu. Sa tahad teada: **mitu 500-veateadet sekundis tuleb?**

```logql
sum(rate({app="nginx"} |= "500" [5m]))
```

Loe: "võta kõik nginx-logiread, filtreeri 500-teadet sisaldavad, loe kokku viimase 5 minuti kohta ja jaga läbi minutite arvuga". Tulemus on arv — "500-vigu sekundis".

See on **sama tüüpi number kui Prometheus mõõdik**. Saad sellest teha:

- graafiku Grafanas ("vigade määr viimase tunni jooksul")
- häire ("kui üle 10/sekundis, paku")
- dashboard'i koos muude mõõdikutega

Laboris teed seda osas 3 — võtad payment-teenuse logidest vigade määra, teed graafiku, ja saad **ühe ekraani peale** Zabbixi triggeri (ülevalt, häire number) ja Loki graafiku (all, logide-põhine vigade trend). **Sama sündmus kahest perspektiivist.** See on laboripäeva kulminatsioon.

---

## 7. Alloy — agent, mis kogub ja saadab

Logid ei ilmu Loki-sse ise. Vaja on **agenti**, mis neid kogub ja saadab. Grafana maailmas on see agent **Grafana Alloy**.

Kuni 2024 oli Loki ametlik agent **Promtail** — lihtne, fokuseeritud, töötas hästi. Aga Grafana Labs tuli välja ambitsioonikama ideega: **üks agent kõigeks**. Alloy oskab:

- Koguda logisid (nagu Promtail)
- Koguda mõõdikuid (nagu Prometheus exporter)
- Koguda trace'e (nagu OpenTelemetry collector)

Üks binaary, üks konfig, üks protsess — kolme vana agendi asemel. **Promtail on nüüd feature-freeze olekus**, uusi funktsioone sinna ei tehta. Uutes paigaldustes kasutatakse Alloyd.

Laboris kasutad sa Alloyd. Tema konfig on lihtne — mis faili lugeda, kuhu saata, mis sildid lisada. Sa mount'id host-masinast logifaili konteinerisse ja Alloy loeb seda pidevalt. Iga uus logirida läheb Loki-sse.

Üks oluline detail, mis tuleb hiljem: **Alloy on samuti OpenTelemetry standardit toetav**. OpenTelemetry (OTel) on cloud-native observability uus standard, mis pole veel valdav, aga kasvab kiiresti. See on kursuse päev 5 teema. Loki ja Alloy on mõlemad OTel-valmis — see tähendab, et kui su rakendus kirjutab OTel-vormingus, saab Alloy selle otse vastu võtta.

---

## 8. Üks praktiline hoiatus — Helm charts

Kui sa hakkad pärast kursust Kubernetes-is Lokit paigaldama, kohtud Grafana Labs-i poolse segadusega: **Loki Helm charts**.

Google otsingust leiad **kolm erinevat Helm chart'i**:
- `grafana/loki` — **ainus, mida 2026 aastal peaks kasutama**
- `grafana/loki-stack` — aegunud, enam ei uuendata
- `grafana/loki-distributed` — aegunud, enam ei uuendata

Vanad tutorialid Medium-is ja YouTube'is viitavad kõigile kolmele. **Kasuta ainult `grafana/loki`**. See on ametlik ja hooldatav.

Kordan, sest see on konkreetne asi, mille pärast inimesed aega kaotavad:

> **Loki Helm chart 2026: `grafana/loki`. Mitte midagi muud.**

Sama kehtib Alloy kohta — `grafana/alloy` (**mitte** `grafana/agent`, mis oli vana nimi).

---

## 9. Kokkuvõte

Viis asja loengust meelde jätmiseks:

**1. Loki = logid + sildid.** Indekseerib ainult sildid, mitte sisu. Sellepärast 2-5x odavam kui Elasticsearch, aga otsing sisu järgi on aeglasem.

**2. Silt kirjeldab, KUST logi tuleb.** App, env, host, namespace. **Mitte** trace_id, user_id, IP — need on logirea sisu osa, mitte kardinaalsust-tekitav silt.

**3. LogQL on sarnane PromQL-iga.** Siltide filter (`{app="nginx"}`) + tekstifilter (`|= "error"`) + parser (`json`, `logfmt`, `pattern`).

**4. LogQL teeb ka mõõdikuid.** `rate({app="nginx"} |= "500" [5m])` annab sulle 500-vigade määra sekundis — saad panna graafikule ja häiresse.

**5. Alloy, mitte Promtail.** Üks agent kõigeks (logid + mõõdikud + trace'id). Promtail on aegumas.

Laupäeva teine pool on täielikult Loki. Osa 1 on LogQL brauseris, osa 2 on Loki + Alloy + Grafana stack, osa 3 on logist mõõdik + FINAAL koos Zabbixiga.

---

## Küsimused enesetestiks

<details>
<summary><strong>Küsimused (vastused all)</strong></summary>

1. Miks Zabbix ei asenda logiteenust?
2. Selgita oma sõnadega: kuidas Loki erineb Elasticsearchist?
3. Mis on logivoog (log stream) ja miks on nende arv oluline?
4. Miks `trace_id` EI saa olla Loki silt?
5. Sul on JSON-logi. Mis LogQL parser sobib? Kirjuta näidispäring.
6. Sul on logi kujul `2026-04-25 10:23 ERROR user=ann`. Mis parser sobib?
7. Miks Alloy, mitte Promtail?

??? note "Vastused"

    1) Zabbix loeb arve, mitte ridu. Ta ütleb "vigu on liiga palju", aga ei näita milliseid. Tsentraalne logiteenus (Loki, Elasticsearch) on teistsugune tööriist — logid salvestatakse terviklikult, otsid ridu mitte arve. Kaks erinevat rolli monitooringus.

    2) Elasticsearch indekseerib **kogu teksti** — iga sõna igas logireas läheb indeksisse. Kiire otsing, aga kallis (indeks suurem kui andmed). Loki indekseerib **ainult sildid**, sisu pakitakse ja läheb odavasse objektimälusse. Otsing sisu järgi aeglasem, aga 2-5x odavam kogupildis.

    3) Logivoog = unikaalse sildikombinatsiooniga logiridade kogum. Kardinaalsus = logivoogude arv. Loki töötab hästi kuni ~100 000 voolu; sealt edasi hakkab indeks paisuma ja päringud aeglustuvad. Seepärast ei tohi siltideks valida dünaamilisi välju.

    4) `trace_id` on iga päringu jaoks unikaalne. Kui su rakendus teeb 1 miljon päringut päevas, tekib 1 miljon eraldi logivoogu. Loki jääb alla — indeks ei mahu, päringud aeglustuvad, kirjutamine hakkab pidurdama. `trace_id` kuulub Structured Metadata sisse (Loki 3.0+), mitte siltidesse.

    5) `json` parser. Näide: `{app="api"} | json | level = "error"`.

    6) `pattern` parser. Näide: `{app="api"} | pattern \`<_> <_> <level> <_>\` | level = "ERROR"`.

    7) Alloy kogub ühe agendiga logisid, mõõdikuid ja trace'e. Promtail kogus ainult logisid. Alloy asendab kolme vanemat agenti — Promtail, Grafana Agent, OpenTelemetry Collector. Üks binaary, üks konfig. Grafana Labs on Promtaili feature-freeze-nud, uute paigaldustega kasuta Alloyd.

</details>

---

## Allikad

| Allikas | URL |
|---------|-----|
| Grafana Loki docs | <https://grafana.com/docs/loki/latest/> |
| Labels best practices | <https://grafana.com/docs/loki/latest/get-started/labels/bp-labels/> |
| Cardinality | <https://grafana.com/docs/loki/latest/get-started/labels/cardinality/> |
| LogQL | <https://grafana.com/docs/loki/latest/query/> |
| Grafana Alloy | <https://grafana.com/docs/alloy/latest/> |
| Loki 3.0 release | <https://grafana.com/blog/2024/04/09/grafana-loki-3.0-release/> |
| Structured Metadata | <https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/> |

**Versioonid:** Loki 3.7.1, Grafana Alloy 1.15.1, Grafana 12.4.3.

---

*Järgmine: [Labor: Loki](../../labs/02_zabbix_loki/loki_lab.md)*

--8<-- "_snippets/abbr.md"
