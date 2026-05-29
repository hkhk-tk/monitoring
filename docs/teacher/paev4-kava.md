---
tags:
  - Day4
  - TICK
  - InfluxDB
  - SIEM
  - Wazuh
  - kava
---

# Päev 4 — Kava ja ettevalmistus

**30. mai 2026 · 10:00–14:30 · Haapsalu KHK**
**Teema:** TICK Stack (InfluxDB 3) + kesksed logimissüsteemid ja SIEM

---

## Päevakava

Päev on kahes osas. **Hommik:** aegread ja TICK Stack käed-külge omal VM-il. **Pärastlõuna:** kesksed logimissüsteemid ja SIEM — loeng + arutelu, sest seda osa hands-on ei tee (OpenSearchi ehitasid juba päev 3, Wazuh ja Kafka on liiga rasked ühe päeva laborisse). Lab osad 5–7 jäävad koju.

| Kell | Min | Tegevus | Kus |
|------|-----|---------|-----|
| 10:00–10:10 | 10 | **Kordamine** — "mis vahe on Prometheuse pull-mudelil ja aegrea-andmebaasil?" Lase arvata enne seletamist | Klass |
| 10:10–10:20 | 10 | **TICK kontsept** — InfluxDB 3 Core, T-I-C-K → konsolideeritud, miks aegread eraldi DB. Paralleel Prometheus+Grafanaga | Klass |
| 10:20–11:05 | 45 | **TICK hands-on** — InfluxDB 3 Core + Telegraf + Explorer Docker Compose'iga, line protocol, esimene SQL päring (lab osad 1–3) | Oma VM |
| 11:05–11:15 | 10 | ☕ Paus | — |
| 11:15–11:35 | 20 | **Telegraf + SQL** — agent kogub süsteemimeetrikad, päring SQL-iga (lab osa 4) | Oma VM |
| 11:35–11:55 | 20 | **Arutelu: TICK vs Prometheus** — push vs pull, kardinaalsus, millal kumba (IoT/aegread vs cloud-native) | Klass |
| 11:55–12:25 | 30 | 🍽️ Lõuna | — |
| 12:25–12:40 | 15 | **Bridge: kesksed logimissüsteemid** — maastiku kaart tahvlile. "Nägite Loki (päev 2), ELK + OpenSearch (päev 3). Mis veel ja miks?" | Klass |
| 12:40–13:00 | 20 | **SIEM kui mõiste** — logimine vs SIEM, EDR/XDR/SOAR/MDR kihid lühidalt, NIS2 kontekst | Klass |
| 13:00–13:30 | 30 | **Wazuh — konkreetne SIEM** — arhitektuur (agent/manager/indexer/dashboard), Wazuhi indekseerija = OpenSearch (side päev 3-le), Active Response kontsept. **Demo kui testitud**, muidu screenshot-läbikäik | Klass |
| 13:30–13:40 | 10 | ☕ Paus | — |
| 13:40–14:00 | 20 | **Apache Kafka logimises** — miks puhver, producers → Kafka → consumers, suure mahuga keskkonna skaala. Kontseptuaalne, installi ei tee | Klass |
| 14:00–14:25 | 25 | **Kokkuvõte: logimise + SIEM maastik** — tabel tahvlile ([cheat sheet](../materials/lectures/paev4-cheat-sheet.md)). "Mida teie oma organisatsioonis?" | Klass |
| 14:25–14:30 | 5 | Refleksioon + kodutöö (lab osad 5–7) | Klass |

**Aja jaotus:** TICK hands-on ~65 min · loeng/bridge ~85 min · arutelu + kokkuvõte ~45 min · pausid + lõuna 50 min · algus/lõpp 25 min.

## Meetod

Päev järgib **Kolbi tsüklit**, aga kahe erineva rütmiga:

- **Hommik (TICK)** — kogemus enne teooriat. InfluxDB 3 läheb käima enne, kui seletame line protocoli ja aegrea-mudelit. Sa kirjutad ise iga punkti ja iga SQL päringu, ei vaata ekraanilt.
- **Pärastlõuna (SIEM + maastik)** — kontseptuaalne, sest hands-on'i siin ei jõua. Rõhk on **valima oskamisel**, mitte nimede teadmisel: millal TICK, millal SIEM, millal Kafka-puhver. Iga ploki järel arutelu "mis on teil tööl".

