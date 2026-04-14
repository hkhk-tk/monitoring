# Päev 1: Monitooring, Prometheus ja Grafana

*Loengumaterjalid koolitajale ja osalejatele*

---

## Osa 1: Miks monitooring? (arutelu 15 min)

> **Koolitaja märkus:** Ära loe seda ette. Küsi grupi käest ja lase neil rääkida. Need inimesed TEAVAD miks monitoring oluline on. Sinu roll on struktureerida arutelu ja lisada raamistik.

### Sissejuhatav küsimus

*"Kuidas te praegu teate, et midagi on teie süsteemides valesti?"*

Lase igal osalejal lühidalt vastata. Kirjuta tahvlile märksõnad.

Tõenäolised vastused:
- "Kasutaja helistab" — reaktiivne
- "Zabbix saadab emaili" — automaatne aga ühetasandiline
- "Vaatan logisid" — manuaalne
- "Nagios/PRTG/muu annab teada" — legacy
- "Ei teagi enne kui midagi on katki" — aus

### Kolm sammast

```
┌─────────────┐  ┌─────────────┐  ┌─────────────┐
│   METRICS   │  │    LOGS     │  │   TRACES    │
│             │  │             │  │             │
│ Mitu?       │  │ Mida?       │  │ Kus?        │
│ Kui kiiresti?│  │ Mis juhtus? │  │ Mis teel?   │
│ Kui palju?  │  │ Millal?     │  │ Kus aeglane?│
│             │  │             │  │             │
│ Prometheus  │  │ Loki / ELK  │  │ Tempo /     │
│ Zabbix      │  │ Graylog     │  │ Jaeger      │
│ InfluxDB    │  │ Splunk      │  │ Zipkin      │
└─────────────┘  └─────────────┘  └─────────────┘
      ↑                ↑                ↑
      └────────────────┼────────────────┘
                       │
              Grafana / Kibana
              (visualiseerimine)
```

**Täna** ehitame metrics-samba üles. Järgmistel kordadel lisame logid ja trace'id.

### Monitoring vs Observability

**Monitoring** vastab küsimusele: "Kas süsteem on üleval?"

**Observability** vastab küsimusele: "Miks süsteem on aeglane?"

Erinevus: monitoring on eeldefineeritud kontrollid (kas disk on täis? kas teenus vastab?). Observability on võime uurida suvalist küsimust ilma et oleksid seda ette teadnud.

Selle kursuse jooksul liigume monitoringust observability poole.

---

## Osa 2: Prometheus arhitektuur (10 min, pärast Docker Compose üles panemist)

> **Koolitaja märkus:** Seleta PÄRAST kui nad on Prometheuse juba käivitanud ja näinud Targets lehte. "Nüüd kui te nägite et see töötab — seletan kuidas."

### Pull-mudel

```
                  ┌─────────────────┐
                  │   PROMETHEUS     │
                  │                 │
                  │  Scrapes every  │
                  │  15 seconds     │
                  │                 │
                  └──┬──────┬──────┬┘
                     │      │      │
              GET /metrics  │      │
                     │      │      │
                     ▼      ▼      ▼
              ┌──────┐ ┌──────┐ ┌──────┐
              │Node  │ │Node  │ │Nginx │
              │Exp.  │ │Exp.  │ │Exp.  │
              │:9100 │ │:9100 │ │:9113 │
              └──────┘ └──────┘ └──────┘
              mon-vm   target   target-web
```

Prometheus **tõmbab** (pull) andmeid target'itelt. Mitte target'id ei saada.

**Miks pull, mitte push?**

- Prometheus teab täpselt kes on üleval (kui ei saa vastust → masin on maas)
- Lihtne debugging — ava `/metrics` brauseris ja näed täpselt mida Prometheus näeb
- Ei vaja keerulist autentimist target'itel
- Skaleerub: lisa uus target → Prometheus hakkab automaatselt tõmbama

**Millal push on parem?** Lühiajalised job'id (batch), tulemüüri taga olevad masinad → siis kasutatakse Pushgateway'd. Aga 95% juhtudel pull on õige.

*Küsi: "Zabbix kasutab agente mis push'ivad andmeid serverile. Mis on selle lähenemise plussid ja miinused?"*

### TSDB — ajaridaandmebaas

Prometheus salvestab andmeid ajaridadena:

```
node_cpu_seconds_total{cpu="0", mode="idle"} @timestamp → väärtus
node_cpu_seconds_total{cpu="0", mode="idle"} @1713430800 → 123456.78
node_cpu_seconds_total{cpu="0", mode="idle"} @1713430815 → 123457.12
node_cpu_seconds_total{cpu="0", mode="idle"} @1713430830 → 123457.45
```

Iga 15 sekundi järel uus punkt. See on ajarida.

Prometheus TSDB on optimeeritud:
- Kiire kirjutamine (append-only)
- Kiire lugemine ajavahemiku järgi
- Tõhus tihendamine (compression)
- Vaikimisi 15 päeva retention

**Mitu andmepunkti see tähendab?**
3 target'it × ~500 metrikat × 4 punkti/min × 60 min × 24h × 15 päeva ≈ **~130 miljonit andmepunkti**

