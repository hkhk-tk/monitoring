# VM ligipääs

Igal osalejal on oma isiklik VM Proxmoxi peal. VM-il on **kaks IP-aadressi** — üks klassivõrgus ja teine VPN/haldusvõrgus. Kasuta seda, mis su asukohale sobib.

## Kaks võrku

| Võrk | Prefiks | Millal kasutada |
|------|---------|-----------------|
| Klassiruum | `192.168.35.0/24` | Kui oled koolis, ühendatud klassi Wi-Fisse või võrku |
| Haldus / VPN | `192.168.100.0/24` | Kui töötad kodust, VPN peab olema aktiivne |

**Sama VM, samad sisu — ainult IP erineb.** Vali endale sobivam ja hoia sellega.

## Sinu VM

| Osaleja | Kasutajanimi | Klassis (35.x) | VPNiga (100.x) |
|---------|--------------|----------------|----------------|
| Kaarel | kaarel | 192.168.35.121 | 192.168.100.121 |
| Siim | siim | 192.168.35.122 | 192.168.100.122 |
| Margus | margus | 192.168.35.123 | 192.168.100.123 |
| Heini | heini | 192.168.35.124 | 192.168.100.124 |
| Allar | allar | 192.168.35.125 | 192.168.100.125 |
| Marko | marko | 192.168.35.126 | 192.168.100.126 |
| Kuido | kuido | 192.168.35.127 | 192.168.100.127 |
| Andres | andres | 192.168.35.128 | 192.168.100.128 |
| Andrus | andrus | 192.168.35.129 | 192.168.100.129 |
| Mailis | mailis | 192.168.35.130 | 192.168.100.130 |
| Ahti | ahti | 192.168.35.131 | 192.168.100.131 |

**SSH:**

```bash
ssh <kasutajanimi>@<sinu-ip>
```

Näide Kaarelile klassis:

```bash
ssh kaarel@192.168.35.121
```

Parool jagatakse kohapeal (küsi koolitajalt kui vaja).

## Brauserist ligipääs

Asenda `<sinu-ip>` oma VM-i IP-ga — kas `192.168.35.12X` (klassis) või `192.168.100.12X` (VPNiga).

| Teenus | URL | Märkused |
|--------|-----|----------|
| Prometheus | `http://<sinu-ip>:9090` | PromQL päringud, targets, alerts |
| Grafana | `http://<sinu-ip>:3000` | admin / `monitoring2026` |
| Alertmanager | `http://<sinu-ip>:9093` | Alertide ülevaade |
| Node Exporter | `http://<sinu-ip>:9100/metrics` | Toormetrikad |

## Target-masinad (jagatud)

Need on jagatud — kõik osalejad monitoorivad samu masinaid. Target-masinatel on ka kaks IP-d, kasuta sedasama võrku, mis su VM-ile pääsemisel.

| Masin | Klassis | VPNiga | Teenused |
|-------|---------|--------|----------|
| mon-target | 192.168.35.140 | 192.168.100.140 | node_exporter (:9100), zabbix-agent (:10050), logi-generaator (`/var/log/app.log`) |
| mon-target-web | 192.168.35.141 | 192.168.100.141 | nginx (:80), stub_status (:8080), node_exporter (:9100), zabbix-agent (:10050) |

> **Labori juhendis näete IP-d `192.168.100.140` / `.141`** — see töötab alati (VPN + klassis). Kui eelistad klassivõrku, asenda `100` → `35` päringutes.

## Kasulikud käsud

```bash
docker compose up -d        # Käivita stack
docker compose ps            # Staatuse kontroll
docker compose logs -f       # Logide jälgimine
docker compose down -v       # Peata ja kustuta kõik
docker compose restart       # Taaskäivita
```
