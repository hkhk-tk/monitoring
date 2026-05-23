# Päev 3: Elastic Stack ja OpenSearch — labor

**Kestus:** 4 tundi (klassitöö umbes 3 h, ülejäänu kodused lisaülesanded)

**Tase:** kesktase–edasijõudnud

**Eeldused:** Päev 1 logimise põhialused, mitme konteineriga Docker Compose, Loki ja Alloy (Päev 2). Enne labi loe läbi [Päev 3: ELK ja OpenSearch loeng](../../materials/lectures/paev3-elk-loeng.md) (eriti L2 arhitektuur ja quorum).
**VM:** sinu VM (`ssh <eesnimi>@192.168.35.12X` klassivõrgust või `192.168.100.12X` VPN-ist)

---

## Miks see labor

Päev 2 [Loki labori](../../labs/02_zabbix_loki/loki_lab.md) abil said sa logidest aru **siltide** (`level`, `service`) järgi — see on kiire ja kerge. Täna vaatame, mis juhtub, kui vaja on **iga sõna** otsitavaks (audit, tugitiim, „leia kõik read, kus mainitakse kasutaja X“) ja kui logimahtu tuleb nii palju, et üks server ei piisa.

Sellest labist tuled välja nelja oskusega:

1. **Elasticsearch + Kibana** — üks sõlm, `YELLOW`, siis kolm sõlme ja `GREEN` (shard’id ja taastumine kätega läbi tehtud).
2. **OpenSearch kõrvuti** — sama API/UI loogika, erinev litsents ja ökosüsteem.
3. **Vector-otsingu maitse** — miks BM25 ei seo „DB timeout“ ja „psycopg2 error“.

Kõik toimub sinu VM-il Docker Compose’iga; kaks eraldi kausta (`~/paev3/elk` ja `~/paev3/os`), sest 6 GB RAM ei võimalda mõlemat korraga jooksma hoida.

---

## 🎯 Õpiväljundid

**Teadmised:**

1. Selgitab, miks ühe sõlmega Elasticsearchi klaster on olekus `YELLOW`.
2. Eristab `master`-, `data`- ja `coordinating`-sõlmi ning nende koormust.
3. Põhjendab, miks tootmisklastris peab olema **3** master-kandidaati (quorumi loogika).
4. Eristab Elasticsearchi ja OpenSearchi nii API kui ka kasutajaliidese tasandil.
5. Toob vähemalt kaks olukorda, kus eelistada Lokit, ja kaks, kus eelistada Elastic Stacki.

**Oskused:**

6. Käivitab Elasticsearchi ja Kibana Docker Compose’i abil.  
7. Laiendab ühe sõlmega klastri kolmeks sõlmeks ja jälgib shard’ide ümberpaigutamist.  
8. Simuleerib ühe sõlme kadumist (`docker compose stop`) ja jälgib taastumist.  
9. Käivitab OpenSearchi ja OS Dashboardsi ning võrdleb Kibana ja OpenSearchi (REST API ja UI tasandil).

---

## Labi struktuur

Labor on neljas osas. Klassis jõuad tavaliselt osadeni 1–3; osa 4 ja lisaülesanded võivad jääda koju.

| Osa | Teema | ~aeg | Mida sa mõistad lõpus |
|-----|-------|------|------------------------|
| 1 | Üks ES + Kibana + KQL | 50 min | Miks üks sõlm on `YELLOW`; täistekstiotsing vs Loki |
| 2 | 3-sõlmeline klaster + simulatsioon | 70 min | Miks 3 sõlme; sõlme kadu, shard’ide taastumine, quorum |
| 3 | OpenSearch võrdlus | 50 min | ES vs OS API/UI; millal kumb valida |
| 4 | Vector `knn` demo | 30 min | Semantiline otsing vs BM25 (lühike praktiline näide) |

Töökaustad: `~/paev3/elk` (Elasticsearch) ja `~/paev3/os` (OpenSearch). **Ära aja neid korraga** — enne OS käivitamist peata ES, et mälu jätkuks.

---

## Eeltöö

Päeva 2 stack kasutab päris palju mälu. Enne alustamist pane see maha:

