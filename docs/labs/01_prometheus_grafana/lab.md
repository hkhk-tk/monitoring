# Päev 1: Prometheus + Grafana — Labor

**18. aprill 2026 · 10:00–14:30**

---

## Keskkond

| Masin | Admin IP | Klassi IP | Mis seal on |
|-------|----------|-----------|-------------|
| **Sinu VM** (`mon-<nimi>`) | 192.168.100.12X | 192.168.5.12X | Docker host |
| **mon-target** | 192.168.100.140 | 192.168.5.140 | Linux server, node_exporter, logid |
| **mon-target-web** | 192.168.100.141 | 192.168.5.141 | Nginx, node_exporter |

```bash
ssh student@192.168.5.12X
```

---

## 1. Stack üles (25 min)

```bash
mkdir -p ~/paev1/config && cd ~/paev1
```

### docker-compose.yml

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
    restart: unless-stopped
    extra_hosts:
      - "mon-target:192.168.100.140"
      - "mon-target-web:192.168.100.141"

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

### config/prometheus.yml

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

### config/alert.rules.yml

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

### config/alertmanager.yml

```yaml
global:
  resolve_timeout: 5m
route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'webhook-demo'
receivers:
  - name: 'webhook-demo'
    webhook_configs:
      - url: 'http://localhost:9095/alert'
        send_resolved: true
```

### config/grafana-datasources.yml

```yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
```

### Käivita ja kontrolli

```bash
docker compose up -d
docker compose ps        # Kõik 4 peavad olema running
```

**Kontroll:**

| Teenus | URL | Oodatav |
|--------|-----|---------|
| Prometheus | `http://<sinu-ip>:9090` → Status → Targets | 3 target'it UP (rohelised) |
| Grafana | `http://<sinu-ip>:3000` | Login: admin / monitoring2026 |
| Alertmanager | `http://<sinu-ip>:9093` | UI avaneb |
| mon-target metrics | `curl http://192.168.100.140:9100/metrics` | Näed metrikaid |

Kui mõni target on DOWN — kontrolli kas IP ja port on õiged. `extra_hosts` peab klapima.

---

## 2. PromQL (30 min)

Prometheus UI → Graph tab.

### Tase 1: Baas

```promql
# Kes on üleval?
up

# Mitu GB mälu igal masinal?
node_memory_MemTotal_bytes / 1024^3

# Millal masin käivitati? (Unix timestamp)
node_boot_time_seconds

# Mitu CPU core'i?
count by(instance) (node_cpu_seconds_total{mode="idle"})
```

### Tase 2: rate() ja aritmeetika

```promql
# CPU kasutus protsendina per masin
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Mälu kasutus protsendina
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Ketta täituvus protsendina
100 - (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)

# Võrguliiklus Mbit/s
rate(node_network_receive_bytes_total[5m]) * 8 / 1024^2
```

Proovi neid **Graph** vaates — näed trende ajas.

### Tase 3: Filtreerimine ja grupeerimine

```promql
# Ainult target-masinad
up{job="targets"}

# CPU kasutus ainult target-web masinal
100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle", instance=~".*141.*"}[5m])) * 100)

# Top masin mälu kasutuse järgi
topk(1, (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)

# Keskmine CPU kasutus üle kõigi masinate
avg(100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100))
```

### Väljakutse 1

Kirjuta päring: **mitu päeva on iga masin järjest töötanud (uptime)?**

??? tip "Lahendus"
    ```promql
    (time() - node_boot_time_seconds) / 86400
    ```

### Väljakutse 2

Kirjuta päring: **mis on kõigi masinate keskmine ketta täituvus protsendina?**

??? tip "Lahendus"
    ```promql
    avg(100 - (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100))
    ```

### Väljakutse 3 (edasijõudnud)

Kirjuta päring: **predict_linear — millal saab mon-target ketas täis?** (vastus tundides)

??? tip "Lahendus"
    ```promql
    predict_linear(node_filesystem_free_bytes{mountpoint="/", instance=~".*140.*"}[1h], 24*3600) < 0
    ```
    Kui tulemus on 1, siis ketas saab täis järgmise 24h jooksul.

---

## 3. Grafana — USE method dashboard (35 min)

Grafana: `http://<sinu-ip>:3000` (admin / monitoring2026)

Prometheus data source on automaatselt seadistatud.

### Ülesanne: Ehita USE meetodi dashboard

**USE** = Utilization, Saturation, Errors — iga ressursi kohta 3 küsimust.

Loo uus dashboard: **+ → New dashboard**. Salvesta nimega **"USE — Süsteemi tervis"**.

Ehita see tabel paneelide abil:

| Rida | U (kasutus) | S (küllastus) | E (vead) |
|------|-------------|---------------|----------|
| **CPU** | CPU % (Time series) | Load / CPU cores (Time series) | — |
| **Mälu** | RAM % (Gauge) | Swap kasutus MB (Stat) | — |
| **Disk** | Ketta täituvus % (Gauge) | Disk I/O aeg (Time series) | Disk read errors (Stat) |
| **Võrk** | Traffic Mbit/s (Time series) | — | Interface errors (Stat) |

**PromQL valemid iga paneeli jaoks:**

