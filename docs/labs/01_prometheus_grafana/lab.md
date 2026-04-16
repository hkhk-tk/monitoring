# Päev 1: Prometheus + Grafana — Labor

**18. aprill 2026 · 10:00–14:30**

> **Enne labi:** Loe läbi [observability loeng](../../materials/lectures/paev1-observability.md) ja [Prometheus loeng](../../materials/lectures/paev1-loeng.md).

---

## Meie keskkond täna

Sinu VM on juba ette valmistatud. Kolm serverit ootavad monitoorimist:

| Masin | IP | Mis seal jookseb |
|-------|----|-----------------|
| **Sinu VM** | 192.168.100.12X | Docker, node_exporter |
| **mon-target** | 192.168.100.140 | Linux server, rakenduse logid |
| **mon-target-web** | 192.168.100.141 | Nginx veebiserver |

Logi oma VM-ile sisse:
```bash
ssh <sinu-nimi>@192.168.100.12X
```

**Kirjuta oma IP siia:** `_______________________`  
(vajad seda kogu labori vältel brauseri URL-is)

---

## Osa 1: Monitooringu stack üles (45 min)

Selle osa lõpuks jookseb sinu VM-il neli konteinerit: Prometheus, Grafana, Alertmanager ja Node Exporter. Kõik omavahel ühendatud.

### Samm 1.1 — Töökausta loomine

```bash
mkdir -p ~/paev1/config
cd ~/paev1
```

> **Miks `config/` alamkaust?** Prometheus, Alertmanager ja Grafana vajavad konfiguratsioone. Hoiame need eraldi kaustas — nii on hiljem lihtne muuta ilma `docker-compose.yml`-i puutumata.

Kontrolli:
```bash
pwd
```
Peaksid nägema `/home/<sinu-nimi>/paev1`

---

### Samm 1.2 — Mida me üldse ehitame?

Enne failide loomist — vaata seda pilti:

```
Sinu VM
┌─────────────────────────────────────────────────┐
│                                                 │
│  ┌─────────────┐     ┌─────────────┐           │
│  │  Prometheus │────▶│   Grafana   │ :3000      │
│  │    :9090    │     │             │           │
│  └──────┬──────┘     └─────────────┘           │
│         │                                       │
│         │ scrape iga 15s                        │
│         ▼                                       │
│  ┌─────────────┐  ┌──────────────────────────┐ │
│  │Node Exporter│  │     Alertmanager :9093   │ │
│  │    :9100    │  └──────────────────────────┘ │
│  └─────────────┘                               │
└─────────────────────────────────────────────────┘
         │ scrape
         ▼
mon-target :9100  +  mon-target-web :9100
```

Prometheus **tõmbab** (pull) meetrikaid kõigilt kolmelt sihtmärgilt. Grafana küsib Prometheuselt andmeid visualiseerimiseks. Alertmanager võtab vastu hoiatusi Prometheuselt.

---

### Samm 1.3 — Node Exporter: kontrolli et töötab

Enne stacki käivitamist — veendu, et sihtmärgid vastavad:

```bash
curl http://localhost:9100/metrics | head -5
```

```bash
curl http://192.168.100.140:9100/metrics | head -5
```

```bash
curl http://192.168.100.141:9100/metrics | head -5
```

> **Mida näed?** Ridu mis algavad `# HELP` ja `# TYPE` — see on Prometheus'e tekstiformaat. Node Exporter loeb Linuxi `/proc` ja `/sys` kataloogidest süsteemiinfo ja pakub selle sellel pordil.

⚡ **Kontrolli:** Kõik kolm peavad vastama. Kui mõni ei vasta — teavita koolitajat.

---

### Samm 1.4 — `docker-compose.yml`: teenuste kirjeldus

Loo fail:
```bash
nano docker-compose.yml
```

Kopeeri sisu:

```yaml
services:
  prometheus:
    image: prom/prometheus:v2.53.0
    container_name: prometheus
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./config/alert.rules.yml:/etc/prometheus/alert.rules.yml
      - prometheus-data:/prometheus
    ports:
      - "9090:9090"
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--web.enable-lifecycle'
    extra_hosts:
      - "mon-target:192.168.100.140"
      - "mon-target-web:192.168.100.141"
    restart: unless-stopped

  node-exporter:
    image: prom/node-exporter:v1.8.2
    container_name: node-exporter
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
    ports:
      - "9100:9100"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:11.1.0
    container_name: grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=monitoring2026
    volumes:
      - grafana-data:/var/lib/grafana
      - ./config/grafana-datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml
    ports:
      - "3000:3000"
    restart: unless-stopped

  alertmanager:
    image: prom/alertmanager:v0.27.0
    container_name: alertmanager
    volumes:
      - ./config/alertmanager.yml:/etc/alertmanager/alertmanager.yml
    ports:
      - "9093:9093"
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:
```