```bash
# Päev 1 stack alla (kui veel jookseb)
cd ~/paev1 2>/dev/null && docker compose down 2>/dev/null

# Päev 2 alla (Zabbix + Loki konteinerid lähevad alla — see on ootuspärane)
cd ~/paev2/zabbix 2>/dev/null && docker compose down 2>/dev/null
cd ~/paev2/loki 2>/dev/null && docker compose down 2>/dev/null

# Kontrolli mälu seisu
free -h
```

**Vaba mälu võiks olla vähemalt 5 GB.** Kui ei ole, vaata, mis veel jookseb: `docker ps`.

Loo päev 3 jaoks eraldi töökaust:

```bash
mkdir -p ~/paev3/elk && cd ~/paev3/elk
```

!!! warning "Mälu piiri peal"
    Sinu VM-il on 6 GB RAM-i. Kolmesõlmeline Elasticsearchi klaster ja Kibana võtavad koos umbes 4 GB. Hoia `free -h` teises terminalis silma all. Kui mälu saab täis, võib mõni konteiner OOM-killeri tõttu maha kukkuda.

---

## Osa 1 · Elasticsearch ja Kibana eraldi

> **Taust:** Päev 2 kasutasid Lokit – kerge, kiire ja Grafanaga hästi sobiv lahendus. Loki indekseerib aga peamiselt **silte** (labels), mitte logiridade sisu. Kui audit nõuab, et iga logisõna oleks otsitav (näiteks: „leia kõik read, kus mainitakse kasutaja ID-d X mistahes kohas viimase 90 päeva jooksul“), jääb Loki hätta. Sellisel juhul on vaja **täistekstiindeksit** – sõnaraamatut, kus iga sõna „teab“, millises dokumendis ta esineb. Selleks kasutame Elasticsearchi.

Alustuseks käivitame **ainult ühe** Elasticsearchi sõlme ja Kibana. Tootmiskeskkonnas nii ei tehta – siin on eesmärk **näha, mida Kibana näitab kohe pärast esimese indeksi loomist**.

### 1.1 Ainult Elasticsearch

Loo fail `docker-compose.yml`:

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

**Miks `ES_JAVA_OPTS=-Xms512m -Xmx512m`?** Vähendame heap’i 512 MB peale ühe sõlme kohta, sest varsti lisame kaks sõlme juurde ja 6 GB VM ei taluks vaikimisi 1 GB heap’i iga sõlme kohta.

**Miks `xpack.security.enabled=false`?** Laborikeskkond on isoleeritud ja hoiame seadistuse võimalikult lihtsa. Tootmiskeskkonnas on see peaaegu alati `true` – turvalisust üldjuhul välja ei lülitata.

Käivita ainult Elasticsearch:

```bash
sudo sysctl -w vm.max_map_count=262144
docker compose up -d es01
```

Oota umbes 30 sekundit, kuni Elasticsearch käivitub, ja kontrolli seejärel:

```bash
curl http://localhost:9200
```

Vastuseks peaks tulema JSON, kus on näha klastri nimi `lab-cluster` ja versioon `8.15.x`. Kui vastust ei tule, oota veel umbes 10 sekundit – Elasticsearch tuleb suhteliselt aeglaselt üles.

!!! tip "Kui curl vastab Connection refused"
    Vaata logisid käsuga `docker compose logs es01`. Otsi rida, kus on kirjas `started`. Kui näed veateadet `bootstrap check failed`, on `vm.max_map_count` endiselt liiga madal. Pärast VM taaskäivitust võib `sysctl` vaja uuesti käivitada.

### 1.2 Esimene indeks ja klastri olek

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

Seal on veerg **`health`**, mille väärtus on praegu **`yellow`**. Miks?

```bash
curl "http://localhost:9200/_cluster/health?pretty"
```

Olulisemad read:

```json
"status" : "yellow",
"unassigned_shards" : 1,
```

**`unassigned_shards: 1`** tähendab, et ühel replica-shard’il ei ole kohta. Vaikimisi on `number_of_replicas: 1`, ehk primary-shard’ist tehakse üks koopia. See koopia peab asuma **teises sõlmes** kui primary. Praegu on klastris ainult **üks sõlm**, seega jääb replica „õhku“.