| Paneel | PromQL |
|--------|--------|
| CPU kasutus % | `100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)` |
| Load / cores | `node_load1 / count by(instance) (node_cpu_seconds_total{mode="idle"})` |
| Mälu kasutus % | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` |
| Swap MB | `(node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes) / 1024^2` |
| Disk täituvus % | `100 - (node_filesystem_free_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)` |
| Disk I/O aeg | `rate(node_disk_io_time_seconds_total[5m])` |
| Disk errors | `rate(node_disk_read_errors_total[5m])` |
| Võrk Mbit/s | `rate(node_network_receive_bytes_total{device!="lo"}[5m]) * 8 / 1024^2` |
| Interface errors | `rate(node_network_receive_errs_total[5m])` |

**Legend** iga paneelis: `{{instance}}` — siis näed milline masin on milline.

### Dashboard variables

Dashboard settings (hammasratas) → Variables → Add variable:

| Seade | Väärtus |
|-------|---------|
| Name | `instance` |
| Type | Query |
| Query | `label_values(up, instance)` |
| Multi-value | ✅ |
| Include All | ✅ |

Nüüd muuda paneelides kõik päringud: lisa filter `{instance=~"$instance"}`.

Näiteks: `100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle", instance=~"$instance"}[5m])) * 100)`

Ülaossa tekib dropdown — saad filtreerida masinate kaupa.

### Valmisdashboard importimine

Kiire alternatiiv: **+ → Import → Dashboard ID: 1860** → Prometheus data source.

See on **Node Exporter Full** — professionaalne ülevaade. Võrdle enda ehitatud dashboardiga.

---

## 4. Alerting (25 min)

### Alert rules — juba olemas

Prometheus → Status → Rules — kolm rule'i peaks olema nähtavad.

Prometheus → Alerts — näed Inactive / Pending / Firing staatused.

### Ülesanne: Lisa oma alert

Muuda `config/alert.rules.yml`, lisa:

```yaml
      # Mälu üle 85%
      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 85
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Mälu üle 85%: {{ $labels.instance }} ({{ $value | printf \"%.0f\" }}%)"

      # Predict: ketas saab täis 4h jooksul
      - alert: DiskWillFillIn4Hours
        expr: predict_linear(node_filesystem_free_bytes{mountpoint="/"}[1h], 4*3600) < 0
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "Ketas saab täis 4h jooksul: {{ $labels.instance }}"
```

Laadi uuesti:

```bash
curl -X POST http://localhost:9090/-/reload
```

Kontrolli: Prometheus → Status → Rules — uued rule'id peavad olema nähtavad.

### Arutelu: Alert design

*Mõtle oma töökontekstis:*

- Milline alert peaks sind kell 3 öösel äratama?
- Milline alert on "nice to know" ja läheb Slacki?
- Milline alert on mõttetu müra mida keegi ei vaata?

---

## 5. 🔥 Kaoose test (15 min)

**Koolitaja tekitab probleeme mon-target ja mon-target-web masinatel.**

Sinu ülesanne:
1. **Leia probleem** oma Grafana dashboardist ja/või Prometheus Alerts lehelt
2. **Tuvasta mis juhtus** — milline masin, mis ressurss?
3. **Ütle välja** mis sa arvad et juhtus

Jälgi:
- Prometheus → Alerts (kas midagi muutub Pending / Firing?)
- Grafana dashboard (kas graafik muutub?)
- Alertmanager :9093 (kas alert jõuab kohale?)

---

## 6. Väljakutsed (edasijõudnud, kui aega jääb)

### Väljakutse A: Recording rules

Lisa `config/prometheus.yml` faili `rule_files` sektsiooni uus fail, loo `config/recording.rules.yml`:

```yaml
groups:
  - name: node_recording
    rules:
      - record: instance:cpu_utilization:ratio
        expr: 1 - avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m]))
      - record: instance:memory_utilization:ratio
        expr: 1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)
```

Muuda `prometheus.yml`:
```yaml
rule_files:
  - alert.rules.yml
  - recording.rules.yml
```

Reload ja proovi: `instance:cpu_utilization:ratio` — peaks andma kiire tulemuse.

### Väljakutse B: File-based service discovery

Asenda staatiline `targets` konfigiga `file_sd_configs`:

```yaml
  - job_name: 'nodes-dynamic'
    file_sd_configs:
      - files:
          - '/etc/prometheus/targets.json'
        refresh_interval: 15s
```

Loo `config/targets.json`:
```json
[
  {
    "targets": ["mon-target:9100", "mon-target-web:9100"],
    "labels": { "env": "lab", "team": "infra" }
  }
]
```

Lisa Docker Compose'i Prometheus volume: `- ./config/targets.json:/etc/prometheus/targets.json`

`docker compose up -d` ja kontrolli — targets peaks ilmuma ilma restart'ita.

### Väljakutse C: Monitoori kaasõppija masinat

Lisa oma `config/prometheus.yml` faili naabri VM:

```yaml
      - targets: ['192.168.100.12Y:9100']
        labels:
          host: 'naaber'
```

Reload. Nüüd näed naabri metrikaid oma dashboardis.

---

## Puhasta (pärast tundi)

```bash
cd ~/paev1
docker compose down -v
```

Järgmisel laupäeval alustame uue stackiga (Zabbix + Loki).

---

## Tõrkeotsing

| Probleem | Kontrolli |
|----------|-----------|
| Konteiner ei käivitu | `docker compose logs prometheus` |
| Target DOWN | `curl http://192.168.100.140:9100/metrics` — kas vastab? |
| "connection refused" | Kas `extra_hosts` on docker-compose.yml-is õige? |
| PromQL "no data" | Prometheus → Status → Targets → kas scrape töötab? |
| Grafana ei näita andmeid | Kas data source URL on `http://prometheus:9090`? |
| Alert ei fire | `curl -X POST http://localhost:9090/-/reload` pärast muutmist |
| Port kinni | `sudo ss -tlnp \| grep <port>` |
