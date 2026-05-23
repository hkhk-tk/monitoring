# Päev 3: Elastic Stack & OpenSearch — Labor

**Kestus:** 4 tundi (klassis ~3h, ülejäänu lisaülesannetena kodus)
**Tase:** Kesk-edasijõudnud
**Eeldused:** Päev 1 logimise põhialused, Docker Compose mitme-konteineri stack, Loki + Alloy (Päev 2)
**VM:** sinu VM (`ssh <eesnimi>@192.168.35.12X` klassivõrgust või `192.168.100.12X` VPN-ist)

---

## 🎯 Õpiväljundid

**Teadmised:**

1. Selgitab, miks single-node Elasticsearch klaster näitab `YELLOW` olekut
2. Eristab `master`, `data`, `coordinating` sõlmerolle ja nende koormust
3. Põhjendab, miks production-klastris peab olema **3** master-kandidaati (quorum-matemaatika)
4. Eristab Elasticsearchi ja OpenSearchi API ja UI tasandil
5. Suudab nimetada kaks olukorda kus eelistaks Lokit ja kaks kus Elastic Stacki

**Oskused:**

6. Käivitab Elasticsearch + Kibana stacki Docker Compose abil
7. Laiendab single-node klastri 3-node klastriks ja jälgib shard'ide ümberpaigutust
8. Simuleerib node'i kao (`docker compose stop`) ja vaatab recovery'd
9. Käivitab OpenSearch + OS Dashboards ja võrdleb Kibanaga (REST API + UI)

---

## Eeltöö

Päev 2 stack võtab RAM-i. Puhasta enne alustamist:

```bash
# Päev 1 stack alla (kui veel jookseb)
cd ~/paev1 2>/dev/null && docker compose down 2>/dev/null
# Päev 2 alla (Zabbix + Loki containerid lähevad alla — oodatud)
cd ~/paev2/zabbix 2>/dev/null && docker compose down 2>/dev/null
cd ~/paev2/loki 2>/dev/null && docker compose down 2>/dev/null

# Kontrolli RAM-i
free -h
```

**Vaba RAM peaks olema vähemalt 5 GB.** Kui pole, kontrolli mis veel jookseb: `docker ps`.

Loo päev 3 töökaust:

```bash
mkdir -p ~/paev3/elk && cd ~/paev3/elk
```

!!! warning "RAM piiri peal"
    Sinu VM-il on 6 GB RAM. 3-node Elasticsearch klaster + Kibana samaaegselt = ~4 GB. Hoia `free -h` jooksvalt teises terminalis lahti. Kui RAM saab täis, mõni container kukub OOM-killer'i alla.

---

## Osa 1 · Elasticsearch ja Kibana üksinda

> **Probleem:** Päev 2 nägid Lokit — kerge, kiire, Grafana-sõbralik. Aga Loki indekseerib **labelid**, mitte logi sisu. Kui sinu audit nõuab, et kõik logi-sõnad oleks otsitavad (näiteks "leia kõik logiread, kus mainitakse kasutaja ID-d X mistahes kohas viimase 90 päeva jooksul") — Loki ei suuda seda. Vaja on **täistekstiindeksit** — sõnaraamatut, kus iga sõna teab, millises dokumendis ta asub. See on Elasticsearch.

Esmalt paneme **ühe** Elasticsearch node'i ja Kibana püsti. Seda ei tehta production'is kunagi — me kasutame seda lihtsalt selleks, et **näha mida Kibana näitab esimese indeksi loomisega**. Vastus on ootamatu.

### 1.1 Ainult Elasticsearch

Loo `docker-compose.yml`:

```yaml
services:
  es01:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.15.3
    container_name: es01
    environment:
      - node.name=es01
      - cluster.name=lab-cluster
      - discovery.type=single-node
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    ulimits:
      memlock:
        soft: -1
        hard: -1
    ports:
      - "9200:9200"
    volumes:
      - es01-data:/usr/share/elasticsearch/data

volumes:
  es01-data:
```

**Miks `ES_JAVA_OPTS=-Xms512m -Xmx512m`** — vähendame heap'i 512 MB peale per node, sest peagi tuleb klastris 3 node'i ja sinu 6 GB VM ei taluks vaikimisi 1 GB per node.