??? question "Mõtle (enne kui edasi kerid)"
    Mis juhtub, kui kustutad praeguse ainsa sõlme? Kas indeks jääb alles, kui seadistus on `replicas: 1`?

??? note "Selgitus (loe alles pärast oma vastust)"
    Indeks kaob. `replicas: 1` ei aita, kui koopia ei asu **teises sõlmes**. See on põhjus, miks tootmisklastris on **vähemalt kaks sõlme** ja replica-de arv on vähemalt 1.

### 1.3 Kibana lisamine

Lisa Kibana `docker-compose.yml` faili, **enne** plokki `volumes:`:

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

Käivita Kibana:

```bash
docker compose up -d kibana
```

Oota umbes 45 sekundit ja ava seejärel brauserist `http://<sinu-VM-IP>:5601`. Klassivõrgus kasuta `192.168.35.12X`, VPN-ist `192.168.100.12X`.

Kibanas vali vasakult menüüst `☰` → **Management** → **Stack Monitoring** → **Or, set up with self monitoring** → Enable.

Stack Monitoring vaade näitab nüüd klastri `lab-cluster` olekuks `YELLOW`, 1 sõlme ning indeksi `test-logs` olekuks samuti `YELLOW` (1 replica on endiselt määramata).

!!! tip "Kui Kibana näitab not ready yet"
    Oota veel umbes 30 sekundit. Kibana käivitub alles siis, kui Elasticsearch on täielikult valmis.

### 1.4 KQL-päring Discover vaates

Vasakul vali **Discover**, loo uus data view (`test-logs*`) ja sea ajaperioodiks „Last 24 hours“.

Saada terminalist veel mõned dokumendid:

```bash
for level in info warn error; do
  curl -X POST "http://localhost:9200/test-logs/_doc" \
    -H "Content-Type: application/json" \
    -d "{\"message\": \"logi tüübiga $level\", \"level\": \"$level\"}"
  echo
done
```

Vajuta Discover’is **Refresh**. Näed nelja dokumenti.

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

Viimane päring peaks andma 0 tulemust – klassikaline näide sellest, et KQL-i `and` töötab dokumendi tasandil, mitte sõna tasandil.

??? question "Mõtle"
    Sa just kirjutasid neli KQL-päringut. Mis on suurim erinevus KQL-i ja LogQL-i (Päev 2 Loki) süntaksite vahel? Kumb tundub esmapilgul loomulikum?

---

## Osa 2 · Laienda 3-sõlmeline klaster

> **Probleem:** Osa 1 lõpus oli sinu klaster YELLOW. Sa tead, miks (replica on määramata). Oletame, et oled e-poe SRE ja see klaster töötab tootmises. YELLOW olek tähendab: **kaotad ühe DB krahhi korral logiandmed lõplikult**. See ei ole vastuvõetav. Lahendus ei ole „panen replicas: 0“ (siis ei ole üldse kaitset). Lahendus on lisada sõlmi. Küsimus on: **mitu** ja **kuidas** nad omavahel suhtlevad? Järgmise tunni jooksul saad vastuse.

Tüüpiline tootmismudel on **3 dedicated master + N data**, aga 6 GB RAM-i puhul kasutame lihtsustatud varianti: **3 sõlme, igal kõik rollid**. Quorumi loogika toimib samamoodi – vaatame seda lähemalt.

