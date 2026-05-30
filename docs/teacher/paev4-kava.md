---
tags:
  - Day4
  - TICK
  - InfluxDB
  - SIEM
  - Wazuh
  - kava
---

# Päev 4 — TICK Stack + kesksed logimissüsteemid

**30. mai 2026 · 10:00–14:30 · Haapsalu KHK**

Kaks osa. **Hommik:** aegread ja TICK Stack käed-külge omal VM-il. **Pärastlõuna:** kesksed logimissüsteemid ja SIEM loenguna — hands-on'i siin ei tee (OpenSearchi ehitasid päev 3; Wazuh ja Kafka on liiga rasked ühe päeva laborisse). Lab osad 5–7 jäävad koju.

## Päevakava

| Kell | Tegevus | Kus |
|------|---------|-----|
| 10:00–10:20 | Kordamine + TICK kontsept — pull-mudel vs aegrea-DB, T-I-C-K, miks aegread eraldi DB | Klass |
| 10:20–11:05 | **TICK hands-on** — InfluxDB 3 Core + Telegraf + Explorer, line protocol, esimene SQL (lab 1–3) | Oma VM |
| 11:05–11:15 | ☕ Paus | — |
| 11:15–11:35 | **Telegraf + SQL** — agent kogub süsteemimeetrikad (lab 4) | Oma VM |
| 11:35–11:55 | Arutelu: TICK vs Prometheus — push vs pull, kardinaalsus | Klass |
| 11:55–12:25 | 🍽️ Lõuna | — |
| 12:25–13:00 | Kesksed logimissüsteemid + SIEM mõiste — logimine vs SIEM, EDR/XDR/SOAR, NIS2 | Klass |
| 13:00–13:30 | **Wazuh** — arhitektuur (agent/manager/indexer/dashboard), indekseerija = OpenSearch, Active Response | Klass |
| 13:30–13:40 | ☕ Paus | — |
| 13:40–14:00 | Apache Kafka logitorudes — miks puhver, producers → Kafka → consumers | Klass |
| 14:00–14:25 | Kokkuvõte: logimise + SIEM maastik ([cheat sheet](../materials/lectures/paev4-cheat-sheet.md)) | Klass |
| 14:25–14:30 | Refleksioon + kodutöö (lab 5–7) | Klass |

## Enne klassi

**Loe ette** (klassiajal teeme, ei loe): [Päev 4 loeng](../materials/lectures/paev4-loeng.md) (~90 min). [Otsustustabelid](../materials/lectures/paev4-cheat-sheet.md) on valikuline.

**Kontrolli oma VM:**

- [ ] SSH + VPN töötab ([VM ligipääs](../resources/vm-access.md))
- [ ] Päev 3 ELK/OpenSearch stack maas: `docker compose down` (TICK vajab ~2 GB vaba mälu)
- [ ] `docker` ja `docker compose` töötavad

!!! warning "Kui `docker pull` jääb toppama"
    Kui näed `Image ... Pulling` ja see ei liigu: VM-il pole töötavat IPv6 ühendust, aga Docker proovib seda enne IPv4-le langemist. Lülita IPv6 välja ja proovi uuesti:
    ```bash
    sudo sysctl -w net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1
    sudo systemctl restart docker
    ```

## Õpiväljundid

Päeva lõpuks osaleja:

- **Selgitab**, miks aegread vajavad eraldi andmebaasi (mitte PostgreSQL-i), ja toob kaks olukorda kummagi — InfluxDB ja Prometheus — kasuks
- **Ehitab** InfluxDB 2.7 + Telegraf stacki Docker Compose'iga, läbib esmase seadistuse (org, bucket, token)
- **Kirjutab** line protocol rea ja päringustab andmeid Flux'iga (UI Data Explorer)
- **Eristab** lihtsat logimist ja SIEM-i, kirjeldab Wazuhi nelja komponenti ja Active Response'i rolli
- **Põhjendab**, miks Kafka logitorudes puhvrina eksisteerib
- **Valib** kesksete logimislahenduste vahel (Loki / ELK / OpenSearch / SIEM) oma organisatsiooni kontekstis

## Laborikeskkond

Oma VM: 4 GB RAM, 2 CPU, Docker eelinstallitud. TICK on kerge ja mahub mängleva kergusega, kui päev 3 stack on maas.

!!! note "Miks InfluxDB 2.7, mitte 3?"
    Lab-serverite CPU (Intel Xeon E5-2660, Sandy Bridge) ei toeta **AVX2** käsustikku, mida InfluxDB 3 binäär nõuab — v3 sureb käivitamisel (SIGILL, exit 132). Seetõttu kasutame **InfluxDB 2.7** (Go binäär, töötab igal CPU-l). Kontseptsioonid on samad; erinevus on päringukeel: v2.7 kasutab **Flux**'i (või InfluxQL v1-compat kaudu), mitte SQL-i nagu v3.

| Teenus | Port | Kirjeldus |
|--------|------|-----------|
| InfluxDB 2.7 | 8086 | Aegrea-andmebaas + veebiliides (UI sissehitatud, eraldi Explorerit pole) |
| Telegraf | — | Agent, kogub süsteemimeetrikad (ei kuula porti) |
| Mosquitto (MQTT) | 1883 | Sensorite brokker — osa 7 (kodutöö) |

UI sisselogimine: **admin / Monitor2026!** · org `hkhk` · bucket `mon`. Täpsed IP-d: [VM ligipääs](../resources/vm-access.md).

## Järgmine kord (6.06)

**Päev 5 — Tempo + OpenTelemetry**: hajutatud jälgimine (distributed tracing), kolmas sammas. Seome kõik viis päeva kokku **LGTM stackiga** (Loki + Grafana + Tempo + Mimir) ja vaatame 2026 trende. Eeltöö: päev 4 kodutöö (lab osad 5–7) esitatud.