## Enne klassi

**Lugemine:**

1. [Päev 4 loeng](../materials/lectures/paev4-loeng.md) — eelduslik enne klassi (~90 min); klassis 10:00–14:30 jutustus + lab
2. [Otsustustabelid](../materials/lectures/paev4-cheat-sheet.md) — valikuline, klassi kokkuvõtteks

Need on **eelduslikud**. Klassiajal hommikul teeme, ei loe — aeg on praktikaks.

**Tehniline kontroll:**

- [ ] SSH ligipääs VM-ile töötab ([vm-access](../resources/vm-access.md))
- [ ] VPN ühendub (kui töötad kodust)
- [ ] Päev 3 ELK/OpenSearch stack VM-il **maha pandud** (`docker compose down` — vabasta mälu, TICK vajab ~2 GB)
- [ ] `docker` ja `docker compose` VM-il töötavad

## Õpiväljundid

Päeva lõpuks osaleja:

- **Selgitab**, miks aegread vajavad eraldi andmebaasi (mitte PostgreSQL-i), ja toob kaks olukorda kummagi — InfluxDB ja Prometheus — kasuks
- **Ehitab** InfluxDB 3 Core + Telegraf + Explorer stacki Docker Compose'iga, loob tokeni ja andmebaasi
- **Kirjutab** line protocol rea ja päringustab andmeid SQL-iga
- **Eristab** lihtsat logimist ja SIEM-i, ning kirjeldab Wazuhi nelja komponenti ja Active Response'i rolli
- **Põhjendab**, miks Kafka logitorudes puhvrina eksisteerib
- **Valib** kesksete logimislahenduste vahel (Loki / ELK / OpenSearch / SIEM) kriteeriumide alusel oma organisatsiooni kontekstis

## Laborikeskkond

Iga osaleja: oma VM (4 GB RAM, 2 CPU, Docker eelinstallitud). TICK on kerge — InfluxDB 3 Core + Explorer + Telegraf mahuvad mängleva kergusega, kui päev 3 stack on maas.

| Teenus | Port | Kirjeldus |
|--------|------|-----------|
| InfluxDB 3 Core | 8181 | Aegrea-andmebaas, SQL päringud |
| InfluxDB 3 Explorer | 8888 | Veebiliides — haldus ja päring |
| Telegraf | — | Agent, kogub süsteemimeetrikad (ei kuula porti) |

Täpsed IP-d, kasutajanimed, paroolid: [VM ligipääs](../resources/vm-access.md).

## Arutelude lähtekohad

Klassis arutame **konkreetseid asju teie töökeskkonnast** — need pole testiküsimused.

**TICK vs Prometheus (11:35):**

- Kus su praeguses süsteemis aegread juba tekivad — ja kas Prometheus piisab, või tuleks pikaajaliseks hoiuks eraldi TSDB?
- Push vs pull — kumb su keskkonda paremini sobib ja miks?

**SIEM (pärastlõuna):**

- Kas su organisatsioon on **NIS2** mõjualas? Mis see logimisele ja juhtumikäsitlusele tähendab?
- Kasutate juba SIEM-i (Splunk, Sentinel, Wazuh, midagi muud), või on logid praegu "ainult logid"?
- Kui ehitaksid Wazuhi piloodi — millised hostid esimesena, mis reeglid?

**Maastik (kokkuvõte):**

- Loki vs ELK vs OpenSearch vs SIEM — maksumus, keerukus, skaala, otsinguvõimekus. Mida teie oma kontekstis valiksite?

## Järgmine kord (6.06)

Viiendal päeval **Tempo + OpenTelemetry** — hajutatud jälgimine (distributed tracing), kolmas sammas. Seome kõik viis päeva kokku **LGTM stackiga** (Loki + Grafana + Tempo + Mimir) ja vaatame **2026 trende**. Õpid:

- Trace, span, context propagation — kuidas üks päring läbi mitme teenuse jälgitavaks teha
- OpenTelemetry kui vendor-neutraalne standard instrumenteerimisele
- Kus kogu kursuse jooksul õpitu (metrics, logs, traces) ühte pildi kokku saab

Eeltöö: päeva 4 labori kodutöö (osad 5–7) esitatud.
