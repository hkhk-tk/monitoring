# Observability trendid 2026

*Lisalugemine päev 5 juurde. Loengu Osa V andis lühikokkuvõtte; siin sügavamalt.*

Neli päeva ehitasid tööriistu. See peatükk astub sammu tagasi: kuhu valdkond liigub, mida tasub karjääris jälgida, ja kus on turundus paksem kui sisu. Sysadmini vaatest, ilma luiketamiseta.

---

## 1. Konsolideerimine — eraldi tööriistadest platvormideks

Kursuse jooksul nägid eraldi tööriistu: Prometheus mõõdikuteks, Loki logideks, Tempo jälgedeks, Zabbix, OpenSearch. Iga üks oma UI, oma päringukeel, oma agent. See on **best-of-breed** lähenemine — vali igale tööle parim tööriist.

Turg liigub teises suunas: **single pane of glass**, üks platvorm kõigele. Grafana koondab LGTM-i ühte kogemusse. OpenSearch pakub observability-moodulit logide, mõõdikute ja jälgede peale. Datadog, New Relic ja Dynatrace müüvad „kõik ühes" SaaS-platvorme.

Kumb võidab? Mõlemad jäävad. Suured organisatsioonid, kus on tiimid igale signaalile, jäävad sageli best-of-breed'i juurde, sest paindlikkus on tähtsam. Väiksemad ja need, kes tahavad vähem hooldust, lähevad platvormi peale. Tähtis muutus on, et **integratsioon on müügiargument** — keegi ei taha enam kolme eraldatud tööriista, mille vahel käsitsi ID-sid kopeerida. Korrelatsioon (mida lab Osa 4 näitas) on muutunud baasootuseks, mitte boonuseks.

Tööl tähendab see: kui valid uut tööriista, küsi „kui hästi ta teiste signaalidega seostub", mitte ainult „kui hea ta oma signaalis on".

---

## 2. OpenTelemetry kui vaikevalik

Päev 2 oli Promtail, päev 4 Telegraf — kumbki oma agent, oma vorming. OTel (loeng Osa II) on koondamas neid üheks standardiks. See pole hüpe, vaid aeglane nihe, aga suund on selge: **uued süsteemid alustavad OTel-ist**.

Miks see oluline: kui rakendus on OTel-iga instrumenteeritud, on backend vahetatav ilma koodi puutumata. See lõhub vendor lock-in'i instrumenteerimise tasemel. Vendor müüb sulle ikka oma backend'i ja UI, aga ei saa sind enam lukustada sellega, et „meie agent on su koodi sees".

Praktiline tähelepanek: vanad süsteemid jäävad oma agentide peale veel aastateks. Sa kohtad tööl mõlemat — legacy vendor-agendid ja uued OTel-torud. Oskus mõlemast aru saada on väärtuslikum kui usk, et OTel on kõik juba üle võtnud. Ta pole.

---

## 3. AI + jälgitavus — kus on sisu, kus turundus

Siin on praegu kõige paksem turunduskiht. Müüakse „agentic AI vähendab MTTR-i 90%", „AI leiab juurpõhjuse automaatselt", „enesetervendavad süsteemid". Vaatame ausalt, mis tegelikult töötab ja mis mitte.

**Mis töötab praegu:**

- **Anomaaliatuvastus.** Mustri-õpe normaalsest käitumisest ja hälbe märkamine — see on küps. Aitab leida „midagi on teisiti" ilma käsitsi läve seadmata.
- **Lihtsate juhtumite triaaž.** Disk täis, OOM-kill, ilmne latentsuspiik — siin AI-soovitus säästab aega ja eksib harva.
- **Logide kokkuvõte.** Tuhande logirea tihendamine „mis siin juhtus" kokkuvõtteks — kasulik esmaseks pilguks.

**Mis ei tööta veel:**

