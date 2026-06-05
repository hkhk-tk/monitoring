# Päev 5 (II moodul): Töökindlus ja vaadeldavuse käitamine

**Kursus:** Kaasaegne IT-süsteemide monitooring ja jälgitavus
**Kestus:** ~45 minutit (loeng)
**Tase:** Kesktase — eeldame, et tunned PromQL-i põhitõdesid (Day 1) ja oled näinud, kuidas alertimine töötab

---

## 🎯 Õpiväljundid

Pärast seda loengut oskad:

- Eristada SLI, SLO ja SLA mõisteid ja selgitada, mis on error budget
- Arvutada lihtsa SLO error budget'i ja selgitada, mida burn rate tähendab
- Kirjeldada intsidendireageerimise ja on-call protsesside põhielemente
- Selgitada, mis on Chaos Engineering ja miks see vaadeldavust kontrollib
- Kirjeldada, milliste piirangutega põrkad, kui vaadeldavust suure infrastruktuuri jaoks ehitad
- Põhjendada, miks vaadeldavuse kulu ise vajab jälgimist (observability FinOps)

---

## 1. Esimesest neljast päevast siia

Senised neli päeva olid tööriistadest: Prometheus, Zabbix, Loki, Elastic, TICK, ja äsja tracing. Sa oskad nüüd andmeid koguda ja näidata. Aga andmete kogumine on alles pool tööd. Teine pool on **mida sa nende andmetega teed, kui kell on kolm öösel ja midagi põleb** — ja kuidas üldse otsustada, mis on "põlemine" ja mis lubatud müra.

See moodul on käitamisest. Vähem konfiguratsioonifaile, rohkem otsuseid. Viis teemat: kuidas defineerida töökindluse eesmärgid (SLI/SLO), kuidas intsidentidele reageerida, kuidas süsteemi vastupidavust katsetada (Chaos Engineering), kuidas vaadeldavust suures mastaabis arhitektuurida, ja kuidas hoida selle kõige kulu kontrolli all.

---

## 2. Teema 1 — SLI, SLO ja Error Budget

Algame mõistetest, sest neid aetakse pidevalt segamini.

- **SLI (Service Level Indicator)** — mõõdetav näitaja teenuse käitumisest. Näiteks: "kui suur osa päringutest õnnestus ja vastas alla 500ms". See on number, mille sa mõõdad.
- **SLO (Service Level Objective)** — eesmärk selle SLI jaoks. Näiteks: "99,9% päringutest õnnestub ja vastab alla 500ms 30 päeva jooksul". See on siht, mille endale sead.
- **SLA (Service Level Agreement)** — lepinguline lubadus kliendile, tavaliselt SLO-st lõdvem, rahalise tagajärjega kui rikud.

SLI on mõõdik, SLO on siht, SLA on leping. Sisemiselt elad SLO-de järgi; SLA on see, mille pärast advokaadid muretsevad.

### Error budget — kõige praktilisem idee

Siit tuleb idee, mis muudab kogu mõtteviisi. Kui sinu SLO on 99,9% kättesaadavust, siis ülejäänud **0,1% on lubatud läbikukkumine**. See 0,1% on sinu **error budget** — eelarve, mille sa võid "kulutada".

Pane tähele numbrit: 99,9% kuus tähendab **43,2 minutit allakäiku kuus**.[^1] See pole stretch-eesmärk ega ideaal. See on lagi. Niikaua kui sul on eelarvet järel, võid julgelt deployda, eksperimenteerida, riskida. Kui eelarve on otsas, **külmutad feature-töö** ja keskendud stabiilsusele.[^2]

| SLO | Lubatud allakäik kuus | Lubatud allakäik aastas |
|-----|----------------------|------------------------|
| 99% | ~7,3 tundi | ~3,65 päeva |
| 99,9% ("kolm üheksat") | ~43,2 minutit | ~8,8 tundi |
| 99,99% ("neli üheksat") | ~4,3 minutit | ~52,6 minutit |
| 99,999% ("viis üheksat") | ~26 sekundit | ~5,3 minutit |

