# Päev 2: Loki — logid Grafana ökosüsteemis

**Kestus:** ~20 minutit iseseisvat lugemist
**Eeldused:** Päev 1 (Prometheus, Grafana, PromQL alused), Zabbixi loengu kontseptsioonid
**Versioonid laboris:** Loki 3.2.1, Promtail 3.2.1, Grafana 11.1.0
**Viited:** [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/) · [LogQL docs](https://grafana.com/docs/loki/latest/query/)

---

## Õpiväljundid

Pärast selle materjali läbitöötamist osaleja:

1. **Selgitab** Loki rolli LGTM stackis ja selle arhitektuuri erinevust Elasticsearchist
2. **Põhjendab** miks labelite disain on Lokis kriitilise tähtsusega (cardinality)
3. **Eristab** LogQL-i kahte etappi — label selector ja log pipeline
4. **Kirjeldab** neli parserit (json, logfmt, pattern, regexp) ja teab millal kumba kasutada
5. **Mõistab** kuidas logist metrika teha (`rate()`, `count_over_time`) ja miks see on oluline

---

## 1. Puuduv tükk

Eile ehitasid Prometheuse — sa näed **numbreid**. CPU 87%, mälu 2.1 GB, päringuid 1200/s. Dashboard näitab spike'i kell 14:30.

Aga mida sa nüüd teed? SSH serverisse, `grep "error" /var/log/app.log`, kerid läbi tuhandeid ridu. Kui servereid on 50, kordad seda 50 korda. See on 2003. aasta tööprotsess 2026. aasta infrastruktuuril.

Loki toob logid Grafanasse. Sama koht kus sa juba vaatad metrikaid, näed nüüd ka logisid. Kliki graafikul spike'il, näed kohe mis logid sel hetkel tulid. See pole mugavus — see on **observability teine sammas** (metrics + **logs** + traces).

---

## 2. Loki vs Elasticsearch — kaks erinevat filosoofiat

Elasticsearch (ELK stack, päev 3) indekseerib **kogu logi sisu**. Iga sõna, iga number igas logis on otsitav. See on võimas — mis tahes otsingut saad teha sekundiga.

Loki indekseerib **ainult labeleid**. Logi sisu ise hoitakse lihtsalt tihendatud tekstina. Otsimiseks filtreerid labelite järgi õige voo välja ja seejärel grep'id sisu sees.

```
Elasticsearch:
  Logirida → iga sõna indekseeritud → otsing O(1)
  Hind: palju RAMi, palju ketast, keeruline klaster

Loki:
  Logirida → ainult labelid indekseeritud → otsing: label filter + brute-force sisu sees
  Hind: vähe RAMi, vähe ketast, lihtne ülesehitus
```

### Miks keegi valib Loki?

Elasticsearch on nagu raamatukogu kus iga raamat on sõnahaaval kataloogitud. Loki on nagu raamatukogu kus raamatud on riiulitel teema ja autori järgi, aga sisu leidmiseks pead lehitsema.

Praktikas: enamik logi-otsinguid on kujul "näita mulle **payment** teenuse **ERROR** logid viimase tunni jooksul". See on labelite filter (teenus + tase) + ajavahemik. Loki teeb seda kiiresti, sest labelid on indekseeritud ja ajaga piiratud skaneerimismaht on väike.

Kogu sisu otsing ("leia kõik logid mis sisaldavad sõna X kõigist teenustest kogu ajaloost") on Lokis aeglane. Elasticsearchis kiire. Aga kui tihti sul seda tegelikult vaja on?

| Kriteerium | Loki | Elasticsearch |
|-----------|------|---------------|
| RAM nõue | Väike (~256 MB) | Suur (GB-d) |
| Hoidla kulu | Odav (tihendatud tekst) | Kallis (indeksid) |
| Otsing labelite järgi | Kiire | Kiire |
| Täistekstiotsing | Aeglane | Kiire |
| Grafana integratsioon | Natiivne | Plugin |
| Keerukus | Lihtne | Keeruline klaster |

---

## 3. Labelid — Loki kõige tähtsam kontseptsioon

Lokis on label andmevoo identifikaator. `{job="applog", service="payment", level="ERROR"}` on üks voog. Iga unikaalne labelite kombinatsioon loob uue voo.

### Cardinality lõks

Ahvatlev on teha label igast asjast: `{trace_id="abc123"}`. Aga trace_id on unikaalne iga päringu kohta — tuhandeid unikaalseid väärtusi. Tulemus: tuhandeid vooge, Loki indeks paisub, päringud aeglustuvad.

**Reegel:** labelisse pane ainult väärtused, millest on kuni ~100 unikaalset varianti.

Hea label: `service` (5 väärtust), `level` (3 väärtust), `env` (2 väärtust), `region` (3 väärtust).

Halb label: `trace_id`, `user_id`, `request_id`, `ip_address`, `url_path`.

Unikaalsed identifikaatorid kuuluvad logi **sisu** sisse, mitte labelitesse. Neid saab otsida `|=` või parseri abil.

---

## 4. LogQL — kahe-etapiline päringukeel

LogQL koosneb kahest osast: **label selector** valib voo, **log pipeline** filtreerib ja parsib selle voo sees.

```logql
{job="applog", level="ERROR"}  |  pattern `<_> [<_>] [<service>] <_>`  |  service="payment"
└──── label selector ──────┘     └──────────── log pipeline ────────────────────────────┘
```

### Label selector — `{...}`

See on nagu Prometheuse label filter. `{job="applog"}` valib kõik read mis tulid `applog` job'ist.

### Log pipeline — `| ...`

Pärast label selector'it tulevad filter'id ja parserid:

**Sisu filter:** `|= "ERROR"` (sisaldab), `!= "test"` (ei sisalda), `|~` (regex)

**Parser:** teisendab struktureerimata teksti labeliteks. Neli valikut:

| Parser | Sisend | Millal |
|--------|--------|--------|
| `json` | `{"level":"error","msg":"fail"}` | JSON-logid |
| `logfmt` | `level=error msg=fail` | Key=value logid |
| `pattern` | Vabatekst | Kõige levinum, kiire, loetav |
| `regexp` | Vabatekst | Keerulised formaadid |

`pattern` on tavaliselt esimene valik. Mall: `<nimi>` püüab labeli, `<_>` ignoreerib.

```logql
{job="applog"} | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<_>`
```

Pärast parsimist saad filtreerida labelite järgi: `| level="ERROR" | duration > 100`.

---

## 5. Logist metrika — miks see on oluline

Logid ei pea jääma tekstiks. Loki saab lugeda ridu, arvutada kiirusi, grupeerida — sama mis Prometheus, aga allikas on logi, mitte `/metrics`.

```logql
# Mitu ERROR rida sekundis iga teenuse kohta
sum by (service) (
  rate(
    {job="applog"}
      | pattern `<_> [<level>] [<service>] <_>`
      | level="ERROR"
      [5m]
  )
)
```

Tulemus on number — Grafanas graafik. Sa just teisendad logi metrikaks.

**Miks see on oluline?** Mitte igal rakendusel pole `/metrics` endpoint'i. Aga logisid kirjutab iga rakendus. Kui saad logist metrika — saad monitoorida kõike.

See on ka alus **log-based alert'idele**: kui error rate ületab künnise, käivitu. Mitte numbri, vaid teksti põhjal — aga arvutatuna numbriks.

---

## 6. LGTM stack — kuhu Loki paigutub

Grafana Labs ehitab terviklahendust mille nimi koosneb neljast tähest:

```
L — Loki       (logid)        ← täna
G — Grafana    (visualiseering) ← eile
T — Tempo      (trace'd)       ← päev 5
M — Mimir      (metrikad)      ← Prometheuse pikaajaline hoidla
```

Eile ehitasid G + M osa (Grafana + Prometheus). Täna lisad L (Loki). Päeval 5 tuleb T (Tempo). Koos moodustavad need täieliku observability platvormi — kõik kolm sammast ühes kohas, omavahel seotud.

See "omavahel seotud" on võtmekoht: Grafana dashboardil kliki metrika spike'il → avanevad selle aja logid (Loki). Logis kliki trace_id-l → avaneb trace (Tempo). Trace'is kliki spannil → näed selle teenuse logisid. Üks klikk viib ühelt sambalt teisele.

Päev 3 vaatame ELK-i — teistsugune filosoofia, teistsugune ökosüsteem. Päev 4 TICK stack — veel üks lähenemine. Kursuse lõpuks on sul tervikpilt.

---

## Allikad

| Allikas | URL | Miks oluline |
|---------|-----|--------------|
| Loki dokumentatsioon | [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/) | Ametlik allikas |
| LogQL spetsifikatsioon | [grafana.com/.../query](https://grafana.com/docs/loki/latest/query/) | Päringukeel |
| Pattern parser | [grafana.com/.../pattern](https://grafana.com/docs/loki/latest/query/log_queries/#pattern) | Laboris kasutusel |
| LogQL simulator | [grafana.com/.../analyzer](https://grafana.com/docs/loki/latest/query/analyzer/) | Harjutamine brauseris |
| Promtail konfig | [grafana.com/.../promtail](https://grafana.com/docs/loki/latest/send-data/promtail/configuration/) | Logide kogumine |
| Loki vs Elasticsearch | [grafana.com/blog](https://grafana.com/blog/2020/05/12/an-only-slightly-biased-comparison-of-loki-and-elasticsearch/) | Võrdlus (Grafana vaatepunkt) |

---

*Järgmine: [Loki labor](../labs/02_zabbix_loki/loki_lab.md)*