!!! tip "Enne Osa 2"
    Loe loengust plokk [Cluster state ja quorum — miks kolm master node'i](../../materials/lectures/paev3-elk-loeng.md#cluster-state-ja-quorum-miks-kolm-master-nodei) (võtab kuni 3 minutit). Selles osas eeldame, et saad selgitada, miks tootmises on vähemalt 3 master-kandidaati, mitte 2.

### 2.1 Peata ja muuda struktuuri

Oled kaustas `~/paev3/elk` (kui mitte: `cd ~/paev3/elk`). Peata setup:

```bash
cd ~/paev3/elk
docker compose down
```

Andmed (volume `es01-data`) jäävad alles, me ei kustuta neid.

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

Võrreldes ühe sõlmega seadistusega on lisandunud kolm olulist muutujat:

- `discovery.seed_hosts` – loend teistest sõlmedest, kellega ühendust võtta klastri leidmiseks.  
- `cluster.initial_master_nodes` – esmakordsel käivitamisel kasutatav master-kandidaatide loend (kasutatakse ainult esimesel käivitusel).  
- `discovery.type=single-node` on eemaldatud – me ei ole enam ühe sõlmega klaster.  

Iga sõlm on nüüd korraga `master`, `data` ja `ingest` rollis (vaikimisi, kui `node.roles` ei ole eraldi määratud). See on **labori konfiguratsioon**, mitte tootmiskeskkonna soovitus. Tootmises eraldatakse master- ja data-sõlmed (vt loengu L2 osa).

### 2.2 Käivita 3-sõlmeline klaster

```bash
docker compose up -d
```

Jälgi RAM-i:

```bash
free -h
```

Oota umbes 60 sekundit ja kontrolli klastri olekut:

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

**GREEN!** Replica `test-logs` indeksist sai nüüd koha (teises sõlmes kui primary). Vaata sõlmi:

```bash
curl "http://localhost:9200/_cat/nodes?v"
```

Näed kolme sõlme. Ühe `master` veerus on täht `*` – see on valitud master. Teised on master-kandidaadid.

Ava Kibanas **Stack Monitoring** – klaster on GREEN ja näitab kolme sõlme.

!!! tip "Kui klaster ei tule 60 sekundiga üles"
    Vaata `docker compose logs es01 | grep -i "master"`. Otsi rida `master node changed`. Kui näed `master not discovered yet`, oota veel veidi.

### 2.3 Simuleeri sõlme kadumist

Praegu on klaster terve. Simuleeri probleemi – kujuta ette, et see on AWS-i saadavuspiirkonna (AZ) vea algus:

```bash
docker compose stop es02
```

Kohe pärast seda kontrolli:

```bash
curl "http://localhost:9200/_cluster/health?pretty"
```

Näed vastuses midagi sellist:

```json
"status" : "yellow",
"number_of_nodes" : 2,
"unassigned_shards" : 1,
```

**YELLOW** tähendab, et ühe shard’i koopia kaotas oma sõlme ja klaster otsib sellele uut kohta. Oota umbes 60 sekundit ja kontrolli uuesti:

```bash
sleep 60 && curl "http://localhost:9200/_cluster/health?pretty"
```

Nüüd peaks klaster olema jälle **GREEN** – shard kopeeriti kahele allesjäänud sõlmele. Vaata shard’e:

```bash
curl "http://localhost:9200/_cat/shards?v"
```

Iga shard (primary + replica) paikneb nüüd ühel kahest allesjäänud sõlmest.

!!! tip "Kui klaster jääb YELLOW"
    Vaata, kas `unassigned_shards > 0` – see võib tähendada, et shard ei mahu (diskiruumi piirang). `curl localhost:9200/_cluster/allocation/explain?pretty` aitab põhjuse välja selgitada.

### 2.4 Too sõlm tagasi

```bash
docker compose start es02
```

Oota umbes 60 sekundit (ES Java käivitub aeglaselt) ja vaata uuesti:

```bash
curl "http://localhost:9200/_cat/shards?v"
```

Näed, et osa shard’e liigub tagasi sõlmele `es02`. Klaster **tasakaalustab** end uuesti – see on automaatne shard’ide taastamine. Kibana Stack Monitoring näitab sama.

??? question "Mõtle (enne edasilugemist)"
    Sinu organisatsioonis – kui klaster on jagatud kahe andmekeskuse vahel, kuhu paigutad master-kandidaadid? Kuidas tagad, et ühe andmekeskuse kadu ei muuda klastrit **read-only** olekusse?

??? note "Mõttearendus"
    Tüüpiline lahendus on **kolm eraldi asukohta** – kaks andmekeskust ja üks arbiter/witness kolmandas asukohas (näiteks pilves, eraldi AZ-is). Quorum nõuab üle 50% master-kandidaatidest. Kui sul on ainult kaks andmekeskust (2 × 1 master = 2 kandidaati), siis ühe DC kadumisel jääb alles 1 master ja quorum kaob. Kolmas asukoht hoiab quorum’i alles. Seetõttu **ainult kaks andmekeskust ei ole klastrile piisav**, vaja on vähemalt kolme erinevat „failure domain’i“.

### 2.5 Test: katkesta kaks sõlme

Kui sul on aega ja tahad näha, mis juhtub quorum’i kadumisel:

```bash
docker compose stop es02 es03
sleep 10
curl "http://localhost:9200/_cluster/health?pretty"
```

Vastuseks on kas viga või `master_not_discovered_exception`. Klaster ei suuda valida masterit, sest quorum (2) puudub.

Too sõlmed tagasi:

```bash
docker compose start es02 es03
```

Oota umbes 45 sekundit ja kontrolli uuesti – klaster taastub GREEN olekusse.

??? question "Mõtle"
    Kirjuta paberile või tekstifaili **kaks lauset** selle kohta, kelle jaoks sinu töökohas oleks selle stsenaariumi mõju kõige valusam. Kas auditispetsialist (logid kadunud)? Tugitiim (otsing maas)? Arendustiim (trace’id kadunud)?

---

## Osa 3 · OpenSearch kõrvale – võrdlus Elasticsearchiga

> **Probleem:** Sinu juht küsib: „Miks me ostame ELK-i, kui OpenSearch on tasuta?“ Sul on umbes 30 sekundit, et vastata. Selle osa eesmärk on, et sul oleks **konkreetne** vastus, mitte ainult vendorite turundus. Mõlemad platvormid on sinu töökohas potentsiaalselt olulised ja sa pead suutma põhjendatult valida.

OpenSearch hargnes 2021. aastal Elasticsearch 7.10.2 versioonist (litsentsimuudatuse tõttu) ja arenes sealt edasi oma suunas. Täna (2026) on mõlemad lahendused küpsed. Neid kõrvuti proovides saad praktilise võrdluse.

**Kontekstivahetus:** Osa 1–2 töötasid kaustas `~/paev3/elk`. Nüüd **peatame ES-i**, et vabastada RAM — indeks `test-logs` ja volume’id (`es01-data` jne) **ei kao**, need jäävad kettale. OpenSearch käivitame **teises kaustas** `~/paev3/os` (sama port 9200, aga teine klaster). Hiljem saad ES tagasi tõsta: `cd ~/paev3/elk && docker compose up -d`.

!!! warning "Mälu risk OpenSearchiga"
    3 ES-sõlme + 3 OS-sõlme + Kibana + OS Dashboards = umbes 9–10 GB RAM-i. **Sinu 6 GB VM ei pea seda vastu.** Peata enne OpenSearchi käivitamist kindlasti Elasticsearchi klaster.

### 3.1 Peata ES, vabasta RAM

Oled kaustas `~/paev3/elk`:

```bash
cd ~/paev3/elk
docker compose down
free -h
```

Veendu, et vaba mälu oleks 4–5 GB. Andmed (volumes `es01-data` jne) jäävad alles — `docker compose down` ei kustuta volume’e.

### 3.2 OpenSearchi klastri Compose

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

Olulisemad erinevused ES-seadistusest:

- `cluster.initial_cluster_manager_nodes` (mitte `master_nodes`) – OpenSearch loobus alates 2.0 versioonist sõnast „master“ ja kasutab `cluster_manager`. Mõiste on sama, nimi erineb.  
- Pildi nimi `opensearchproject/opensearch:2.18.0` – versioon vastab AWS-i poolt toetatule.  
- `DISABLE_SECURITY_PLUGIN=true` – OpenSearch Security plugin on vaikimisi sees, labori jaoks lülitame selle välja.  

### 3.3 Käivita ja kontrolli

```bash
docker compose up -d
sleep 60
free -h
curl "http://localhost:9200/_cluster/health?pretty"
```

Oodatav vastus on sisult sama, mis ES-i puhul:

```json
"cluster_name" : "lab-os-cluster",
"status" : "green",
"number_of_nodes" : 3,
```

!!! tip "Kui OpenSearch ei ole valmis"
    Oota veel 30–60 sekundit – OpenSearch käivitub tavaliselt veidi aeglasemalt kui Elasticsearch.

### 3.4 OS Dashboards – sarnane Kibana UI

Ava brauserist `http://<sinu-VM-IP>:5601` – avaneb OS Dashboards.

Vasakul üleval vali `☰` → **Discover**. Kasutajaliides on ligikaudu 80% ulatuses Kibanaga samasuguse loogikaga: sama navigatsioon, sama Discover-vaade, sama Index Patterns kontseptsioon.

### 3.5 REST API sarnasus

Saada OpenSearchi sama dokument, mida panid varem Elasticsearchi:

```bash
curl -X POST "http://localhost:9200/test-logs/_doc" \
  -H "Content-Type: application/json" \
  -d '{"message": "esimene logi OS-is", "level": "info"}'
```

Vaata indekseid:

```bash
curl "http://localhost:9200/_cat/indices?v"
```

Väljund on sama struktuuriga (samad veerud, sama `health: green`, sest 3 sõlme).

KQL-päringud Discoveris töötavad sama süntaksiga:

```kql
level : "info"
```

### 3.6 Olulised erinevused

API ja UI tasandil on erinevusi vähe. Olulisemad erisused on seal, kus tooted on pärast 2021. aastat eraldi arenenud:

| Aspekt | Elasticsearch 8.x | OpenSearch 2.x |
|---|---|---|
| Turvalisus | xpack (Elastic License) | OpenSearch Security (Apache 2.0) |
| Vector otsing | `dense_vector` + ELSER + `semantic_text` | `knn_vector` + ML Commons + FAISS |
| Litsents | Elastic License 2.0 / SSPL / AGPLv3 osad komponendid | Apache 2.0 |
| AWS integratsioon | Marketplace’i kaudu | Natiivne (Bedrock, SageMaker, IAM, KMS) |
| Cluster manager / master | `master` tähisega | `cluster_manager` tähisega (sama roll) |

Praktilised valikud:

- **AWS-keskne organisatsioon** (Bedrock, SageMaker, IAM) – tihti OpenSearch, sest integratsioon on natiivne.  
- **Olemasolev Elasticu investeering** (Logstash, ECS, ELSER) – sageli eelistatakse Elasticsearchi.  
- **On-prem / hybrid-cloud ilma AWS-ita** – Elasticsearch on tavaline valik.  
- **Litsentsipoliitika väga tundlik** (nt avalik sektor) – OpenSearchi Apache 2.0 litsents võib olla eelistatud.  

??? question "Mõtle"
    Sinu organisatsiooni puhul – milline neist neljast punktist on kõige olulisem? Kas üks faktor kaalub teisi üle või on mitu sama tugevat?

---

## Osa 4 · Vector-otsing – lühike maitseproov

> **Probleem:** tugitiim saab päevas kümneid tiketeid. Paljud kirjeldavad sama probleemi erinevaid sõnu kasutades: „DB ei vasta“, „andmebaas timeout“, „PostgreSQL connection refused“, „psycopg2 OperationalError“. BM25 (tavaline täistekstiotsing) **ei seo** neid omavahel – sõnastikus pole need lähedased. Vector-otsing aga seob. Vaatame seda numbriliselt.

!!! note "Eeldus enne Osa 4"
    OpenSearchi klaster peab jooksma kaustas `~/paev3/os`. Kontrolli: `cd ~/paev3/os && docker compose ps` — kolm `os0X` konteinerit peavad olema `Up`. Kui ES on veel üleval või mälu on otsas, lõpeta Osa 3 enne siia tulekut.

Loengu [vector/RAG lisalugemine](../../materials/lectures/paev3-vector-rag-lisalugemine.md) räägib BM25-st (lexical) ja vector-otsingust. Siin teeme **lühiülevaate**, mitte täismahus ELSER-seadistuse. Eesmärk on näha, kuidas `knn_vector` väli praktikas käitub ilma embedding-mudelit üles panemata — kasutame sama OpenSearchi klastrit, mis Osa 3 lõpus üleval oli.

### 4.1 Indeks vector-väljaga

```bash
cd ~/paev3/os
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

`knn_vector` on OpenSearchi vector-tüüp. Päriselus on dimensioon tavaliselt 384, 768 või 1536, kuid **4 dimensiooni** valime selleks, et saaks vektoreid käsitsi kirjutada ja käitumist lihtsalt jälgida.

### 4.2 Dokumentide lisamine

Kujutame ette, et allpool on logiread, mille embedding-mudel on juba vektoriteks arvutanud 4-mõõtmelises ruumis. Esimene grupp on andmebaasiprobleemid, teine võrguprobleemid:

```bash
# Database connection probleemid (sarnased vektorid)
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "DB connection timeout", "embedding": [0.9, 0.1, 0.0, 0.0]}'
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "connection pool exhausted", "embedding": [0.85, 0.15, 0.0, 0.0]}'
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "psycopg2 OperationalError", "embedding": [0.88, 0.12, 0.0, 0.0]}'