See tabel selgitab, miks "viis üheksat" maksab varanduse: 26 sekundit kuus tähendab, et sul ei tohi praktiliselt kunagi midagi katki minna. Enamiku ärirakenduste jaoks on 99,9% mõistlik; viit üheksat tasub nõuda ainult siis, kui sul on selleks tõeline põhjus ja raha.

### Burn rate — kui kiiresti eelarve põleb

Error budget on staatiline lagi. **Burn rate** ütleb, kui kiiresti sa seda kulutad. Burn rate 1 tähendab, et kulutad täpselt sellise tempoga, et eelarve saab otsa täpselt SLO-akna lõpus.[^3] Burn rate 5 tähendab viiekordset tempot — 30 päeva eelarve põleks ära 6 päevaga.

See on alertimise tuum. Vanasti seadistasid alarmi "kui vigade määr > X". Probleem: see lärmab kogu aeg ja sa kaotad usu alarmidesse. Burn rate annab nüansi:

| Olukord | Vigade määr | Burn rate | Eelarve otsas | Alarmi tase |
|---------|-------------|-----------|---------------|-------------|
| Normaalne | 0,05% | 0,5× | 60 päeva | — |
| Kerge halvenemine | 0,10% | 1,0× | 30 päeva | INFO |
| Mõõdukad probleemid | 0,30% | 3,0× | 10 päeva | WARNING |
| Tõsised probleemid | 0,60% | 6,0× | 5 päeva | CRITICAL (aeglane) |
| Suur intsident | 1,50% | 15× | 2 päeva | CRITICAL (kiire) |
| Kriitiline allakäik | 5,00% | 50× | 0,6 päeva | CRITICAL (kiire) |

(Allikas: SLO 99,9%, 30-päevane aken.[^4])

Google SRE workbook soovitab **mitme aknaga, mitme burn rate'iga** strateegiat: kutsu inimene kohe välja (page), kui burn rate > 14,4 ühe tunni aknas (2% kuueelarvest ära ühe tunniga); saada madalama prioriteediga tiket, kui burn rate > 6 kuue tunni aknas.[^5] Kiire põlemine → on-call inimese telefon heliseb. Aeglane põlemine → läheb järjekorda, lahendad tööajal.[^6]

**Miks sysadminile oluline:** see on otsene Prometheus + Alertmanager seadistus. SLI on `rate()` päring õnnestunud vs kõigi päringute suhtest, SLO on number sinu peas, error budget ja burn rate on recording rule'id ja alarmireeglid. Day 1 PromQL-i oskus + see mõtteviis = töötav SLO-dashboard Grafanas, OTel-instrumenteeritud teenuste mõõdikutest.[^7]

---

## 3. Teema 2 — Intsidentidele reageerimine ja on-call

Alarm käivitus. Mis nüüd? Töökindluse mõte pole ainult mõõta — see on **reageerida struktureeritult**, mitte paanikas.

On-call protsess on see, kes ja kuidas reageerib. Burn rate alarmid on kasulikud ainult siis, kui nad jõuavad **õige inimeseni õigel ajal**. Praktikas kaardistatakse burn rate eskaleerimispoliitikasse: kiire põlemine (>14,4×) läheb on-call inseneril otse, aeglane põlemine (>6× kuue tunni jooksul) madalama kiireloomulisusega järjekorda.[^8]

Intsidendireageerimise tüüpiline elukaar:

```
TUVASTUS        → alarm käivitub (burn rate, mitte üksik viga)
TRIAGE          → kui hull? kes peab teadma? mis on mõju?
LOKALISEERIMINE → kus see on? (siin tuleb mängu trace + log + metric korrelatsioon)
LEEVENDAMINE    → peata verejooks (rollback, scale, failover) — ENNE põhjuse leidmist
LAHENDAMINE     → tegelik parandus
POSTMORTEM      → mis juhtus, miks, mida muudame — ILMA süüdistamata
```