- **Keeruliste hajutatud bugide juurpõhjus.** Kui viga tuleb kolme teenuse koosmõjust ja äriloogikast, ei mõista AI konteksti. Ta viitab, kuhu vaadata, aga lahendaja jääb inimene.
- **Tegelik enesetervendus tootmises.** Automaatne parandus eeldab usaldust, mida enamik tiime kriitilistele süsteemidele ei anna — sama põhjus, miks Wazuhi Active Response (päev 4) on kahe teraga mõõk.

Reegel, mida karjääris kasutada: iga kord, kui näed protsenti („vähendab X% võrra"), küsi **kelle juhtumitel ja mis tingimustel**. Demos lihtsa juhtumiga 90% on tõsi; sinu keerulises tootmises võib olla 20%. Turundus ei valeta numbriga — ta jätab konteksti ütlemata.

---

## 4. Kardinaalsus ja kulu — vaikne piirang

Päev 4 mainis kardinaalsust tag-disaini juures: liiga palju unikaalseid silte (nt `trace_id` mõõdiku sildiks) teeb andmebaasi aeglaseks ja kalliks. 2026 on see muutumas keskseks oskuseks, mitte servamärkuseks.

Põhjus on lihtne: mida rohkem signaale ja silte kogud, seda rohkem salvestust ja arvutust maksad. Pilve-observability arved on paljudes organisatsioonides kasvanud kiiremini kui andmemaht — sest kardinaalsus plahvatab, kui igale päringule lisada uus dimensioon. Mõni tiim avastab, et nende Datadogi arve on suurem kui serverite oma.

Suund on **teadlik kogumine**: mitte „kogu kõik igaks juhuks", vaid „kogu see, mida tegelikult pärid". See tähendab sämplimist (jälgedest hoitakse osa, mitte kõiki), agregeerimist serva pool (Collector tihendab enne saatmist) ja siltide distsipliini. Sysadmini oskus, mis otse rahasse läheb.

Tööl tähendab see, et „lisame veel ühe sildi" pole tasuta — iga uus dimensioon korrutab seeriate arvu. Enne kui lisad, küsi, kas sa selle järgi tegelikult kunagi pärid.

---

## 5. Mida sellest karjääri jaoks kaasa võtta

**OTel oskus kandub edasi.** Kui õpid OpenTelemetry, ei õpi sa ühe vendori tööriista, vaid standardi, mis töötab kõigi backend'idega. See on parim ajainvesteering selles valdkonnas.

**Korrelatsioon on baasootus.** Kolm signaali eraldatuna pole enam piisav. Oska liikuda mõõdikult logile ja jäljele — see eristab inseneri, kes lahendab probleemi minutitega, sellest, kes kammib logisid tundide kaupa.

**SLO on ühine keel.** Tehnika ja äri räägivad SLO kaudu. Oskus tõlkida „p99 latentsus" → „lubasime 99,9%, eelarve on alles" teeb sinust insenerist, keda juhtkond kuulab.

**Ole AI-väidete suhtes kaine.** Mitte tõrjuv — anomaaliatuvastus ja triaaž töötavad tõesti. Aga küsi alati konteksti numbri taga. See hoiab sind nii ülevoolavast hype'ist kui pimedast eitusest.

**Kardinaalsus on raha.** Iga silt maksab. Teadlik kogumine on oskus, mis muutub väärtuslikumaks, mida kallimaks pilve-observability läheb.

---

## Allikad

| Allikas | URL |
|---------|-----|
| OpenTelemetry — what is OTel | <https://opentelemetry.io/docs/what-is-opentelemetry/> |
| CNCF observability maastik | <https://landscape.cncf.io/> |
| Google SRE — SLO ja veaeelarve | <https://sre.google/sre-book/service-level-objectives/> |
| Grafana — kardinaalsus ja kulu | <https://grafana.com/docs/loki/latest/get-started/labels/cardinality/> |
| Grafana stack ülevaade | <https://grafana.com/about/grafana-stack/> |

--8<-- "_snippets/abbr.md"