# Võrguvead (teine klaster)
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "network unreachable", "embedding": [0.0, 0.0, 0.9, 0.1]}'
curl -X POST "http://localhost:9200/log-vectors/_doc" -H "Content-Type: application/json" \
  -d '{"message": "route to host failed", "embedding": [0.0, 0.0, 0.85, 0.15]}'
```

Kolm esimest vektorit on ligikaudu `[0.85–0.9, 0.1–0.15, 0, 0]`, kaks viimast `[0, 0, 0.85–0.9, 0.1–0.15]`. Need moodustavad vektorruumis kaks eraldi klastrit – embedding-mudel paigutab sarnased asjad lähestikku.

### 4.3 Vector-päring

Otsi midagi, mille vektor on `[0.9, 0.1, 0.0, 0.0]` (database-klastri lähedal):

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

Vaata vastust ise:

1. Mis järjekorras tulemused on?  
2. Millised on `_score` väärtused?  
3. Kas kolm database-klastri sõnumit tulevad enne kahte network-klastri sõnumit?  

Kui vastus on „jah“, nägid praktikas, miks `knn`-otsing on **semantiline** ja mitte ainult sõnapõhine. BM25 ei annaks „psycopg2“ ja „DB connection timeout“ vahel sellist seost.

??? question "Mõtle"
    Kas sinu tööl on konkreetne otsingustsenaarium, kus tugitiim või arendajad otsivad praegu „vale sõnaga“? Kas vector-otsing võiks seda aidata?

### 4.4 Mis oleks järgmine samm (seda klassis ei tee)

Täielik vector-otsingu lahendus vajaks:

1. **Embedding-mudelit** klastris (nt `sentence-transformers/all-MiniLM-L6-v2`).  
2. **Ingest-pipelinet**, mis arvutab `message → embedding` automaatselt.  
3. **Hybrid-päringut**, mis kombineerib BM25 ja vector-otsingu.  
4. **ML-sõlme**, et mitte koormata põhiklastrit ML-arvutustega.  

Elasticsearchi `semantic_text` väli teeb sammud 1 ja 2 automaatselt – see on kirjas lisaülesandes A.

---

## ✅ Lõpukontroll (tehnika + arusaamine)

**Tehniline (kontrollitav):**

- [ ] `docker compose ps` kaustas `~/paev3/elk` näitab 3 ES-sõlme + Kibana – kõik on `healthy` või `Up`.  
- [ ] `curl http://localhost:9200/_cluster/health?pretty` näitab `status: green` ja `number_of_nodes: 3`.  
- [ ] `curl http://localhost:9200/_cat/nodes?v` näitab kolme sõlme, ühel `*` master-veerus.  
- [ ] Kibana Stack Monitoring näitab GREEN klastri olekut.  
- [ ] Simuleerisid sõlme kadumist (`docker compose stop es02`), klaster läks YELLOW ja tuli umbes 60 sekundiga GREEN olekusse tagasi.  
- [ ] OpenSearchi klaster kaustas `~/paev3/os` käivitub ja näitab `status: green` 3 sõlmega.  
- [ ] OS Dashboards kasutajaliides on selgelt Kibana-laadne.  
- [ ] `knn_vector` väljaga päring annab database-klastri sõnumid esimesteks tulemusteks.  