Salvesta: `Ctrl+O` → `Enter` → `Ctrl+X`

> **Kolm asja mida märkida:**
> - `extra_hosts` — ütleb Prometheuse konteinerile et `mon-target` = `192.168.100.140`. Ilma selleta ei teaks konteiner seda nime.
> - `volumes:` — `/proc:/host/proc:ro` annab Node Exporterile juurdepääsu Linuxi süsteemiinfole. `:ro` = read-only, turvalisem.
> - `web.enable-lifecycle` — lubab Prometheuse konfiguratsiooni uuendada HTTP kaudu (ilma restartita).

---

### Samm 1.5 — `prometheus.yml`: mida jälgida?

```bash
nano config/prometheus.yml
```

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

rule_files:
  - alert.rules.yml

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'local'
    static_configs:
      - targets: ['node-exporter:9100']
        labels:
          host: 'minu-vm'

  - job_name: 'targets'
    static_configs:
      - targets: ['mon-target:9100']
        labels:
          host: 'target-linux'
          role: 'server'
      - targets: ['mon-target-web:9100']
        labels:
          host: 'target-web'
          role: 'webserver'
```

> **Kolm sektsiooni:**
> - `global` — üldseaded: scrape'i iga 15 sekundit, hinda alertireegleid iga 15 sekundit
> - `rule_files` — kust leida alertireegleid
> - `scrape_configs` — **keda** jälgida. Iga `job_name` on grupp sihtmärke. `labels` lisab metainfot — näiteks `role: webserver` ütleb hiljem Grafanas et see on veebiserver.

**Mõtlemisküsimus:** Miks kasutame `node-exporter:9100` mitte `localhost:9100`?

<details>
<summary>Vastus</summary>
Prometheus jookseb Docker konteineris. Konteineri sees tähendab `localhost` tema enda konteinerit, mitte VM-i. Docker võrgus saavad konteinerid üksteisega rääkida teenuse nimega — `node-exporter` on teenuse nimi `docker-compose.yml`-is.
</details>

---

### Samm 1.6 — `alert.rules.yml`: kolm esimest reeglit

```bash
nano config/alert.rules.yml
```

```yaml
groups:
  - name: node_alerts
    rules:
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.instance }} on maas!"

      - alert: HighCpuUsage
        expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 80
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Kõrge CPU: {{ $labels.instance }} ({{ $value | printf \"%.0f\" }}%)"

      - alert: DiskSpaceLow
        expr: (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Kettaruum otsakorral: {{ $labels.instance }}"
```

> **`for: 1m` on kriitiline.** Ilma selleta saad alerti iga lühiajalise spike peale. `for: 1m` tähendab: "tingimus peab kehtima katkematult 1 minuti enne hoiatuse saatmist." See väldib valehäireid.

---

### Samm 1.7 — Kaks väikest konfifaili

Alertmanager:
```bash
nano config/alertmanager.yml
```
```yaml
global:
  resolve_timeout: 5m
route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'null'
receivers:
  - name: 'null'
```

> Praegu `null` receiver — alertid kuvatakse UI-s aga ei saadeta kuhugi. Tegelikus elus seadistataks siin Slack, email või PagerDuty.

Grafana andmeallikas:
```bash
nano config/grafana-datasources.yml
```
```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

> See fail ütleb Grafanale käivitumisel: "Lisa automaatselt Prometheus andmeallikas, URL on `http://prometheus:9090`." Ilma selleta peaks seda käsitsi tegema.

---

### Samm 1.8 — Käivita stack

```bash
docker compose up -d
```

Vaata mis juhtub — Docker laeb pildid alla (esimene kord võtab kauem):
```bash
docker compose logs -f
```

Logi jälgimisest välja: `Ctrl+C`

Kontrolli konteinerite olek:
```bash
docker compose ps
```

⚡ **Kõik 4 konteinerit peavad olema `running`.** Kui mõni on `exited`:
```bash
docker compose logs <teenuse-nimi>
```

---

### Samm 1.9 — Kontrolli brauseris

Ava brauseris (kasuta oma IP-d):

**Prometheus:** `http://192.168.100.12X:9090`

Mine `Status → Targets`. Näed nimekirja sihtmärkidest.

⚡ **Kõik 3 sihtmärki peavad olema roheline `UP`.**

Kui mõni on `DOWN` — kontrolli terminalis:
```bash
curl http://192.168.100.140:9100/metrics | head -3
```

**Grafana:** `http://192.168.100.12X:3000`

Login: `admin` / `monitoring2026`

Mine `Connections → Data sources` — Prometheus peaks olema automaatselt lisatud.

**Alertmanager:** `http://192.168.100.12X:9093`

Peaks avanema UI ilma errorita.

---

### ✅ Osa 1 lõpukontroll

Enne edasi liikumist veendu:

- [ ] `docker compose ps` — 4 konteinerit staatuses `running`
- [ ] Prometheus Targets — 3 sihtmärki staatuses `UP`
- [ ] Grafana avab sisselogimislehe
- [ ] Alertmanager UI avaneb

Kui kõik on roheline — oled valmis PromQL-iks. 🟢

---

## Osa 2: PromQL — küsi andmeid kolmelt serverilt (30 min)

Prometheus UI → **Graph** tab. Siin kirjutad päringuid ja näed tulemusi.

### Samm 2.1 — Kes vastab?

Kirjuta päringukasti ja vajuta `Execute`:

```promql
up
```

> **Mida näed?** Iga sihtmärk ühe reana. Väärtus `1` = vastab, `0` = maas. See on Prometheus'e enda mõõdik — ta genereerib selle automaatselt iga scrape'i põhjal.

Vaheta vaade `Table` ja `Graph` vahel. Mis vahe on?

---

### Samm 2.2 — Esimene päris mõõdik

```promql
node_memory_MemTotal_bytes
```

Näed kolme rida — üks iga serveri kohta. Väärtus on baitides.

Teisenda gigabaitidesse:
```promql
node_memory_MemTotal_bytes / 1024 / 1024 / 1024
```

> **Miks jagame 1024-ga kolm korda?** bytes → kilobytes → megabytes → gigabytes. Prometheus annab alati baitides — teisendamine on sinu töö.

**Küsimus:** Mitu GB on igal serveril RAM-i?

| Server | RAM (GB) |
|--------|----------|
| Sinu VM | |
| mon-target | |
| mon-target-web | |

---

### Samm 2.3 — Counter vs Gauge

Proovi:
```promql
node_cpu_seconds_total
```

> See on **Counter** — ainult kasvab. Näitab sekundite arvu alates käivitusest. See arv ise ei ütle midagi kasulikku.

Nüüd `rate()` funktsiooniga:
```promql
rate(node_cpu_seconds_total{mode="idle"}[5m])
```

> **`rate()`** arvutab Counter'i kasvukiiruse sekundis, vaadates viimast 5 minutit (`[5m]`). Tulemus on murdarv 0-1 vahel — osakaal ajast mil CPU on jõude.

CPU kasutus protsendina:
```promql
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

Vaheta `Graph` vaatesse. Näed trendi ajas kolme serveril.

**Küsimus:** Milline server on hetkel kõige rohkem koormatud?

---

### Samm 2.4 — Filtreerimine label'ite järgi

Kõik mõõdikud kõigilt serveritelt korraga võib olla palju. Filtreeri:

```promql
# Ainult mon-target
node_load1{job="targets", host="target-linux"}

# Ainult veebiserver
node_memory_MemAvailable_bytes{host="target-web"}

# Kõik peale oma VM
node_load1{job!="local"}
```

> **`=`** on täpne vaste, **`!=`** on "mitte võrdne", **`=~`** on regex.

Proovi regex:
```promql
node_load1{job=~"targ.*"}
```

---

### Samm 2.5 — Väljakutsed

**Väljakutse 1:** Kirjuta päring mis näitab mitu päeva on iga masin töötanud.

<details>
<summary>Vihje</summary>
`node_boot_time_seconds` on Unix timestamp millal masin käivitus. `time()` on praegune aeg.
</details>

<details>
<summary>Lahendus</summary>

```promql
(time() - node_boot_time_seconds) / 86400
```
</details>

---

**Väljakutse 2:** Kirjuta päring mis näitab ketta täituvust protsendina kõigil serveritel.

<details>
<summary>Vihje</summary>
`node_filesystem_free_bytes` ja `node_filesystem_size_bytes` — mõlemad on olemas. Filtreeri `mountpoint="/"`.
</details>

<details>
<summary>Lahendus</summary>

```promql
100 - (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)
```
</details>

---

**Väljakutse 3 (edasijõudnud):** Millal saab mon-target ketas täis praeguse tempoga?

<details>
<summary>Lahendus</summary>

```promql
predict_linear(node_filesystem_free_bytes{mountpoint="/", host="target-linux"}[1h], 24*3600) < 0
```

Kui tulemus on `1` — ketas saab täis järgmise 24h jooksul praeguse tarbimistempo järgi.
</details>

---

## Osa 3: Grafana — USE meetodi dashboard (35 min)

> **Loengust meenu:** USE = Utilization, Saturation, Errors. Iga ressursi kohta kolm küsimust. See annab süsteemaatilise ülevaate ilma tähtsat maha jätmata.

Grafana: `http://192.168.100.12X:3000`

### Samm 3.1 — Impordi professionaalne dashboard

Enne oma dashboardi ehitamist — vaata mida professionaalsed tööriistad pakuvad.

**Dashboards → New → Import**

Sisesta ID: `1860` → **Load** → vali Prometheus → **Import**

See on **Node Exporter Full** — üks populaarseimaid Grafana dashboarde maailmas.

Uuri 2 minutit:
- Kui palju paneele on?
- Kliki ühel paneelis `Edit` — vaata PromQL päringut
- Mis on sinu VM-i CPU kasutus praegu?

---

### Samm 3.2 — Loo oma dashboard

**Dashboards → New → New Dashboard → + Add visualization**

**Esimene paneel — serverite staatus:**

Päring:
```promql
up
```

- Visualization tüüp: **Stat**
- Value mappings: `1` → `UP` (roheline), `0` → `DOWN` (punane)
- Title: `Serverite staatus`
- Legend: `{{instance}}`

Kliki **Apply**.

> **Miks Stat, mitte Time series?** Staatus on hetkeolukord — kas server vastab praegu. Time series näitaks ajalugu, aga siin tahame selget ühte vastust.

---

**Teine paneel — CPU kasutus ajas:**

Kliki **Add** → **Visualization**

Päring:
```promql
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

- Visualization: **Time series**
- Unit: `Percent (0-100)`
- Legend: `{{instance}}`
- Title: `CPU kasutus %`

Apply.

---

**Kolmas paneel — mälu kasutus:**

```promql
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100
```

- Visualization: **Gauge**
- Unit: `Percent (0-100)`
- Thresholds: `0` roheline → `70` kollane → `85` punane
- Title: `Mälu kasutus %`

> **Miks Gauge?** Gauge näitab hetke väärtust visuaalselt — pool-ring täitub ja muudab värvi. Sobib hästi ühe numbri näitamiseks koos ohumärgiga.

Apply.

---

**Neljas paneel — ketta täituvus:**

```promql
100 - (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)
```

- Visualization: **Bar gauge**
- Unit: `Percent (0-100)`
- Thresholds: `80` kollane, `90` punane
- Title: `Ketta täituvus %`

Apply.

Salvesta dashboard: `Ctrl+S` → nimi: **"Päev 1 — USE ülevaade"**

---

### Samm 3.3 — Variables: dünaamiline dashboard

Praegu näitab dashboard kõiki servereid korraga. Lisa filter.

**Dashboard settings** (hammasratas) → **Variables** → **Add variable**:

| Väli | Väärtus |
|------|---------|
| Name | `instance` |
| Type | Query |
| Data source | Prometheus |
| Query | `label_values(up, instance)` |
| Multi-value | ✅ |
| Include All | ✅ |

**Apply** → **Save dashboard**

Nüüd muuda CPU paneeli päringut — lisa filter:
```promql
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle", instance=~"$instance"}[5m])) * 100)
```

Tee sama kõigile paneelidele.

⚡ **Kontrolli:** Vali dropdown'ist ainult `mon-target` — kas teised kaovad?

---

## Osa 4: Alerting — hoiatuste testimine (20 min)

### Samm 4.1 — Vaata olemasolevaid reegleid

Prometheus: `http://192.168.100.12X:9090/alerts`

Näed kolme reeglit staatuses **Inactive** — tingimused ei kehti praegu.

**Olekud:**
- 🟢 `Inactive` — tingimus ei kehti
- 🟡 `Pending` — tingimus kehtib, aga `for:` aeg pole täis
- 🔴 `Firing` — hoiatus aktiivne

---

### Samm 4.2 — Tekita alert ise

```bash
sudo systemctl stop node_exporter
```

Mine Prometheus → Alerts. Jälgi muutust:

- ~15 sek: `local` target läheb `DOWN`
- ~1 min: `InstanceDown` läheb `Pending` 🟡
- ~2 min: `InstanceDown` läheb `Firing` 🔴

Vaata ka Alertmanager UI — kas alert jõudis sinna?

Taasta:
```bash
sudo systemctl start node_exporter
```

---

### Samm 4.3 — Lisa oma alert

Ava fail:
```bash
nano config/alert.rules.yml
```

Lisa `DiskSpaceLow` pärast uus reegel:

```yaml
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Mälu üle 85%: {{ $labels.instance }} ({{ $value | printf \"%.0f\" }}%)"
```

Uuenda Prometheust ilma restartita:
```bash
curl -X POST http://localhost:9090/-/reload
```

Kontrolli: `Status → Rules` — uus reegel peab olema nähtav.

---

### Arutelu: Alert design (5 min)

Mõtle oma töökontekstis:

- Milline alert peaks sind **kell 3 öösel** äratama?
- Milline alert sobib hommikusse **Slacki sõnumisse**?
- Milline alert on **mõttetu müra** mida keegi ei vaata?

---

## Osa 5: 🔥 Kaose test — leia probleem (15 min)

**Koolitaja tekitab probleeme.** Sinu ülesanne on need ise üles leida.

Jälgi samaaegselt:
- Grafana dashboard
- Prometheus → Alerts
- Alertmanager UI

Leia vastused:
1. Milline server on probleemi all?
2. Mis ressurss on mõjutatud?
3. Mis hetkel probleem algas? (vaata graafikut)
4. Kas alert käivitus? Kui kaua läks?

---

## Lisaülesanded (kui aega jääb)

### A — Recording rules

Keerulised päringud on aeglased. Recording rules arvutavad need ette.

Loo `config/recording.rules.yml`:

```yaml
groups:
  - name: node_recording
    rules:
      - record: instance:cpu_utilization:ratio
        expr: 1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))

      - record: instance:memory_utilization:ratio
        expr: 1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
```

Lisa `config/prometheus.yml` `rule_files` sektsiooni:
```yaml
rule_files:
  - alert.rules.yml
  - recording.rules.yml
```

Reload ja proovi: `instance:cpu_utilization:ratio` — tulemus on sama, aga palju kiirem.

---

### B — Monitoori kaasõppijat

Lisa `config/prometheus.yml` scrape_configs sektsiooni:

```yaml
  - job_name: 'naaber'
    static_configs:
      - targets: ['192.168.100.12Y:9100']
        labels:
          host: 'naaber-vm'
```

(Asenda `Y` naabri IP lõpuga)

```bash
curl -X POST http://localhost:9090/-/reload
```

Nüüd näed naabri meetrikaid oma dashboardis. Kes teist on rohkem koormatud?

---

## Puhastamine (pärast tundi)

```bash
cd ~/paev1
docker compose down -v
```

Järgmisel laupäeval alustame puhtalt — Zabbix + Loki.

---

## Tõrkeotsing

| Probleem | Lahendus |
|----------|----------|
| Konteiner ei käivitu | `docker compose logs <nimi>` |
| Target DOWN | `curl http://192.168.100.140:9100/metrics` — kas vastab? |
| Grafana ei näita andmeid | Data source URL peab olema `http://prometheus:9090` |
| PromQL "no data" | Prometheus → Status → Targets — kas scrape töötab? |
| Alert ei käivitu | `curl -X POST http://localhost:9090/-/reload` — kas reload õnnestus? |
| `connection refused` | `docker compose ps` — kas konteiner jookseb? |

---

## Allikad

| Allikas | URL |
|---------|-----|
| Prometheus dokumentatsioon | https://prometheus.io/docs/ |
| PromQL cheat sheet | https://promlabs.com/promql-cheat-sheet/ |
| Node Exporter mõõdikud | https://github.com/prometheus/node_exporter |
| Grafana dokumentatsioon | https://grafana.com/docs/grafana/latest/ |
| Node Exporter Full dashboard | https://grafana.com/grafana/dashboards/1860 |
| Awesome Prometheus alerts | https://samber.github.io/awesome-prometheus-alerts/ |
| AlertManager dokumentatsioon | https://prometheus.io/docs/alerting/latest/alertmanager/ |
