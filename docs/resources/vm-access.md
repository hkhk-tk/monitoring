# VM ligipääs

## Sinu masin

```bash
ssh student@192.168.5.12X
# parool: Monitoring2026!
```

Asenda `X` oma numbriga (jagatakse kohapeal).

## Brauserist ligipääs

| Teenus | URL | Märkused |
|--------|-----|----------|
| Prometheus | `http://192.168.5.12X:9090` | PromQL päringud, targets, alerts |
| Grafana | `http://192.168.5.12X:3000` | admin / monitoring2026 |
| Alertmanager | `http://192.168.5.12X:9093` | Alertide ülevaade |
| Node Exporter | `http://192.168.5.12X:9100/metrics` | Toormetrikad |

## Target-masinad

Need on jagatud — kõik osalejad monitoorivad samu masinaid.

| Masin | IP | Teenused |
|-------|-----|----------|
| mon-target | 192.168.5.140 | node_exporter (:9100), zabbix-agent (:10050), logi-generaator (/var/log/app.log) |
| mon-target-web | 192.168.5.141 | nginx (:80), stub_status (:8080), node_exporter (:9100), zabbix-agent (:10050) |

## Kasulikud käsud

```bash
docker compose up -d        # Käivita stack
docker compose ps            # Staatuse kontroll
docker compose logs -f       # Logide jälgimine
docker compose down -v       # Peata ja kustuta kõik
docker compose restart       # Taaskäivita
```
