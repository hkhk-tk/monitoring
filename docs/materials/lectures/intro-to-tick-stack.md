# TICK Stack — Aegreade monitooring

## Miks me seda õpime?

Tunned ilmselt juba Prometheust ja Grafanat. Need töötavad suurepäraselt Kubernetese ja mikroteenuste jaoks. Aga kujuta ette teistsugust maailma — tehast tuhandete sensoritega, igaüks saadab temperatuuri või vibratsiooni iga sekund. Miljoneid andmepunkte päevas. Või Bolti sõidud: GPS-koordinaadid, kiirus, aku tase pidevas vormis.

Sellist andmevoogu nimetatakse **aegreadateks** (time series data). Prometheus saab mingi määrani hakkama, aga tööstuses — Tesla tootmisliinidest Siemensi tuulikuteni, NASA rakettidest Starshipi robotkulleriteni — domineerivad **spetsialiseeritud aegreade andmebaasid**. Kõige populaarsem neist on InfluxDB, mille populaarsus DB-Engines edetabelis on kolm korda kõrgem kui lähima konkurendi oma.

Eesti kontekstis on see relevantne — Skeleton Technologies, Starship, Bolt, kõik töötavad aegreadatega. TICK Stack on tööturul hinnatud oskus.

Tänane tund: mis see on, kuidas see arenes, ja miks laboris kasutame just **InfluxDB 3 Core**'i.

---

## Mis on aegreadata?

Tavaline andmebaas (MySQL, PostgreSQL) on ehitatud tehingute jaoks. E-poes klient teeb tellimuse, laoseis muutub — sündmust võib hiljem muuta või kustutada.

Aegreadata on fundamentaalselt erinev. Temperatuurisensor ütleb iga 10 sekundi tagant "praegu 23.5 kraadi". Vanu näite ei muudeta — see **OLI** sel hetkel 23.5. Sa ainult lisad uusi punkte, ja sind huvitab peamiselt "mis juhtus ajas".

| Tavaline andmebaas | Aegreade andmebaas |
|--------------------|---------------------|
| Üksikud tehingud | Pidev andmevoog |
| Andmeid muudetakse | Ainult lisatakse |
| "Mis on praegune seis?" | "Mis juhtus ajas?" |
| Sadu kirjutamisi sekundis | Miljoneid kirjutamisi sekundis |

Kui proovid miljoneid mõõtmisi sekundis MySQL-i panna, see lihtsalt ei tööta. Mitte sellepärast, et MySQL oleks halb — lihtsalt valedele tööle loodud. Sama kui kruvikeerajaga naela lüüa.

---

## Kuidas TICK Stack sündis

2012. Paul Dix töötab San Franciscos monitooringufirmas ja lööb pead vastu seina — tavalised andmebaasid ei skaleeru nende kasutusel. Ta otsustab: "Teen selle, mida pole olemas." 2013 sünnib **InfluxDB** (sõnast "influx" — sissevool, andmed voolavad sisse).

Andmebaasist üksi ei piisa. Kuidas andmed sinna saavad? Kuidas neid näha? Kuidas hoiatusi seada? Järgmistel aastatel ehitavad nad välja ökosüsteemi:

- **T**elegraf — agent, mis jookseb serveris ja kogub andmeid (üle 300 plugini: CPU, Docker, MQTT, Modbus, mida iganes sensor)
- **I**nfluxDB — andmebaas ise
- **C**hronograf — veebiliides graafikuteks
- **K**apacitor — hoiatuste mootor ("kui CPU >90% üle 5 minuti, saada email")

Nii sündis **TICK Stack** — nelja komponendi eesnimede järgi.

---

## Kolm ajastut

Stack on aastatega oluliselt muutunud. **InfluxData ise** ütleb ametlikus Platform-dokumentatsioonis:

