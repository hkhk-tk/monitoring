---
tags:
  - Day3
  - Elasticsearch
  - OpenSearch
  - kava
---

# Päev 3 — Kava ja ettevalmistus

**23. mai 2026 · 10:00–14:30 · Haapsalu KHK**
**Teema:** Elasticsearch & OpenSearch — andmehaldus, klaster, otsing

---

## Päevakava

Klassis teeme **loengu-plokid + arutelud**. Iga ploki järel arutame koos: mida see tähendab teie organisatsioonis, mis erineb teie praktikast, mis ühtib. **Lab tehakse kodutööna** — omas tempos, Slack-is küsi kui jääd kinni.

| Kell | Min | Tegevus | Vorming |
|------|-----|---------|---------|
| 10:00–10:05 | 5 | Sissejuhatus + tutvumine + päeva kava | Klass |
| 10:05–10:35 | 30 | **Plokk 1** — Paradigm shift (Zabbix → andmehaldus) · Maastik 2026 · Ajalugu | Loeng |
| 10:35–10:55 | 20 | **Arutelu 1** — paradigm + maastik teie organisatsioonis | Arutelu |
| 10:55–11:05 | 10 | ☕ Paus | — |
| 11:05–11:35 | 30 | **Plokk 2** — Dokumendi-mudel (JSON, indeksid, mappings, data streams) · Stack ingestion (Beats / Logstash / Elastic Agent / OTel) | Loeng |
| 11:35–11:55 | 20 | **Arutelu 2** — teie praegune logimise stack ja struktuur | Arutelu |
| 11:55–12:10 | 15 | **Plokk 3** — Elasticsearch vs OpenSearch täna (komponendid, security, AWS, hinnad, kus kumb) | Loeng |
| 12:10–12:40 | 30 | 🍽️ Lõuna | — |
| 12:40–13:05 | 25 | **Plokk 4** — Klastri arhitektuur · ILM (shardid, replicad, quorum, hot/warm/cold tiers, snapshots) | Loeng |
| 13:05–13:20 | 15 | **Arutelu 4** — teie cluster sizing ja log-retention | Arutelu |
| 13:20–13:35 | 15 | **Plokk 5** — APM ja traces · Kibana monitooringule (Discover, Dashboards, Alerting, ML AD) | Loeng |
| 13:35–13:50 | 15 | **Arutelu 5** — APM ja Kibana praktikas teil | Arutelu |
| 13:50–14:00 | 10 | ☕ Mini-paus | — |
| 14:00–14:15 | 15 | **Plokk 6** — Otsing: BM25 vs vector vs hybrid · RAG monitooringus | Loeng |
| 14:15–14:25 | 10 | **Arutelu 6** — vector search ja RAG teie kontekstis | Arutelu |
| 14:25–14:30 | 5 | Refleksioon + kodutöö selgitamine | Klass |

**Aja jaotus:** loengut ~130 min (6 plokki) · arutelusid ~80 min (5 vooru) · pausid + lõuna 50 min · sissejuhatus + lõpp 10 min. **Klassis ei tee laborit** — kogu praktiline osa on kodutööna.

## Arutelude küsimused

Klassis arutame **konkreetseid asju teie töökeskkonnast**. Kui mõtled need enne klassi läbi, saad teiste kogemustele juurde lisada. Need pole testiküsimused — need on **mõtlemise lähtekohad**.

### Arutelu 1 (10:35–10:55) — paradigm + maastik

- Kuidas teie organisatsioonis on logimise / monitooringu paradigma — Zabbix-stiili host-tsentriline, andme-tsentriline (ELK / Loki / Splunk), või segu?
- **Iceberg**, **OpenTelemetry**, **vector search / RAG** — millised neist on teil juba kasutuses, milliseid plaanite? Mis takistab?
- Kas **Splunki hinnamuutus** või **Palo Alto omandamine** on sundinud alternatiivi otsima?

### Arutelu 2 (11:35–11:55) — logimise struktuur ja ingestion

- Teie logid praegu — **JSON-struktureeritud** (`{"level":"error", ...}`) või vabakujuline tekst (`May 22 ERROR: ...`)?
- Ingestion-stack — Beats, Logstash, Elastic Agent + Fleet, Fluent Bit, OTel Collector — **mis on praegu** ja **mida tahaks asendada**?
- Logide-maht päevas — kas Kafka / Redis vahepuhver on olemas, või klaster otse vastu võtab?
- **ECS** (Elastic Common Schema) — kasutate või on oma sõnastik?

### Arutelu 4 (13:05–13:20) — cluster sizing ja retention

- Teie ES / OS klaster — **mitu master**, mitu data node, multi-AZ või single-AZ?
- Hot → Warm → Cold → Frozen — millised tier'id on **tegelikult kasutusel**? Kus on pinge?
- Logide **retention** — kui kaua hoiate? Kus on **kulu peamine kasvataja**? Kas audit-nõue vs operativ-vajadus on tasakaalus?
- Snapshot S3-le — tehtud? **Restore testitud**?

### Arutelu 5 (13:35–13:50) — APM ja Kibana