**Miks `xpack.security.enabled=false`** — lab on isoleeritud, hoiame asju lihtsamana. Production-keskkonnas see praktiliselt alati `true` — security't tavaliselt välja ei lülitata.

Käivita ainult ES:

```bash
sudo sysctl -w vm.max_map_count=262144
docker compose up -d es01
```

Oota ~30 s, kuni ES tõuseb. Kontrolli:

```bash
curl http://localhost:9200
```

Vastus peaks olema JSON, mis ütleb klastri nime `lab-cluster` ja versiooni `8.15.x`. Kui ei tule midagi, oota veel 10 s — ES käivitub aeglaselt.

💡 **Kui `curl` ütleb `Connection refused`:** kontrolli `docker compose logs es01`. Otsi rida `"started"`. Kui näed `bootstrap check failed`, siis `vm.max_map_count` on liiga madal.

### 1.2 Loo esimene indeks, vaata olekut

Loo indeks ja saada üks dokument:

```bash
curl -X POST "http://localhost:9200/test-logs/_doc" \
  -H "Content-Type: application/json" \
  -d '{"message": "esimene logi", "level": "info"}'
```

Vaata indeksite olekut:

```bash
curl "http://localhost:9200/_cat/indices?v"
```

Märkad veergu **`health`**, mille väärtus on **`yellow`**. **Miks?**

```bash
curl "http://localhost:9200/_cluster/health?pretty"
```

Vastus ütleb:

```json
"status" : "yellow",
"unassigned_shards" : 1,
```

**`unassigned_shards: 1`** — replica shard'il pole kohta. Default `number_of_replicas: 1` tähendab, et primary shard'ist tehakse 1 koopia. Koopia peab paiknema **eri node'is** kui primary. Sul on **1 node**, niisiis koopia jääb õhku rippuma.

💭 **Mõtle (vastust ära kerige enne):** Mis juhtub, kui sa kustutad kogemata praeguse ainsa node'i? Kas indeks on taastatav `replicas: 1` seadistusega?

> 🔍 **Mõttearendus** (loe alles pärast oma vastust): Indeks kaob. `replicas: 1` ei aita, kui koopia pole **eri node'il**. See on, miks production-klastrites on **vähemalt 2 node'i** ja replicas ≥ 1.

### 1.3 Lisa Kibana

`docker-compose.yml`-i, **enne** `volumes:` rida, lisa:

```yaml
  kibana:
    image: docker.elastic.co/kibana/kibana:8.15.3
    container_name: kibana
    depends_on:
      - es01
    environment:
      - ELASTICSEARCH_HOSTS=http://es01:9200
    ports:
      - "5601:5601"
```

Käivita:

```bash
docker compose up -d kibana
```

Oota ~45 s. Ava brauser: `http://<sinu-VM-IP>:5601`. Klassist `192.168.35.12X`, VPN-ist `192.168.100.12X`.

Kibanas vasakul üleval `☰` → **Management** → **Stack Monitoring** → **Or, set up with self monitoring** → enable.

Seejärel **Stack Monitoring** näitab: klaster `lab-cluster`, **olek YELLOW**, 1 node, indeks `test-logs` `YELLOW` (1 replica unassigned).

💡 **Kui Kibana ütleb `Kibana server is not ready yet`:** oota veel 30 s. Kibana vajab ES-i täielikult valmis, enne kui käivitub.

### 1.4 KQL otsing Discover'is

Vasakul **Discover** → loo data view (`test-logs*`) → ajaperioodiks "Last 24 hours".

Saada veel paar dokumenti terminalist:

```bash
for level in info warn error; do
  curl -X POST "http://localhost:9200/test-logs/_doc" \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"logi tüübiga $level\", \"level\": \"$level\"}"
  echo
done
```

Vajuta Discover'is **Refresh**. Näed 4 dokumenti.

Proovi KQL filtreid:

```kql
level : "error"
```

```kql
level : "error" or level : "warn"
```

```kql
message : *logi*
```

```kql
level : "error" and message : *info*
```

Viimane peaks tagastama 0 tulemust — õpiku näide, kuidas KQL **and** töötab dokumentide tasandil, mitte sõna tasandil.

