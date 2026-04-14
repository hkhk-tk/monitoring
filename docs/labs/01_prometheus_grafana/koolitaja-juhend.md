# Koolitaja juhend — Päev 1

*Ainult sinule. Osalejad seda ei näe.*

---

## Päeva rütm

| Aeg | Min | Tegevus | Kolb | Mida SINA teed |
|-----|-----|---------|------|----------------|
| 10:00 | 5 | Tutvustusring | CE | Küsi: nimi, roll, mida monitoorid, mida tahad |
| 10:05 | 15 | "Miks monitoring?" arutelu | CE→RO | Juhid arutelu. Kirjutad tahvlile. Joonista 3 sammast |
| 10:20 | 30 | Docker Compose üles | AE | Kõnnid ringi, aitad. Kõigil peab Prometheus UI avanema |
| 10:50 | 10 | Pull-mudel, TSDB seletus | AC | Seleta NÜÜD. Nad nägid juba targets lehte. |
| 11:00 | 30 | PromQL harjutused | AE | Anna päringud ükshaaval. "Kes saab esimesena vastuse?" |
| 11:30 | 10 | ☕ Paus | | |
| 11:40 | 30 | Grafana esimene dashboard | AE | Esimene paneel koos, siis iseseisvalt |
| 12:10 | 30 | 🍽️ Lõuna | | |
| 12:40 | 35 | USE meetod + dashboard disain | AE+AC | Seleta USE, siis ehitavad dashboardi selle järgi |
| 13:15 | 10 | ☕ Paus | | |
| 13:25 | 25 | Alertmanager + alert design | AE+AC | Alert fatigue arutelu. Securer mees räägib. |
| 13:50 | 15 | 🔥 KAOOSE TEST | CE | Tekita probleemid. Kes leiab? |
| 14:05 | 10 | Reflektsioon | RO | "Mida kasutaksid tööl? Mis oli uus?" |
| 14:15 | 15 | Puhver / edasijõudnud | AE | Recording rules, file_sd, predict_linear |

---

## Kaose skriptid — käivitad mon-target masinal

SSH: `ssh student@192.168.100.140`

### Test 1: Teenus läheb maha (lihtne)
```bash
# Peata node_exporter
sudo systemctl stop node_exporter
# Oota ~1 min → InstanceDown alert peaks firing'ima
# Taasta:
sudo systemctl start node_exporter
```

### Test 2: CPU spike
```bash
# Tekita 100% CPU koormust 2 minutit
stress-ng --cpu 0 --timeout 120s &
# Kui stress-ng pole installitud:
sudo apt install -y stress-ng
# Oota → HighCpuUsage alert peaks firing'ima
```

### Test 3: Ketas täis (ettevaatlikult!)
```bash
# Tekita 500MB faile
dd if=/dev/zero of=/tmp/fillup bs=1M count=500
# Peale testi:
rm /tmp/fillup
```

### Test 4: Logi-generaator hakkab ainult ERROR'eid andma
```bash
# Peata normaalne generaator
sudo systemctl stop log-generator
# Käivita ainult error'id
while true; do
  echo "$(date '+%Y-%m-%d %H:%M:%S') [CRITICAL] [payment] Connection timeout to database" >> /var/log/app.log
  sleep 1
done
# Ctrl+C ja taasta:
sudo systemctl start log-generator
```

### Test 5: mon-target-web Nginx maha (veebileht ei vasta)
```bash
ssh student@192.168.100.141
sudo systemctl stop nginx
# Oota → node_exporter töötab endiselt, aga HTTP check ebaõnnestub
sudo systemctl start nginx
```

---

## Arutelu küsimused (kasuta vastavalt olukorrale)

### Avamine (10:05)
- "Kuidas te praegu teate et midagi on valesti?"
- "Mis on teie suurim monitoring-alane valukoht?"
- "Kui tihti juhtub et saate teada probleemist kasutaja kaudu?"

### Pull vs Push (10:50)
- "Zabbix agent push'ib. Prometheus pull'ib. Mis on vahe?"
- "Securer: 2000 seadmega — kumba mudelit eelistaksid?"
- "Mis juhtub kui target on tulemüüri taga?"

### Dashboard disain (12:40)
- "Mis info PEAB olema esimesel dashboard ekraanil?"
- "Eesti Pank: millist infot nõuab audit?"
- "Mis vahe on dashboardil mis on seinale ja millega teed troubleshoot'imist?"

### Alert fatigue (13:25)
- "Mitu alerti päevas on normaalne?"
- "Securer: 2000 seadme puhul — kui 1% annab vale alarmi, see on 20 emaili päevas"
- "Mis on vahe 'nice to know' ja 'wake me up at 3am' alertil?"

### Reflektsioon (14:05)
- "Mida saaksite homme tööl kasutusele võtta?"
- "Mis oli üllatav?"
- "Mis küsimused jäid vastamata?"

---

## Backup plaan

**Kui Docker ei tööta kellegi VM-il:**
- Tee paaristöö — kaks inimest ühe VM peal
- Või: kopeeri docker-compose.yml ja config/ teise masinasse

**Kui mon-target ei vasta:**
- Nad monitoorivad ainult oma VM-i (node-exporter)
- Lisa prometheus.yml-i: targets ainult localhost

**Kui jõuate kiiremini valmis kui 14:30:**
- Recording rules
- File-based service discovery
- predict_linear() alertid
- Grafana variables + template'id
- Dashboard import (ID 1860)

**Kui jõuate aeglasemalt:**
- Jäta Alertmanager lühemaks (ainult demo)
- Jäta USE meetod seletus välja, tee järgmine kord
- Kaoose test tegid ainult 1 (node_exporter maha)
