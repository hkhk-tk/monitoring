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

Selle peatüki lõpuks suudad:

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

See on tüütu ja ajakulukas. Sellepärast kasutatakse **tsentraalseid logisüsteeme** — kõik rakendused saadavad oma logid ühte kohta, sa otsid brauserist, filtreerid keskkonna ja teenuse järgi, ja leiad vajaliku sekunditega.

Üks võimalus on **Elasticsearch / ELK** — olemas juba 2010-st, tugev otsing, aga kallis. Terabaiti logisid päevas → kümneid tuhandeid eurosid kuus, sest Elasticsearch indekseerib kogu logi teksti. Uuem konkurent on **Loki** — Grafana Labs-i tööriist, mis läheneb teistmoodi ja on oluliselt odavam. Täna tegeleme temaga.

---

## 2. Loki koht LGTM pildis

Kursuse Grafana Stack readeri juures nägid **LGTM** akronüümi: **L**oki + **G**rafana + **T**empo + **M**imir. Korda kiirelt, mis on kes:

- **Grafana** — UI, visualiseerija
- **Mimir** — mõõdikud (Prometheus-ühilduv, skaleeruv)
- **Loki** — logid
- **Tempo** — trace'id (distributed tracing)

Kõik neli on **Grafana Labs-i** tehtud, kõik **avatud lähtekoodiga**, kõik on ehitatud samale mõttele: indekseeri vähe, salvesta odavalt objektimälus (S3), skaleeru horisontaalselt.

Loki roll on selge: **ta on logiosa.** Ta võtab logiridu vastu, salvestab need, ja Grafana UI kaudu saad neid pärida. Ta ei joonista graafikuid ise — selle teeb Grafana. Ta ei kogu logisid ise — selleks on **Alloy** (agent, vt §7).

Kui paned LGTM stacki püsti, on sul kolm konteinerit: **Loki** (logisalv), **Alloy** (logide kogumise agent), **Grafana** (UI). Zabbix elab eraldi, oma maailmas. Ühel päeval on sul seega kaks erinevat vaadet: traditsiooniline seire (Zabbix) ja cloud-native observability (LGTM).

!!! tip "Loe ka"
    Laiem pilt LGTM stackist on [Grafana Stack — LGTM ülevaade](../../resources/grafana-stack.md) readeris. Vaata see enne laborit üle.

---

## 3. Loki põhiidee: "nagu Prometheus, aga logidele"

Loki autori Tom Wilkie üks varasemaid lühikirjeldusi 2018. aastast:

> "Like Prometheus, but for logs."

Prometheus töötab nii: mõõdikud on **sildistatud** (nt `up{job="api", env="prod"}`), sildid on indekseeritud, väärtus ise on lihtsalt number. Sildid teevad otsingu kiireks.

Loki kasutab sama mõtet logide puhul. Iga logirida tuleb koos **siltidega** (`app="nginx"`, `env="prod"`, `host="mon-target"`). Sildid lähevad indeksisse. **Logirea sisu ise aga EI lähe indeksisse** — see pakitakse ja salvestatakse objektimällu (S3, MinIO) tavalise failina.

See on Loki peamine erinevus Elasticsearchist. Elasticsearch indekseerib **kogu teksti** — iga sõna igas logireas läheb hiiglaslikku indeksisse. Otsing on kiire ("otsi sõna `database` miljardist logireast sekundis"), aga indeks kasvab suuremaks kui andmed ise. Salvestus on SSD-l, ja see maksab.

Loki indeks on **megabaidid**, mitte terabaidid, sest silte on vähe. Kogu mahukas logitekst on odavas objektimälus (S3 gigabait = sent kuus). Hind on selles, et otsing **sisu järgi** on aeglasem — Loki peab esmalt filtreerima sildi järgi, siis teksti läbi skännima. Kui aga kasutad silte mõistlikult (esmalt kitsendad rakenduse või teenuse järgi, alles siis otsid veateadet), on see praktikas piisavalt kiire.

Paljud organisatsioonid, kes on Elasticsearchilt Lokile üle läinud, on suutnud logimise kulusid mitmekümne protsendi võrra vähendada.

---

## 4. Labelid ja logivood — mõiste, mis Loki kas tööle paneb või kinni jookseb

Siin on Loki jaoks **kriitiline koht**. Kui sildid on valesti valitud, ei tööta süsteem hästi. Kui sildid on paigas, on Loki väga tõhus.

### Mis on logivoog (log stream)

