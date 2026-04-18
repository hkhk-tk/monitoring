# Päev 1 — Kava ja ettevalmistus

**18. aprill 2026 · 10:00–14:30 · Haapsalu KHK**
**Teema:** Monitooringu alused + Prometheus + Grafana

---

## Päevakava

| Kell | Min | Tegevus | Kus |
|------|-----|---------|-----|
| 10:00–10:05 | 5 | Sissejuhatus — tutvumisring | Klass |
| 10:05–10:20 | 15 | **Miks monitooring?** — avaarutelu | Klass |
| 10:20–10:35 | 15 | **Kolm sammast** — metrics, logs, traces tahvlil | Klass |
| 10:35–11:05 | 30 | **Prometheus + Node Exporter** — Docker Compose üles | Oma VM |
| 11:05–11:15 | 10 | Mini-teooria — pull-mudel, TSDB, scrape interval | Klass |
| 11:15–11:30 | 15 | **PromQL baas** — esimesed päringud ise | Oma VM |
| 11:30–11:40 | 10 | ☕ Paus | — |
| 11:40–12:10 | 30 | **Grafana install + data source** — esimene paneel | Oma VM |
| 12:10–12:40 | 30 | 🍽️ Lõuna | — |
| 12:40–13:15 | 35 | **Grafana süvitsi** — variables, row'd, oma stsenaarium | Oma VM |
| 13:15–13:25 | 10 | ☕ Paus | — |
| 13:25–13:50 | 25 | **Alertmanager** — alert rules, routing, esimene alert | Oma VM |
| 13:50–14:05 | 15 | **Kokkuvõte + reflektsioon** | Klass |
| 14:05–14:30 | 25 | Puhver / lisaharjutused | Oma VM |

## Meetod

Päev järgib **Kolbi õppimistsüklit**: kogemus → reflektsioon → teooria → katsetamine. See tähendab praktikas:

- **Teooria tuleb pärast kogemust** — Prometheus läheb käima enne, kui seletame pull-mudelit
- **Sa kirjutad ise** — iga PromQL päring, iga paneel, iga alert tehakse omal masinal, mitte vaadatakse ekraanilt
- **Diferentseeritud stsenaariumid** — Grafana dashboard ehitatakse sinu enda töökonteksti põhjal (võrguseadmed, süsteemide tervis, rakenduse jõudlus vms)
- **Reflektsioon on formaalne etapp** — 15 min lõpus, kus arutame mida kasutad tööl

## Enne klassi

**Lugemine (~75 min kokku):**

1. [Loeng 1 — monitooring, logimine, observability](lectures/paev1-observability.md) — 35 min
2. [Loeng 2 — Prometheus ja Grafana](lectures/paev1-loeng.md) — 50 min

Need on **eelduslikud**. Klassiajal teeme, ei loe — aeg on väärtuslik praktikaks.

**Tehniline kontroll:**

- [ ] SSH ligipääs VM-ile töötab ([vm-access](../resources/vm-access.md))
- [ ] VPN ühendub (kui töötad kodust)
- [ ] Terminal ja brauser käepärast
- [ ] `docker` ja `docker compose` VM-il töötavad (eelinstallitud)

## Õpiväljundid

Päeva lõpuks osaleja:

- **Eristab** logimise, seire ja observability kontseptsioone
- **Rakendab** USE ja RED meetodeid konkreetse süsteemi jälgitavuse kavandamisel
- **Ehitab** töötava Prometheus + Node Exporter + Grafana + Alertmanager stacki Docker Compose'iga
- **Kirjutab** PromQL päringuid counter, gauge ja histogram mõõdikutele
- **Kavandab** Grafana dashboardi oma töökonteksti põhjal (variables, paneelid, organiseeritud row'des)
- **Konfigureerib** alertireegli + Alertmanager routing'i, demonstreerib oleku ülemineku `Pending → Firing`

## Laborikeskkond

Iga osaleja: oma VM (4 GB RAM, 2 CPU, Docker eelinstallitud) + jagatud target-masinad.

| Teenus | Port | Kirjeldus |
|--------|------|-----------|
| Prometheus | 9090 | Andmekogumine, PromQL |
| Grafana | 3000 | Visualiseerimine |
| Alertmanager | 9093 | Hoiatuste haldamine |
| node_exporter | 9100 | Süsteemi mõõdikud |

Täpsed IP-d, kasutajanimed, paroolid: [VM ligipääs](../resources/vm-access.md).

## Järgmine kord (25.04)

Teisel päeval vaatleme **Zabbix** (agent-põhine monitooring, võrdlus Prometheus pull-mudeliga) ja **Loki** + Promtail (Grafana ökosüsteemi logimislahendus). Õpid:

- Zabbix-agendi erinevus Prometheus exporter'ist ja millal kumba eelistada
- Loki label-indeks vs ELK täisindeks — millal kumba
- Ühendatud dashboard, kus mõõdikud ja logid koos (LogQL + PromQL)

Eeltöö: päeva 1 labori kodutöö esitatud.