💭 **Mõtle:** Sa just kirjutasid 4 päringut KQL-iga. **Vasta peast:** mis on suur erinevus KQL-i ja LogQL-i (Päev 2 Loki) süntaksite vahel? Kumb tundub esmapilgul intuitiivsem?

---

## Osa 2 · Laienda 3-node klastriks

> **Probleem:** Osa 1 lõpus oli sinu klaster YELLOW. Sa tead, miks (replica unassigned). Aga oletame, et sa oled e-poe SRE — sinu klaster töötab production'is ja YELLOW olek tähendab: **kaotad ühe DB krahhi puhul logi-andmed lõplikult**. See pole vastuvõetav. Lahendus pole "lülitan replicas: 0-ks" (siis ei ole **mingit** kaitset). Lahendus on lisada node'e. Aga **mitu**? Ja **kuidas** nad omavahel räägivad? Vastuse leiad järgmise tunni jooksul.

**Production-mudel** on **3 dedicated master + N data**, aga 6 GB RAM-iga teeme lihtsama versiooni: **3 node'i, igaühel kõik rollid**. Quorum-matemaatika töötab sama — vaatame kuidas.

> 📖 **Enne kui edasi lähed:** Loengu plokk **L2.2 "Cluster state ja quorum"** seletab, miks just kolm, mitte kaks. Loe see üle (max 3 minutit). Selles osas eeldame seda teadmist.

### 2.1 Peata ja restruktureeri

Peata praegune setup:

```bash
docker compose down
```

Andmed (volume `es01-data`) jäävad alles — me ei kustuta neid.

Asenda kogu `docker-compose.yml` sisu uuega:

```yaml
services:
  es01:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.15.3
    container_name: es01
    environment:
      - node.name=es01
      - cluster.name=lab-cluster
      - discovery.seed_hosts=es02,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    ulimits:
      memlock: { soft: -1, hard: -1 }
    volumes:
      - es01-data:/usr/share/elasticsearch/data
    ports:
      - "9200:9200"

  es02:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.15.3
    container_name: es02
    environment:
      - node.name=es02
      - cluster.name=lab-cluster
      - discovery.seed_hosts=es01,es03
      - cluster.initial_master_nodes=es01,es02,es03
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    ulimits:
      memlock: { soft: -1, hard: -1 }
    volumes:
      - es02-data:/usr/share/elasticsearch/data

  es03:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.15.3
    container_name: es03
    environment:
      - node.name=es03
      - cluster.name=lab-cluster
      - discovery.seed_hosts=es01,es02
      - cluster.initial_master_nodes=es01,es02,es03
      - xpack.security.enabled=false
      - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
    ulimits:
      memlock: { soft: -1, hard: -1 }
    volumes:
      - es03-data:/usr/share/elasticsearch/data

  kibana:
    image: docker.elastic.co/kibana/kibana:8.15.3
    container_name: kibana
    depends_on: [es01, es02, es03]
    environment:
      - ELASTICSEARCH_HOSTS=http://es01:9200
    ports:
      - "5601:5601"

volumes:
  es01-data:
  es02-data:
  es03-data:
```

Märkad **kolme uut muutujat** võrreldes single-node setupiga:

- `discovery.seed_hosts` — loend teistest node'idest, kellega ühenduda klastri leidmiseks
- `cluster.initial_master_nodes` — algse klastri loomisel master-kandidaatide loend (kasutatakse **AINULT** esimesel käivitusel)
- `discovery.type=single-node` on **eemaldatud** — me ei ole enam single-node

Iga node on `master, data, ingest` rollis korraga (default kui pole `node.roles` määratud). See on **lab-konfiguratsioon**, mitte production. Production'is on master ja data eraldatud (vt loengu L2).

### 2.2 Käivita 3-node klaster

```bash
docker compose up -d
```

Vaata RAM-i jälgides:

```bash
free -h
```

Oota ~60 s. Kontrolli klastri olekut:

```bash
curl "http://localhost:9200/_cluster/health?pretty"
```

Oodatav vastus:

```json
"status" : "green",
"number_of_nodes" : 3,
"number_of_data_nodes" : 3,
"active_shards" : 2,
"unassigned_shards" : 0,
```

**GREEN!** Praegu replica `test-logs` indeksist sai koha (eri node'il kui primary). Vaata node'e:

```bash
curl "http://localhost:9200/_cat/nodes?v"
```

Näed kolme node'i. Ühel on `master` veerus täht `*` — see on **valitud master**. Teised on master-kandidaadid.

Ava Kibana **Stack Monitoring** — klaster näitab nüüd GREEN, 3 node'i.

💡 **Kui klaster ei tule üles 60 s jooksul:** `docker compose logs es01 | grep -i "master"`. Otsi `master node changed`. Kui näed `master not discovered yet`, oota veel.

### 2.3 Simuleeri node'i kadu

Praegu klaster on terve. Simuleeri probleemi — kujuta ette, et see on AWS AZ kao algus:

```bash
docker compose stop es02
```

Kohe kontrolli:

```bash
curl "http://localhost:9200/_cluster/health?pretty"
```

Näed:

```json
"status" : "yellow",
"number_of_nodes" : 2,
"unassigned_shards" : 1,
```

**YELLOW** — üks shard'i koopia kaotas oma node'i. Klaster otsib uut kohta. Oota 60 s ja kontrolli uuesti:

```bash
sleep 60 && curl "http://localhost:9200/_cluster/health?pretty"
```

Nüüd peaks olema **GREEN** uuesti — shard tehti ümber kahele allesjäänud node'ile. Vaata indeksite olekut:

```bash
curl "http://localhost:9200/_cat/shards?v"
```

Iga shard (primary + replica) on nüüd ühel kahest järelejäänud node'ist.

💡 **Kui klaster jäi YELLOW:** vaata kas `unassigned_shards > 0` — ehk shard ei mahu (disk space). `curl localhost:9200/_cluster/allocation/explain?pretty` näitab miks.

### 2.4 Too node tagasi

```bash
docker compose start es02
```

Oota ~60 s (ES Java käivitub aeglaselt), vaata uuesti:

```bash
curl "http://localhost:9200/_cat/shards?v"
```

Näed, et mõned shard'id liiguvad tagasi es02-le. Klaster **balansseerib uuesti** — see on automaatne shard recovery. Kibanas Stack Monitoring näitab sama.

💭 **Mõtle (enne edasilugemist):** Sinu organisatsiooni keskkonnas — kui sa pead haldama klastrit, mis on jagatud kahe andmekeskuse vahel — kus on master-kandidaadid? Kuidas tagad, et üks DC kadu ei tee klastrit **read-only**?

> 🔍 **Mõttearendus:** Vastus on **kolmes asukohas** — kaks DC-d ja üks **arbiter/witness** kolmandas asukohas (näiteks pilves AZ-i kõrval). Quorum nõuab > 50% master-kandidaate. 2 DC × 1 master = 2 kandidaati, üks DC kadu → 1 master = quorum kadunud. Vaja on **3. asukohta** ainult selleks, et säilitada quorum DC-katkestuse ajal. See on, miks **ainult kaks andmekeskust pole klastri jaoks lahendus** — vaja minimaalselt 3 erinevat võrgu-failure-domeeni.

### 2.5 Testi: katkesta 2 node'i

Kui sul on aega ja oled valmis nägema, mis juhtub, kui klaster quorum'i kaotab:

```bash
docker compose stop es02 es03
sleep 10
curl "http://localhost:9200/_cluster/health?pretty"
```

Vastus näitab error või `master_not_discovered_exception`. Klaster ei suuda valida masterit, sest quorum (2) puudub.

Too tagasi:

```bash
docker compose start es02 es03
```

Oota ~45 s, kontrolli uuesti — klaster taastub GREEN olekusse.

💭 **Mõtle:** Kirjuta paberile (või tekstifaili) **2 lauset**, kelle jaoks sinu töökohas selle stsenaariumi tagajärjed oleksid kõige raskemad. Kas auditi-spetsialistile (logid kadunud)? Tugitiimile (otsing maas)? Dev-tiimile (rakenduse trace kadunud)? Vasta enda peast — koolitajal hea hiljem küsida.

---

## Osa 3 · OpenSearch kõrval — võrdlus ES-iga

> **Probleem:** Sinu juht küsib: "miks me ELK-i ostame, kui OpenSearch on tasuta?" Sul on 30 sekundit vastata. Praeguse osa eesmärk: sa saad **konkreetse** vastuse, mitte vendor-turunduse. Mõlemast platvormist on sinu töökohal kaal — sa pead suutma valida.

**Sama tehniline alus 2021-st** — OpenSearch hargnes Elasticsearch 7.10.2-st (litsentsi vahetuse tõttu) ja läks oma teed. Täna (2026) on mõlemad küpsed. Kõrvuti tegemine annab sulle kätte konkreetse võrdluse.

!!! warning "RAM-piiri rikkumise oht"
    3-node ES + 3-node OS + Kibana + OS Dashboards samaaegselt = ~9–10 GB. **Sinu 6 GB VM ei pea seda üleval.** **Peata kindlasti ES klaster** enne OpenSearchi käivitamist.

### 3.1 Peata ES, vabasta RAM

```bash
docker compose down
free -h
```

Vaata, et RAM oleks vaba (4–5 GB free). Andmed (volumes `es01-data` jne) jäävad, tuled hiljem tagasi.

### 3.2 OpenSearch klastri compose

Loo uus kaust ja `docker-compose.yml`:

```bash
mkdir -p ~/paev3/os && cd ~/paev3/os
```

```yaml
services:
  os01:
    image: opensearchproject/opensearch:2.18.0
    container_name: os01
    environment:
      - node.name=os01
      - cluster.name=lab-os-cluster
      - discovery.seed_hosts=os02,os03
      - cluster.initial_cluster_manager_nodes=os01,os02,os03
      - bootstrap.memory_lock=true
      - DISABLE_SECURITY_PLUGIN=true
      - DISABLE_INSTALL_DEMO_CONFIG=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
    ulimits:
      memlock: { soft: -1, hard: -1 }
    volumes:
      - os01-data:/usr/share/opensearch/data
    ports:
      - "9200:9200"

  os02:
    image: opensearchproject/opensearch:2.18.0
    container_name: os02
    environment:
      - node.name=os02
      - cluster.name=lab-os-cluster
      - discovery.seed_hosts=os01,os03
      - cluster.initial_cluster_manager_nodes=os01,os02,os03
      - bootstrap.memory_lock=true
      - DISABLE_SECURITY_PLUGIN=true
      - DISABLE_INSTALL_DEMO_CONFIG=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
    ulimits:
      memlock: { soft: -1, hard: -1 }
    volumes:
      - os02-data:/usr/share/opensearch/data

  os03:
    image: opensearchproject/opensearch:2.18.0
    container_name: os03
    environment:
      - node.name=os03
      - cluster.name=lab-os-cluster
      - discovery.seed_hosts=os01,os02
      - cluster.initial_cluster_manager_nodes=os01,os02,os03
      - bootstrap.memory_lock=true
      - DISABLE_SECURITY_PLUGIN=true
      - DISABLE_INSTALL_DEMO_CONFIG=true
      - "OPENSEARCH_JAVA_OPTS=-Xms512m -Xmx512m"
    ulimits:
      memlock: { soft: -1, hard: -1 }
    volumes:
      - os03-data:/usr/share/opensearch/data

  os-dashboards:
    image: opensearchproject/opensearch-dashboards:2.18.0
    container_name: os-dashboards
    depends_on: [os01, os02, os03]
    environment:
      - OPENSEARCH_HOSTS=http://os01:9200
      - DISABLE_SECURITY_DASHBOARDS_PLUGIN=true
    ports:
      - "5601:5601"

volumes:
  os01-data:
  os02-data:
  os03-data:
```

**Märkad erinevusi ES-iga:**

- `cluster.initial_cluster_manager_nodes` (mitte `master_nodes`) — OpenSearch sai 2.0-st lahti sõnast "master", kasutab `cluster_manager`. **Sama mõiste, lihtsalt erinev nimi.**
- Pildi nimi `opensearchproject/opensearch:2.18.0` — versioon vastab AWS-i toetatud versioonile
- `DISABLE_SECURITY_PLUGIN=true` — OpenSearch Security plugin on **vaikimisi sees** (erinevalt ES-ist), keelame labi jaoks

### 3.3 Käivita ja kontrolli

```bash
docker compose up -d
sleep 60
free -h
curl "http://localhost:9200/_cluster/health?pretty"
```

Oodatud vastus on **sama mõtega kui ES-il**:

```json
"cluster_name" : "lab-os-cluster",
"status" : "green",
"number_of_nodes" : 3,
```

💡 **Kui näed `OpenSearch is not running` või `cluster manager not discovered`:** oota veel 30–60 s. OS käivitub aeglasemalt kui ES.

### 3.4 OS Dashboards — sarnasus Kibanaga

Ava brauser: `http://<sinu-VM-IP>:5601`. OS Dashboards UI.

Vasakul üleval `☰` → **Discover**. UI on **80% identne** Kibanaga. Sama navigatsioon, sama Discover-vaade, sama Index Patterns mõiste.

### 3.5 Võrdle: REST API on sisuliselt identne

Saada sama dokument OS-i, kui sa ES-i panid:

```bash
curl -X POST "http://localhost:9200/test-logs/_doc" \
  -H "Content-Type: application/json" \
  -d '{"message": "esimene logi OS-is", "level": "info"}'
```

Vaata indeksit:

```bash
curl "http://localhost:9200/_cat/indices?v"
```

Täpselt sama vorming, sama veerud, sama `health: green` (sest 3 node'i).

KQL-päringud Discoveris töötavad **täpselt sama süntaksiga**:

```kql
level : "info"
```

### 3.6 Mis on tegelikud erinevused?

API ja UI tasandil vähesed. Erinevused tulevad neis kohtades, kus toode on **2021+ arenenud**:

| Aspekt | Elasticsearch 8.x | OpenSearch 2.x |
|---|---|---|
| Security plugin | xpack (Elastic License) | OpenSearch Security (Apache 2.0) |
| Vector search | `dense_vector` + ELSER + `semantic_text` | `knn_vector` + ML Commons + FAISS |
| Litsents | Mitmekordne litsentsimudel (Elastic License 2.0 / SSPL / AGPLv3 osa komponentidest) | Apache 2.0 |
| AWS integratsioon | Marketplace'i kaudu | Natiivne (Bedrock, SageMaker, IAM, KMS) |
| Cluster manager / master | `master` täht | `cluster_manager` täht (samaväärne) |

**Praktiline otsus tüüpiliselt:**

- **AWS-keskne organisatsioon** (kasutab Bedrocki, SageMakeri, IAM-i) → tihti OpenSearch, sest natiivne integratsioon
- **Olemasolev Elastic-investeering** (Logstash pipeline'id, Elastic Common Schema, ELSER-i kasutus) → ES
- **Hybrid-cloud või on-prem ilma AWS-ita** → ES kipub olema tavalisem valik
- **Tugev litsentsi-vastane joon** (avalik sektor, kus AGPL/SSPL on probleem) → OpenSearch

💭 **Mõtle:** Sinu organisatsiooni puhul — milline neist neljast joonist puudutab kõige rohkem? Kas vastus on selge, või on rohkem kui üks faktor oluline?

---

## Osa 4 · Vector search — maitseproov

> **Probleem:** Sinu tugitiim saab päevas 50 tiketit. Pooled on samad probleemid eri sõnadega: "DB ei vasta", "andmebaas timeout", "PostgreSQL connection refused", "psycopg2 OperationalError". BM25 otsing (tavaline täistekstiotsing) **ei seo** neid omavahel — need pole sõnastikus sarnased. Vector search teeb seda. Vaatame **arvuliselt**, kuidas.

L3 loengu osa rääkis BM25-st (lexical) ja vector otsingust. Praegune osa on **lühike maitseproov**, mitte täielik ELSER setup. Eesmärk: näed, kuidas `knn_vector` field töötab praktikas, ilma et peaksid embedding-mudelit laadima.

OS klaster on praegu üleval Osa 3 järel. Kasutame seda.

### 4.1 Loo indeks vector field'iga

```bash
curl -X PUT "http://localhost:9200/log-vectors" \
  -H "Content-Type: application/json" \
  -d '{
    "settings": { "index.knn": true },
    "mappings": {
      "properties": {
        "message": { "type": "text" },
        "embedding": { "type": "knn_vector", "dimension": 4 }
      }
    }
  }'
```

Märkad **`knn_vector`** — OpenSearchi vector-tüüp. Reaalsuses on dimensioon 384, 768 või 1536. **4 dimensiooni** on selleks, et saaksime käsitsi vektoreid kirjutada ja vaadata, mis juhtub.

### 4.2 Saada dokumente

Kujutame, et need on logiread, mille embedding-mudel on juba vektoriteks arvutanud (4-dim ruum). Kaks tähenduspaari:

```bash
# Database connection issues (sarnased vektorid)
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "DB connection timeout", "embedding": [0.9, 0.1, 0.0, 0.0]}'
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "connection pool exhausted", "embedding": [0.85, 0.15, 0.0, 0.0]}'
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "psycopg2 OperationalError", "embedding": [0.88, 0.12, 0.0, 0.0]}'

# Network-related (eraldi klaster)
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "network unreachable", "embedding": [0.0, 0.0, 0.9, 0.1]}'
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "route to host failed", "embedding": [0.0, 0.0, 0.85, 0.15]}'
```

**Vaata vektoreid** — kolm esimest on `[0.85-0.9, 0.1-0.15, 0, 0]` lähedal. Viimased kaks on `[0, 0, 0.85-0.9, 0.1-0.15]`. **Need moodustavad kaks eri klastrit vektorruumis** — embedding-mudel paneb sarnased asjad lähestikku.

### 4.3 Vector päring

Otsi midagi, mille vektor on `[0.9, 0.1, 0.0, 0.0]` (sarnane database-klastri'ga):

```bash
curl -X POST "http://localhost:9200/log-vectors/_search?pretty" \
  -H "Content-Type: application/json" \
  -d '{
    "size": 5,
    "query": {
      "knn": {
        "embedding": {
          "vector": [0.9, 0.1, 0.0, 0.0],
          "k": 3
        }
      }
    }
  }'
```

**Uuri vastust ise**, mitte loe minu järeldust. Vaata:

1. Mis järjekorras tulemused on?
2. Millised `_score` väärtused?
3. Kas database-grupi 3 sõnumit on **kõik enne** network-grupi sõnumeid?

Kui vastus on "jah" — siis nägid praktikas, miks `knn` otsing on **semantiline**, mitte sõnapõhine. BM25 ei oleks seda teinud, sest "psycopg2" pole sõnaraamatuna "DB connection timeout" lähedal.

💭 **Mõtle:** Sinu töökohas — kas on **konkreetne otsingustsenaarium**, kus tugitiim või dev-tiim **otsib praegu täiesti vale märksõnaga**? Kas vector search aitaks?

### 4.4 Mis tulekul (ei tehta klassis)

Täielik setup vajaks:

1. **Embedding-mudel** klastris (HuggingFace `sentence-transformers/all-MiniLM-L6-v2` või sarnane)
2. **Ingest pipeline** mis arvutab `message → embedding` automaatselt
3. **Hybrid päring** (BM25 + vector koos)
4. **ML node** — eraldi node ML tööle, et mitte koormata põhi-klastrit

ES-i `semantic_text` field teeb sammud 1+2 **automaatselt** — see on lisaülesanne A all.

---

## ✅ Lõpukontroll (kombineeritud — tehnika + arusaamine)

**Tehniline (verifitseeritav):**

- [ ] Sinu `docker compose ps` ~/paev3/elk järel näitab 3 ES node + Kibana — kõik `healthy` või `Up`
- [ ] `curl http://localhost:9200/_cluster/health?pretty` näitab `status: green` ja `number_of_nodes: 3`
- [ ] `curl http://localhost:9200/_cat/nodes?v` näitab kolme node'i, ühel `*` master veerus
- [ ] Kibana Stack Monitoring näitab GREEN klastri olekut
- [ ] Sa simuleerisid node'i kao (`docker stop es02`), klaster läks YELLOW ja taas GREEN ~60 s pärast
- [ ] OpenSearchi klaster ~/paev3/os käivitub ja näitab `status: green` 3 node'iga
- [ ] OS Dashboards UI on **selgesti sarnane** Kibanaga
- [ ] Vector päring `knn_vector` field'iga annab database-grupi sõnumid esimesteks

**Arusaamine (vasta peast, kirjuta paberile või tekstifaili):**

- [ ] Suudad **ühe lausega** seletada, miks production tahab 3, mitte 2 master-kandidaati
- [ ] Suudad nimetada **2 olukorda**, kus eelistaksid Lokit Elasticsearchile, ja **2**, kus vastupidi
- [ ] Mõistad **miks dimensioon 4** vector-näites oli pedagoogiline lihtsustus, mitte päris kasutus
- [ ] Suudad **ühe lausega** öelda, mis on `master` vs `cluster_manager` erinevus ES-i ja OS-i vahel

---

## 🚀 Lisaülesanded (kes jõuab ette)

**A. ELSER-mudel ja `semantic_text`** — Elastic ES klastris (peata OS, käivita ES):

1. Laadi ELSER mudel: Kibana → Machine Learning → Trained Models → Download `.elser_model_2`
2. Deploy mudel
3. Loo indeks `semantic_text` field'iga (vt loengu L3 koodi)
4. Saada paar dokumenti, vaata kuidas Elastic automaatselt teeb BM25 + ELSER hybridit

**B. Snapshot S3-le** — simuleeri snapshot:

1. Loo lokaalne kaust `mkdir -p ~/paev3/snapshots`
2. Lisa Compose'i `volumes: - ~/paev3/snapshots:/snapshots` kõigile ES node'idele
3. Registreeri repository: `curl -X PUT localhost:9200/_snapshot/local -d '{"type":"fs","settings":{"location":"/snapshots"}}'`
4. Tee snapshot, kustuta indeks, taasta

**C. Kafka kui ingest buffer** — ehita Filebeat → Kafka → Logstash → ES pipeline (vt L2 "Andmevoog" Mermaid)

---

## Veaotsing

| Probleem | Kontroll | Lahendus |
|---|---|---|
| `Connection refused` curl-il | `docker compose ps` | Container pole `Up`. `docker compose logs <node>` |
| `bootstrap check failed` ES logis | `sysctl vm.max_map_count` | `sudo sysctl -w vm.max_map_count=262144` |
| Container kukub OOMkill | `dmesg \| grep -i oom` | RAM piiril. Peata teised stack'id, või vähenda heap'i 256m peale |
| Kibana `not ready yet` 2 min pärast | `docker logs kibana \| tail -50` | ES pole üleval. `curl localhost:9200` ENNE Kibana ootamist |
| Klaster jäi YELLOW pärast node-tagasi-toomist | `curl localhost:9200/_cluster/allocation/explain?pretty` | Disk space, shard allocation rules |
| OS Dashboards `OpenSearch is not running` | `curl http://localhost:9200/_cluster/health` | OS klaster pole valmis. Oota 60 s |
| `master_not_discovered_exception` | `docker logs es01 \| grep -i master` | 2+ node maas. Quorum kadunud. Too node'id tagasi |

---

## 📚 Allikad

| Allikas | URL | Miks oluline |
|---|---|---|
| Elasticsearch ametlik docs | <https://www.elastic.co/guide/en/elasticsearch/reference/current/> | Ainus autoriteetne allikas konfiguratsiooni jaoks |
| OpenSearch ametlik docs | <https://opensearch.org/docs/latest/> | Vastav OS dokumentatsioon |
| Elastic semantic_text + ELSER | <https://www.elastic.co/guide/en/elasticsearch/reference/current/semantic-text.html> | Lisaülesanne A kontekst |
| OpenSearch k-NN ja neural search | <https://opensearch.org/docs/latest/search-plugins/neural-search/> | Vector search OS-is |
| Elasticsearch Docker Compose example | <https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html> | Production-sarnane multi-node setup |
| OpenSearch Docker Compose | <https://opensearch.org/docs/latest/install-and-configure/install-opensearch/docker/> | OS multi-node setup |

--8<-- "_snippets/abbr.md"