Iga logirida Lokis kuulub **logivoogu**. Logivoog on ridade kogum, millel on **täpselt samad sildid**.

Näiteks need kolm rida:

```text
{app="nginx", env="prod"} "GET /api/users 200"
{app="nginx", env="prod"} "GET /api/orders 500"
{app="nginx", env="prod"} "POST /api/login 200"
```

...on **kõik samas logivoos**, sest nende siltide komplekt on sama: `app="nginx", env="prod"`.

Kui aga ühel real oleks `env="dev"`, oleks see juba **teine logivoog**. Iga unikaalne siltide kombinatsioon = üks logivoog.

### Kardinaalsus — logivoogude arv

**Kardinaalsus** tähendab lihtsalt "mitu erinevat logivoogu sul on". Kui jälgid 5 rakendust 3 keskkonnas, on kardinaalsus 5 × 3 = 15 logivoogu. See on rahulik number.

Loki tunneb end hästi kuni umbes **100 000 logivooni**. Sealt edasi hakkab indeks paisuma, päringud aeglustuvad, kirjutamine pidurdub. Loki on mõeldud **vähesteks, suurteks vooludeks**, mitte miljoniks pisikeseks.

### Kus asi tuksi läheb

Kujuta ette, et paned sildiks `trace_id`:

```text
{app="api", trace_id="abc123"}
{app="api", trace_id="def456"}
{app="api", trace_id="ghi789"}
...
```

Iga päring tekitab uue `trace_id`, iga uus `trace_id` loob **uue logivoo**. Kui rakendus teeb päevas 1 miljon päringut, on sul päevas 1 miljon logivoogu. Sellise kardinaalsusega Loki enam ei toimi.

Sama probleem tekib, kui sildiks panna:

- IP-aadress (iga klient = uus voog)
- Kasutaja ID (iga kasutaja = uus voog)
- Ajatempel (iga sekund = uus voog)
- Pordi number (iga ühendus = uus voog)

### Reegel

Lihtne reegel: **silt kirjeldab, kust logi tuleb. Logi sisu jääb logireale.**

Head sildid kirjeldavad allikat ja on stabiilsed:

- `app` (nginx, api, payment-service)
- `env` (dev, staging, prod)
- `host` või `instance`
- `namespace` (Kubernetes)
- `region`

Halvad sildid on dünaamilised, potentsiaalselt piiramatud:

- `trace_id`, `request_id`, `session_id`
- `user_id`, `email`, `ip`
- `order_id`, `transaction_id`

Kui on vaja neid dünaamilisi välju **otsinguks**, siis Loki 3.0-st (2024) alates on olemas **Structured Metadata**. See on eraldi kiht (sildid-indeksis — metadata-otsitav-ent-indekseerimata — logi sisu-pakitud). `trace_id` ja `user_id` sobivad sinna. Laboris sellest detaili ei vaja — piisab, kui jätad meelde: **trace_id ei ole label**.

---

## 5. LogQL — päringukeel, mis meenutab PromQL-i

Kui Grafana UI-s küsid Lokist logisid, kirjutad **LogQL** päringu. Keel on tehtud PromQL-iga sarnaseks, et Prometheuse kogemus tuleks kasuks.

### Lihtne näide

```logql
{app="nginx", env="prod"}
```

Loe: "anna mulle kõik logivood, kus `app` on `nginx` ja `env` on `prod`". Tulemuseks on logiread. See on kõige lihtsam LogQL — ainult siltide filter.

### Filter sõne järgi

```logql
{app="nginx", env="prod"} |= "error"
```

Lisaks sildifiltrile kitsendame ridadeni, mis sisaldavad sõna "error". `|=` tähendab "sisaldab". Muud variandid: `!=` (ei sisalda), `|~` (regex).

### Parserid — neli tükki

Siiani vaatasime logisid **tavalise tekstina**. Sageli on logid aga **struktureeritud** — JSON, logfmt, või kindla mustriga tekst. Parser võtab logirea osadeks ja annab väljad, mida saab eraldi filtreerida.

**JSON parser.** Kui logi on `{"level":"error","user":"ann","duration":42}`:

```logql
{app="api"} | json | level = "error" and duration > 100
```

JSON parser teeb `level` ja `duration` väljad otsitavaks. Üsna puhas variant, kui logid juba JSON-is.

**Logfmt parser.** Kui logi on `level=error user=ann duration=42ms`:

```logql
{app="api"} | logfmt | level = "error"
```

Logfmt on Go-maailma "võti=väärtus" standard. Paljud Go-rakendused logivad nii.