Kaks asja, mida rõhutada. Esiteks: **leevendamine enne lahendamist**. Kell kolm öösel ei pea sa teadma *miks* — pead peatama mõju. Rollback kõigepealt, juurpõhjus hommikul. Teiseks: **blameless postmortem**. Kui inimesi süüdistatakse, varjatakse vigu, ja sa kaotad õppimise. Eesmärk on süsteemi parandada, mitte süüdlast leida.

Siin seob kolm sammast end kokku. Alarm (metric) ütleb *et* midagi on; trace ütleb *kus*; log ütleb *mis täpselt*. Day 5 esimene moodul (tracing) ja see moodul kohtuvad just intsidendi keskel: kell kolm öösel on `trace_id`-järgi liikumine metrist trace'i ja logini see, mis vahet teeb 5-minutilise ja 4-tunnise lahenduse vahel.

**Miks sysadminile oluline:** Alertmanager ei ole ainult "saada e-mail". See on routing, grouping, silencing, eskaleerimine. On-call rotatsioon, runbook'id (mida teha kui X alarm), ja postmortem-kultuur on sama olulised kui tööriist ise.

---

## 4. Teema 3 — Chaos Engineering: vaadeldavuse kontrollimine

Sul on dashboardid, alarmid, SLO-d. Aga kas need **tegelikult töötavad**, kui midagi katki läheb? Ainus viis teada saada on midagi katki teha — kontrollitult.

Chaos Engineering on praktika, kus sa sihilikult tekitad süsteemis tõrkeid — tapad konteinereid, lisad võrgulatentsust, koormad CPU-d täis — et näha, kas süsteem käitub nii nagu arvasid ja kas sinu **vaadeldavus märkab seda**. Idee pärineb Netflixist, kelle "Chaos Monkey" tappis tootmises juhuslikult instantse, et sundida insenere ehitama vastupidavaid süsteeme.

Vaadeldavuse seisukohast on see test sinu monitooringule, mitte ainult rakendusele:

```
HÜPOTEES        → "kui tapan ühe maksevärava instantsi, peaks LB
                   suunama teisele ja SLO ei tohiks kannatada"
KATSE           → tapa üks instants (kontrollitult, väikese raadiusega)
VAATLUS         → kas alarm käivitus? kas dashboard näitas? kas trace
                   näitas failover'i? kas SLO burn rate liikus?
ÕPPETUND        → kui alarm EI käivitunud — sinu monitooring on pime
```

Kõige väärtuslikum tulemus on sageli see, kui Chaos-katse paljastab, et **sinu alarm ei käivitunudki**. Parem avastada see kontrollitud katses kella kahel pärastlõunal kui tegelikus intsidendis kella kolmel öösel. Reegel: alusta väikese raadiusega (blast radius), tootmise-lähedases keskkonnas, ja laienda alles siis, kui usaldad tulemusi.

**Miks sysadminile oluline:** dashboard, mida pole katsetatud, on lihtsalt arvamus. Chaos Engineering muudab "ma arvan, et meil on monitooring" → "ma tean, et meil on monitooring, sest ma katsetasin seda".

---

## 5. Teema 4 — Vaadeldavuse arhitektuur suurtele süsteemidele

Senised laborid jooksid ühel VM-il, paari konteineriga. Tootmises on lood teised. Kui sul on 70+ serverit (nagu mõnel meie kursuse osalejal tööl), tuhandeid konteinereid, kümneid teenuseid — siis vaadeldavuse arhitektuur ise muutub probleemiks.

Kolm piirangut, millega põrkad:

**Andmemaht.** Üks moodne süsteem genereerib gigabaite logisid ja miljoneid mõõdikuid päevas. Sa ei saa kõike igavesti hoida. Vastus on **kihistatud salvestus**: kuum andmestik (viimased päevad, kiire) eraldi, külm (vanad, odav objektisalvestus) eraldi. Loki ja Tempo on selleks ehitatud — indeks minimaalne, sisu objektisalvestuses.

