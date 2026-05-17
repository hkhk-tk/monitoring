# Päev 3: Elastic Stack & OpenSearch — Labor

**Kestus:** 4 tundi (klassis ~3h, ülejäänu lisaülesannetena kodus)
**Tase:** Kesk-edasijõudnud
**Eeldused:** Päev 1 logimise põhialused, Docker Compose mitme-konteineri stack, Loki + Promtail (Päev 2)
**VM:** sinu VM (`ssh <eesnimi>@192.168.35.12X` klassivõrgust või `192.168.100.12X` VPN-ist)

---

## 🎯 Õpiväljundid

**Teadmised:**

1. Selgitab, miks single-node Elasticsearch klaster näitab `YELLOW` olekut
2. Eristab `master`, `data`, `coordinating` sõlmerolle ja nende koormust
3. Põhjendab, miks production-klastris peab olema **3** master-kandidaati (quorum-matemaatika)
4. Eristab Elasticsearchi ja OpenSearchi API ja UI tasandil

**Oskused:**

5. Käivitab Elasticsearch + Kibana stacki Docker Compose abil
6. Laiendab single-node klastri 3-node klastriks ja jälgib shard'ide ümberpaigutust
7. Simuleerib node'i kao (`docker compose stop`) ja vaatab recovery'd
8. Käivitab OpenSearch + OS Dashboards ja võrdleb Kibanaga (REST API + UI)

---

## Eeltöö

Päev 2 stack võtab RAM-i. Puhasta enne alustamist:

```bash
# Päev 2 alla (Zabbix + Loki containerid lähevad alla — oodatud)
cd ~/paev2/zabbix && docker compose down 2>/dev/null
cd ~/paev2/loki && docker compose down 2>/dev/null

# Kontrolli RAM-i
free -h
```

**Vaba RAM peaks olema vähemalt 5 GB.** Kui pole, kontrolli mis veel jookseb: `docker ps`.

Loo päev 3 töökaust:

```bash
mkdir -p ~/paev3/elk && cd ~/paev3/elk
```

!!! warning "RAM piiri peal"
    Sinu VM-il on 6 GB RAM. 3-node Elasticsearch klaster + Kibana + Filebeat samaaegselt = ~5–6 GB. Hoia `htop` või `free -h` jooksvalt teises terminalis lahti. Kui RAM saab täis, mõni container kukub OOM-killer'i alla.

---

## Osa 1 · Elasticsearch ja Kibana üksinda

Esmalt paneme **ühe** Elasticsearch node'i ja Kibana püsti. See on **mitte** production-setup — see on selleks, et näha, **mida Kibana näitab esimese indeksi loomisega**. Vastus on huvitav.

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

**Miks `xpack.security.enabled=false`** — lab on isoleeritud, hoiame asju lihtsamana. Production-keskkonnas on see **alati `true`**.

Käivita ainult ES:

```bash
docker compose up -d es01
```

Oota ~30 s, kuni ES tõuseb. Kontrolli:

```bash
curl http://localhost:9200
```

Vastus peaks olema JSON, mis ütleb klastri nime `lab-cluster` ja versiooni `8.15.x`. Kui ei tule midagi, oota veel 10 s — ES tõuseb aeglaselt.

💡 **Kui `curl` ütleb `Connection refused`:** kontrolli `docker compose logs es01`. Otsi rida `"started"`. Kui näed `bootstrap check failed`, siis `vm.max_map_count` on liiga madal — käivita `sudo sysctl -w vm.max_map_count=262144`.

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

**`unassigned_shards: 1`** — replica shard'il ei ole kohta. Default `number_of_replicas: 1` tähendab, et primary shard'ist tehakse 1 koopia. Koopia peab paiknema **eri node'is** kui primary. Sul on **1 node**, niisiis koopia jääb õhku rippuma.

💭 **Mõtle:** Mis juhtub kui sa kustutad kogemata praeguse ainsa node'i? Vasta enne edasi lugemist.

(Vastus: kogu indeks kaob. `replicas: 1` ei aita kui koopia pole **eri node'il**. See on miks production-klastrites on **vähemalt 2 node'i** ja replicas ≥ 1.)

### 1.3 Lisa Kibana

`docker-compose.yml` lõppu, **enne** `volumes:` rida, lisa:

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

💡 **Kui Kibana ütleb `Kibana server is not ready yet`:** oota veel 30 s. Kibana vajab ES-i täielikult valmis enne kui tõuseb.

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

💭 **Mõtle:** Praegune indeks on 1 primary + 1 replica (replica unassigned). Kui käivitad 1000 logi sekundis, kuhu need lähevad ja mis juhtub indekseerimise kiirusega kui replica oleks paigutatud eri node'is?

---

## Osa 2 · Laienda 3-node klastriks