**Pattern parser.** Kui logi on vabatekst **stabiilse struktuuriga** (nt `2026-04-25 10:23 ERROR user=ann request failed`):

```logql
{app="api"} | pattern `<_> <_> <level> <_>` | level = "ERROR"
```

`<_>` tähendab "jäta vahele", `<level>` tähendab "nimeta see väli level-iks". Pattern sobib hästi vanematele rakendustele, mis logivad vabateksti, aga alati samas formaadis.

**Regexp parser.** Täiesti ebastandardne tekst, kus pattern ei sobi. See jääb viimaseks valikuks — aeglasem ja tõrkealtim.

### Parseri valik lühidalt

| Logi formaat                         | Parser   |
|--------------------------------------|----------|
| `{"level":"error"}`                  | `json`   |
| `level=error duration=42ms`          | `logfmt` |
| Vabatekst stabiilse struktuuriga     | `pattern`|
| Täiesti ebastandardne                | `regexp` |
| Ühekordne kiire otsing, struktuurita | `|=`     |

Laboris teed osas 1 need neli harjutust Grafana ametlikul simulaatoril — enne kui oma Loki üldse üles paned. Nii on lihtsam LogQL-i tunnetus kätte saada ilma, et peaks samal ajal infrastruktuuri pärast muretsema.

---

## 6. Logidest metrika — hüpe tekstist numbriks

Loki oskab teha asja, mida Elasticsearch tavaliselt ei tee. LogQL lubab sul **logidest tuletada mõõdikuid** — logiridadest saad tavalise PromQL-laadse numbri, mida saab panna Grafana graafikule või siduda häiretingimusega.

Näide. Nginx logib iga päringu. Sind huvitab: **mitu 500-veateadet sekundis tuleb?**

```logql
sum(rate({app="nginx"} |= "500" [5m]))
```

Loe: "võta kõik nginx-logiread, filtreeri read, mis sisaldavad 500, loe need kokku viimase 5 minuti kohta ja jaga ajaga". Tulemus on `500`-vigu sekundis.

See on **sama tüüpi number kui Prometheus mõõdik**. Sellest saab teha:

- graafiku Grafanas ("vigade määr viimase tunni jooksul")
- häire (nt "kui üle 10/sekundis, anna teada")
- dashboard'i koos teiste mõõdikutega

Laboris teed seda osas 3 — võtad payment-teenuse logidest vigade määra, teed graafiku, ja paned **ühele ekraanile** Zabbixi triggeri (üleval, häire) ja Loki graafiku (all, logipõhine trend). Sama sündmus kahest küljest vaadatuna.

---

## 7. Alloy — agent, mis kogub ja saadab

Logid ei ilmu Lokisse iseenesest. Vaja on **agenti**, mis need kätte saab ja edasi saadab. Grafana ökosüsteemis on see **Grafana Alloy**.

Kuni 2024 oli Loki ametlik agent **Promtail** — lihtne ja konkreetne, tegeles ainult logidega. Grafana Labs otsustas selle asemel teha ühe laiema agendi: **Alloy**.

Alloy oskab:

- koguda logisid (nagu Promtail)
- koguda mõõdikuid (nagu Prometheus exporter)
- koguda trace'e (nagu OpenTelemetry collector)

Üks binaar, üks konfig, üks protsess — kolme eraldi agendi asemel. **Promtail on nüüd feature-freeze olekus**, uusi võimekusi sinna juurde ei tehta. Uutes paigaldustes on eelistatud Alloy.

Laboris kasutad Alloyd. Konfiguratsioon on sirgjooneline — mis faili lugeda, kuhu saata, mis sildid juurde panna. Mount'id host-masinast logifaili konteinerisse ja Alloy loeb seda pidevalt; iga uus logirida jõuab Loki-sse.

Oluline nüanss hilisemate päevade jaoks: **Alloy toetab OpenTelemetry standardit**. OpenTelemetry (OTel) on cloud-native observability kasvav standard. Loki ja Alloy on OTel-valmis — kui rakendus kirjutab OTel-formaadis, saab Alloy selle otse vastu võtta.

---

## 8. Praktiline hoiatus — Helm charts

Kui hakkad pärast kursust Kubernetesis Lokit paigaldama, satud üsna kiiresti Grafana Helm chart’ide otsa.

Google otsing annab **kolm erinevat Loki Helm chart'i**:

- `grafana/loki` — **see on 2026. aastal kasutatav variant**
- `grafana/loki-stack` — aegunud, enam ei uuendata
- `grafana/loki-distributed` — samuti aegunud

Paljud vanemad blogipostitused ja videod viitavad neile kõigile. Pärast koristustööde tegemist on seis lihtne: **kasuta `grafana/loki` chart’i**. See on ametlik ja hooldatud.

Sama mõte kehtib Alloy kohta — `grafana/alloy` (**mitte** `grafana/agent`, mis oli vana nimi).

---

## 9. Kokkuvõte

Viis asja, mis tasub sellest peatükist meelde jätta:

**1. Loki = logid + sildid.** Indekseerib ainult sildid, mitte sisu. Sellepärast on ta märgatavalt odavam kui Elasticsearch, aga sisu järgi otsimine on aeglasem.

**2. Silt kirjeldab, kust logi tuleb.** App, env, host, namespace. **Mitte** trace_id, user_id, IP — need kuuluvad logirea sisu, mitte labelite hulka.

**3. LogQL on PromQL-ile lähedane.** Siltide filter (`{app="nginx"}`) + tekstifilter (`|= "error"`) + parser (`json`, `logfmt`, `pattern`).

**4. LogQL-st saab ka mõõdikuid.** `rate({app="nginx"} |= "500" [5m])` annab 500-vigade määra sekundis — sobib graafikuks ja häireks.

**5. Alloy on uus vaikimisi agent.** Üks agent logide, mõõdikute ja trace'ide jaoks. Promtail jääb ajalukku.

Laupäeva teine pool kuulub Lokile. Osa 1 on LogQL brauseris, osa 2 on Loki + Alloy + Grafana stack, osa 3 on logist tuletatud mõõdik + finaal koos Zabbixiga.

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

    1) Zabbix loeb arve, mitte ridu. Ta ütleb "vigu on liiga palju", aga ei näita milliseid. Tsentraalne logiteenus (Loki, Elasticsearch) salvestab logid tervelt ja otsid sealt ridu, mitte ainult loendit. Need täiendavad üksteist.

    2) Elasticsearch indekseerib kogu teksti — iga sõna igas logireas läheb indeksisse. Otsing on väga kiire, aga kallis (indeks võib kasvada suuremaks kui andmed). Loki indekseerib ainult sildid, sisu pakitakse ja läheb odavasse objektimällu. Sisu järgi otsimine on aeglasem, aga kogukulu väiksem.

    3) Logivoog = logiridade kogum, millel on sama siltide komplekt. Kardinaalsus = logivoogude arv. Loki töötab hästi kuni ~100 000 voolu; sealt edasi läheb indeks liiga suureks, päringud ja kirjutamine aeglustuvad.

    4) `trace_id` on iga päringu jaoks erinev. Kui rakendus teeb 1 miljon päringut päevas, tekitab see 1 miljon logivoogu. See maht on Lokile liiast: indeks kasvab üle pea, päringud aeglustuvad. `trace_id` sobib Structured Metadata kihti, mitte labeliks.

    5) `json` parser. Näide: `{app="api"} | json | level = "error"`.

    6) `pattern` parser. Näide: `{app="api"} | pattern \`<_> <_> <level> <_>\` | level = "ERROR"`.

    7) Alloy kogub ühe agendina logisid, mõõdikuid ja trace'e. Promtail tegeles ainult logidega. Alloy asendab Promtaili, Grafana Agenti ja OpenTelemetry Collectori ühe binaarina. Grafana Labs enam Promtaili ei arenda, uusi paigalduseid tehakse Alloyga.

</details>

---

## Allikad

| Allikas             | URL |
|---------------------|-----|
| Grafana Loki docs   | <https://grafana.com/docs/loki/latest/> |
| Labels best practices | <https://grafana.com/docs/loki/latest/get-started/labels/bp-labels/> |
| Cardinality         | <https://grafana.com/docs/loki/latest/get-started/labels/cardinality/> |
| LogQL               | <https://grafana.com/docs/loki/latest/query/> |
| Grafana Alloy       | <https://grafana.com/docs/alloy/latest/> |
| Loki 3.0 release    | <https://grafana.com/blog/2024/04/09/grafana-loki-3.0-release/> |
| Structured Metadata | <https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/> |

**Versioonid:** Loki 3.7.1, Grafana Alloy 1.15.1, Grafana 12.4.3.

---

*Järgmine: [Labor: Loki](../../labs/02_zabbix_loki/loki_lab.md)*

--8<-- "_snippets/abbr.md"