- **APM** — Elastic, Jaeger, Tempo, Datadog APM, või pole veel? Mis platvormi-lukustus risk?
- **Kibana Alerting (Rules)** — kasutate või endiselt **Watcher**? Kuhu alertid lähevad (Slack, PagerDuty, e-mail, webhook)?
- **Stack Monitoring** — kasutate self-monitoring jaoks?
- **ML Anomaly Detection** — proovinud? Mis tulemusega — worth-it või over-engineered?

### Arutelu 6 (14:15–14:25) — vector search ja RAG

- Vector search teil — kus näete **reaalset väärtust**: incident response AI, runbook-otsing, alert-korrelatsioon, postmortem auto-draft, semantic log search?
- LLM-eksperimendid teie firmas — Bedrock, OpenAI API, Anthropic, on-prem mudel, või veel pole?
- Hybrid search (BM25 + vector) — plaanite migreerida, või praegune BM25 piisab?

## Õpiväljundid

Päeva lõpuks osaleja:

- **Selgitab**, miks logide salvestus JSON-dokumentidena teeb võimalikuks structured search ja millega see erineb tekstifaili `grep`-ist
- **Eristab** Beats, Logstash, Elastic Agent + Fleet ja OpenSearchi ingestion-tööriistu (Data Prepper, Fluent Bit, OTel Collector) ning otsustab, milline kuhu sobib
- **Kirjeldab** time-based indeksite, mappings'ute, templates'i, alias'te ja data streams'i rolli logide-monitooringus
- **Põhjendab**, miks production-klastris on **3** master-kandidaati (quorum-matemaatika) ja mis juhtub split-brain'iga
- **Kirjeldab** APM-i rolli Elastic Stack'is (traces) ja seletab, miks APM-klastri sizing ≠ logide-klastri sizing
- **Loetleb** Kibana monitooringu-funktsioone (Discover, Dashboards, Stack Monitoring, Alerting, ML Anomaly Detection) ja nende OpenSearch-vasted
- **Eristab** lexical otsingut (BM25) ja vector otsingut (HNSW) — millal kumb monitooringu-kontekstis sobib
- **Otsustab**, millal valida Elastic Cloud, Elasticsearch on-prem, Amazon OpenSearch Service, OpenSearch Serverless või OpenSearch on-prem

**Kodutööst:**

- **Ehitab** 3-node Elasticsearch klastri Docker Compose'iga, simuleerib node-kadu ja näeb YELLOW → GREEN recovery'd
- **Käivitab** OpenSearch 3-node + OS Dashboards võrdluseks
- **Eksperimenteerib** kNN vector päringuga monitooringu-kontekstis

## Kodutöö — Lab Päev 3

Klassipäeva järel teete laborid omas tempos. Hinnanguline aeg: **~3 tundi**.

[**📘 Lab Päev 3 — ELK Stack & OpenSearch**](../labs/03_elk_stack/lab.md)

Sisu:

- **Osa 1** — ES + Kibana single-node, YELLOW state, esimene KQL päring
- **Osa 2** — 3-node klaster, node-kill simulatsioon, recovery
- **Osa 3** — OpenSearch + OS Dashboards, võrdlus Elasticuga
- **Osa 4** — kNN vector demo

**Küsi Slackis** kui jääd kinni — kanal `#paev3-elk`. Vasta esmalt teistele kui suudad — õpetamine teistele kinnistab.

## Laborikeskkond

Iga osaleja: oma VM (6 GB RAM, 4 CPU, Docker eelinstallitud) + ühised target-masinad.

| Teenus | Port | Kirjeldus |
|--------|------|-----------|
| Elasticsearch | 9200 | 3-node klaster ~/paev3/elk |
| Kibana | 5601 | Stack Monitoring, Discover |
| OpenSearch | 9200 (peale ES alla) | 3-node klaster ~/paev3/os |
| OS Dashboards | 5601 (peale Kibana alla) | OS UI |

**Töökaustad VM-il:**

- `~/paev1/` — Prometheus + Grafana (alla viia)
- `~/paev2/zabbix/`, `~/paev2/loki/` — Päev 2 (alla viia)
- `~/paev3/elk/` — Elasticsearch + Kibana
- `~/paev3/os/` — OpenSearch + OS Dashboards

!!! warning "RAM-piirang"
    Sinu VM-il on 6 GB RAM. 3-node ES + Kibana = ~5.5 GB. **OpenSearchi käivitamise eel** tuleb ES `docker compose down` teha — ei mahu paralleelselt.

Täpsed IP-d, kasutajanimed, paroolid: [VM ligipääs](../resources/vm-access.md).

## Järgmine kord (30.05)

Neljandal päeval vaatleme **TICK Stack** (InfluxDB 3 Core, Telegraf, Chronograf, Kapacitor) ja **kesksed logimissüsteemid** (rsyslog, syslog-ng, journald + remote, log shippers). Õpid:

- TICK vs Prometheus pull-mudeli erinevus aegridade salvestuses
- InfluxDB 3 Core uue arhitektuuri eripära (Parquet + Iceberg)
- "Centralized logging architecture" praktikas
- Millal valida TICK vs Prometheus vs ELK aegridade jaoks

**Eeltöö:** Päev 3 cheat sheet välja prinditud või kuvarinurka — kasutame Päev 4 võrdluseks.