Osa 1 jättis sind YELLOW olekuga. Lahendus: lisa rohkem node'e samasse klastrisse. **Production-mudel** on **3 dedicated master + N data**, aga 6 GB RAM-iga teeme lihtsama versiooni: **3 node'i, igaileks kõik rollid**. Quorum-matemaatika töötab sama — vaatame kuidas.

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

Ava Kibana **Stack Monitoring** — klaster nuumber näitab nuud GREEN, 3 node'i.

💡 **Kui klaster ei tule üles 60 s jooksul:** `docker compose logs es01 | grep -i "master"`. Otsi `master node changed`. Kui näed `master not discovered yet`, oota veel — või kontrolli `vm.max_map_count`.

### 2.3 Simuleeri node'i kadu

Praegu klaster on terve. Simuleeri probleemi:

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

**YELLOW** — üks shard'i koopia kaotas oma node'i. Klaster otsib uut kohta. Oodake 60 s ja kontrolli uuesti:

```bash
sleep 60 && curl "http://localhost:9200/_cluster/health?pretty"
```

Nuud peaks olema **GREEN** uuesti — shard tehti ümber kahele allesjäänud node'ile. Vaata indeksite olekut:

```bash
curl "http://localhost:9200/_cat/shards?v"
```

Iga shard (primary + replica) on nüüd ühel kahest järels jäänud node'ist.

💡 **Kui klaster jäi YELLOW:** vaata kas `unassigned_shards > 0` — ehk shard ei mahu (disk space). `curl localhost:9200/_cluster/allocation/explain?pretty` näitab miks.

### 2.4 Too node tagasi

```bash
docker compose start es02
```

Oota 30 s, vaata uuesti:

```bash
curl "http://localhost:9200/_cat/shards?v"
```

Näed, et mõned shard'id liiguvad tagasi es02-le. Klaster **balansseerib uuesti** — see on automaatne shard recovery. Kibanas Stack Monitoring näitab samuti.

💭 **Mõtle:** Mis juhtub kui **kaks** node'i kaovad korraga? Kas klaster töötab edasi? Põhjus on **quorum** — vaata loengu L2 plokis "Cluster state ja quorum". (Vastus: ei tööta. 3 master-kandidaadi quorum = 2; ühe järgse 1 node'iga ei ole enamust, master-valimine peatub, klaster on `read-only` või kaotab oleku-juhtimise.)

### 2.5 Testi: katkesta 2 node'i

Kui sul on aega ja oled valmis nägema klastri sigatud:

```bash
docker compose stop es02 es03
sleep 10
curl "http://localhost:9200/_cluster/health?pretty"
```

Vastus näitab error või `master_not_discovered_exception`. Klaster ei suuda valida masterit, sest quorum (2) puudub.

Töösta tagasi:

```bash
docker compose start es02 es03
```

Oota ~45 s, kontrolli uuesti — klaster taastub GREEN olekusse.

💭 **Mõtle:** Kui sinu organisatsiooni production-klaster on 3 master + 5 data node ja üks AZ kukub (kustutab 1 master + 2 data), mis juhtub? Vasta loengu L2 "99.9% praktikas" tabeli põhjal.

---

## Osa 3 · OpenSearch kõrval — võrdlus ES-iga

Nüüd vaatame teist külge. **Sama tehniline alus 2021-st** — OpenSearch hargnes Elasticsearch 7.10.2-st ja läks oma teed. Täna (2026) on mõlemad küpsed. Kõrvuti tegemine annab sulle kätte konkreetse võrdluse, mitte ainult vendor-turunduse.

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

- `cluster.initial_cluster_manager_nodes` (mitte `master_nodes`) — OpenSearch sai 2.0-st lahti sõnast "master", kasutab `cluster_manager`. **Sama mõiste, eri nimi.**
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

💡 **Kui näed `OpenSearch is not running` või `cluster manager not discovered`:** oota veel 30–60 s. OS tuleb üles aeglasemalt kui ES, eriti kõva lõikamisega heap'iga.

### 3.4 OS Dashboards — sarnasus Kibanaga

Ava brauser: `http://<sinu-VM-IP>:5601`. OS Dashboards UI.

Vasakul üleval `☰` → **Discover**. UI on **80% identne** Kibanaga. Sama navigatsioon, sama Discover-vaade, isegi sama Index Patterns mõiste (kuigi OS-is on need pakutud kui "index patterns").

### 3.5 Võrdle: REST API on identne

Saada sama dokument OS-i kui sa ES-i panid:

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

KQL päringud Discover'is töötavad **täpselt sama syntaxiga**:

```kql
level : "info"
```

### 3.6 Mis on tegelikud erinevused?

API ja UI tasandil vähesed. Erinevused tulevad neis kohtades, kus toode on **2021+ arenenud**:

| Aspekt | Elasticsearch 8.x | OpenSearch 2.x |
|---|---|---|
| Security plugin | xpack (Elastic License) | OpenSearch Security (Apache 2.0) |
| Vector search | `dense_vector` + ELSER + `semantic_text` | `knn_vector` + ML Commons + FAISS |
| Litsents | AGPL-3 / SSPL / Elastic License | Apache 2.0 |
| AWS integratsioon | Marketplace'i kaudu | Natiivne (Bedrock, SageMaker, IAM, KMS) |
| Cluster manager / master | `master` täht | `cluster_manager` täht (samaväärne) |

💭 **Mõtle:** Sinu organisatsiooni keskkonnaga — kas eelistaks ES õi OS? Vasta L1.3 "Kus kumb sobib" raamile tuginedes.

---

## Osa 4 · Vector search — maitseproov

L3 loengu osa rääkis BM25-st (lexical) ja vector otsingust. Praegune osa on **lühike maitseproov**, mitte täielik ELSER setup. Eesmärk: näed kuidas `knn_vector` field töötab praktikas, ilma et peaksid embedding-mudelit laadima.

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

Märkad **`knn_vector`** — OpenSearchi vector tyup. Reaalsuses on dimensioon 384, 768 või 1536. **4 dimensiooni** on selleks, et saaksime käsitsi vektoreid kirjutada ja vaadata mis juhtub.

### 4.2 Saada dokumente

Kujutame, et need on logi-read, mille embedding-mudel on juba arvutanud vektorid (4-dim ruum). Kaks jätku-paari tähendusega:

```bash
# Database connection issues (sarnased vektorid)
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "DB connection timeout", "embedding": [0.9, 0.1, 0.0, 0.0]}'
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "connection pool exhausted", "embedding": [0.85, 0.15, 0.0, 0.0]}'
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "psycopg2 OperationalError", "embedding": [0.88, 0.12, 0.0, 0.0]}'

# Network-relateds (eraldi klaster)
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "network unreachable", "embedding": [0.0, 0.0, 0.9, 0.1]}'
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "route to host failed", "embedding": [0.0, 0.0, 0.85, 0.15]}'
```

### 4.3 Vector päring

Otsi midagi, mille vektor on `[0.9, 0.1, 0.0, 0.0]` (sarnane database-cluster'iga):

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

Vastus järjestab kolm dokumenti **kõige sarnasemast vektorist**:

1. `DB connection timeout` (skoor ~1.0, täielik match)
2. `connection pool exhausted` (skoor ~0.99, väga sarnane)
3. `psycopg2 OperationalError` (skoor ~0.99, väga sarnane)

**Märkad** — BM25 ei oleks suutnud `connection pool exhausted` ja `psycopg2 OperationalError` siduda "database connection issues" mõistega, sest sona-tasandil pole nad sarnased. Vector mudel teadis (treenimise käigus oli näinud miljardit näidet), et need on **tähenduselt** sarnased.

💭 **Mõtle:** Mis on selle setup'i piirangud reaalses keskkonnas?

(Vastused: (1) vektorid pole reaalsed — vajame embedding-mudelit, mis arvutab `text → vector`; (2) 4-dim ruum on liiga väike täiendava tähenduse jaoks — reaalsus = 384+ dim; (3) production'is vajab ML node'i mudeli käivitamiseks.)

### 4.4 Mis tulekul (ei tehta klassis)

Täielik setup vajaks:

1. **Embedding-mudel** klastris (HuggingFace `sentence-transformers/all-MiniLM-L6-v2` või sarnane)
2. **Ingest pipeline** mis arvutab `message → embedding` automaatselt
3. **Hybrid päring** (BM25 + vector koos)
4. **ML node** — eraldi node ML tööle, et mitte koormata põhi-klastrit

See on **üksipikku tutorial** OpenSearchi dokumentatsioonis (link allikates). Kodus saad proovida.

---

## ✅ Lõpukontroll (enesekontroll, verifitseeritav)

- [ ] Sinu `docker compose ps` ~/paev3/elk järel näitab 3 ES node + Kibana — kõik `healthy` või `Up`
- [ ] `curl http://localhost:9200/_cluster/health?pretty` näitab `status: green` ja `number_of_nodes: 3`
- [ ] `curl http://localhost:9200/_cat/nodes?v` näitab kolme node'i, ühel `*` master veerus
- [ ] Kibana Stack Monitoring näitab GREEN klastri olekut
- [ ] Sa simuleerisid node'i kao (`docker stop es02`), klaster läks YELLOW ja taas GREEN ~60 s pärast
- [ ] OpenSearchi klaster ~/paev3/os käivitub ja näitab `status: green` 3 node'iga
- [ ] OS Dashboards UI on **selgesti sarnane** Kibanaga
- [ ] Vector päring `knn_vector` field'iga tagastab `DB connection timeout` ja `connection pool exhausted` kõige sarnasemate võtmetena, kuigi neil pole ühist sõna

---

## 🚀 Lisaülesanded (kes jõuab ette)

**A. ELSER mudel ja `semantic_text`** — Elastic ES klastris (peatuse OS, käivita ES):

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