**Kardinaalsus.** Day 2 Loki juures mainisime: kui paned `trace_id` või kasutaja-IP mõõdiku sildiks, plahvatab aegridade arv. Iga unikaalne sildikombinatsioon on uus aegrida. Suures süsteemis on see esimene asi, mis su Prometheuse mälu täis sööb. Distsipliin siltidega on arhitektuuri-küsimus, mitte detail.

**Pikaajaline salvestus ja kõrgkäideldavus.** Üks Prometheus ei skaleeru lõpmatuseni ega ela üle masina surma. Siin tulevad **Mimir, Thanos, VictoriaMetrics** — nad võtavad Prometheuse andmed, replikeerivad, hoiavad pikalt objektisalvestuses ja teevad päringud horisontaalselt skaleeritavaks. Tracing-poolel tegi Tempo 3.0 sama: eraldas loe- ja kirjutustee, et üks halb päring ei viiks tervet süsteemi alla.[^9]

| Vajadus | Väike süsteem | Suur süsteem |
|---------|---------------|--------------|
| Mõõdikud | üks Prometheus | Mimir / Thanos / VictoriaMetrics |
| Logid | Loki üksik | Loki klastrina, S3 taga |
| Traces | Tempo üksik | Tempo klastrina, sampling |
| Salvestus | lokaalne ketas | kihistatud: kuum + külm (S3) |

**Miks sysadminile oluline:** sama tööriistad (Prometheus, Loki, Tempo), aga klasterdatud, replikeeritud, objektisalvestuse taga. Arhitektuuri otsus tehakse enne kui andmemaht sind tabab — pärast on valus migreerida.

---

## 6. Teema 5 — Vaadeldavuse kulu ja FinOps

Viimane teema, mida sageli unustatakse, kuni arve saabub. Vaadeldavus ei ole tasuta. Iga mõõdik, mille salvestad, iga logirida, iga trace maksab — salvestuses, töötluses, ja eriti SaaS-platvormidel (Datadog, New Relic) päringutes.

Tekib paradoks: mida rohkem sa kogud, seda rohkem näed — aga seda rohkem maksad. Klassikaline lõks on **logide üle-kogumine**: DEBUG-tase tootmises, iga päringu täis-payload, kõik säilitatud aastaks. Arve kasvab, aga 99% sellest ei vaadata kunagi.

Observability FinOps on praktika, kus sa **jälgid vaadeldavuse enda kulu** ja optimeerid teadlikult:

- **Sampling** — ära salvesta kõiki trace'e. Tail-based sampling (Day 5 I moodul) hoiab aeglased ja vigased, viskab normaalsed ära. Säilitad signaali, mitte müra.
- **Säilitusajad (retention)** — kas sa tegelikult vajad 90 päeva DEBUG-logisid? Tihti piisab 7 päevast kuumast + 30 päevast külmast.
- **Kardinaalsuse kontroll** — vähem unikaalseid silte = vähem aegridu = vähem kulu. Sama distsipliin, mis päästis Prometheuse mälu, päästab ka arve.
- **Õige salvestustasand** — kuum (kallis, kiire) ainult värskele, vana objektisalvestusse (odav).

Ole siin aus turundusega: SaaS-platvormid lubavad "unified observability" ja "AI-põhist kuluoptimeerimist". Praktikas on suurim kokkuhoid lihtne distsipliin — ära kogu seda, mida sa ei vaata. Avatud lähtekoodiga virn (Prometheus + Loki + Tempo objektisalvestuse peal) on tihti oluliselt odavam kui SaaS, aga maksad selle eest oma ajaga (käitamine, hooldus). See on klassikaline build-vs-buy otsus, mitte tehniline vaid äriline.

**Miks sysadminile oluline:** "miks meie Datadogi arve kahekordistus?" on küsimus, mida sulle tööl esitatakse. Vastus on peaaegu alati kardinaalsus, üle-kogumine või vale säilitusaeg. Vaadeldavuse kulu jälgimine on sama mõõdikutöö, mida oled terve kursuse õppinud — lihtsalt suunatud sissepoole.