**Arusaamine (vasta peast, kirjuta paberile või tekstifaili):**

- [ ] Suudad ühe lausega selgitada, miks tootmiskeskkond vajab 3, mitte 2 master-kandidaati.  
- [ ] Suudad nimetada kaks olukorda, kus eelistad Lokit Elasticsearchile, ja kaks olukorda, kus vastupidi eelistad Elastic Stacki.  
- [ ] Mõistad, miks dimensioon 4 vector-näites oli pedagoogiline lihtsustus, mitte päris kasutus.  
- [ ] Suudad ühe lausega selgitada, mis vahe on `master` ja `cluster_manager` rolli nimetustel ES-i ja OS-i kontekstis.  

---

## 🚀 Lisaülesanded (kellel veel aega jääb)

**A. ELSER-mudel ja `semantic_text`** – Elasticu ES-klastri peal (peata OS, käivita ES):

1. Laadi ELSER-mudel: Kibana → Machine Learning → Trained Models → Download `.elser_model_2`.  
2. Deploy’ ülemudeli.  
3. Loo indeks `semantic_text` väljaga (vt loengu L3 koodi).  
4. Saada paar dokumenti ja vaata, kuidas Elastic teeb automaatselt BM25 + ELSER hübriidotsingu.  

**B. Snapshot lokaalsesse „S3“** – snapshot’i simulatsioon:

