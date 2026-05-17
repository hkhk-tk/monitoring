---
tags:
  - Elasticsearch
  - OpenSearch
  - VectorSearch
  - AI
  - Day3
---

# Päev 3: Elastic Stack & OpenSearch — kust tuli, kus on, kuhu läheb

**Kursus:** Kaasaegne IT-süsteemide monitooring ja jälgitavus
**Kestus:** ~60 min loengut, hajutatud läbi päeva — L1 (30 min) avamisel, L2 (15 min) enne klastri-laienemist, L3 (15 min) enne vector-osa
**Tase:** Kesktase → kesk-edasijõudnud. Eeldame, et logimine on selge (Päev 2, Loki), Docker mitme-konteineri stack on selge
**Eeldused:** Päev 1 (observability kolm sammast, Prometheus pull-mudel) · Päev 2 (Zabbix host-tsentriline, Loki + Promtail, label vs sisu indekseerimine)

---

## Õpiväljundid

Pärast seda loengut oskad:

- **Selgitada**, kuidas tööstus liikus klassikalisest host-tsentrilisest seirest (Zabbix) andme-tsentrilisele observability'le ja milline jõud seda muutust ajas
- **Eristada** Elasticsearchi ja OpenSearchi: kust ühine tüvi, miks lahkuminek 2021, kuidas seis 2026
- **Kirjeldada** Elasticsearchi sõlmerolle (master, data, ingest, coordinating) ja kuidas shardid + replica'd päringut teenindavad
- **Põhjendada**, miks tõsiselt mõeldud klastris on vähemalt 3 dedicated master sõlme ja mis on quorum
- **Eristada** lexical otsingut (BM25 inverted index'iga) ja vector otsingut (HNSW lähimnaaber-graafiga)
- **Selgitada**, mis on ELSER, `semantic_text`, OpenSearch neural search, FAISS ja RAG muster
- **Otsustada**, millal valida Elastic Cloud, Elasticsearch on-prem, Amazon OpenSearch Service, OpenSearch Serverless või OpenSearch on-prem

---

## L1.0 — Zabbixilt andmehaldusele: paradigm shift

> **Loengu osa 0**, kohe peale õpiväljundeid. ~5 min, enne L1.1 maastiku osa.  
> **Miks see sulle oluline:** annab sulle argumendi managementile — miks Zabbixist (mis on klassikaline ja stabiilne) üksi enam ei piisa ja milleks teie organisatsioonis ELK / OpenSearch / Loki kihiks vaja läheb.

Eile tutvusid Zabbixiga. Sa nägid neli mõistet ahelas — **Host → Item → Trigger → Action**. See on klassikaline arhitektuur, mis on töötanud 25 aastat: sa tead, **mis hostid** sul on, **mida nendelt mõõdad** ja **mis tingimustel hoiatust saadetakse**. Iga element on eeldefineeritud, schema on jäik.

Pärastlõunal lisasid sinna Loki. Loki tõi logide tsentraliseerimise — sa ei pea enam SSH-ga 50 serverisse logima, et `grep ERROR` teha. See näeb välja lihtsalt mugavusena. Aga see on tegelikult **palju enamat** — see on osa **paradigm shift'ist**, mida tööstus on viimase 10 aasta jooksul teinud.

### Kaks paradigmat kõrvuti

| | Klassikaline (Zabbix) | Andme-tsentriline (ELK / OS / TICK / Loki) |
|---|---|---|
| **Põhi-küsimus** | "Mu host on X, mida ma sellelt mõõdan?" | "Mul on andmed, mida ma neilt küsida saan?" |
| **Andmemudel** | Schemaful (Item = nimi + tüüp + intervall) | Schema-less (dünaamiline mapping, JSON-id) |
| **Päringud** | **Eeldefineeritud** (Trigger avaldis) | **Ad-hoc** (jooksvalt loodud KQL, ESQL, LogQL) |
| **Skaala suund** | Rohkem hoste, rohkem agente | Rohkem andmesõlmi, rohkem shardide |
| **Sa tead** | **ette**, mida sa otsid | **avastad** mustreid andmetest |

See ei ole tehnoloogiline mood, vaid vastus reaalsetele probleemidele. Neli jõudu, mis selle pöörde tekitasid.

### 1. Cloud-native — host pole enam stabiilne entity

Zabbix eeldab, et **`host` on stabiilne objekt** — sa lood selle UI-s, seod template'iga ja jälgid kuid või aastaid. Kubernetes maailmas ei toimi see. Pod tuleb ja kaob iga 4 minuti tagant, IP-aadress muutub, replica arv skaleerub 3-st 30-le ja tagasi. Kui sa lood Zabbixi host'i iga pod'i kohta, oled hommikul 5000 surnud host'iga.

K8s-mõtteviis on hoopis: **"andmed on entity"**. Pod kirjutab logisid ja metricsid stdout'ile, agent kogub kõik, paneb sildid külge (`namespace=prod, app=api, pod=api-7d4f`), saadab tsentraalsesse storage'sse. Pärast saab päringuga küsida `{app="api", namespace="prod"}` — pole tähtis, mis IP, mis pod, mis hetkest mis hetkeni. Andmed räägivad ise.

### 2. Andmemahud on kasvanud 100x

10 aastat tagasi: tüüpiline keskmise suurusega ettevõte genereeris ~10 GB logisid päevas. Täna: sama suurusega ettevõte mikroteenuste arhitektuuriga genereerib **1–10 TB logisid päevas**. Suuremad SaaS-ettevõtted ja telekomid liiguvad **50–500 TB/päev** suunas. Datadogi 2024 "State of Cloud Costs" raport [^datadog2024] näitab, et **observability andmemahud kasvavad keskmiselt 20–30% aastas** ettevõtetel, mis migreeruvad pilve ja mikroteenustele.

Zabbixi MySQL/PostgreSQL andmebaas saab koormatud — Zabbix on hostide ja itemite jaoks loodud, mitte miljardite sündmuste salvestamiseks.

ELK, OpenSearch, Loki, Splunk on **algusest peale** ehitatud horisontaalselt skaleeruva andmehoidlana. Shardid, replica'd, object storage. Andmetagavara kasv lahendatakse rohkem sõlmede lisamisega.

### 3. Otsingu ja korrelatsiooni vajadus

Zabbix vastab küsimusele: **"kas miski on katki?"** — kena, aga see ei ole alati piisav. Kui kasutaja kaebab "API on aeglane esmaspäeval pärast kella 14:00", tahad sa küsida:

- Mis päringud olid sel ajal aeglased? (logid)
- Mis SQL-päringud sel ajal andmebaasi koormasid? (logid)
- Mis hosti pealt päringud tulid? (logid + trace'id)
- Kas mingi deploy juhtus äsja enne? (audit-logid)
- Kas seda mustrit on varem nähtud? (ajalooline agregeerimine)

Need on **ad-hoc päringud**, mis avastavad mustreid. Zabbix Trigger ei oska seda — ta vastab ainult sellele, mille jaoks ta on eelnevalt seadistatud. ELK / OS Kibana Discover, OpenSearch Dashboards, Loki Explore — kõik on disainitud just selliseid avastamise-päringuid teha.

### 4. AI ja ML nõue

Anomaalia-tuvastus, root cause analysis, klastri-mustri leidmine, ennustav alerting — kõik need vajavad **andmebaasi**, mille peal saab agregeerida, statistikat teha, ML-mudeleid sõita. Threshold-trigger ("kui CPU > 80%, hoiata") on lihtne reegel; "ennusta järgmise 2 tunni põhjal, kas süsteem kukub" on hoopis teine asi.

Lisaks 2024–26 lisandus uus mõõde: **semantic search ja RAG** (vt L3 hiljem). LLM-id vajavad relevante dokumente ette anda — ja need dokumendid tulevad ELK / OS-st kui vector storage'st. Zabbix Item ei sobi RAG-ile.

### Pilt 2026 — mitte "üks asendab teist", vaid "koos töötavad"

Pärast seda pööret ei kao Zabbix kuhugi. **Ta elab edasi seal, kus klassikaline seire on õige tööriist:**

- Infrastruktuur (host CPU, mälu, ketas, võrk)
- Võrguseadmed (Cisco / MikroTik / HP SNMP-ga)
- Hardware-monitooring (IPMI, ventilaatorid, temperatuur, UPS)
- Stabiilsed pikaajalised teenused (PostgreSQL master, Nginx LB)

**ELK / OpenSearch / Loki / TICK on lisaks** — andmehalduse kihid, mis tegelevad:

- Logidega (struktureeritud ja mitte)
- Forensikaga (mis konkreetselt juhtus tunni X jooksul)
- Full-text otsinguga (kasutaja kogemus)
- Semantic search'iga ja RAG-iga (uus 2024+)
- Multi-source korrelatsiooniga (metrics + logs + traces ühes vaates)

Tüüpiline modernne monitooringu-stack aastal 2026 koosneb mitmest kihist, mis teevad eri tööd:

- **Zabbix** — võrguseadmed, hardware, klassikaline host-monitooring
- **Prometheus + Grafana** — Kubernetes ja mikroteenuste mõõdikud
- **Loki** — operatiivsed logid Grafana Explore'is (kerge, odav)
- **Elasticsearch või OpenSearch** — forensika, audit-logid, full-text otsing, semantic search
- **Tempo + OpenTelemetry** — traces (Päev 5)

Niisiis täna ei õpi sa Zabbixi asendust — õpid täiendavat tööriistakihti, mis tegeleb teistsuguste probleemidega kui Zabbix.

!!! tip "💭 Mõtle hetk — enne edasilugemist"
    Sinu praeguse töökeskkonna logide ja sündmuste haldamine — kumb paradigma on sees? Klassikaline (host → item → trigger Zabbix-stiilis) või andme-tsentriline (logid kogutakse ühte storage'sse, päringud jooksvalt)? Või mõlemad korraga?

    Kui mõlemad — milline rahvas üle sinu meeskonna teeb kumba? Kas need on samad inimesed või eraldatud rollid?

---

## L1.1 — Maastik 2026

> **Loengu osa 1, hajutuse 1. plokk.** ~10 min, jätkub kohe L1.0 järel.  
> **Miks see sulle oluline:** aitab sul aru saada, millisesse ökosüsteemi tasub praegu panustada — Elastic-i suunda, OpenSearchi suunda, või Grafana LGTM suunda. Iga otsus lukustab sind aastateks.

Eelnev tabel ütleb mis paradigma muutus on. Aga miks just **praegu** on selle paradigma esindajad — Elastic Stack ja OpenSearch — sellised nagu nad on? Sest 2024–26 on observability-turul olnud rohkesti mängumuutuseid.

### Konsolideerimise laine

Viimase paari aasta jooksul on suured tegijad ostnud teisi suuri tegijaid:

- **Palo Alto Networks ostis Splunki** (sept 2024, ~$28 miljardit) [^palo-splunk] — Splunk muutub osaks security platvormist
- **Cisco** üritas Splunki osta, tehing ütleti 2024 alguses üles, Palo Alto astus sisse
- **IBM ostis HashiCorpi** (2024) — Terraform, Vault, Consul tulevad IBM-i pärandi alla
- **Datadog** kasvab agressiivselt, ostab väiksemaid (Codiac, Eppo, Voltron)
- **Grafana Labs** kasvab orgaaniliselt, hoiab open source'i ja paneb suure panuse LGTM stackile

Mida see sysadminile tähendab? **Vendor lock-in** on tagasi tulekul, isegi observability-ruumis, kus open source on olnud tugev. Iga kord, kui sa valid vendori, vaata litsentsi ja edasine ostumuster.

### Open source vastureaktsioon

Iga litsentsi-muutus tekitas forki:

- HashiCorpi Terraform → **OpenTofu** (Linux Foundation, 2023)
- HashiCorpi Vault → **OpenBao** (Linux Foundation, 2024)
- Elasticsearch → **OpenSearch** (AWS taga, **Linux Foundation septembris 2024** — OpenSearch Software Foundation moodustati neutraalse koduriigiga)
- MongoDB → ei ole tugevat forki (litsents jäi)

OpenSearch on 2026-l küpsuses: OpenSearch Foundationi raportite põhjal **sajad miljonid allalaadimised**, kümned tuhanded pull request'id ja kümned partnerid — see on üks suurimaid avatud otsingumootori projekte maailmas [^os-foundation]. AWS panustab sellesse jätkuvalt suuresti, aga ka Aiven, Logz.io, Oracle ja teised kontribueerivad.

2024 lõpus muutis Elastic litsentsi tagasi — lisas AGPL-i olemasolevatele SSPL + Elastic License valikutele. Shay Banon (Elastic-i looja) kirjutas blogiposti pealkirjaga "Elasticsearch is Open Source, Again". Hea PR, aga reaalsus on, et OpenSearch eksisteerib edasi ja kasvab.

### OpenTelemetry on võitnud instrumenteerimise

Üks asi, mis 2024–25 on selgelt välja kujunenud: **OpenTelemetry on muutunud de facto standardiks** rakenduste instrumenteerimisel. Datadog, Splunk, Elastic, Grafana, New Relic ja Dynatrace pakuvad kõigil OTel-põhist sisendit. See tähendab, et **rakenduse instrumenteerimine ei lukusta sind enam vendorile** — kui kirjutad oma rakenduse OTel SDK-ga, saad ükskõik kuhu eksportida.

See on tähtsam kui tundub. Tähendab, et tänapäeva mõistlik arhitektuur on: OTel rakenduses → OTel Collector → ükskõik mis backend (Datadog, Tempo, Jaeger, Elastic APM, OpenSearch). Sa saad vendori vahetada ilma rakenduse koodi puutumata.

### Andmesalvestuse standard tulemas

Vähem tuntud, aga sysadminile oluline: **Apache Iceberg** on kiiresti kujunemas üheks standardseks tabeliformaadiks logi- ja turbeandmete andmejärvedes. Splunk Federated Search/Analytics, Snowflake, Databricks ja teised platvormid lisavad tuge Iceberg-tabelitele, mis lubab hoida logisid ühises objektisalvestuses (S3) ja teha päringuid mitme tööriistaga. Praegu on see veel uuem suund, aga tasub teada.

### AI-pööre — vector search ja Bedrock

Ja siis on **AI-pööre**. Ei "agentic AI päästab kõik" turundus, vaid praktilised muutused:

- **Vector search** on saanud nõudeks. Elasticsearch 8.x lisas `dense_vector` field 2022, ELSER 2023, `semantic_text` 2024.
- **OpenSearch 2.x** sisaldab **neural search** ja **ML Commons** plugin'it, integreerib **FAISS**'i (Facebook AI Similarity Search) ja toetab Amazon SageMakeri ja Bedrocki mudeleid.
- **Amazon OpenSearch Serverless** on Bedrock Knowledge Bases'i peamine ja tihedalt integreeritud vector-backend; AWS-i referentsarhitektuur RAG-lahendustele kasutab seda vaikimisi.
- **RAG** (Retrieval-Augmented Generation) — muster, kus LLM enne vastamist küsib relevante dokumente vector storage'st. ELK ja OS on selleks andmebaasiks.

Klientidele ei piisa enam "leia logist sõna error" — nad tahavad semantic similarity, AI-powered alerting, hybrid search. Day 3 lõpuks vaatame `semantic_text` ja neural search praktikas. Aga enne — kust me siia jõudsime?

---

## L1.2 — Ajalugu, kust me siia jõudsime

> **Loengu osa 1, hajutuse 2. plokk.** ~8 min, jätkub samas blokis.  
> **Miks see sulle oluline:** aitab sul mõista, miks täna ELK ja OpenSearch ON kaks paralleelset projekti, kumb nendest on sinu olukorraga lähemal, ja miks järgmine sarnane litsentsi-drama tuleb tagasi (kui seda ei oska näha).

```mermaid
timeline
    title Elasticsearch & OpenSearch — võtmesündmused
    1999 : Apache Lucene<br/>(Doug Cutting, inverted index)
    2010 : Elasticsearch sünd<br/>(Shay Banon)
    2013 : ELK Stack<br/>(Elasticsearch + Logstash + Kibana)
    2015 : Beats lisandub<br/>Amazon ES Service käivitub
    2019 : Elastic vs AWS<br/>kohtuvaidlus + kompromiss
    2021 : Litsentsi-drama<br/>SSPL + Elastic License<br/>AWS forkib OpenSearchi (1.0)
    2023 : Vector search<br/>ES dense_vector + OS neural search<br/>FAISS integratsioon
    2024 : AGPL-3 lisandub Elasticile<br/>OpenSearch Software Foundation<br/>(Linux Foundation)<br/>semantic_text field<br/>Bedrock Knowledge Bases + OS Serverless
    2026 : Mõlemad open source<br/>mõlemad tootmiskolblikud<br/>valik = kontekst + meeskond
```

### 1999 — Apache Lucene sünd

Doug Cutting (sama mees, kes hiljem Hadoopi kirjutas) avaldab Java otsingulibrary nimega Lucene. Põhi-algoritm: **inverted index**. Sõna → dokumentide nimekiri, kus see sõna esineb. Sama põhi-idee, mis Elasticsearch'is tänapäeval kasutusel.

Lucene oli library, mitte server — programmeerija pidi selle oma rakendusse põimima.

### 2010 — Shay Banon ja Elasticsearch

Shay Banon, Iisraeli arendaja, kirjutas oma naise toidu-retseptide otsingusüsteemi jaoks Lucene peale REST API ja distribuiable klastri. Tegi sellest open source'i — Elasticsearch sünnib.

Asi võttis hoogu kiiresti — 2012 asutati Elastic NV (firma) Hollandis. Esimene major release 1.0 — 2014.

### 2013 — ELK Stack sünd

Logstash (alates 2009) ja Kibana (alates 2011) liideti samasse ökosüsteemi. Sünnib **ELK Stack** — Elasticsearch + Logstash + Kibana. Mängumuutja logide jaoks. Enne ELK-i oli logide tsentraliseerimine kallis (Splunk) või kohutavalt valus (syslog + grep). ELK demokrastiseeris logide kogumise.

### 2015 — Beats lisandub, AWS astub sisse

Logstash oli raske (JVM, suur RAM). Lisandusid kerged agendid Go-s: **Filebeat** (failidest logid), **Metricbeat** (süsteemi mõõdikud), **Auditbeat** (audit-logid), **Packetbeat** (võrgupaketid). ELK saab "Elastic Stack"-iks.

Samal aastal käivitas Amazon **Amazon Elasticsearch Service**'i — managed Elasticsearch AWS-is. See oli kaubanduslik edu, aga ka tüli algus.

### 2019 — kohtuvaidlus

Elastic NV süüdistas Amazonit kaubamärgi-rikkumises ja eksitavas turunduses, esitas hagi. [Kohtuvaidlus lõppes 2019 kompromissiga](https://www.elastic.co/blog/elastic-and-amazon-reach-agreement-on-trademark-infringement-lawsuit), aga **tehnoloogiline ja ärilise pinge jäi**.

### 2021 — litsentsi-drama

Elastic NV ei näinud AWS-i Amazon ES teenusest tulu. Argument: AWS müüb meie tööd, meie ei saa midagi tagasi.

**Jaanuaris 2021** Elastic muudab versioonis **7.11** litsentsi: **Apache 2.0 → SSPL (Server Side Public License) + Elastic License**. SSPL nõuab, et kui sa pakud SSPL-tarkvara teenusena, peab kogu sinu teenuse stack ka avatud lähtekoodiga olema. **Open Source Initiative (OSI) ei tunnista SSPL-i open source litsentsina.**

Praktikas: AWS ei saa enam Apache 2.0 tingimustel Elasticsearchi managed teenusena pakkuda.

Vastus tuli kiiresti. AWS fork-is **viimase Apache 2.0 versiooni — Elasticsearch 7.10.2** — aprillis 2021. Koos Logz.io, Aiveni jt-ga moodustub **OpenSearch projekt** — Apache 2.0 all, AWS-i taga. Mai 2021 — esimene OpenSearch 1.0 release.

See oli **valuline lõik**. Kahe aasta jooksul oli ökosüsteem segaduses — millisel litsentsil mis versioon, kas Logstash on ELK või OpenSearchi osa (mõlema, Logstash jäi Apache 2.0-le), kas Kibana saab kasutada OpenSearchiga (algselt jah, hiljem ei).

### 2023 — vector search

Elasticsearch 8.x lisab `dense_vector` field type, kNN otsingu, transformer-mudelite integratsiooni (Hugging Face). OpenSearch 2.x lisab neural search plugin'i ja FAISS integratsiooni.

### 2024 — kaks paralleelset uudist

Augustis 2024 kirjutab Shay Banon blogiposti **"Elasticsearch is Open Source, Again"**. Lisatakse **AGPL-3** kui kolmas litsents-valik (senise SSPL + Elastic License kõrvale). AGPL on OSI heaks kiidetud — niisiis Elasticsearch on tehniliselt jälle open source.

Septembris 2024 — **Linux Foundation kuulutab välja OpenSearch Software Foundation'i**. AWS andis OpenSearch projekti üle neutraalsele koduriigile. Kontribuendid: AWS, Aiven, Logz.io, Oracle ja teised. **OpenSearch ei kao** — eksisteerib edasi paralleelse projekti kujul.

### 2026 — kus me oleme

Mõlemad on open source. Mõlemad lisavad AI-võimekust agressiivselt. Mõlemad on tootmiskõlblikud. Valik on **kontekst- ja meeskonna-põhine**, mitte tehniline. Aga sa pead teadma, **mis nendega täna teha saab**. Selle juurde läheme nüüd.

---

## L1.3 — Elasticsearch vs OpenSearch täna

> **Loengu osa 1, hajutuse 3. plokk.** ~12 min, jätkub samas blokis kuni L1 lõpuni.  
> **Miks see sulle oluline:** otsustamise raam, mille järgi valida Elastic Cloud, Elasticsearch on-prem, Amazon OpenSearch Service, OpenSearch Serverless või OpenSearch on-prem — koos hinnamudelite ja TCO komponentidega, mida CFO sinult küsib.

### Komponendid — peaaegu identsed

Sama tüvi 2021-st tähendab, et komponendid kannavad sageli sama nime ja teevad sama asja. Esmalt vaatame **Elastic Stack** terviklikult, siis kõrval OpenSearchi vasted.

```mermaid
flowchart LR
    subgraph S["📊 Andmeallikad"]
        H["Host: CPU, RAM,<br/>disk, network"]
        A["Rakendused"]
        L["Logifailid<br/>(nginx, app, syslog)"]
        N["Võrgupaketid"]
    end

    subgraph B["📦 Beats (kerged Go agendid)"]
        FB["Filebeat"]
        MB["Metricbeat"]
        AB["Auditbeat"]
        PB["Packetbeat"]
    end

    LS["⚙️ Logstash<br/>parse • enrich • filter"]

    subgraph ES_C["🗄️ Elasticsearch klaster"]
        ES["master + data + ingest + coord<br/>storage • search • ML"]
    end

    KB["📈 Kibana<br/>dashboards • alerts • APM • SIEM"]

    H --> MB
    A --> FB
    A --> MB
    L --> FB
    N --> PB

    FB --> LS
    MB --> LS
    AB --> LS
    PB --> LS

    LS --> ES
    FB -. "võib käia ka<br/>otse, ilma Logstashita" .-> ES

    ES <--> KB

    style ES fill:#fff3e0
    style KB fill:#e3f2fd
    style LS fill:#f3e5f5
```

**Õkosüsteemide vaste — sama rollid, eri nimed:**

| Roll | Elastic Stack | OpenSearch ökosüsteem |
|---|---|---|
| Distribuiable otsingumootor + dokumendisalvestus | Elasticsearch | OpenSearch |
| UI ja dashboardid | Kibana | OpenSearch Dashboards |
| Andmevoog (pipeline'id, parse, transform) | Logstash | Logstash *(sama, Apache 2.0)* + Data Prepper (OS-spetsiifiline) |
| Kerged agendid | Beats (Filebeat, Metricbeat, Auditbeat...) | Beats + Data Prepper |
| APM / tracing | Elastic APM | OpenSearch trace analytics |

Kibana ja OpenSearch Dashboards näevad **80% identsed** välja — sama tüvi 2021-st. Sa avad ühe ja vaatad teist, vahel on raske ütelda, kummaga töötad. Erinevused tekivad seal, kus toode on 2021+ arenenud.

**Mida diagramm süsadminile ütleb:**

- **Beats** on kerged Go-agendid host'idel — kogu raske töö (parse, enrich) toimub mujal
- **Logstash** on **valikuline** — lihtsate kasutusjuhtude jaoks Beats saadab otse ES-i. Logstash tuleb juurde kui vaja keerukamaid pipeline'e (grok parsing, geoIP, lookup tabelid)
- **Elasticsearch klaster** on südamik — sealsamas elavad nii **logid**, **mol metrics**, **APM traçeid** kui **vector embeddings**
- **Kibana** ei ole "ainult dashboardid" — ta on **kogu Elastic Stack'i UI**, sh APM, SIEM (security), Observability, Machine Learning kasutajaliidesed

### Security — siin algab erinevus

**Elastic xpack** (osa Elastic License) on Elastici enda security stack. RBAC, doc-level security, field masking, audit-log, SSO, krüpteerimine. Põhilised asjad on tasuta (Basic license), edasijõudnud (SAML SSO, audit) kommerts (Platinum+).

**OpenSearch Security plugin** (Apache 2.0) on **vaba**. Teeb sama asju: RBAC, doc-level, field masking, audit. Konfiguratsioon erineb (YAML failid vs API), aga võimekus on sageli **rikastam vabas versioonis** kui Elastic xpack basic.

### AWS integratsioon — OS-i tugevaim eelis

**Amazon OpenSearch Service** on disainitud AWS-i ökosüsteemis natiivselt töötama:

- **IAM, Cognito, SAML, KMS** — autentimine ja krüpteerimine läbi AWS-i identity-süsteemi
- **CloudWatch, CloudTrail** — sisseehitatud monitooring ja audit
- **Zero-ETL integratsioonid** — CloudWatch Logs, DynamoDB, DocumentDB, S3, Security Lake andmed otseselt OS-i ilma eraldi pipeline'ita
- **Bedrock + SageMaker + OpenAI / Cohere / DeepSeek** — vector mudelite integratsioon klikiga
- **Cross-AZ data transfer included** — kuluvõit Multi-AZ klastritele
- **Graviton ja OR1 instances** — cost-effective AWS-i enda hardware

Kui sul on AWS-i keskkond, OpenSearch on pärisilmas tihti **lihtsam ja odavam** kui Elasticsearch Cloud Marketplace'i kaudu.

### Machine learning ja vector search

**Elastic** pakub kahte asja, mis on praktikas väga lihtsalt kasutatavad:

- **ELSER** (Elastic Learned Sparse EncodeR) — Elastic-i enda treenitud sparse retrieval mudel. Pre-trained, töötab inglise keeles. Lisaks toetab Elastic teisi embedding-mudeleid (nt e5-põhised multilingual mudelid), mida saab `semantic_text` väljaga siduda.
- **`semantic_text` field** (alates 8.13, 2024) — sa lisad oma indeksisse semantic_text-tüüpi välja, Elastic indekseerib selle automaatselt nii BM25-ga (sõnaline) kui ELSER-iga (semantiline). Päring annab hübriid-skoori. **Üks API, kaks otsingumeetodit korraga.**

**OpenSearch** pakub kahte komplementaarset võimalust:

- **ML Commons plugin** — sa registreerid oma mudeli (HuggingFace, ONNX, custom). Rohkem konfigureerimist, aga rohkem paindlikkust.
- **Neural search plugin** — high-level abstraktsioon, mis kasutab ML Commons'i sees.
- **FAISS integratsioon** — Facebook AI Similarity Search Library, optimeeritud vector indekseerimine.
- **OpenSearch Serverless vector database** — alates 2024 on see **default vector DB Amazon Bedrock Knowledge Bases'i jaoks**. AWS-i ametlik RAG-infrastruktuur.

Praktikas — Elastic on **välja-kastist** lihtsam (`semantic_text` on üks rida), OpenSearch on **paindlikum ja AWS-iga sügavalt integreeritud** (oma mudel, oma fine-tuning).

### Cloud ja managed teenused

| Pakkuja | Toode | Tähelepanekud |
|---|---|---|
| Elastic NV | Elastic Cloud (AWS, GCP, Azure) | täisteenus, 14-päevane trial krediitkaardiga |
| AWS | Amazon OpenSearch Service | kõige populaarsem managed OS, AWS-natiivne |
| AWS | **Amazon OpenSearch Serverless** | auto-scaled, vector DB Bedrock Knowledge Bases'i default |
| Aiven | OpenSearch managed | multi-cloud, ei lukusta AWS-i |
| Logz.io | OpenSearch-põhine SaaS | spetsialiseerunud logidele |
| Bonsai, Elastic.co | Väiksemad managed pakkujad | startup'idele |

### Skaala arvud (2026)

Amazon OpenSearch Service'i raamid annavad arusaama, mida need süsteemid praktikas tähendavad [^aws-os-quotas]:

- **25 PB** hot data ühes klastris
- **15 PB** warm data lisaks
- **1000 data node'i** maksimum
- **200 coordinator node'i** lisaks
- **99.99% availability** Multi-AZ + standby arhitektuuri korral
- **Trillions of requests per month** — agregeeritud kõik AWS-i kliendid

Need ei ole tüüpilised numbrid, mida sa oma keskkonnas kohtad — aga need näitavad, et tehnoloogia ei ole **see** piirang. Piirang on tüüpiliselt eelarve ja arendaja-aeg.

### Hinnad ja TCO — millest tegelikult koosneb arve

Kui CFO küsib "miks Splunk on nii kallis ja kas saaks ELK-le üle minna?", siis vajad sa raami, kuidas neid võrrelda. Pole ühte "oige" hinda — on **kolm fundamentaalselt erinevat hinnamudel**:

| Hinnamudel | Kes kasutab | Mis on kulu juur |
|---|---|---|
| **Per-GB-ingested** | Splunk Cloud [^splunk-pricing], Datadog Logs [^datadog-pricing] | Iga GB sissetulev logi maksab. Lihtne arvutada, aga **karistab logi-mahtu** — sundib sind logimist vähendama. |
| **Instance-based (resource)** | Amazon OpenSearch Service [^aws-os-pricing], self-hosted ES/OS | Maksad **node'ide eest** (RAM × CPU × ketas), mitte logi-mahtude eest. Kasv on ennustatav, aga sa pead **ise dimensioneerima**. |
| **Tier'i-põhine** | Elastic Cloud (Standard/Gold/Platinum/Enterprise) [^elastic-pricing], Confluent Cloud | Vali tier (RAM/CPU/storage komplekt) + add-ons. Tasakaal lihtsuse ja paindlikkuse vahel. |

**Praktilised suurused** (avalike hinnakirjade põhjal, 2026 alguses):

- **AWS OpenSearch Service**, 3-node klaster `r6g.large.search` (2 vCPU, 16 GB RAM, 100 GB EBS gp3): umbes **$260–320/kuu** on-demand + storage + transfer. Reserved Instances annab 30–50% allahindlust 1–3 aasta lepingul.
- **Elastic Cloud**, Standard tier, väike production setup (4 GB RAM hot + 60 GB storage): umbes **$95–110/kuu**. Skaleerub lineaarselt tier'idega.
- **Splunk Cloud**, ajaloolised hinnad olid `$1500–2000/GB/päev` tier; 2024+ uus "Workload Pricing" mudel on paindlikum, aga **suurusjärk on sama** — 100 GB/päev = 5–6-kohaline aastane arve.
- **Loki + Grafana Cloud** (Day 2 katsetatud) on **3–10× odavam** per-GB ELK-st, sest indekseerib ainult silte, mitte täisteksti. Compromiss — vähem otsingu-paindlikkust.

**TCO komponendid, mis sageli unustatakse:**

1. **Cross-AZ data transfer** — AWS-is maksab data liikumine AZ'ide vahel ($0.01–0.02/GB). 1 TB/päev kolme AZ'i vahel = ~$30/päev. **Amazon OpenSearch Service includes seda** — see on suur nähtamatu eelis. Self-managed ES Multi-AZ EC2-l peab kasutaja seda maksma.
2. **RAM kui peamine kulutaja** — ES/OS armastab heap-mälu (vector search'iga eriti, HNSW graafid mälus). 32 GB RAM node maksab tihti rohkem kui 1 TB SSD.
3. **Operations overhead** — self-hosted on "tasuta tarkvara", aga DevOps-tunde on vaja. SaaS = 2–3× tarkvara-hind, aga DevOps-aega ei kulu.
4. **Search workload** — vector search on **CPU-intensiivne**. ELSER mudel + 1M dokumenti = märgatav CPU-löik klastri kogu-koormusele. Planeeri **eraldi node'id ML tööle**, kui plaanid AI-funktsioone.

**Mõistlik harjutus:** võta oma praeguse seire-eelarve, jaga see klassi `[tarkvara, hardware/cloud, personali-aeg, andmeedastus]` kategooriasse. Kui sa lihtsalt vahetad Splunki ELK vastu, **personali-aeg tõenaoliselt kasvab** ja seda tuleb arvestada otsuses.

!!! tip "💭 Mõtle hetk — enne edasilugemist"
    Sinu organisatsiooni praegune logimine — kumb hinnamudel on aluseks? Per-GB-ingested (Splunk, Datadog), instance-based (ES/OS on-prem või AWS) või SaaS-tier?

    Kui sa ei tea — see ise on signaal: keegi sinu finants- või operatsiooni-rollis teab seda, aga see info ei jõua sinuni. Esmaspäeval tasub küsida.

### Litsents — lühidalt

- **Elasticsearch** = AGPL-3 **või** SSPL **või** Elastic License (kolmest valida)
- **OpenSearch** = Apache 2.0 (lihtne, vaba)

Kui sa pakud teenust kommertsiaalselt ja tahad vältida juriidilist debatti — OpenSearch on lihtsam. Kui sul on lihtsalt sisemine kasutus, Elasticsearchi kõik kolm litsentsi on okei.

### Kus kumb sobib — sysadmin perspektiivist

**Vali Elastic Cloud / Elasticsearch on-prem kui:**

- Sul on kommertsiaalne nõue (sertifitseerimine, 24/7 support)
- AI / semantic search on prio ja sa tahad lihtsat API-d (`semantic_text`)
- Sa kasutad Elastic APM-i (Elastic on siin tugevam kui OpenSearch)
- Sa pole AWS-is

**Vali Amazon OpenSearch Service kui:**

- Sa oled AWS-i keskkonnas
- Vendor lock-in vältimine on prio (Apache 2.0)
- Tahad Multi-AZ + standby out-of-the-box (99.99%)
- AWS-i Bedrock-integratsioon ja RAG on tee

**Vali OpenSearch Serverless kui:**

- Sa ehitad RAG-rakendust Bedrock Knowledge Bases'iga
- Vector DB peaks auto-skaleeruma (mitte fixed-size klaster)
- Operational overhead peab olema null

**Vali OpenSearch on-prem kui:**

- Suur self-hosted klaster, vaba security plugin on tähtis
- Andmed ei tohi AWS-i lahkuda (compliance, GDPR)
- Sa tahad oma ML mudelid laadida (ML Commons paindlikkus)

Sellega oleme valmis labi alustama. **Osa 1**: paneme Elasticsearchi ja Kibana single-node klastrina püsti. Vaata, mis juhtub esimese indeksi loomisega ja miks Kibana näitab klastri olekut **kollasena**.

---

## L2 — Arhitektuur: sõlmed, shardid, quorum, 99.9%

> **Loengu osa 2.** ~15 min, hajutuse 2. plokk — enne Osa 2 (3-node klastri laienemine).  
> **Miks see sulle oluline:** aitab sul dimensioneerida klastrit, mis ei kuku ootamatult — mitu master node'i, kui palju RAM-i, kus on backup'id, kuidas Kafka puhverdab koormust, ja millal mis indeks tier'isse läheb.

Osa 1 lõpus nägid sa midagi, mis võib esimese pilguga tunduda imelik: lõid indeksi, läksid Kibanasse, ja **klastri olek näitas kollasena**. Andmed olid sees, otsing töötas, aga oleku-tuli oli kollane. Miks?

Vastus on **replica shardides** ja sellega, et single-node klastris pole võimalik neid kuhugi paigutada. Selle teema raames vaatame, kuidas Elasticsearch (ja OpenSearch — identne arhitektuur) on **päriselt** ehitatud, et mõista, miks production-klaster näeb välja teistsugune kui Osa 1 setup.

### Sõlmerollid — neli rolli, sama binary

Elasticsearchi node ja OpenSearchi node on sama binary, aga konfiguratsioonis saab määrata, mis **rolli** see node täidab. Üks node võib täita mitut rolli korraga (väikeses klastris üks node täidab kõike). Aga tootmiskeskkondades **eraldatakse rollid**:

| Roll | Mida teeb | Resurssi-profiil |
|---|---|---|
| **master** | Hoiab klastri olekut (mis indeksid, mis shardid, mis node-id), võtab vastu cluster-tasemel päringuid (indeksi loomine, shard'i liigutamine) | Vähe CPU, vähe mälu, kiired diskid |
| **data** | Hoiab tegelikke shardide andmeid, indeksib uusi dokumente, vastab otsingu-päringutele | Palju CPU, palju mälu (heap + page cache), kiired diskid |
| **ingest** | Käivitab ingest pipeline'e (grok, geoIP, rename, script processor jne) enne dokumendi salvestamist | Palju CPU |
| **coordinating** | Võtab vastu klientide päringuid, jagab need data node'idele, koondab tulemused | Vähe diski, keskmine CPU/mälu |

Iga node on **vaikimisi kõik neli rolli** (default). Tootmises eraldad neid:

- 3 × dedicated master (väikesed, ainult master)
- N × data nodes (suured, palju mälu)
- 2+ × coordinating-only nodes load balancer rollis (suure päringukoormuse korral)
- ingest võib olla data node'il kaasas või eraldi

**Miks eraldada?** Sest master peab klastri olekut hoidma **stabiilselt**. Kui sama node teeb ka data tööd ja saab raske päringu — GC pause, OOM, ülekoormus — kogu klastri olekuhaldus läheb maha. Eraldatud master-only node on **väike ja vaikne**, ainult olekut hoiab.

Visuaalselt näeb production-klaster välja umbes nii:

```mermaid
flowchart TB
    subgraph KL["🌐 Klient / app / Logstash / Beats"]
        APP["Rakendus saadab päringuid"]
    end

    APP --> LB["Öle LB / DNS"]

    subgraph C["Coordinating-only nodes"]
        C1["coord-1"]
        C2["coord-2"]
    end

    subgraph M["👑 Master-only nodes (3) — quorum"]
        M1["master-1"]
        M2["master-2"]
        M3["master-3"]
    end

    subgraph D["💾 Data nodes (N, koos ingest rolliga)"]
        D1["data-1<br/>shard A1, B2 replica"]
        D2["data-2<br/>shard A2, B1 replica"]
        D3["data-3<br/>shard B1, B2, A2 replica"]
    end

    LB --> C1
    LB --> C2
    C1 -. cluster state .-> M
    C2 -. cluster state .-> M
    C1 --> D1
    C1 --> D2
    C1 --> D3
    C2 --> D1
    C2 --> D2
    C2 --> D3
    M -. juhib shard'ide paigutust .-> D

    style M fill:#ffe0b2
    style D fill:#c8e6c9
    style C fill:#bbdefb
```

Klient ei pea teadma, kus mis shard on — coordinator teab seda master'i cluster state'ist ja teeb routing'u ära.

### Shardid — primary ja replica

Indeks Elasticsearchis on **loogiline konteiner**. Füüsiliselt jaotub ta **shardideks** — Lucene-indeksid, mis paiknevad data node'idel.

Indeksi loomisel määrad kaks numbrit:

- **`number_of_shards`** (primary) — mitmeks tükiks indeks jaotub. Vaikimisi 1. Hilisem muutmine on raske (reindex), niisiis vali ette.
- **`number_of_replicas`** — mitu koopiat igast primary shardist tehakse. Vaikimisi 1. Saab jooksvalt muuta.

Näide: indeks `logs-2026.05` `number_of_shards: 3` ja `number_of_replicas: 1` = **3 primary + 3 replica = 6 shardi kokku**. Kui sul on 3 data node'i, paigutab Elasticsearch shardid nii, et iga primary ja tema replica on **eri node'idel** — muidu node'i kadu kaotaks andmed.

**Roll päringus:**

- Indekseerimine: dokument läheb **primary**'sse, sealt **replica**'sse (synchronous, mitte fire-and-forget). Kui replica ei kinnita, primary käsib master'il replica märkida `STALE`.
- Otsing: koordinaator vaatab, kus iga shardi koopia on, ja saadab päringu **ühele neist** (round-robin, mitte kõigile). Replica niisiis pole ainult HA, vaid ka **päringu-koormuse jagaja**.

**Tagasi Osa 1 kollase oleku juurde:** single-node klaster. `number_of_replicas: 1` (default). Replica peab paiknema **erinevas node'is** kui primary. Erinevat node'i pole. Replica jääb **unassigned**. Klastri olek = **YELLOW** ("toimib, aga pole redundantne"). Lisa teine node → replica paigutub → GREEN. See on Osa 2 esimene samm.

### Cluster state ja quorum — miks **kolm** master node'i

Master node hoiab **cluster state**'i: tabelit, mis loetleb iga indeksi, shardi, node-i ja nende staatuse. See on üks autoriteetne allikas — ja see peab olema **järjepidev kõigil masteri-kandidaatidel**.

Probleem tekib siis, kui võrk lahkneb (network partition). Kujuta ette: 2 master node'i, võrk lahkneb pooleks.

- Node A arvab: "B kadus, mina olen ainus, ma olen master"
- Node B arvab: "A kadus, mina olen ainus, mina olen master"
- Klastri olek lahkneb kaheks. Ühel pool kirjutatakse indeksisse X, teisel pool kirjutatakse indeksisse Y. Võrk taastub — **konflikt**, andmed on ebajärjepidevad. See on **split-brain**.

```mermaid
flowchart LR
    subgraph L["AZ-1 / Datacenter 1"]
        A["👑 master-1<br/>(arvab: olen ainus)"]
        DA["data-1"]
    end

    subgraph R["AZ-2 / Datacenter 2"]
        B["👑 master-2<br/>(arvab: olen ainus)"]
        DB["data-2"]
    end

    A -. ❌ kadunud .-x B
    A --> DA
    B --> DB
    DA -. kirjutab indeks X .-> DA
    DB -. kirjutab indeks Y .-> DB

    style A fill:#ffcdd2
    style B fill:#ffcdd2
```

Kaks master'it korraga, mõlemad võtavad kirjutusi vastu — võrk taastub, **kumb on "õige" andmeseis?**

Lahendus: **quorum**. Master valitakse ainult siis, kui **enamus** master-kandidaatidest nõustub. Enamus tekib ainult ühel pool partitsiooni.

Matemaatika: kui sul on **N** master-kandidaati, quorum = **⌊N/2⌋ + 1**.

- N=2 → quorum=2 → kui üks kaob, klaster peatub. Halvem kui üks node!
- N=3 → quorum=2 → üks võib kaduda, klaster töötab edasi. ✅
- N=5 → quorum=3 → kaks võib kaduda. Suurematele klastritele.

**Niisiis tõsiselt mõeldud klaster algab 3 dedicated master node'iga.** Mitte sellepärast et "3 on hea arv", vaid sellepärast et quorum-matemaatika nõuab paaritut arvu ja vähem kui 3 ei talu ühtegi kadu.

### 99.9% (ja 99.99%) praktikas

**99.9% uptime** = ~8.7 tundi downtime aastas. **99.99%** = ~52 minutit aastas. **99.999%** ("viis üheksat") = ~5 minutit aastas. Igale lisanduvale üheksale kasvab kulu eksponentsiaalselt.

Mida need numbrid praktikas nõuavad:

| SLA | Mida nõuab |
|---|---|
| 99.5% (best-effort) | 1 node võib jooksta, restart on okei. |
| 99.9% | 3-node klaster, replica=1, automaatne shard recovery. Master + data eraldatud või kombineeritud. Plaaniline hooldus nädalavahetustel. |
| 99.99% | **Multi-AZ** (3 erinevat data-keskust või AWS Availability Zone'i). 3 dedicated master üle AZ'ide. Replica üle AZ-ide. Snapshot-de regulaarne testimine. |
| 99.999% | Multi-region + CCR (Cross-Cluster Replication). Reaalselt vähesed väljärakendused nõuavad seda. |

**Multi-AZ + standby** (AWS OpenSearch Service erijuhtum): 3 master + 3 data üle 3 AZ-i, lisaks **standby data nodes** ühes AZ-is, mis ei võta päringuid vastu, aga hoiavad replicaid. AZ kao korral standby võtab koormuse üle ilma rebalancing'uta. See on AWS-i ametlik **99.99% mudel**.

### Snapshots — ainus tegelik backup

Replica ei ole backup. Kui keegi kustutab `_delete_by_query` valega õla, replica sai sama käsu — andmed kadusid mõlemast. Backup tähendab **snapshot**'i, mis on sõltumatu point-in-time koopia välises storage'is.

Elasticsearch ja OpenSearch toetavad snapshot'e mitmesse repositooriumisse:

- **S3** (kõige levinum) või S3-ühilduvad (MinIO, Ceph)
- **Azure Blob, GCS**
- **Shared filesystem** (NFS) — testimiseks ok, tootmisse mitte
- **HDFS** — vanad keskkonnad

```http
PUT _snapshot/my_s3_repo
{
  "type": "s3",
  "settings": { "bucket": "my-elasticsearch-backups", "region": "eu-north-1" }
}

PUT _snapshot/my_s3_repo/snapshot_2026_05_17
{ "indices": "logs-*", "include_global_state": false }
```

**Snapshot Lifecycle Management (SLM)** automatiseerib: igapäevased snapshotid, 30 päeva säilitamine, vana kustutamine. **Aga —** ja see on oluline — **testi restore**'i regulaarselt. Snapshot, mida pole kunagi taastatud, ei ole backup.

### CCR — Cross-Cluster Replication

Kahe klastri vahel: üks **leader**, teine **follower**. Leader'i indeksid replikeeritakse follower'isse asynkroonselt. Kasutusjuhtumid:

- **Disaster recovery** — teine klaster teises piirkonnas, leader'i kao korral follower võtab üle
- **Geo-distribuited reads** — Euroopa, USA, APAC klastrid replikeerivad samad andmed, kliendid otsivad kõige lähemast
- **Andmete eristamine** — production indeksid replikeeritakse analytics-klastrisse, kus DBA-d teevad raskeid päringuid ilma tootmist mojutamata

Elasticsearchis on CCR **Platinum-licence** feature. OpenSearchis on **cross-cluster replication** plugin **vaba**. See on üks koht, kus OpenSearch licens-strateegia paistab välja sysadminile.

### Andmevoog ja Kafka kui ingest buffer

Reaalses tootmiskeskkonnas ei voola logid otse `Filebeat → Elasticsearch`. Vahel on **buffer**, mis lahendab kolm konkreetset probleemi:

1. **Peak hours** — logide maht ei ole ühtlane. Black Friday õhtu = 10× tavakoormus. Kui ES on selle jaoks dimensioneerimata, ingest queue üleujutub, dokumendid kaovad.
2. **ES downtime** — plaaniline uuendus või unplanned outage. Agendid (Filebeat, Vector, Fluent Bit) saadavad andmeid kuhugi, kuhu peavad. Kui ES ei vasta, agent peab kas pufferdama lokaalselt või kaotama.
3. **Multi-consumer** — sama logivoog läheb ES-i (operatiivne), S3 Iceberg'sse (analytics), Splunki (security), Loki-sse (Grafana). Iga konsument ei pea iseseisvalt agendiga rääkima.

**Apache Kafka** [^kafka] on de facto standard selle puhverdamise jaoks. Tüüpiline pipeline:

```mermaid
flowchart LR
    A["📜 Rakendused<br/>Filebeat / Vector / Fluent Bit"] --> K[("Kafka<br/>topic: logs-raw")]
    K --> L1["Logstash<br/>(parse, enrich)"]
    K --> S3["S3 / Iceberg<br/>(long-term)"]
    K --> SP["Splunk / SIEM"]
    L1 --> ES[("Elasticsearch / OpenSearch")]

    style K fill:#fff3e0
    style ES fill:#c8e6c9
```

**Komponendid, mida tasub teada:**

- **Kafka Connect** — sisseehitatud konnektorid: source (Filebeat-laadne) ja sink (`elasticsearch-sink-connector`). Konfiguratsioonifail, mitte koodi-kirjutamine.
- **Schema Registry** (Confluent) — hoiab Avro/Protobuf schemasid, et tootja ja tarbija ei lahkneks. Oluline kui logid on struktureeritud.
- **Confluent Platform** — kommertspakkuja Apache Kafka peal (Confluent Cloud, Confluent Server). Apache Kafka ise on tasuta, Confluent-i lisand on enterprise-features (RBAC, audit, multi-region).
- **Amazon MSK** ja **Aiven for Apache Kafka** — managed Kafka pilves.

Suur küsimus mille peale komistab paljud setup'id: **mis on retention?** Kafka topic'us hoitakse sõnumeid määratud aeg (default 7 päeva) või määratud mõõtani (näiteks 100 GB topic'u kohta). Pikem retention = rohkem disk. Lyhem = kui ES on maas üle retention'i, kaotad andmeid.

Netflix, Uber ja Booking.com on avalikult kirjutanud oma `Kafka → Elasticsearch` pipeline'idest. Tüüpiline skaala: **kümned kuni sajad miljardid sõnumeid päevas**, mis lähevad puhvrist mitmesse konsumendisse. [^netflix-kafka]

### Indeksite elutsükkel — ILM ja Hot/Warm/Cold tiers

Log-indeksid on **time-series**: tehakse iga päev (`logs-2026.05.17`), kirjutatakse ainult üks päev, päringuid tehakse vähem aja jooksul. Kui sa hoiad neid kõik **kuum-tasemel** (kiired SSD-d, replicas, RAM-cache), satud kahel viisil:

- **Kulu** — kiired diskid on kallid. 6 kuu kõik indeksid kuumal SSD-l = nDC eelarve.
- **Klastri rõhk** — iga avatud indeks tarbib heap-mälu, file descriptoreid, segmente. Tuhandeid avatud indekseid ühes klastris lööb master node'i.

Lahendus: **Index Lifecycle Management (ILM)** Elasticsearchis [^ilm-es], ehk **Index State Management (ISM)** OpenSearchis [^ism-os]. Mõlemad teevad sama asja — indeksid läbivad **tier'eid** vananedes:

| Tier | Tüüpiline vanus | Hardware | Replicas | Operatsioon |
|---|---|---|---|---|
| **🔥 Hot** | 0–7 p | Kiire SSD, palju RAM | 1–2 | Kirjutamine + päringud, hoitakse RAM-is |
| **🌡️ Warm** | 7–30 p | Aeglasem SSD või kiired HDD | 1 | Ainult päringud, force-merge tehtud |
| **❄️ Cold** | 30–90 p | HDD, vähem RAM | 0–1 | Päringud aeglased aga toimivad |
| **🧊 Frozen** | 90+ p | **S3 / object store** | 0 (searchable_snapshot) | Päringud toimivad, aga eraldi cache-st, sekundid kuni minutid |
| **🚮 Delete** | 365+ p | — | — | Indeks kustutatakse või jäetakse ainult snapshot S3-s |

**Searchable snapshots** (mol Elastic ja OpenSearch) on võtmetehnoloogia frozen-tier'i jaoks: indeks elab **ainult S3-s**, mitte data node'i kettal. Klaster hoiab väiksed metadata-fragmendid, päring läheb S3-le. Kulu kukub **10–20×** (S3 on odav), aga päringu latentsus kasvab.

Tüüpiline ILM-policy näide (Elastic JSON):

```json
PUT _ilm/policy/logs-policy
{
  "policy": {
    "phases": {
      "hot":    { "actions": { "rollover": { "max_age": "7d", "max_size": "50gb" } } },
      "warm":   { "min_age": "7d",  "actions": { "forcemerge": { "max_num_segments": 1 }, "set_priority": { "priority": 50 } } },
      "cold":   { "min_age": "30d", "actions": { "freeze": {} } },
      "frozen": { "min_age": "90d", "actions": { "searchable_snapshot": { "snapshot_repository": "my_s3_repo" } } },
      "delete": { "min_age": "365d", "actions": { "delete": {} } }
    }
  }
}
```

**Rollover** — vahetatakse kirjutus-indeks (`logs-000001` → `logs-000002`) kui jooksev indeks jõuab 7 päeva või 50 GB. Vana indeks suletakse kirjutamisele, läheb warm-tier'isse väikselt ootama. **Data streams** (Elasticsearch 7.9+, OpenSearch 1.2+) automatiseerib selle — sa kirjutad data-stream'i `logs`, ES halduskeel määrab õige backing indeksi.

**Tier'ide praktiline jagamine** ei pea olema kõikiidne. Väike klaster (3 data node) võib hoida hot + warm samadel node'idel, ja cold + frozen on S3. Suur klaster (50+ data node) eraldab tier'id node-rollidega (`node.roles: [data_hot]`, `data_warm`, `data_cold`, `data_frozen`).

### Kokkuvõte L2-st

Production-klaster 2026 koosneb: **3 dedicated master + N data + 2+ coordinating-only**, kus N sõltub indeksite ja päringukoormuse mahust. Shardide arv valitakse ette indeksi loomisel. Replicad jagavad päringukoormust ja annavad HA. Quorum nõuab paaritu arvu master-kandidaate, miinimum 3. 99.9% on saavutatav 3-node klastris, 99.99% nõuab Multi-AZ + standby, 99.999% Multi-region + CCR. Snapshot S3-le on ainus tegelik backup — ja seda tuleb testida.

Osa 2 lab'is laiendad single-node klastri 3-node klastriks ja vaatad, kuidas oleku-tuli muutub YELLOW → GREEN, ning katsetad, mis juhtub kui ühe node'i tapad.

---

## L3 — Otsing: lexical (BM25) vs vector, ja kuidas need töötavad

> **Loengu osa 3.** ~15 min, hajutuse 3. plokk — enne Osa 4 (semantic_text + kNN demo).  
> **Miks see sulle oluline:** aitab sul otsustada, kas sinu kasutusjuhul (logide otsing, audit, klienditugi, dokumentatsioon) on vector search või RAG vajalik — või piisab klassikalisest BM25-st. Vector pole alati õige lahendus.

Logi-otsing on Elasticsearchi põhi-kasutusjuhtum, mida köik teavad. Aga 2024+ on otsing **kaheks haru ajunenud**: klassikaline **lexical** (sõnapotsing) ja moderne **vector / semantic** (tähendus-otsing). Mõlema all on **algoritmid** mida tasub tunda — mitte sellepärast et sa neid käsitsi implementeeriks, vaid sellepärast et sa pead mõistma, **miks** üks või teine sobib või mitte.

### Lexical otsing: inverted index + BM25

**Inverted index** on Lucene'i (ja seega ka Elasticsearch / OpenSearch) põhi-andmestruktuur. Idee on lihtne: tagurpidi tavalisest dokument-→-sõnade-suunast on **sõna-→-dokumentide** suund.

Dokumendid:
```
doc1: "the quick brown fox"
doc2: "the lazy dog"
doc3: "the quick blue ocean"
```

Inverted index:
```
the   → [doc1, doc2, doc3]
quick → [doc1, doc3]
brown → [doc1]
fox   → [doc1]
lazy  → [doc2]
dog   → [doc2]
blue  → [doc3]
ocean → [doc3]
```

Päring `quick brown` → vaatame mis dokumentides on `quick` (doc1, doc3), mis dokumentides on `brown` (doc1). Eeldades AND-loogikat: doc1. Eeldades OR-loogikat: doc1 ja doc3.

See on **kiire** (otsiba sõna hash-tabelist, mitte kõigi dokumentide läbivaatamine) ja **täpne** (kui sõna on samas vormis, leitakse).

Aga "kiire ja täpne" pole **piisav**. Vaja on **järjestada** — milline dokument on **kõige relevantsem** päringule?

### BM25 — relevantsi algoritm

**BM25** (Best Matching 25, Okapi BM25 perekond) on Lucene'is vaikimisi kasutusel olev relevantsuse-algoritm — versioonist 5.0 alates Elasticsearchis (varem TF-IDF). Skoor sõltub kolmest jouust:

1. **Term frequency (TF)** — mitu korda otsisõna dokumendis esineb? Rohkem = parem, aga **küllastusega** (10 esinemist on parem kui 1, aga 100 ei ole oluliselt parem kui 10).
2. **Inverse document frequency (IDF)** — kui haruldane on otsisõna kogu korpuses? `the` on igas dokumendis, **madala IDF-iga** (ei aita eristada). `quorum` on harva, **kõrge IDF**.
3. **Field length normalization** — lyhike dokument, kus sõna esineb, on tihti relevantsem kui pikk dokument, kus sama sõna esineb.

Matemaatiliselt: `score(D, Q) = Σ IDF(qi) · (TF(qi, D) · (k₁ + 1)) / (TF(qi, D) + k₁ · (1 - b + b · |D|/avgdl))`

Sinu ülesanne ei ole seda valemi peäst teada. Sinu ülesanne on mõista, **mida BM25 mootor järjestab**: dokumendid, mis sisaldavad päringus olevaid sõnu **sageli, haruldastes kohtades ja lühikestes lõikudes**.

### Kus lexical otsing kukub läbi

Proovi monitooringu-perspektiivist võtta — oled hommikul kontoris, dashboard näitab et **API on aeglane**, ja sa otsid logist `database connection problems`. Mida BM25 tähistab? Dokumendid, kus on sõnad **"database"**, **"connection"** ja **"problems"**.

Aga mida sina **tegelikult otsid**? Läbi viimase 24 tunni logide on neid kirjeid sellistel kujudel:

- `ERROR: DB timeout after 30s`
- `Connection pool exhausted, waiting 5s`
- `Lost connection to database server, retrying`
- `SQLException: Cannot acquire connection`
- `psycopg2.OperationalError: server closed the connection`

**Ükski neist ei sisalda sõna "problems".** Tihti ei sisalda isegi "database". BM25 ei leia neid. See on **vocabulary mismatch problem** — sinu mentaalne sõnastik ("database connection problems") ja logi-rea sõnastik (`pool exhausted`, `OperationalError`) on erinevad.

Praktikas tähendab see, et incident response võtab kauem — sa pead läbi proovima 5–10 erinevat otsisõna, enne kui leiad selle, mis su logides kasutusel on.

Lahendus: **vector otsing**, mis ei võrdle sõnu, vaid **tähendusi**.

### Edasine areng — vector search ja RAG monitooringus

Alates 2024-st on Elasticsearch ja OpenSearch lisanud **vector search** ja **RAG (Retrieval-Augmented Generation)** võimekuse. Tänu sellele toimivad:

- **Elastic AI Assistant** ja **Splunk AI Assistant** — sa küsid `mis juhtus eile õhtul kell 19:00?`, AI leiab vector storage'st (sinu logid + traces + alerts) konteksti ja vastab.
- **Semantic log pattern matching** — `leia kõik database connectivity issues` leiab nii `pool exhausted`, `OperationalError`, `lost connection`.
- **Alert-korrelatsioon** — 1000 alerti grupeeritakse mustrite järgi ja antakse juur-põhjus.
- **Runbook-otsing** — `kuidas taaskäivitada Redis cluster?` leiab vastuse sinu organisatsiooni wiki-st.
- **Postmortem auto-draft** — AI kirjutab esmase mustandi incident'i kohta.

Tänase loengu põhi-fookus on **logide-otsing klassikaliselt** (BM25), sest see on igapäevatöö Kibana Discoveri ja OpenSearch Dashboards'i Discover'i lahtris. Vector search ja RAG-i tehniline pool — embedding mudelid, HNSW algoritm, FAISS, ELSER, `semantic_text`, ML Commons, hybrid search — on **eraldi lisalugemises**:

!!! abstract "📖 Lisalugemine"
    Vt eraldi peatükk **[Päev 3 — Lisalugemine: Vector search, RAG ja AI monitooringus](paev3-vector-rag-lisalugemine.md)** — ~25 min lugemist, sobib süvenemiseks AI-suuna huvilisele.

### Kokkuvõte L3-st

Lexical (BM25) on **logide-otsingu standard** — kiire, täpne, soodne. Sinu igapäevatöö Kibana Discover'is ja OS Dashboards Discover'is on **see**. Vector search ja RAG on **edasine areng**, mis 2024+ ilmub AI Assistant tööriistadesse — detailid lisalugemises.

!!! tip "💭 Mõtle hetk — enne edasilugemist"
    Sinu organisatsioonis — mis on **igapäevane otsingu-muster** logides? Kas piisab "otsi `ERROR`" lihtsast tekstist (BM25), või tahaksid küsida "leia kõik database-probleemid" loomuliku keelega (vector + RAG)?

    Esmaspäeval — vaata Kibana Discoveris (või samaväärses), mis on need 3–5 otsisõna, mida sa kasutad kõige sagedamini. Need on sinu **BM25 sword'id**.

Osa 4 lab'is kasutate Kibana Discover'i ja OS Dashboards Discover'it logide otsimiseks BM25 ja KQL-i abil.

---

**Embedding mudel** (nt sentence-transformer, OpenAI text-embedding, ELSER, BGE, E5) võtab teksti ja annab tagasi vektori — tüüpiliselt **384 … 1536 dimensiooniga** liugujuturuga arve. See vektor esindab teksti **tähendust** geomeetrilises ruumis.

Näide (lihtsustatud, ainult 3 dimensiooni):

| Tekst | Vector |
|---|---|
| "king" | [0.21, 0.85, 0.12] |
| "kuningas" | [0.23, 0.83, 0.11] |
| "jalats" | [0.78, 0.10, 0.45] |
| "sneaker" | [0.81, 0.09, 0.47] |

Nägemine — "king" ja "kuningas" on **lähedal** (rojaalsuse-ruumis). "jalats" ja "sneaker" on **lähedal** (jalanõu-ruumis). Kuid "king" (rojaalsus) ja "sneaker" on **kaugel**. Mudel õppis selle treenimise käigus miljarditelt teksti-paaridelt.

Päringu vektor `tossud kontorisse` arvutatakse sama mudeli abil — saame teise vektori. Otsing leidab dokumendid, mille vektor on päringuvektorile **kõige lähemal**.

**Sarnasuse-meetrika:** cosine similarity, dot product või euclidean distance. Cosine on kõige levinum normaliseeritud vektorite jaoks.

### Probleem: kuidas leida lähemaid vektoreid kiiresti

Kui sul on **1 miljon dokumenti**, igaks 384-dimensiooniline vektor, ja küsid "leia 10 sarnasemat", **täpne lahendus** on:

1. Arvuta päring → vektor
2. Arvuta cosine similarity päring-vektori ja iga 1M dokumendi vektori vahel
3. Järjesta

See on **brute force kNN** (k Nearest Neighbors). 1M dokumendi puhul = miljon cosine-arvutust iga päringu kohta. **Liiga aeglane**.

Lahendus: **ANN — Approximate Nearest Neighbors**. Loobume väikese täpsuse-protsendi nimel kiirusest. Saame 95% "õigeid" tulemusi, aga 1000× kiiremini.

### HNSW — Hierarchical Navigable Small World

Algoritm, mida nii Elasticsearch (Lucene 9+ kaudu) kui OpenSearch kasutavad. Idee:

1. Ehita **graaf**, kus iga sole = dokumendi vektor. Sole ühendatakse oma õlalt lähemate naabritega.
2. Tee see graaf **mitmel kihil**: ülemine kiht vähe sole'tega (kaughelmed), alumine kiht ühine kõik sole'd (lähihelmed).
3. Otsing: alusta ülemiselt kihilt suvaliselt sole'lt, liigu "siia" alati lähema naabrini. Sample down kihtide kaupa.

```mermaid
flowchart TD
    subgraph L2["🔝 Kiht 2 — vähe sole'sid, kauged hupped"]
        L2A(("A")) --- L2B(("B")) --- L2C(("C"))
    end

    subgraph L1["↗️ Kiht 1 — keskmiselt tihe"]
        L1A(("A")) --- L1D(("D"))
        L1B(("B")) --- L1E(("E"))
        L1B --- L1A
        L1C(("C")) --- L1F(("F"))
        L1C --- L1B
    end

    subgraph L0["🔍 Kiht 0 — kõik dokumendid, tihe naabruskond"]
        N1(("1")) --- N2(("2"))
        N2 --- N3(("3"))
        N3 --- N4(("4"))
        N4 --- N5(("5"))
        N5 --- N6(("6"))
        N1 --- N4
        N2 --- N5
        N3 --- N6
    end

    Q["🎯 Päringu vektor q"] -.algus.-> L2A
    L2A -.alla.-> L1A
    L1A -.alla.-> N4
    N4 -.lähima naabrini.-> N5

    style Q fill:#fff59d
    style N5 fill:#a5d6a7
```

Otsing jälgib **logaritmilist teed** — algab ülemiselt vähe-sole-kihilt suure hüppega, lihvitakse iga kihiga täpsemaks. Päring 1M-vektori kollektsioonis ~5ms, mitte 500ms.

Kompromiss: HNSW eelistab **mälus** vektoreid hoida (RAM kallis). Lucene HNSW kasutab graafe, mis on osa Lucene'i segment-failidest. **Off-heap mälu nous** on suur — RAM-koormus 1 miljardi vektori puhul on märkimisväärne ja seda tuleb arvestada.

**FAISS** — Facebook AI Similarity Search Library — on alternatiiv HNSW-le. OpenSearch ML Commons toetab nii **NMSLIB HNSW** kui **FAISS**'i (sh **IVF** ja **PQ** algoritmid). FAISS-i tugev külg on **mälukasutuse vähendamine** kompressiooniga (Product Quantization) — väike täpsuse-langus, aga 4-8× väiksem mälukulu. Suurte vector DB-de jaoks oluline.

### Elastic'i käik: ELSER + `semantic_text`

Elastic-i strateegia on **lihtne API**.

**ELSER** (Elastic Learned Sparse EncodeR) — Elastic-i enda treenitud mudel, mis annab **sparse** vektoreid (mitte dense). Töötab pre-trained, ei pea fine-tune'ima. Esmane versioon on inglise keele, **multilingual ELSER (e5-multilingual)** lisandus 2024. Kasutamiseks lihtsalt download'id mudeli ja laed klastri.

**`semantic_text` field type** (Elasticsearch 8.13+, 2024) — mapping-level abstraktsioon, mis teeb kaks asja korraga:

```json
PUT my-index
{
  "mappings": {
    "properties": {
      "content": {
        "type": "semantic_text",
        "inference_id": "my-elser-endpoint"
      }
    }
  }
}
```

Kui sa indekseerid dokumendi `content` väljaga, **Elastic teeb automaatselt**:

1. BM25 inverted indeksi (lexical otsing)
2. ELSER-i kaudu sparse vektori (semantic otsing)

Päring:
```json
GET my-index/_search
{ "query": { "semantic": { "field": "content", "query": "tossud kontorisse" } } }
```

Elastic teeb **hybrid otsingu** ja annab kombineeritud skoori. **Üks API, kaks otsingumeetodit.**

### OpenSearch'i käik: ML Commons + Neural Search

OpenSearch on **paindlikum, aga rohkem konfigureerimist**.

**ML Commons** — plugin, mis lubab klastrisse laadida ja käivitada ML-mudeleid. Toetab nii lokaalseid mudeleid (Hugging Face transformers, ONNX) kui ka väliseid inference-teenuseid üle HTTP API: Amazon SageMaker, Amazon Bedrock ja teised mudeli-API-d.

**Neural Search plugin** — high-level abstraktsioon, mis kasutab ML Commons'i sees. Sa konfigureerid **ingest pipeline'i**, mis lisab dokumentidele vektorid:

```json
PUT _ingest/pipeline/text-embedding
{
  "processors": [{
    "text_embedding": {
      "model_id": "my-embedding-model",
      "field_map": { "content": "content_embedding" }
    }
  }]
}
```

Seejärel: `neural` query type päringuks. **Üle nelja sammu, mitte ühe — aga sa kontrollid iga sammu** ja võid panna oma kohandatud mudeli, fine-tune'itud sinu spetsiifilisele andmekorpusele.

### RAG — Retrieval-Augmented Generation

Muster, kus LLM enne vastamist küsib **relevante dokumente** vector storage'st. Põhjus: LLM-i koolitusandmed on lõplikud (ja vananenud), aga sinu organisatsiooni dokumendid on uued ja spetsiifilised.

Tüüpiline RAG arhitektuur:

```mermaid
flowchart TD
    U["👤 Kasutaja küsimus<br/>'Kuidas configureerida X?'"] --> E["Embedding mudel"]
    E --> QV["Küsimuse vektor<br/>[0.21, 0.85, ...]"]
    QV --> VDB[("Vector DB<br/>ES / OS<br/>HNSW indeks")]
    VDB --> TOP["Top 5 sarnasemat<br/>dokumenti"]
    TOP --> CTX["LLM context:<br/>[dokumendid] + [küsimus]"]
    CTX --> LLM["🤖 LLM<br/>(Claude / Llama / Titan)"]
    LLM --> ANS["💬 Vastus,<br/>põhistatud<br/>dokumentidel"]

    style U fill:#e3f2fd
    style ANS fill:#e8f5e9
    style VDB fill:#fff3e0
    style LLM fill:#f3e5f5
```

!!! info "Amazon Bedrock Knowledge Bases"
    AWS-i ametlik RAG-mootor **Bedrock Knowledge Bases** kasutab **Amazon OpenSearch Serverless'i** vaikimisi vector DB-na alates 2024. Sa upload'id dokumente S3-le, valid mudeli (Claude, Llama, Titan, DeepSeek jne), ja AWS teeb embedding'u + indekseerimise + päringu-loogika automaatselt. See on **viiteid arhitektuur** AWS-i klientidele.

**RAG monitooringu kontekstis — sinu igapäevatöö SREna:**

- **Incident response AI assistant** — sa küsid `mis juhtus eile õhtul kell 19:00?`, AI Assistant leiab vector storage'st (sinu logid + traces + alerts) relevante andmed ja võtab kokku töevi-mustri. **Elastic AI Assistant** ja **Splunk AI Assistant** positsioneerivad end just selliste kasutusjuhtude peale 2024+.
- **Runbook-otsing** — sa küsid `kuidas taaskäivitada Redis cluster kui see kukub?`, AI leiab sinu organisatsiooni Confluence'ist või wiki-st konkreetse runbooki ja annab vastuse koos sammudega.
- **Alert-korrelatsioon ja summarization** — 1000 alerti tuli ühe tunni jooksul, AI Assistant ütleb "kõik on seotud `cassandra-cluster-3` split-brain'iga, põhjus on võrgu-lüli `sw-rack-12`".
- **Semantic log pattern matching** — sa küsid `leia kõik database connectivity issues`, vector otsing leiab nii `connection refused`, `pool exhausted`, `OperationalError` kui `lost connection to host` — isegi kui sa pole neid sõnu otsisõnas kasutanud.
- **Postmortem auto-draft** — incident'i järel AI Assistant kirjutab esimese mustandi: "19:03 alert tekkis... 19:07 root cause oli... 19:15 lahendus oli..." — sinu ülesanne on üle vaadata ja parandada.

RAG **ei asenda LLM-i koolitamist** — ta annab LLM-ile kontekstit. LLM-il pole vaja teada sinu firma 2026 juhendid; ta saab need vector DB-st kontekstina, vastab nende baasil.

!!! tip "💭 Mõtle hetk — enne edasilugemist"
    Sinu organisatsioonis — on mõni koht, kus RAG (LLM + vector DB) annaks reaalset väärtust? Näiteks: sisemine dokumendi-otsing, IT-toe esmaste vastuste automaatika, regulatiivsete dokumentide-otsing, koodibaasi-navigeerimine?

    Või vastupidi: kuhu see **ei sobi** — kus on ainult täpne vastus oodatud (audit, finants, juriidilised vastused)?

### Hybrid search — BM25 + vector koos

Praktikas ei vali sa "lexical või vector" — **kõige paremad tulemused tulevad mõlema kombineerimisest**. Sellepärast on Elasticsearchi `semantic_text` ja OpenSearchi hybrid search query molemad disainitud nii, et nad annavad **mol-skoori**: BM25 osa + vector cosine osa, kaalutud kokku.

**Miks kombineerida?**

- BM25 on **kõva match'iga täpne** — kui kasutaja otsib `error code 1023`, leiad dokumendid, kus see konkreetselt esineb. Vector mudel ei pruugi numbri-koodi seostada.
- Vector on **tähenduse-poolt täpne** — kui kasutaja otsib `slow database`, leiad dokumendid, kus on "performance degradation in PostgreSQL". BM25 ei seostaks.

Kaalud (näide): 0.3 × BM25 + 0.7 × vector — õiged kaalud leiad katsetamisega, see oleneb kasutusjuhtust ja andmestikust.

### Otsustamise raam: millal mida?

| Kasutusjuhus | Soovitus | Miks |
|---|---|---|
| Operatiivlogide otsing (`error`, `timeout`, `host=X`) | **BM25 (lexical)** | Sa tead sõna, otsid sõna. Vector lisab ülekulu, mis pole vajalik. |
| Audit / compliance / juriidiline otsing | **BM25 + filtrid** | Sa tahad täpset matchi, mitte sarnast. Audit-logide jaoks vector on isegi **valeoht** — ei tohi anda "sarnast" tulemust. |
| Dokumentatsiooni / wiki / runbook'ide otsing | **Hybrid** | Insenerid otsivad mõtteid ("kuidas Redis taaskäivitada"), mitte sõna-vorme. |
| Incident response / RCA päringud ("mis juhtus eile 19:00?") | **Hybrid + RAG** | Vajab semantilist seost logide / traces / alerts vahel. |
| Semantic log pattern matching (`database connectivity issues`) | **Vector** | BM25 ei leia `pool exhausted`, `OperationalError` kui otsisõnas neid pole. |
| Anomaalia-tuvastus logides ja metrikus | **ML-mudelid** (Elastic ML / OS Anomaly Detection) | Eraldi ML pipeline, mitte otsing. Vector võib täiendada. |
| Alert-korrelatsioon ja postmortem-mustandid | **Vector + RAG** (AI Assistant) | Kogub kontekstit mitmest allikast, LLM võtab kokku. |

### Kokkuvõte L3-st

Lexical (BM25) on **kiire, täpne, soodne** — logide ja täpse-matchi-otsingu jaoks parim. Vector on **tähenduselt täpne, kallim resurssidelt** — dokumentatsiooni, klienditoe ja RAG-i jaoks parim. **Hybrid kombineerib mõlemad** ja annab tavaliselt parima tulemuse. ELSER + `semantic_text` Elastic'is on lihtsam, OpenSearch ML Commons + Neural Search + FAISS on paindlikum.

Osa 4 lab'is töötate Elasticsearchi `semantic_text` väljaga ja kNN päringuga, ning vaatate OpenSearch'is neural search'i. Sama log-source mõlemasse — võrdle tulemusi.

---

## 🎯 Cheat sheet — võta töö juurde kaasa

Need neli kompaktset tabelit on mõeldud **igapäevaseks otsuseks**, mitte loengu meeldejätmiseks. Prindi välja või hoia kuvarinurkas.

### ① Otsus: Elasticsearch või OpenSearch — ja missugune?

| Sinu olukord | Vali | Miks |
|---|---|---|
| AWS-i keskkond + vendor lock-in vältimine | **Amazon OpenSearch Service** | Apache 2.0, Multi-AZ + standby kaasas, Cross-AZ transfer kaasas |
| AWS + RAG / Bedrock Knowledge Bases | **OpenSearch Serverless** | Default vector DB Bedrock-ile, auto-scale, null ops overhead |
| Self-hosted, GDPR/compliance, andmed ei lähe AWS-i | **OpenSearch on-prem** | Apache 2.0, vaba security plugin, ML Commons paindlik |
| AI / semantic search prio + lihtne API | **Elastic Cloud** | `semantic_text` field = üks rida = lexical + vector korraga |
| Kommertsiaalne tugi + Elastic APM | **Elasticsearch on-prem (Platinum)** | 24/7 SLA, APM tugevam kui OS-il |
| Väike sisekasutus, eelarve madal | **OpenSearch on-prem** (1–3 node) | Apache 2.0, ei pea litsentsi kontrollima |

### ② Otsus: klastri-dimensioneerimine

```
UPTIME NÕUE         →  KLASTRI-DISAIN
─────────────────────────────────────────────────────
99.5%  (best-effort) →  1 node, restart OK
99.9%  (8.7h/aastas) →  3 master + N data, replicas=1, snapshots S3
99.99% (52min/aastas)→  3 master + N data üle 3 AZ-i + standby AZ
99.999% (5min/aastas) →  Multi-region + CCR (harva vajalik)
```

**Checklist enne tootmist:**

- [ ] 3 dedicated master node'i (mitte 1, mitte 2)
- [ ] Data node'idel `heap = pool RAM-ist`, max 31 GB (compressed OOPs)
- [ ] `number_of_replicas ≥ 1` kõikidele indeksitele
- [ ] Snapshot S3-le (SLM / ISM policy)
- [ ] **Restore testitud** vähemalt 1 kord
- [ ] ILM-policy hot → warm → cold → frozen → delete
- [ ] Kafka või sarnane buffer kui logi-maht > 100 GB/päev

### ③ Otsus: lexical, vector või hybrid otsing? (monitooringu kontekstis)

| Kasutusjuhus | Vali | Märkus |
|---|---|---|
| Operatiivlogid (`error`, `timeout`, `host=X`) | **BM25 (lexical)** | Vector lisab kulu ilma kasuta |
| Audit / compliance / juriidiline | **BM25 + filtrid** | Vector võib anda "sarnase" — **valeoht** auditi jaoks |
| Runbook / wiki / dokumentatsiooni otsing | **Hybrid** | Inseneri sõnastik ≠ dokumendi sõnastik |
| Incident response ("mis juhtus eile 19:00?") | **Hybrid + RAG** | Vajab konteksti mitmest allikast |
| Pattern matching (`db connection issues`) | **Vector** | BM25 ei leia sarnaseid väljendusi |
| Anomaalia-tuvastus aegridades | **ML-mudelid** (Elastic ML / OS AD) | Eraldi pipeline, mitte otsing |
| Postmortem auto-draft, alert-summarization | **Vector + RAG** (AI Assistant) | LLM võtab kokku konteksti |

### ④ Otsus: hinnamudel ja TCO eelarve-aluseks

| Mudel | Toode | Hoia silm peal | Salakulud |
|---|---|---|---|
| Per-GB-ingested | Splunk, Datadog Logs | Logi-mahu kasv → arve kasv | Sundib logimist vähendama |
| Instance-based | AWS OpenSearch, ES/OS on-prem | Node-arv × RAM × ketas | **Cross-AZ transfer** (self-hosted) |
| Tier-põhine | Elastic Cloud, Confluent Cloud | Tier-piir, add-on'id | Add-on'id võivad märgatavalt kasvada |
| Hybrid (logi-osa odav) | Grafana Cloud + Loki | Loki = sildid indekseeritakse | Vähem otsingu-paindlikkust kui ELK-l |

**TCO komponendid, mis sageli unustatakse:**

- **Personali-aeg** — self-hosted vajab DevOps-i, see on eelarves
- **Cross-AZ transfer** — self-managed Multi-AZ EC2-l \$0.01–0.02/GB
- **RAM** — vector search kahekordistab heap-vajaduse
- **ML node'id** — ELSER + 1M dokumenti = eraldi node mõistlik

---

## Refleksioon ja enesetest

Päeva lõpus, enne kui klassist välja lähed, mõtle läbi:

1. Mille poolest erineb **schema-on-write** (Zabbix) ja **schema-on-read** (ELK / OS)? Miks see vahe muudab arhitektuurseid otsusi?
2. Sinul on 3 master + 5 data node klaster. Üks AZ kaob (1 master + 2 data). Mis juhtub klastri olekuga ja andmetega?
3. Sinu mõte 3 erinevat olukorda, kus eelistaksid lexical otsingut vector otsingule.
4. **Otsus**: ettevotte audit-keskkonna jaoks vali Elasticsearch on-prem või OpenSearch on-prem. Miks?
5. **Mis küsimus jäi õhku?** — kirjuta see üles. Hommepool tule tagasi.

---

## Allikad

**Ametlik dokumentatsioon:**

- [Elasticsearch ametlik dokumentatsioon](https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html)
- [OpenSearch ametlik dokumentatsioon](https://opensearch.org/docs/latest/)
- [Amazon OpenSearch Service](https://aws.amazon.com/opensearch-service/)
- [Apache Lucene](https://lucene.apache.org/)
- [Facebook AI Similarity Search (FAISS)](https://github.com/facebookresearch/faiss)

**Litsentsi-drama 2021:**

- [Elastic: "Doubling Down on Open"](https://www.elastic.co/blog/why-license-change-aws) — Elastic-i positsioon
- [AWS: "Stepping Up for a Truly Open Source Elasticsearch"](https://aws.amazon.com/blogs/opensource/stepping-up-for-a-truly-open-source-elasticsearch/) — AWS-i vastus
- [Shay Banon: "Elasticsearch is Open Source, Again"](https://www.elastic.co/blog/elasticsearch-is-open-source-again) — 2024 AGPL-i lisamine
- [Linux Foundation: OpenSearch Software Foundation kuulutus](https://www.linuxfoundation.org/press/aws-and-the-linux-foundation-establish-the-opensearch-software-foundation) — sept 2024

**Võrdlused (sissejuhatuse jaoks):**

- [Coralogix: Elasticsearch vs OpenSearch — Key Differences](https://coralogix.com/guides/elasticsearch/elasticsearch-vs-opensearch-key-differences/)
- [tecRacer: OpenSearch vs Elasticsearch 2024](https://www.tecracer.com/blog/opensearch-vs-elasticsearch-2024/)
- [Getting Started with Elasticsearch & OpenSearch AWS](https://medium.com/@sonishubham65/getting-started-with-elasticsearch-opensearch-aws-b7cdd7e8cafa) — Medium

**Otsing ja AI:**

- [Lucene BM25 algorithm](https://lucene.apache.org/core/8_0_0/core/org/apache/lucene/search/similarities/BM25Similarity.html)
- [Elasticsearch semantic_text field](https://www.elastic.co/guide/en/elasticsearch/reference/current/semantic-text.html)
- [OpenSearch Neural Search plugin](https://opensearch.org/docs/latest/search-plugins/neural-search/)
- [OpenSearch ML Commons](https://opensearch.org/docs/latest/ml-commons-plugin/)
- [Amazon Bedrock Knowledge Bases + OpenSearch Serverless](https://docs.aws.amazon.com/bedrock/latest/userguide/knowledge-base.html)
- [HNSW: Hierarchical Navigable Small World](https://arxiv.org/abs/1603.09320) — algupärane teadusartikkel

[^datadog2024]: Datadog, "State of Cloud Costs 2024" — <https://www.datadoghq.com/state-of-cloud-costs/>. Observability andmemahtude kasvu mõõdab Datadog oma 30 000+ kliendi anonymized telemetria põhjal.

[^kafka]: Apache Kafka ametlik dokumentatsioon — <https://kafka.apache.org/documentation/>. Kafka Connect: <https://kafka.apache.org/documentation/#connect>.

[^netflix-kafka]: Netflix Technology Blog, mitmed artiklid Kafka + Elasticsearch pipeline'ist alates 2018 — <https://netflixtechblog.com/tagged/kafka>. Uber Engineering, "uReplicator" projekt — <https://eng.uber.com/ureplicator-apache-kafka-replicator/>.

[^ilm-es]: Elastic, Index Lifecycle Management — <https://www.elastic.co/guide/en/elasticsearch/reference/current/index-lifecycle-management.html>.

[^ism-os]: OpenSearch, Index State Management — <https://opensearch.org/docs/latest/im-plugin/ism/index/>.

[^splunk-pricing]: Splunk hinnakiri ja Workload Pricing — <https://www.splunk.com/en_us/products/pricing.html>. Ajaloolised per-GB tier'id on dokumenteeritud Splunki community foorumites ja IDC/Forrester analyytikute raportites.

[^datadog-pricing]: Datadog hinnakiri — <https://www.datadoghq.com/pricing/>. Logs sektsioon: per-GB indexed + retention.

[^aws-os-pricing]: Amazon OpenSearch Service hinnakiri — <https://aws.amazon.com/opensearch-service/pricing/>. Instance-pohine arvelduse mudel, Reserved Instance allahindlused 30–50%.

[^elastic-pricing]: Elastic Cloud hinnakiri — <https://www.elastic.co/pricing>. Standard / Gold / Platinum / Enterprise tier'id koos add-on'idega.

[^palo-splunk]: Palo Alto Networks pressiteade tehingu sulgemise kohta (märts 2024) — <https://www.paloaltonetworks.com/company/press/2024/palo-alto-networks-completes-acquisition-of-talon-cyber-security>. Tehingu suurus avalikustati 2023 sept teate ajal — <https://investors.splunk.com/news-releases/news-release-details/palo-alto-networks-acquire-splunk>.

[^os-foundation]: Linux Foundation, "AWS and the Linux Foundation Establish the OpenSearch Software Foundation" — <https://www.linuxfoundation.org/press/aws-and-the-linux-foundation-establish-the-opensearch-software-foundation>. Numbrid (200M+ downloads jms) on OpenSearch projekti enda 2024 aastaraportist — <https://opensearch.org>.

[^aws-os-quotas]: AWS OpenSearch Service service quotas ja arhitektuuri-piirid — <https://docs.aws.amazon.com/opensearch-service/latest/developerguide/limits.html>. Multi-AZ + standby mudel: <https://docs.aws.amazon.com/opensearch-service/latest/developerguide/managedomains-multiaz.html>.

--8<-- "_snippets/abbr.md"

