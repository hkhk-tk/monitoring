# Päev 1: Monitooring, Logimine ja Vaatlus

*Iseseisev lugemine enne labi*

**Eeldused:** Linux CLI põhitõed, võrgunduse alused  
**Kestus:** ~30 minutit

---

## Õpiväljundid

Pärast seda loengut oskad:

- Selgitada, miks monitooring on IT-s eluliselt oluline — ja miks "kasutaja helistab" ei ole monitoring
- Eristada logimist, seiret ja vaatlust
- Kirjeldada observability kolme sammast: metrics, logs, traces
- Selgitada USE ja RED meetodeid ja kasutada neid õigetes kontekstides

---

## 1. Miks see üldse oluline on?

Alustame ausa küsimusega: kas monitooring on tüütu kohustus või päriselt kasulik?

Vastus selgub ühe looga. On reede, kell 18:00. Sinu ettevõte on just käivitanud Black Friday kampaania. Ja siis:

```
18:05 — Twitter: "Teie leht ei lae!"
18:07 — Email: "Maksed ei tööta!"
18:10 — CEO Slackis: "MIS TOIMUB?!"
18:12 — Sina: "...ma ei tea 😰"
```

Tulemus: kaks tundi downtime, 50 000 eurot kadunud müüki, kliendid vihased, CEO veel vihasem. Kõige hullem: sa ei teadnud, et midagi oli valesti, kuni kasutajad helistasid.

See pole hüpoteetiline. Amazon on arvutanud, et üks sekund latency'i kasvu maksab neile 1,6 miljardit dollarit aastas. Bolt, Wise, Pipedrive — Eesti uhkused — investeerivad monitoorimisse miljoneid. Mitte sellepärast, et see on lahe. Sellepärast, et ilma selleta on nad pimedad.

**Monitooring on teie süsteemi nägemine. Ilma selleta lendate ilma instrumentideta.**

---

## 2. Kolm mõistet, mida sageli aetakse segamini

### Logimine — süsteemi päevik

Logimine on sündmuste salvestamine. Iga kord kui midagi juhtub — kirjutatakse see üles.

```
2026-04-18T10:23:41Z INFO  [auth] User jaan@ettevote.ee logged in
2026-04-18T10:23:45Z ERROR [payment] Connection timeout to db-01 after 30s
2026-04-18T10:24:01Z FATAL [payment] All retry attempts failed, transaction aborted
```

Logid vastavad küsimusele: **mis juhtus ja millal?**

Log level'id aitavad filtreerida: `DEBUG` → `INFO` → `WARN` → `ERROR` → `FATAL`. Toodangus tavaliselt `INFO` või kõrgem.

Logide probleem on maht — gigabaite päevas. Ilma tsentraliseeritud lahenduseta (ELK, Loki) oled pime.

### Seire — numbrid ajas

Seire salvestab mõõdikuid pidevalt — aegridadena.

```
cpu_usage{host="web-01"} 45.2  @ 10:23:00
cpu_usage{host="web-01"} 89.1  @ 10:23:30  ← midagi juhtus!
cpu_usage{host="web-01"} 44.2  @ 10:24:00  ← lahenes
```

Seire vastab küsimusele: **kui palju ja kas see on normaalne?**

### Vaatlus — sügavam arusaamine