1. Loo lokaalne kaust `mkdir -p ~/paev3/snapshots`.  
2. Lisa Compose’i kõikidele ES-sõlmedele volume `- ~/paev3/snapshots:/snapshots`.  
3. Registreeri repository:  
   `curl -X PUT localhost:9200/_snapshot/local -d '{"type":"fs","settings":{"location":"/snapshots"}}'`.  
4. Tee snapshot, kustuta indeks ja taasta see snapshot’ist.  

**C. Kafka kui ingest-buffer** – ehita pipeline Filebeat → Kafka → Logstash → ES (lähtudes L2 „Andmevoo“ Mermaid-diagrammist).

---

## Veaotsing

| Probleem | Kontroll | Lahendus |
|---|---|---|
| `Connection refused` curl’iga | `docker compose ps` | Konteiner ei ole `Up`. Vaata `docker compose logs <node>`. |
| `bootstrap check failed` ES logis | `sysctl vm.max_map_count` | `sudo sysctl -w vm.max_map_count=262144`. |
| Konteiner kukub OOM-killeri tõttu | `dmesg \| grep -i oom` | RAM on piiri peal. Peata teised stackid või vähenda heap’i 256 MB peale. |
| Kibana `not ready yet` ka 2 minuti pärast | `docker logs kibana \| tail -50` | ES ei ole üleval. Tee enne Kibana ootamist `curl localhost:9200`. |
| Klaster jäi YELLOW pärast sõlme tagasitoomist | `curl localhost:9200/_cluster/allocation/explain?pretty` | Diskiruumi piirang või shard’ide paigutusreeglid. |
| OS Dashboards näitab `OpenSearch is not running` | `curl http://localhost:9200/_cluster/health` | OS klaster ei ole valmis, oota umbes 60 sekundit. |
| `master_not_discovered_exception` | `docker logs es01 \| grep -i master` | Kaks või enam sõlme on maas, quorum kadus. Too sõlmed tagasi. |

---

## 📚 Allikad

| Allikas | URL | Miks oluline |
|---|---|---|
| Elasticsearchi ametlik dokumentatsioon | <https://www.elastic.co/guide/en/elasticsearch/reference/current/> | Ametlik konfiguratsiooni- ja arhitektuuriinfo. |
| OpenSearchi ametlik dokumentatsioon | <https://opensearch.org/docs/latest/> | Vastav dokumentatsioon OpenSearchi jaoks. |
| Elastic `semantic_text` ja ELSER | <https://www.elastic.co/guide/en/elasticsearch/reference/current/semantic-text.html> | Taust lisaülesande A jaoks. |
| OpenSearch k-NN ja neural search | <https://opensearch.org/docs/latest/search-plugins/neural-search/> | Vector-otsing OpenSearchis. |
| Elasticsearch Docker Compose näide | <https://www.elastic.co/guide/en/elasticsearch/reference/current/docker.html> | Production’ile sarnane multi-node seadistus. |
| OpenSearch Docker Compose | <https://opensearch.org/docs/latest/install-and-configure/install-opensearch/docker/> | OpenSearchi multi-node seadistus. |

--8<-- "_snippets/abbr.md"
