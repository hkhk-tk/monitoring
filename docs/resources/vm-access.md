# VM ligipääs

Igal osalejal on oma isiklik VM Proxmoxi peal. VM-il on **kaks IP-aadressi** — üks klassivõrgus ja teine VPN/haldusvõrgus. Kasuta seda, mis su asukohale sobib.

## Kaks võrku

| Võrk | Prefiks | Millal kasutada |
|------|---------|-----------------|
| Klassiruum | `192.168.35.0/24` | Kui oled koolis, ühendatud klassi võrku |
| Haldus / VPN | `192.168.100.0/24` | Kui töötad kodust — VPN peab aktiivne olema |

**Sama VM, sama sisu — ainult IP erineb.** Vali endale sobivam ja hoia sellega.

## Sinu kasutajanimi ja IP

**Kasutajanimi, VM-i number ja paroolid jagatakse Google Classroomis eraldi.**

Sinu VM-i IP on kujul:

- Klassis: `192.168.35.12X`
- VPNiga: `192.168.100.12X`

…kus `X` asendub sinu isikliku numbriga (näidatud Classroomis).

## SSH

```bash
ssh <kasutajanimi>@<sinu-ip>
```

## Brauserist ligipääs

Asenda `<sinu-ip>` oma VM-i aadressiga.

| Teenus | URL | Märkused |
|--------|-----|----------|
| Prometheus | `http://<sinu-ip>:9090` | PromQL päringud, targets, alerts |
| Grafana | `http://<sinu-ip>:3000` | Login andmed Classroomis |
| Alertmanager | `http://<sinu-ip>:9093` | Alertide ülevaade |
| Node Exporter | `http://<sinu-ip>:9100/metrics` | Toormetrikad |

## Target-masinad (jagatud)

Kõik osalejad monitoorivad samu masinaid. Target-masinatel on ka kaks IP-d; kasuta sedasama võrku, mis su VM-ile pääsemisel. Täpsed IP-d leiad iga labori juhendist.

| Masin | Teenused |
|-------|----------|
| mon-target | node_exporter (:9100), zabbix-agent (:10050), logi-generaator (`/var/log/app.log`) |
| mon-target-web | nginx (:80), stub_status (:8080), node_exporter (:9100), zabbix-agent (:10050) |

## Kasulikud käsud

```bash
docker compose up -d        # Käivita stack
docker compose ps           # Staatuse kontroll
docker compose logs -f      # Logide jälgimine
docker compose down -v      # Peata ja kustuta kõik
docker compose restart      # Taaskäivita
```