Ja see töötab 4GB VM-il. Prometheus on efektiivne.

---

## Osa 3: PromQL süvitsi (pärast baaspäringuid)

> **Koolitaja märkus:** Seda ei pea korraga läbi tegema. Kasuta osade kaupa — esmalt rate(), siis filteerimine, siis agregeerimine.

### Mõõdikutüübid

| Tüüp | Käitumine | Näide | Reegel |
|------|-----------|-------|--------|
| **Counter** | Ainult kasvab (v.a restart → 0) | `http_requests_total`, `node_cpu_seconds_total` | ALATI kasuta koos `rate()` või `increase()` |
| **Gauge** | Tõuseb ja langeb | `node_memory_MemAvailable_bytes`, `temperature` | Kasuta otse, ilma rate()'ita |
| **Histogram** | Jaotus bucket'ites | `request_duration_seconds_bucket` | Kasuta `histogram_quantile()` |
| **Summary** | Eelarvutatud kvantiilid | `go_gc_duration_seconds` | Loetakse otse, ei saa tagantjärele ümber arvutada |

### rate() — kõige olulisem funktsioon

```
Counter väärtus ajas:

150 ─────────────────────────────────── ●
                                      ╱
100 ──────────────────────── ●───────╱
                            ╱
 50 ─────────── ●──────────╱
              ╱
  0 ── ●─────╱
       t1    t2           t3        t4

rate() = (150 - 0) / (t4 - t1) = päringuid sekundis
```

Counter ise on absoluutarv mis ei ütle midagi. `rate()` teeb sellest kiiruse.

```promql
# VALE — counter väärtus ise on mõttetu
node_cpu_seconds_total{mode="idle"}

# ÕIGE — kasvu kiirus sekundis
rate(node_cpu_seconds_total{mode="idle"}[5m])
```

`[5m]` on "range vector" — vaatab viimase 5 minuti andmeid. Mida laiem aken, seda silutum graaf.

### increase() — rate() inimloetav vend

```promql
# Mitu päringut viimase tunni jooksul?
increase(http_requests_total[1h])
```

`increase()` = `rate()` × aeg. Sama loogika, aga annab absoluutarvu, mitte "sekundis".

### Label filtreerimine

```promql
# Täpne võrdlus
node_cpu_seconds_total{mode="idle"}

# Mitte-võrdne
node_cpu_seconds_total{mode!="idle"}

# Regex
node_filesystem_size_bytes{device=~"/dev/.*"}
node_filesystem_size_bytes{mountpoint=~"/|/home"}

# Mitu filtrit korraga (AND)
node_cpu_seconds_total{cpu="0", mode="user"}
```

### Agregeerimine

```promql
# Summa üle kõigi instantside
sum(rate(node_network_receive_bytes_total[5m]))

# Keskmine per masin
avg by(instance) (rate(node_cpu_seconds_total{mode="user"}[5m]))

# Top 3 CPU kasutuse järgi
topk(3, 100 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Mitu target'i on üleval?
count(up == 1)

# Minimaalne vaba kettaruum üle kõigi masinate
min(node_filesystem_free_bytes{mountpoint="/"} / 1024^3)
```

### Aritmeetika

```promql
# CPU kasutus protsendina
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Mälu kasutus protsendina
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Ketta täituvus protsendina
100 - (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)

# Võrguliiklus Mbit/s
rate(node_network_receive_bytes_total[5m]) * 8 / 1024 / 1024
```

---

## Osa 4: USE ja RED meetodid (Grafana dashboardi ajal)

> **Koolitaja märkus:** Seleta kui nad hakkavad dashboardi ehitama. "Ärge lihtsalt pange juhuslikke graafikuid — kasutage raamistikku."

### USE meetod (Brendan Gregg) — infrastruktuuri jaoks

Iga **ressursi** kohta (CPU, mälu, disk, võrk) küsi kolm küsimust:

| | CPU | Mälu | Disk | Võrk |
|---|---|---|---|---|
| **U**tilization (kasutus) | CPU % | RAM % | Disk I/O % | Bandwidth % |
| **S**aturation (küllastus) | Load average | Swap kasutus | I/O wait queue | Dropped packets |
| **E**rrors (vead) | — | OOM kills | Disk errors | Interface errors |

```promql
# USE näide: CPU
# U: kasutus
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
# S: küllastus
node_load1 / count by(instance) (node_cpu_seconds_total{mode="idle"})
# E: vead — CPU vigu tavaliselt ei ole

# USE näide: Mälu
# U: kasutus
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100
# S: küllastus
node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes
# E: vead
rate(node_vmstat_oom_kill[5m])
```

**Praktikas:** Ehita Grafana dashboard mis järgib USE meetodit. Igale ressursile üks rida, kolm paneeli (U, S, E).

### RED meetod (Tom Wilkie) — teenuste jaoks

Iga **teenuse** kohta (API, veebiserver, andmebaas) küsi:

| | Kirjeldus | PromQL näide |
|---|---|---|
| **R**ate | Päringuid sekundis | `rate(http_requests_total[5m])` |
| **E**rrors | Vigaste päringute % | `rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])` |
| **D**uration | Vastuse aeg (p95) | `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))` |

**Praktikas:** Nginx stub_status annab baasmetrikad. Päris RED meetodi jaoks oleks vaja nginx_exporter'it.

*Küsi grupile: "Kumba meetodit kasutaksite oma tööl? Miks?"*

---

## Osa 5: Alerting — signaal vs müra (Alertmanageri ajal)

> **Koolitaja märkus:** Securer OÜ hooldusjuht 2000 seadmega TEAB mis on alert fatigue. Lase tal rääkida.

### Alert'i anatoomia

```yaml
- alert: HighCpuUsage                              # Nimi
  expr: ... > 80                                    # Tingimus (PromQL)
  for: 2m                                           # Kui kaua peab kehtima?
  labels:
    severity: warning                               # Tõsidus
  annotations:
    summary: "CPU üle 80%: {{ $labels.instance }}"  # Inimloetav tekst
```

**`for: 2m`** on kriitiline! Ilma selleta saad alert'i iga lühiajalise spike peale. 2 minutit tähendab: "probleemi peab olema vähemalt 2 minutit enne kui teavitan."

### Hea alert vs halb alert

| Halb alert | Hea alert |
|-----------|----------|
| "CPU on 81%" | "Teenus X vastab aeglaselt (p95 > 2s)" |
| "Disk on 79% täis" | "Disk saab täis 4 tunni pärast praeguse tempoga" |
| Alert igal hommikul kell 3 (cron job) | Alert ainult anomaaliate puhul |
| 50 emaili päevas | 2-3 teavitust nädalas, iga üks vajab tegevust |

### Predict-tüüpi alert (edasijõudnud)

```promql
# Ketas saab täis järgmise 4 tunni jooksul?
predict_linear(node_filesystem_free_bytes{mountpoint="/"}[1h], 4*3600) < 0
```

`predict_linear()` ekstrapoleerib trendi. Kui praegu kulub 1GB/h ja vaba on 3GB, siis 3h pärast on täis.

**See on monitoring vs observability erinevus:** mitte "ketas on 90% täis" vaid "ketas SAAB täis kell 14:00."

### Alertmanageri routing

```yaml
route:
  group_by: ['alertname', 'severity']
  group_wait: 30s       # Oota 30s enne grupeerimist
  group_interval: 5m     # Ära saada sama gruppi tihemini kui 5 min
  repeat_interval: 4h    # Korda alert'i iga 4h, mitte iga minut
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'pager'   # Kriitilised → kohe teavita
    - match:
        severity: warning
      receiver: 'slack'    # Hoiatused → Slacki
```

*Küsi: "Kuidas teie organisatsioonis alertid routing'itakse? Kes saab öise teavituse?"*

---

## Osa 6: Recording rules (edasijõudnud, puhveraja jaoks)

> **Koolitaja märkus:** Kasuta kui aega jääb. Need inimesed jõuavad sinna.

Mõned PromQL päringud on rasked ja aeglased. Recording rules arvutavad need ette:

```yaml
# Lisa prometheus.yml rule_files sektsiooni
groups:
  - name: node_recording_rules
    interval: 15s
    rules:
      - record: instance:node_cpu_utilization:ratio
        expr: 1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))

      - record: instance:node_memory_utilization:ratio
        expr: 1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)

      - record: instance:node_filesystem_utilization:ratio
        expr: 1 - (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"})
```

Nüüd saad dashboardis kasutada `instance:node_cpu_utilization:ratio` ja see on kiire. Nimetamiskonventsioon: `tase:metrika:tüüp`.

---

## Osa 7: File-based service discovery (edasijõudnud, puhveraja jaoks)

Staatilised target'id `prometheus.yml` failis on demo jaoks OK. Päris elus:

```yaml
scrape_configs:
  - job_name: 'nodes'
    file_sd_configs:
      - files:
          - '/etc/prometheus/targets/*.json'
        refresh_interval: 30s
```

`targets/nodes.json`:
```json
[
  {
    "targets": ["192.168.100.140:9100", "192.168.100.141:9100"],
    "labels": {
      "env": "production",
      "team": "infrastructure"
    }
  }
]
```

Muuda JSON faili → Prometheus laeb 30s jooksul uued target'id. Ei pea Prometheust restartima.

*Securer OÜ kontekst: "Kuidas sa 2000 seadme IP-d hallatavaks teed? → file_sd + config management (Ansible genereerib JSON faili)."*

---

## Viited

- [Prometheus dokumentatsioon](https://prometheus.io/docs/)
- [PromQL cheat sheet](https://promlabs.com/promql-cheat-sheet/)
- [Brendan Gregg — USE Method](https://www.brendangregg.com/usemethod.html)
- [Tom Wilkie — RED Method](https://grafana.com/blog/2018/08/02/the-red-method-how-to-instrument-your-services/)
- [Awesome Prometheus alerts](https://samber.github.io/awesome-prometheus-alerts/)
- [Node Exporter dashboard 1860](https://grafana.com/grafana/dashboards/1860)