> *"The InfluxDB 2 platform **consolidates** InfluxDB, Chronograf, and Kapacitor from the InfluxData 1.x platform into a single packaged solution."* — [docs.influxdata.com/platform](https://docs.influxdata.com/platform/)

Ehk "TICK Stack" kui termin on ametlikult **1.x ajastu mõiste**. 2.x-s konsolideeris InfluxData kolm komponenti üheks. Ja 2024-st on juba järgmine põlvkond.

```
  1.x AJASTU             |   2.x AJASTU             |   3.x AJASTU (meie labi)
  ─────────────          |   ─────────────          |   ──────────────────────

  ┌──────────┐           |   ┌──────────────────┐   |   ┌──────────────┐
  │ Telegraf │           |   │   Telegraf       │   |   │   Telegraf   │
  └────┬─────┘           |   └────┬─────────────┘   |   └────┬─────────┘
       ▼                 |        ▼                 |        ▼
  ┌──────────┐           |   ┌──────────────────┐   |   ┌──────────────┐
  │ InfluxDB │           |   │   InfluxDB 2.x   │   |   │ InfluxDB 3   │
  │   1.x    │           |   │   + UI           │   |   │   Core       │
  └────┬─────┘           |   │   + Tasks/Checks │   |   └────┬─────────┘
       ▼                 |   └──────────────────┘   |        ▼
  ┌────┴─────┐           |                          |   ┌──────────────┐
  ▼          ▼           |   (C ja K pole surnud,   |   │ InfluxDB 3   │
┌──────┐ ┌──────┐        |    aga konsolideeritud   |   │  Explorer    │
│Chron.│ │Kapa. │        |    2.x UI ja Tasks       |   │  (eraldi)    │
└──────┘ └──────┘        |    sisse)                |   └──────────────┘
```

**Aprill 2026** InfluxData jagab oma tooted nii:

| Kategooria | Tooted |
|-----------|--------|
| **Peatooted** | InfluxDB 3 Core/Enterprise, Telegraf, InfluxDB 3 Explorer |
| **Muud tooted** | InfluxDB 2.x, InfluxDB 1.x, Chronograf, Kapacitor |

Chronograf ja Kapacitor pole surnud — neid hooldatakse ja neil on palju kasutajaid legacy 1.x süsteemides. Aga InfluxData neid enam peatoodetena ei positsioneeri.

Meie laboris **InfluxDB 3 Core + Telegraf + Explorer**. Põhjused: 27. mail 2026 osutab Docker `influxdb:latest` just 3 Core'ile — see on uus standard järgmiseks 3-5 aastaks. Tööturul kohtad siiski kõiki kolme — 1.x tööstuses, 2.x enamikus ettevõtetes, 3.x tulekul.

---

## Andmemudel

Terminoloogia on kolmes ajastus erinev, aga **idee on sama**: kategooria, indekseeritud tag'id filtreerimiseks, numbrilised field'id väärtustena, ajatempel iga punkti juures.

| Kontseptsioon | 1.x | 2.x | 3.x (meie labi) |
|---------------|-----|-----|------------------|
| Ülemine tase | database + retention policy | organization + bucket | **database** |
| Kategooria | measurement | measurement | **table** |
| Indekseeritud sildid | tags | tags | tags |
| Väärtused | fields | fields | fields |

Üks andmepunkt line protocol vormingus:

```
cpu,host=server01,region=tallinn usage_user=23.5 1705312200000000000
│   └── tag'id                   └── field        └── ajatempel (ns)
└── tabel
```

**Reegel:** tag'idesse pane asjad, mille järgi filtreerid (server, regioon, teenuse nimi) — tag'id on indekseeritud, filtreerimine kiire. Field'idesse pane numbrilised väärtused (protsent, temperatuur, kiirus) — neid ei indekseerita. Valesti disainitud mudel = aeglased päringud.

---

## Päringukeeled

InfluxData on põhjustanud natuke segadust, sest igal versioonil on erinev keel:

**1.x — InfluxQL** (SQL-sarnane, oma süntaksiga):
```sql
SELECT mean(usage_user) FROM cpu WHERE time > now() - 1h GROUP BY time(1m)
```

**2.x — Flux** (funktsionaalne, "torude" süsteem):
```flux
from(bucket: "monitoring")
  |> range(start: -1h)
  |> filter(fn: (r) => r._measurement == "cpu")
  |> aggregateWindow(every: 1m, fn: mean)
```

**3.x — SQL** (peamine) + InfluxQL (tagasi-ühilduvuseks). **Flux on maha jäetud.**
```sql
SELECT AVG(usage_user)
FROM cpu
WHERE time > now() - INTERVAL '1 hour'
GROUP BY DATE_BIN(INTERVAL '1 minute', time)
```

Meie labi kasutab SQL-i. Miks see on hea muudatus:
- SQL oskab iga IT-inimene — universaalne oskus
- Parem ülekantavus teistele töödele (PostgreSQL, MySQL, BigQuery)
- InfluxData enda suund tulevikuks

Kui satud tööle 1.x või 2.x süsteemi, õpid vastava keele juurde. Kontseptsioonid (agregeerimine, aja-aknad, tag-filtreerimine) on kõigis kolmes samad — erinev vaid süntaks.

---

## Kokkuvõte

Aegreadata on pidev andmevoog ajatempliga, ja tavalised SQL-andmebaasid ei tule sellega toime. InfluxData alustas 2013 klassikalise nelja-komponentse TICK Stack'iga (T+I+C+K), konsolideeris 2020 InfluxDB 2.x-sse, ja on nüüd üle liikumas InfluxDB 3-le. Järgmises tunnis ehitame just selle uusima versiooni üles.

---

## 💭 Mõtle

1. Mille poolest erineb aegreadata sinu igapäevatöös tavalistest andmebaasi andmetest — kus su praeguses süsteemis aegread juba tekivad?
2. Su keskkonnas: kui hakkaksid mõõdikuid pikaajaliselt hoidma, kas Prometheus piisab või tuleks eraldi TSDB? Mille järgi otsustaksid?
3. Kui kohtaksid tööl 1.x või 2.x süsteemi — mis on esimene asi, mida peaksid päringukeele juures ümber õppima?