Vaatlus (observability) ühendab kõik kolm sammast täieliku pildi saamiseks:

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   METRICS   │  │    LOGS     │  │   TRACES    │
│             │  │             │  │             │
│ Kui palju?  │  │ Mis juhtus? │  │ Kus on      │
│ Kui kiire?  │  │ Millal?     │  │ kitsaskoht? │
│             │  │             │  │             │
│ Prometheus  │  │ Loki / ELK  │  │ Tempo/Jaeger│
└─────────────┘  └─────────────┘  └─────────────┘
```

Praktiline näide — kasutaja kaebab aeglast lehte:

- **Metrics** näitab: andmebaasi CPU on 100%
- **Logs** näitab: täistabeli skaneerimised iga sekund
- **Traces** näitab: konkreetne päring viibib andmebaasis 4.5 sekundit 5-st

Ilma kõigi kolmeta oled detektiiv ilma tõenditeta.

---

## 3. USE ja RED — mida üldse jälgida?

Tuhandete võimalike mõõdikute hulgast — mida valida? Kaks raamistikku aitavad.

### USE meetod — infrastruktuuriks

Brendan Gregg (Netflix) — iga ressursi kohta kolm küsimust:

- **U**tilization — kui suure osa ressursist kasutad?
- **S**aturation — kas miski ootab järjekorras?
- **E**rrors — kas tekivad vead?

| | CPU | Mälu | Ketas | Võrk |
|---|---|---|---|---|
| **U** | CPU % | RAM % | I/O aeg % | Bandwidth % |
| **S** | Load average | Swap kasutus | I/O järjekord | Dropped packets |
| **E** | — | OOM kills | Disk errors | Interface errors |

### RED meetod — teenusteks

Tom Wilkie (Grafana Labs) — iga teenuse kohta:

- **R**ate — päringuid sekundis
- **E**rrors — veaprotsent
- **D**uration — vastamisaeg

Bolt jälgib sõidupäringute RED meetrikaid reaalajas. Kui Rate langeb järsku — midagi on valesti.

### Google Four Golden Signals

Google SRE raamat — neli signaali katavad 80% probleemidest:

| Signaal | Kirjeldus |
|---------|-----------|
| **Latency** | Kui kiiresti teenus vastab |
| **Traffic** | Kui palju päringuid tuleb |
| **Errors** | Kui suur osa ebaõnnestub |
| **Saturation** | Kui lähedal on ressurss piirile |

Alusta nendest neljast. Kõik muu on bonus.

---

## 4. Monitoring vs Observability

**Monitoring** vastab küsimusele: "Kas süsteem on üleval?"

**Observability** vastab küsimusele: "Miks süsteem on aeglane ja kus täpselt?"

Monitoring on eeldefineeritud kontrollid — sa pead ette teadma mida kontrollida. Observability on võime uurida suvalist küsimust, mida sa ei osanud ette näha.

Selle kursuse jooksul liigume monitoringust observability poole:
- **Päev 1** — Metrics (Prometheus, Grafana)
- **Päev 2** — Logs (Loki) + Zabbix
- **Päev 3** — ELK Stack
- **Päev 4** — TICK Stack
- **Päev 5** — Traces (Tempo, OpenTelemetry)

---

## 5. Tööriistad — maastiku ülevaade

| Sammas | Tööriist | Millal |
|--------|----------|--------|
| Metrics | **Prometheus** | Dünaamilised keskkonnad, Kubernetes |
| Metrics | **Zabbix** | Suur infrastruktuur, legacy |
| Metrics | **InfluxDB** | IoT, kõrge kirjutussagedus |
| Logs | **Loki** | Prometheus ökosüsteem |
| Logs | **ELK Stack** | Keerulised otsingud, suur maht |
| Logs | **Splunk** | Enterprise, masinõpe |
| Traces | **Grafana Tempo** | LGTM stack |
| Traces | **Jaeger** | OpenTelemetry |
| Visualiseerimine | **Grafana** | Kõik eelnimetatud |

**Täna:** Prometheus + Grafana + Alertmanager — kõige levinum kombinatsioon Eesti ettevõtetes.

---

## 6. Intsidentide haldamine

Hoolimata parimast monitooringust juhtuvad intsidendid. Oluline on kuidas reageerid.

```
Tuvastamine → Klassifitseerimine → Uurimine → Lahendamine → Postmortem
```

**Kolm sammu veaotsinguks:**

1. **Detektiivitöö** — vaata logisid, graafikuid, kontrolli mis muutus viimati
2. **Juurpõhjus** — ära paranda sümptomit, leia põhjus
3. **Lahenda ja dokumenteeri** — rakenda, testi, kirjuta üles

SRE kultuuris on blameless postmortem standard — viga juhtus, kuidas süsteem saab paremaks?

---

## 7. Turvalisus ja vastavus

Logimine pole ainult tehniline küsimus. GDPR nõuab:

- Kõigi juurdepääsude logimine isikuandmetele
- Isikuandmete kustutamine nõudmisel
- Teavitamine andmelekkest 72 tunni jooksul

Wise, kes töötleb miljoneid finantstehinguid, peab audit logisid hoidma aastaid. GDPR trahvid ulatuvad 4%-ni aastakäibest — see on konkreetne äririsk.

---

## Kokkuvõte

**Kolm sammast:** Metrics (kui palju?), Logs (mis juhtus?), Traces (kus aeglustub?)

**USE** infrastruktuuri jaoks, **RED** teenuste jaoks — need ütlevad mida jälgida

**Monitoring** = "kas töötab?", **Observability** = "miks ei tööta ja kus täpselt?"

Järgmine: [Prometheus loeng](paev1-loeng.md)

---

## Allikad

| Allikas | Miks lugeda |
|---------|------------|
| [Google SRE raamat — peatükk 6](https://sre.google/sre-book/monitoring-distributed-systems/) | Four Golden Signals, hajutatud süsteemide monitooring — tööstusstandard |
| [Google SRE raamat (tasuta)](https://sre.google/books/) | Must-read kõigile kes haldavad tootmissüsteeme |
| [Brendan Gregg — USE Method](https://www.brendangregg.com/usemethod.html) | USE meetodi looja, Netflix/Oracle |
| [Tom Wilkie — RED Method](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/) | Grafana Labs CTO, RED meetodi autor |
| [Observability Engineering (O'Reilly)](https://www.oreilly.com/library/view/observability-engineering/9781492076438/) | Charity Majors — sügavam lugemine |
| [CNCF Observability Whitepaper](https://github.com/cncf/tag-observability/blob/main/whitepaper.md) | Cloud Native Computing Foundation ametlik seisukoht |
| [observability.dev](https://observability.dev/) | Praktilised näited |
