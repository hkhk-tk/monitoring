---
tags:
  - Day4
  - TICK
  - InfluxDB
  - SIEM
  - cheat-sheet
---

# Päev 4 — Otsustustabelid (võta töö juurde kaasa)

Need tabelid on igapäevaseks otsuseks, mitte loengu meeldejätmiseks. Loeng: [Päev 4 loeng](paev4-loeng.md).

---

## TICK — vanast uueks

| Põlvkond | Komponendid | Päring |
| --- | --- | --- |
| **1.x TICK** | Telegraf + InfluxDB + Chronograf + Kapacitor (4 programmi) | InfluxQL |
| **2.x** | Telegraf + InfluxDB (UI ja hoiatused sees) | Flux + InfluxQL |
| **3.x (lab)** | Telegraf + InfluxDB 3 Core + Explorer | SQL + InfluxQL |

**Mis kuhu:** Chronograf → Explorer · Kapacitor → Processing Engine · Line protocol sama alates 1.x.

---

## TICK vs Prometheus

| Sinu olukord | Vali | Miks |
| --- | --- | --- |
| Kubernetes, mikroteenused, `/metrics` endpoint | **Prometheus** | Pull-mudel, PromQL, ökosüsteem valmis |
| Tööstusandurid, MQTT/Modbus, push vajalik | **InfluxDB + Telegraf** | Agent saadab ise, SQL/line protocol |
| Mõlemad korraga | **Mõlemad** | Prometheus lühiajal, InfluxDB pikaajaline hoid |
| Batch-töö, lühike eluiga | Prometheus **Pushgateway** | Erand pull-mudelis, mitte püsiv push |

---

## Loki vs ELK/OpenSearch vs SIEM

| Sinu olukord | Vali | Miks |
| --- | --- | --- |
| Odav logi, Grafana juba olemas, otsid sildi järgi | **Loki** | Indekseerib vähe, RAM-sõbralik |
| Täisteksti, forensika, keerukad päringud | **ELK / OpenSearch** | Täisindeks, võimas analüütika |
| Turvajuhtumid, korrelatsioon, juhtumid | **SIEM** (Wazuh, Sentinel, Splunk) | Reeglid, ATT&CK, Active Response |
| Logid olemas, turva eraldi | **Kaks stacki** | Loki/ELK operatiivseks, SIEM turvaks |

Valikukriteeriumid: **maksumus**, **keerukus** (kes hooldab), **skaala** (logimaht päevas), **otsing** (silt vs täistekst), **turvafookus** (juhtumid vs otsing).

---

## Millal Kafka vahele?

| Sinu olukord | Kafka? | Miks |
| --- | --- | --- |
| Väike keskkond, üks shipper → üks salvestus | **Ei** | Lihtsam toru, vähem hooldust |
| Logimaht > ~100 GB/päev | **Jah** | Puhver neelab tipud (vt Päev 3) |
| Mitu consumer'it (ELK + SIEM + arhiiv) | **Jah** | Üks voog, mitu lugejat |
| Klaster hoolduse ajal ei tohi logisid kaotada | **Jah** | Sõnumid jäävad Kafkasse |

---

## Wazuh — neli komponenti

| Komponent | Roll |
| --- | --- |
| **Agent** | Kogub logid, protsessid, failimuutused hostist |
| **Manager** | Reeglid, korrelatsioon, Active Response |
| **Indexer** | Salvestus (OpenSearch-põhine) |
| **Dashboard** | UI (OpenSearch Dashboards-põhine) |

---

*Klassi kava: [Päev 4 kava](../../teacher/paev4-kava.md) · Labor: [tick_lab.md](../../labs/04_tick_keskne_logimine/tick_lab.md)*
