# Päev 1 — Kava ja ettevalmistus

**18. aprill 2026 · 10:00–14:30 · Haapsalu KHK**

## Päeva ülesehitus

| Kell | Kestus | Mida teeme | Kus |
|------|--------|------------|-----|
| 10:00–10:15 | 15 min | Tutvumine, ülevaade kursusest, tehnilised kontrollid | Klass |
| 10:15–10:45 | 30 min | **Loeng 1** — monitooring, logimine, observability | Klass |
| 10:45–11:30 | 45 min | **Loeng 2** — Prometheus arhitektuur, pull-mudel, andmemudel | Klass |
| 11:30–11:45 | 15 min | **Paus** | — |
| 11:45–12:30 | 45 min | **Labor osa 1** — Docker Compose stack üles | Oma VM |
| 12:30–13:00 | 30 min | **Lõunapaus** | — |
| 13:00–13:30 | 30 min | **Labor osa 2** — PromQL harjutused | Oma VM |
| 13:30–14:05 | 35 min | **Labor osa 3** — Grafana dashboard USE meetodiga | Oma VM |
| 14:05–14:25 | 20 min | **Labor osa 4** — Alerting + kaose test | Oma VM |
| 14:25–14:30 | 5 min | Kokkuvõte, järgmise päeva eelvaade | Klass |

## Enne klassi

**Lugemine (ligikaudu 75 min kokku):**

1. [Loeng 1: Monitooring, logimine, vaatlus](lectures/paev1-observability.md) — ~30 min
2. [Loeng 2: Prometheus ja Grafana](lectures/paev1-loeng.md) — ~45 min

**Tehniline kontroll:**

- [ ] SSH ligipääs VM-ile töötab ([vm-access](../resources/vm-access.md))
- [ ] Kas VPN töötab (kui töötad kodust)?
- [ ] Terminal ja brauser käepärast
- [ ] Docker ja `docker compose` VM-il (eelinstallitud)

## Õpiväljundid

Päeva lõpuks osaleja:

- **Eristab** logimise, seire ja observability kontseptsioone, seostab need sellega, milliseid küsimusi iga sammas vastab
- **Rakendab** USE ja RED meetodeid konkreetse süsteemi jälgitavuse kavandamisel
- **Ehitab** töötava Prometheus + Grafana + Alertmanager stacki Docker Compose'iga
- **Kirjutab** PromQL päringuid kolmele erinevale mõõdikutüübile (counter, gauge, histogram)
- **Kavandab** Grafana dashboardi USE raamistiku järgi, sealhulgas dünaamilised muutujad
- **Konfigureerib** alertireegli ja demonstreerib olekumuutust Pending → Firing

## Laborikeskkond

Iga osaleja: oma VM (4 GB RAM, 2 CPU, Docker eelinstallitud) + jagatud `mon-target` ja `mon-target-web` masinad.

| Teenus | Port | Kirjeldus |
|--------|------|-----------|
| Prometheus | 9090 | Andmekogumine ja PromQL |
| Grafana | 3000 | Visualiseerimine |
| Alertmanager | 9093 | Hoiatuste haldamine |
| node_exporter | 9100 | Süsteemi mõõdikud (VM-il endal) |

Täpsemad IP-d ja sisselogimisandmed: [VM ligipääs](../resources/vm-access.md).

## Järgmine kord (25.04)

Teisel päeval vaatleme agent-põhist monitooringut (**Zabbix**) ja Grafana ökosüsteemi logimislahendust (**Loki** + Promtail). Õpid kuidas:

- Zabbix-agent erineb Prometheus pull-mudelist ja millal kumba eelistada
- Loki indekseerib logisid label'ite järgi (mitte täissisu kaupa nagu ELK)
- Dashboard ühendab mõõdikud ja logid ühele vaatele (LogQL + PromQL koos)

Eeltöö enne 25.04: päev 1 labori kodutöö esitatud.