---

## 7. Kokkuvõte — mis on täna tähtis

**SLI mõõdab, SLO on siht, SLA on leping.** Sisemiselt elad SLO järgi.

**Error budget = 100% − SLO.** 99,9% kuus = 43,2 minutit lubatud allakäiku. Eelarve otsas → külmuta feature-töö.

**Burn rate ütleb, kui kiiresti eelarve põleb.** Mitme aknaga alarmid: kiire põlemine kutsub kohe välja, aeglane läheb järjekorda. See lõpetab alarmiväsimuse.

**Intsident: leevenda enne kui lahendad, postmortem ilma süüdistamata.** Rollback kõigepealt, juurpõhjus hommikul. Kolm sammast kohtuvad intsidendi keskel.

**Chaos Engineering katsetab sinu monitooringut.** Kui sihiliku tõrke ajal alarm EI käivitu, on su vaadeldavus pime. Parem teada katses kui intsidendis.

**Suur mastaap = samad tööriistad, klasterdatud.** Mimir/Thanos mõõdikutele, kihistatud salvestus, kardinaalsuse distsipliin. Otsus enne kui maht tabab.

**Vaadeldavus maksab — jälgi seda kulu.** Sampling, retention, kardinaalsus. Ära kogu seda, mida sa ei vaata.

---

## Allikad

### Ametlik dokumentatsioon ja standard
| Allikas | URL |
|---------|-----|
| Google SRE Workbook — Alerting on SLOs | https://sre.google/workbook/alerting-on-slos/ |
| Google SRE Book | https://sre.google/sre-book/ |
| Prometheus Alerting | https://prometheus.io/docs/practices/alerting/ |
| Grafana Mimir docs | https://grafana.com/docs/mimir/latest/ |

### Teooria ja praktika
| Allikas | URL |
|---------|-----|
| Error Budget in SRE: Complete Guide (2026) | https://isdown.app/blog/error-budget-sre |
| Understanding Error Budgets (Nobl9) | https://www.nobl9.com/service-level-objectives/error-budget |
| How to Build Burn Rate Alerts (2026) | https://oneuptime.com/blog/post/2026-01-30-sre-burn-rate-alerts/view |

### Praktiline
| Allikas | URL |
|---------|-----|
| SLO dashboard + burn rate Grafanas (2026) | https://oneuptime.com/blog/post/2026-02-06-slo-error-budget-burn-rate-grafana/view |
| Tempo 3.0 — eraldi loe/kirjutustee | https://grafana.com/blog/tempo-3-0-release-all-the-latest-features/ |

[^1]: IsDown (2026). *Error Budget in SRE: The Complete Guide.* https://isdown.app/blog/error-budget-sre
[^2]: IsDown (2026). *Error Budget in SRE: The Complete Guide.*
[^3]: OneUptime (2026). *How to Build Burn Rate Alerts.* https://oneuptime.com/blog/post/2026-01-30-sre-burn-rate-alerts/view
[^4]: OneUptime (2026). *How to Build Burn Rate Alerts.*
[^5]: IsDown (2026). *Error Budget in SRE: The Complete Guide.*
[^6]: Google SRE Workbook. *Alerting on SLOs.* https://sre.google/workbook/alerting-on-slos/
[^7]: OneUptime (2026). *SLO Status Dashboard with Error Budget Burn Rate Visualization.* https://oneuptime.com/blog/post/2026-02-06-slo-error-budget-burn-rate-grafana/view
[^8]: IsDown (2026). *Error Budget in SRE: The Complete Guide.*
[^9]: Grafana Labs (2026). *Tempo 3.0 release.* https://grafana.com/blog/tempo-3-0-release-all-the-latest-features/

---

*See moodul lõpetab kursuse: tööriistadest (Päev 1–5 I moodul) käitamiseni (Päev 5 II moodul). Sa oskad nüüd nii andmeid koguda kui ka otsustada, mida nendega teha.*
