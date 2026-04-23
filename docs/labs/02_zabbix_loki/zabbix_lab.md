# Päev 2 · Labor: Zabbix

**Kestus:** ~2 tundi (pool päev 2 laborist)  
**Tase:** Keskaste  
**VM:** sinu isiklik VM. Klassis `ssh <eesnimi>@192.168.35.12X`, VPN-ilt `ssh <eesnimi>@192.168.100.12X`.  
**Eeldused:** [Päev 2: Zabbix loeng](../../materials/lectures/paev2-loeng.md) loetud. Päev 1 Docker Compose ja Grafana tuttav.

---

## Miks see labor

Päev 1 tegid Prometheusega **pull-mudeli** monitooringut: Prometheus küsib iga 15 sekundi tagant, konfiguratsioon on YAML-failis, mõõdikud tulevad exporter'itelt.

Zabbix on teine maailm. **Push + pull segu**, konfiguratsioon UI-s, modulaarne (4 eraldi komponenti ühe binaari asemel), ja ta on **Baltikumi enterprise-standard** — Telia, Swedbank, riigiasutused. Kui sa töötad Eesti IT-s, sa puutud Zabbixiga kokku.

Selle labi lõpus on sul töötav Zabbix-stack kahe host'iga, kaks töötavat triggerit (üks äriline, üks turbe), ja sa oskad vastata ühele konkreetsele küsimusele: **"payment teenuses on liiga palju vigu — kust kontrollida?"** Sellele küsimusele vastab ka Loki labori FINAAL — seega see labor on **sama sündmuse esimene pool**.

---

## 🎯 Õpiväljundid

Labi lõpuks sa oskad:

1. **Ehitada** Zabbix-stacki Docker Compose'iga **kihiti** (MySQL → Server → Web → Agent) ja testida iga kihti eraldi
2. **Lisada** host, linkida template, jälgida trigger fire/resolve tsüklit UI-s
3. **Kasutada** HTTP Agent + Dependent item mustrit — üks HTTP päring, mitu mõõdikut, ilma välise exporter'ita
4. **Kirjutada** UserParameter'i shell-käsust ja kasutada seda nii jõudluse (payment-vead) kui turbe (honeypot) mõõdikuks

---

## Labi struktuur

Labor on viies osas. Iga osa on ~20–30 minutit ja lõpeb konkreetse võimega.

| Osa | Teema | Võime osa lõpus |
|-----|-------|-----------------|
| 1 | Zabbix baas (MySQL + Server) | Sul jookseb server, mis tunneb DB-d ja kuulab agent'eid |
| 2 | Web UI + esimene agent | Saad brauserist sisse, agent vastab `zabbix_get`-ile |
| 3 | Host, template, trigger, dashboard | Template annab 300 mõõdikut ja trigger läheb stressi peale tulele |
| 4 | HTTP Agent + Dependent item | Nginx stub_status → mitu mõõdikut ilma exporter'ita |
| 5 | UserParameter + honeypot | Oma shell-käsk on nüüd Zabbixi mõõdik, + turbe-trigger |

---

## Eeltöö

**Päev 1 stack maha** (volumes jäävad alles juhuks kui tahad naasta):

```bash
cd ~/paev1 && docker compose down && cd ~
```

!!! tip "Kui `docker compose` ei tööta"
    Mõnes VM-is on Compose vanema nimega. Kasuta `docker-compose` (näiteks `docker-compose up -d`).

**mon-target ja mon-target-web** peale on Zabbix agent juba paigaldatud (koolitaja tegi Ansible'iga). Kontrolli:

```bash
nc -zv 192.168.35.140 10050 && nc -zv 192.168.35.141 10050
```

Mõlemad `succeeded`. Kui ei — ütle koolitajale.

---

## Osa 1 · Zabbix baas (MySQL + Server)

**Eesmärk:** Zabbix Server jookseb ja on ühendatud MySQL-iga. UI-d veel pole.

Miks alustame andmebaasist ja serverist, mitte UI-st? Loeng §2 selgitas — **Zabbixi jõudlusprobleemid lahenevad ~90% ulatuses andmebaasi tasemel**. Kui siin on viga, ei aita UI-klõpsimine midagi. Kihiti ehitamine teeb ka veaotsingu lihtsaks: kui midagi ei tööta, tead **millises lülis** viga on.

```bash
mkdir -p ~/paev2/zabbix/config && cd ~/paev2/zabbix
```

### 1.1 Docker Compose raam

**Eesmärk:** Fail, kuhu teenused järgemööda lisanduvad, + püsiv salvestus MySQL-ile.

Loo `docker-compose.yml`:

```yaml
services:
  # teenused lisanduvad siia

volumes:
  mysql-data:
```

`mysql-data` volume alguses — ilma selleta kaotab `docker compose down` kogu Zabbixi konfi ja ajaloo. Zabbix-i konfiguratsioon **ongi** andmebaasis (erinevalt Prometheus'est, kus konfig on failis) — volume kadu = kõik tööd kadunud.

### 1.2 MySQL

**Eesmärk:** MySQL konteiner on `Up (healthy)` ja `zabbix` andmebaas eksisteerib.

MySQL vajab kaht asja lihtsast variandist lisaks: **healthcheck** (et Zabbix Server teaks, millal DB päriselt valmis on) ja **utf8mb4** (Zabbix nõuab seda kollatsiooni).

Lisa `services:` alla:

```yaml
  mysql:
    image: mysql:8.0
    container_name: mysql
    environment:
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pwd
      MYSQL_ROOT_PASSWORD: root_pwd
      TZ: Europe/Tallinn
    command:
      - mysqld
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_bin
    volumes:
      - mysql-data:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-uroot", "-proot_pwd"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s
    restart: unless-stopped
```

Healthcheck muudab Zabbix Server'i stardi **deterministlikuks** — `depends_on: condition: service_healthy` (järgmises sammus) ootab, kuni MySQL päriselt vastab, mitte ainult "konteiner jookseb". Ilma selleta tekib race condition: Server proovib DB-sse kirjutada enne kui MySQL on valmis, failib, restartib, failib jne.

**Testi kohe:**

```bash
docker compose up -d mysql
docker compose ps
```

Oota kuni näed `Up (healthy)` — esmakäivitusel ~60s (MySQL peab looma tabelid, failid, kasutajad).

```bash
docker exec mysql mysql -uzabbix -pzabbix_pwd -e 'SHOW DATABASES;'
```

Peab näitama rida `zabbix`.

💡 **Kui `unhealthy`:** `free -h` — kas VM-il on piisavalt RAM-i? MySQL 8 vajab ~500 MB. `docker compose logs mysql` näitab täpset viga.

### 1.3 Zabbix Server

**Eesmärk:** Server on üleval, lõi DB-sse ~170 tabelit, ütleb logis "Zabbix Server started".

Server on Zabbixi **aju** — võtab andmeid agent'idelt, hindab triggereid, teeb probleemidest alert'e. Esmakäivitusel loob ta ise kogu andmebaasi skeemi, see võtab ~30 sekundit.

Lisa `services:` alla MySQL-i järele:

```yaml
  zabbix-server:
    image: zabbix/zabbix-server-mysql:ubuntu-7.0.25
    container_name: zabbix-server
    depends_on:
      mysql:
        condition: service_healthy
    environment:
      DB_SERVER_HOST: mysql
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pwd
      TZ: Europe/Tallinn
    ports:
      - "10051:10051"
    restart: unless-stopped
```

`DB_SERVER_HOST: mysql` on **DNS-nimi**, mitte IP. Docker bridge-võrgus konteinerid leiavad üksteist teenuse nime kaudu — `mysql` on teenuse nimi sellesamas compose-failis.

Port 10051 on server-side port (agent'idel on 10050). Server **kuulab** 10051-t, kuhu agent'id saadavad aktiivses režiimis andmeid.

**Testi kohe:**

```bash
docker compose up -d zabbix-server
docker compose logs -f zabbix-server
```

Oota rida `Zabbix Server started. Zabbix 7.0.25`. Ctrl+C kui näed.

```bash
docker exec mysql mysql -uzabbix -pzabbix_pwd zabbix -e 'SHOW TABLES;' | wc -l
```

~170. Server lõi tabelid ise — see on kiire signaal, et DB-ühendus töötab.

💭 **Mõtle:** Prometheus'es oli üks binaar + YAML-fail. Zabbix'is on juba kaks konteinerit (DB + Server) ja pole veel UI-d ega agent'it. Mis see arhitektuuriline erinevus toob kaasa **tootmises** — kas on see raskem või kergem hallata?

---

## Osa 2 · Web UI + esimene agent

**Eesmärk:** Saad brauserist Zabbix'i sisse ja agent vastab server'ile.

Server ja DB töötavad, aga inimese jaoks pole veel midagi näha. Selles osas lisame **kaks eraldi teenust**: Web UI (räägib DB-ga, mitte Server'iga!) ja Agent (saadab Server'ile mõõdikuid).

### 2.1 Zabbix Web

**Eesmärk:** Brauseris avad `http://192.168.35.12X:8080`, logid Admin'ina sisse, vahetad parooli.

Web on **PHP + Nginx konteiner**, mis räägib **otse DB-ga** (mitte Server'iga). See on teadlik disain: frontend skaleerub sõltumatult Server'ist, suurtes keskkondades võid neid mitmendas eksemplaris taga ja loadbalanceriga ette panna.

Lisa:

```yaml
  zabbix-web:
    image: zabbix/zabbix-web-nginx-mysql:ubuntu-7.0.25
    container_name: zabbix-web
    depends_on:
      mysql:
        condition: service_healthy
      zabbix-server:
        condition: service_started
    environment:
      ZBX_SERVER_HOST: zabbix-server
      DB_SERVER_HOST: mysql
      MYSQL_DATABASE: zabbix
      MYSQL_USER: zabbix
      MYSQL_PASSWORD: zabbix_pwd
      PHP_TZ: Europe/Tallinn
      TZ: Europe/Tallinn
    ports:
      - "8080:8080"
    restart: unless-stopped
```

Märkan et Web vajab **mõlemad** aadressid: `DB_SERVER_HOST=mysql` (päris andmete jaoks) ja `ZBX_SERVER_HOST=zabbix-server` (nt "Queue" vaate jaoks, kus Web küsib Server'ilt hetkeseisu).

```bash
docker compose up -d zabbix-web
```

**Brauseris:** `http://192.168.35.12X:8080`. Login `Admin` / `zabbix`.

**Vaheta parool kohe:** üleval paremal ikoon → Users → Admin → Change password → `Monitor2026!`.

Miks kohe? `zabbix` on avalikult teada vaikeparool — iga turvaskänner lööb selle peale linnukese. See on hea **reflex'i harjutus** — tootmises vahetad vaikeparooli enne kui server üldse internetti läheb.

💡 **Kui "Database is not available":** MySQL pole veel healthy. Oota 30s, refresh.

### 2.2 Zabbix Agent

**Eesmärk:** Agent konteiner jookseb sama Docker-võrgus ja vastab Server'i päringule `zabbix_get`.

Agent on Zabbixi **käed-jalad** — ta kogub mõõdikuid (CPU, mälu, ketas, võrk, protsessid) süsteemist kuhu ta paigaldatud on. Meie esimene agent jookseb konteineris siin-samas compose-failis (lihtsaim variant enne kui lisame päris VM-id).

```yaml
  zabbix-agent:
    image: zabbix/zabbix-agent:ubuntu-7.0.25
    container_name: zabbix-agent
    depends_on:
      - zabbix-server
    environment:
      ZBX_SERVER_HOST: zabbix-server
      ZBX_HOSTNAME: docker-agent
      TZ: Europe/Tallinn
    volumes:
      - ./config:/etc/zabbix/zabbix_agentd.d:ro
    restart: unless-stopped
```

**Kriitiline reegel:** `ZBX_HOSTNAME` **peab täpselt ühtima** sellega, mida kasutad UI-s host'i loomisel (järgmises osas). Erinevus ükski sümbol — Server ignoreerib andmeid vaikselt. See on **esimene tüüpiline viga** uutel Zabbixi kasutajatel: konfis `docker-agent`, UI-s kirjutab `Docker-Agent` (suurtähega), andmeid pole kunagi.

Miks see reegel olemas? Agent saadab Server'ile iga mõõdiku koos enda nimega. Server kontrollib: "kas mul on host nimega `docker-agent`?" Kui jah → salvesta. Kui ei → ignoreeri (et kogemata teise firma agent ei pumpaks andmeid).

```bash
docker compose up -d zabbix-agent
docker exec zabbix-server zabbix_get -s zabbix-agent -k agent.ping
```

Vastus `1` — agent elab, Server saab temaga rääkida.

### 2.3 Baas on stabiilne

**Eesmärk:** Enne UI-klikkima minekut veendu kõik 4 konteinerit on `Up` ja MySQL `(healthy)`.

```bash
docker compose ps
```

Kui mõni on `restarting` või `exited`, vaata selle konteineri logi (`docker compose logs <nimi>`) ja lahenda **enne** järgmist osa. Hiljem on viga raskem jälitada, sest sümptomid tulevad UI kaudu ("host punane") ja viga võib olla mitu kihti all.

💭 **Mõtle:** Päev 1-s Prometheus oli üks binaar + konfi-fail. Nüüd sul on neli teenust kes räägivad omavahel kolme viisi: MySQL ↔ Server, MySQL ↔ Web, Server ↔ Agent. Mis on siin eelis, mis puudus?

---

## Osa 3 · Host, template, trigger, dashboard

**Eesmärk:** Lisad kaks host'i (üks konteiner, üks päris VM), linkid template, vaatad kuidas trigger läheb stressi peale tulele ja naaseb.

Loengu 4 mõistet — **Host / Item / Trigger / Action** — saavad selles osas päriseks. Host on mida jälgime, Template on valmis mõõdikute komplekt, Trigger on tingimus millal häirida, Action on mida teha kui trigger läheb tulele (meil aga ainult UI-s nägemine, Discord jääb lisaülesandeks).

### 3.1 Esimene host — docker-agent

**Eesmärk:** UI-s host `docker-agent` on **rohelise ZBX-iga** (saab andmeid).

Lähtume lihtsaimast — iseenda Zabbix agent konteinerist. Sama Docker-võrgu sees, DNS-nimi on stabiilne, võrguprobleeme ei teki.

*Data collection → Hosts → Create host*:

- **Host name:** `docker-agent` (sama mis `ZBX_HOSTNAME` konfis!)
- **Host groups:** `Linux servers`
- **Interfaces → Add → Agent:**
  - DNS name: `zabbix-agent`
  - Connect to: **DNS**
  - Port: `10050`
- **Templates → Select:** `Linux by Zabbix agent`

**Add**. Oota 60s. *Data collection → Hosts* lehel peaks ZBX lüliti muutuma roheliseks.

Kaks asja väärib tähelepanu:

- **Connect to: DNS** (mitte IP). Docker-võrgus IP-d muutuvad iga restart'iga. DNS-nimi `zabbix-agent` on stabiilne — Docker'i sisemine DNS lahendab selle automaatselt.
- **Template `Linux by Zabbix agent`** — üks klõps ja saad ~300 valmismõõdikut + ~50 valmist trigger'it. Ilma template'ita peaksid iga mõõdiku ise looma. See on Zabbixi suur erinevus Prometheusest: **"monitoring out of the box"** vs "kirjuta PromQL ise".

💡 **Kui ZBX punane:** esmalt kontrolli et Host name UI-s on **täpselt** `docker-agent`. Teisena kontrolli et Connect to on DNS, mitte IP.

### 3.2 Teine host — mon-target (päris VM)

**Eesmärk:** Päris VM-i (mitte konteiner) host on UI-s, ZBX roheline.

mon-target on päris VM, mitte konteiner. Agent seal jookseb `systemd` teenusena. Erinevus:

- Connect to on **IP** (192.168.35.140), mitte DNS — ta ei ole samas Docker-võrgus

*Data collection → Hosts → Create host*:

- **Host name:** `mon-target`
- **Host groups:** `Linux servers`
- **Interfaces → Add → Agent:**
  - IP: `192.168.35.140`
  - Connect to: **IP**
  - Port: `10050`
- **Templates:** `Linux by Zabbix agent`

**Kontroll enne UI-s ootamist:**

```bash
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k agent.ping
```

Peab vastama `1`. Kui käsitsi töötab, töötab ka UI kaudu — see on kiire "sanity check" ilma 1 minutit UI-s ootamata.

### 3.3 Trigger fire → resolve tsükkel

**Eesmärk:** Näed esimese korra päris Zabbixi trigger'it läbi kogu tsükli — `Pending → Firing → Resolved`.

`Linux by Zabbix agent` template sisaldab trigger'it:

```
avg(/mon-target/system.cpu.util,5m) > 90
```

Tõlge: "kui CPU kasutus keskmiselt viimase 5 minuti jooksul ületab 90%, löö häiret". **Keskmistatud** trigger on tahtlik — üksikud spike-id ignoreeritakse, aga jätkuv koormus lööb läbi.

Tekita koormust:

```bash
ssh <eesnimi>@192.168.35.140
sudo stress-ng --cpu 4 --timeout 180s &
exit
```

`stress-ng --cpu 4` paneb 4 protsessorit 100% koormuse alla 3 minutiks. Kuna trigger nõuab **5 minutit** keskmist, jookseme tahtlikult üle lävendi, aga **mitte nii kaua** et trigger tegelikult läheb tulele — näed "Pending" oleku.

Järjest jälgi:

- *Monitoring → Problems* — 1-2 min pärast **võib** ilmuda `High CPU utilization` trigger
- Kui `stress-ng` lõppeb (3 min), trigger laheneb ise paari minuti jooksul (CPU keskmine langeb alla lävendi)

Kui tahad näha **Firing** olekut, aja koormust 5+ minuti pikkuseks:

```bash
ssh <eesnimi>@192.168.35.140 'sudo stress-ng --cpu 4 --timeout 360s &'
```

**Miks see tähtis:** iga Zabbix trigger töötab sellel **olekuautomaadil**: `Inactive → Pending → Firing → Resolved`. Kui tulevikus ütled "trigger ei tule", vaata esmalt olekuajalugu — ehk ta alles Pending'us, pole veel lävendi korraks ületanud.

### 3.4 Dashboard

**Eesmärk:** Avad *Monitoring → Dashboards → Global view* ja näed mõlema host'i graafikuid **ilma ühtki päringut kirjutamata**.

Template `Linux by Zabbix agent` tõi kaasa ka valmis dashboardi. CPU, mälu, ketta graafikud on automaatselt olemas mõlema host'i jaoks.

**Võrdle päev 1-ga:** Grafanas kirjutasid sa iga graafiku jaoks PromQL päringu. Siin saad ~20 graafikut ühe linnukesega (template link). Zabbix on **"plug and play"**, Grafana on **"programmable"**. Kumb sobib kuhu:

- Template-lähenemine on hea kui infrastruktuur on **standardne** (500 sarnast Linux-masinat)
- Kood-lähenemine on hea kui sul on **spetsiifilised** vajadused (igale teenusele erinevad SLO-d)

💭 **Mõtle:** Kumb sobib paremini sinu töökeskkonda? Kas sul on pigem 500 sarnast serverit (template võidab) või 50 erinevat spetsialiseeritud teenust (PromQL võidab)?

<details>
<summary>🔧 Edasijõudnule: kirjuta oma trigger</summary>

Template-triggerid on lihtsad. Proovi kirjutada oma memory-trigger:

*Data collection → Hosts → kliki `mon-target` real **Triggers** lingil → Create trigger*:

- Name: `Memory usage critical on {HOST.NAME}`
- Severity: **High**
- Expression (kirjuta käsitsi):

  ```
  last(/mon-target/vm.memory.size[available]) < 100000000
  ```

  (Alla 100 MB vaba mälu)

Või keskmistatud variant (vähem false positive'e):

```
avg(/mon-target/system.cpu.util[,idle],5m) < 20
```

(CPU idle keskmiselt alla 20% viimase 5 min jooksul)

`{HOST.NAME}` on Zabbixi **makro** — trigger'i nimes asendatakse automaatselt host'i nimega. Sama trigger töötab iga host'iga, kellega teda linkida.

[Docs / trigger expressions](https://www.zabbix.com/documentation/7.0/en/manual/config/triggers/expression)

</details>

---

## Osa 4 · HTTP Agent + Dependent items

**Eesmärk:** Teed ühe HTTP päringu Nginx stub_status endpoint'ile ja saad sellest mitu eraldi mõõdikut — **ilma välise exporter'ita**.

Päev 1 Prometheus'es kasutasid `nginx-prometheus-exporter` konteinerit stub_status andmete kogumiseks. Zabbix teeb sama **natiivselt** — Server küsib URL-i otse. See on üks põhjus, miks Zabbix hoidab tihti väiksemat komponenti-parki kui Prometheus-stack.

**Miks see oluline:** iga exporter on üks konteiner rohkem mida hooldada — logid, uuendused, sõltuvused, crash'id. Kui teenus juba pakub HTTP/SNMP/JMX-i liidest, säästab Zabbix sind eraldi exporter'i kirjutamisest.

Selle osa **muster** — üks **master item** (kogu HTTP vastus) + mitu **dependent item**'it (regex'iga üks-ühele välja võetud) — on Zabbixis nii tavaline, et seda tasub ise korra ehitada.

### 4.1 Host ilma interface'ita

**Eesmärk:** Loo `nginx-web` host **ilma ühegi interface'ita** — HTTP Agent ei vaja seda.

*Data collection → Host groups → Create host group* → Name: `Applications` → Add.

*Data collection → Hosts → Create host*:

- **Host name:** `nginx-web`
- **Host groups:** `Applications`
- **Interfaces:** mitte ühtki (ära lisa!)

Miks ilma interface'ita? Interface on Zabbixis "kuidas Server mõõdetava objektiga ühenduse saab" — tavaliselt agent'i kaudu. Aga HTTP Agent tüüpi item **küsib URL-i otse** ja kannab URL-i endaga kaasas. Interface'i pole vaja.

Add. Host ilmub *Hosts* nimekirja, aga ZBX on hall — see on ootuspärane, ta pole agent-host.

### 4.2 Master item — kogu stub_status korraga

**Eesmärk:** Üks item toob Nginx stub_status endpoint'i vastuse Zabbixisse tekstina.

Miks üks master item? Nginx stub_status on selline:

```
Active connections: 12
server accepts handled requests
 2847 2847 8213
Reading: 0 Writing: 2 Waiting: 10
```

Siin on **viis arvu** — Active connections, Accepts, Handled, Requests, Reading/Writing/Waiting. Kui teeksid iga numbri jaoks eraldi HTTP päringu (iga 30 sek), oleks Nginx pool 5× rohkem koormat. **Master küsib üks kord, dependent'id parsivad**.

Kliki `nginx-web` real **Items** → **Create item**:

- **Name:** `Nginx status raw`
- **Type:** HTTP agent
- **Key:** `nginx.status.raw`
- **URL:** `http://192.168.35.141:8080/stub_status`
- **Type of information:** **Text**
- **Update interval:** `30s`

**Add**. Minut pärast *Monitoring → Latest data* näitab stub_status teksti.

Miks **Text**, mitte Numeric? Master item hoiab **toorandmeid** — mitu numbrit ühes vastuses. Numeric ootaks **ühte** numbrit. Parsing toimub järgmises sammus dependent'is.

### 4.3 Dependent item — üks number tekstist välja

**Eesmärk:** Dependent item võtab master'i tekstist välja **ühe konkreetse numbri** (Active connections).

Kliki `nginx-web` real **Items → Create item**:

- **Name:** `Active connections`
- **Type:** **Dependent item**
- **Master item:** `nginx-web: Nginx status raw`
- **Key:** `nginx.connections.active`
- **Type of information:** Numeric (unsigned)
- **Preprocessing → Add:**
  - Type: **Regular expression**
  - Pattern: `Active connections: (\d+)`
  - Output: `\1`

**Add**.

`(\d+)` püüab esimese numbrilise grupi, `\1` viitab sellele output'is. Tulemus: puhas number, salvestatakse Numeric-item'ina.

Tekita Nginx'ile liiklust:

```bash
for i in {1..20}; do curl -s http://192.168.35.141:8080/ > /dev/null & done; wait
```

*Latest data* peaks näitama `Active connections` numbri tõusu.

### 4.4 Tee ise — teine dependent item

**Eesmärk:** Sa ise lisad dependent item'i `Requests total`.

Sama master, uus dependent item:

- **Name:** `Requests total`
- **Key:** `nginx.requests.total`
- **Type of information:** Numeric (unsigned)
- **Preprocessing → Regex:** pattern `requests\s+\d+\s+(\d+)\s+\d+`, output `\1`

Kui regex ei tule kohe välja, kliki **master item** peal **Test** nuppu — Zabbix näitab viimast väljundit ja saad regex'i jooksvalt testida. Sama tööriist ka dependent item'il: **Test → View value** näitab, mis master andis ja mis dependent sellest välja võttis.

Kolmas mõõdik on ka kerge lisada (nt `Reading`, `Writing`, `Waiting`) — vaata kas oled välja selgitanud, kuidas regex tehakse.

💭 **Mõtle:** sa just vältisid eraldi exporter'i jooksutamist. Prometheus'e lähenemisest on see Zabbix'i plusspool. Aga mis on hind? (Vihje: kui pead sama liidest jälgima 50 host'ist, kumb skaleerib paremini — Zabbixi HTTP Agent 50 host'is või üks Prometheus'e exporter mis pakub `/metrics` 50 instanti jaoks?)

<details>
<summary>🔧 Edasijõudnule: JSONPath preprocessing</summary>

Regex töötab stub_status jaoks, aga kui jälgid JSON API-t (nt `/api/health`), on JSONPath mugavam.

Master item URL: JSON-tagastav endpoint  
Master item Type of information: **Text**

Dependent item preprocessing:
- Type: **JSONPath**
- Params: `$.connections.active`

JSONPath on nagu XPath, aga JSON-ile. Regex'ist selgem, vähem vigu, ei murra ümberformatimise peale.

[Docs / preprocessing](https://www.zabbix.com/documentation/7.0/en/manual/config/items/preprocessing)

</details>

---

## Osa 5 · UserParameter + honeypot

**Eesmärk:** Teed Zabbixi agendist iga shell-käsu mõõdiku. Esmalt triviaalne (konstant 42), seejärel päris (payment-vead logifailis), lõpuks turbe-vaatenurgast (honeypot).

Template annab 300 standard-mõõdikut. Aga iga **ärisüsteem** vajab oma mõõdikuid: payment-kanali veaarv, tellimuste järjekord, litsentsi aegumine. Ilma UserParameter'ita peaksid need tulema eraldi exporter'ist. UserParameter teeb sellest **ühe rea konfiga**.

### 5.1 Kõige lihtsam UserParameter — konstant 42

**Eesmärk:** `zabbix_get -k minu.test` tagastab `42`.

Enne päris logifailide kallal töötamist veendu, et mehhanism ise töötab. "Hello world" UserParameter:

```bash
echo 'UserParameter=minu.test, echo 42' > ~/paev2/zabbix/config/test.conf
docker restart zabbix-agent
sleep 5
docker exec zabbix-server zabbix_get -s zabbix-agent -k minu.test
```

Vastus: `42`.

Mis juhtus? Kirjutasid `test.conf` faili compose-kausta kausta, mis on mount'itud konteinerisse `/etc/zabbix/zabbix_agentd.d/`. Agent restart'ib, loeb konfi, registreerib uue võtme. Kui Server nüüd küsib võtit `minu.test`, agent käivitab `echo 42` ja tagastab väljundi.

**Võti** (`minu.test`) on sinu valitud string — tavaline konventsioon on `rakendus.alam-mõõdik`.

### 5.2 Parameetritega võti

**Eesmärk:** Üks UserParameter, palju kasutusviise — `minu.topelt[5]` annab 10, `minu.topelt[100]` annab 200.

Parameetrid muudavad ühe definitsiooni **malliks**:

```bash
cat > ~/paev2/zabbix/config/test.conf <<'EOF'
UserParameter=minu.topelt[*], echo $(($1 * 2))
EOF
docker restart zabbix-agent && sleep 5
docker exec zabbix-server zabbix_get -s zabbix-agent -k "minu.topelt[5]"
docker exec zabbix-server zabbix_get -s zabbix-agent -k "minu.topelt[100]"
```

Esimene annab `10`, teine `200`. `[*]` tähendab "võta kõik parameetrid", `$1` viitab esimesele.

Miks see tähtis? Järgmises sammus kirjutame `applog.errors[payment]`, `applog.errors[auth]`, `applog.errors[api]` — **üks UserParameter, palju item'eid**. Ilma parameetriteta peaks iga teenuse jaoks eraldi UserParameter'i kirjutama. Hiljem tuleb sellest LLD (Low-Level Discovery) ja **item prototype** — ühel definitsioonil palju automaatselt tekkivaid instantse.

### 5.3 Päris UserParameter — payment-vead logifailis

**Eesmärk:** Agent mon-target'il tagastab numbri: mitu ERROR rida on teenuses `payment` viimase 1000 rea hulgas.

mon-target'il jookseb log-generator, mis lisab `/var/log/app/app.log` faili ridu kujul `2026-04-25T10:23:41 [ERROR] [payment] duration=245ms trace_id=12345`. Tahame mõõdikut: **mitu payment-ERROR rida on viimase 1000 rea hulgas?**

Klassikaline shell-lahendus: `tail -n 1000 | grep -c`. UserParameter teeb sellest Zabbixi item'i.

SSH mon-target'ile:

```bash
ssh <eesnimi>@192.168.35.140
sudo tee /etc/zabbix/zabbix_agentd.d/applog.conf <<'EOF'
UserParameter=applog.errors[*], tail -n 1000 /var/log/app/app.log | grep -c "\[ERROR\] \[$1\]"
UserParameter=applog.count[*], tail -n 1000 /var/log/app/app.log | grep -c "\[$1\] \[$2\]"
EOF
sudo systemctl restart zabbix-agent
exit
```

Kaks UserParameter'it:

- `applog.errors[service]` — ainult ERROR-read konkreetses teenuses
- `applog.count[level, service]` — mis tahes level+service kombinatsioon

**Testi kohe** (Server-konteinerist):

```bash
docker exec zabbix-server zabbix_get -s 192.168.35.140 -k "applog.errors[payment]"
```

Peab vastama numbriga (võib-olla 0, kui log-generator just ei ole juhuslikult payment-ERROR'eid tootnud). Enne kui mõõdik salvestatakse Zabbixi, peab `zabbix_get` töötama — see on kõige kiirem tagasiside-silmus.

!!! warning "Piirang: `tail -n 1000`"
    See käsk loeb ainult viimased 1000 rida. Kui logi kasvab kiiresti (nt 100 rida sekundis), võib reaalne veaarv olla palju suurem kui see, mida näed. Tootmises eelistatakse [Log monitoring](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/log_items) item-tüüpi, mis hoiab positsiooni ja loeb ainult uued read. UserParameter + grep on prototüüpkvaliteet.

💡 **Kui `ZBX_NOTSUPPORTED`:** süntaksiviga konfis — `sudo cat /etc/zabbix/zabbix_agentd.d/applog.conf` ja kontrolli. Tavalised vead: `$1` asemel `\$1`, jutumärkides `[ERROR]` asemel `\[ERROR\]`, puuduv koma pärast võtit.

### 5.4 Item ja trigger UI-s {#54-item-trigger}

**Eesmärk:** UI-s on item mis salvestab `applog.errors[payment]` väärtust ja trigger mis läheb tulele kui väärtus > 10.

`zabbix_get` tagastab nüüd numbri, aga **Zabbix ei salvesta seda veel** — pole item'it. Item ütleb Server'ile "hakka seda võtit regulaarselt küsima ja salvesta ajalugu". Trigger lisab tingimuse "ja kui väärtus ületab lävendi, löö häirele".

*Data collection → Hosts → `mon-target` → Items → Create item*:

- **Name:** `Payment errors (last 1000 lines)`
- **Type:** Zabbix agent
- **Key:** `applog.errors[payment]`
- **Type of information:** Numeric (unsigned)
- **Update interval:** `30s`

Miks 30 sekundit? Logi kasvab ~1 rida/sek, 30s annab mõistliku tasakaalu reaktsiooniaja ja Server'i koormuse vahel. Iga sekund oleks üleliigne, iga 5 min oleks aeglasem kui märkad.

**Add**.

*Data collection → Hosts → `mon-target` real **Triggers** lingil → Create trigger*:

- **Name:** `Too many payment errors on {HOST.NAME}`
- **Severity:** Warning
- **Expression:** `last(/mon-target/applog.errors[payment])>10`

**Add**.

`{HOST.NAME}` on makro — trigger'i nimes asendub host'i nimega. Sama trigger töötab iga host'iga, kuhu linkida.

💡 **Trigger navigatsioon Zabbix 7.0:** trigger'i loomiseks mine host'i real **Triggers** lingile. Paljud otsivad menüüst *Alerts → Triggers*, aga seal näeb ainult olemasolevaid trigger'eid, mitte "Create trigger" nuppu.

### 5.5 Error-torm — veendu, et trigger elab

**Eesmärk:** Tekitad 100 ERROR rida ja näed 1 minuti pärast triggeri `Firing`.

Alert on kvaliteetne ainult kui sa oled testinud, et ta päriselt välja lööb. Tootmises see samm sageli jäetakse tegemata — kuni esimene päris probleem tuleb ja selgub et e-kiri ei tulnud.

```bash
ssh <eesnimi>@192.168.35.140 \
  'for i in $(seq 1 100); do echo "$(date -Iseconds) [ERROR] [payment] Spam_$i" | sudo tee -a /var/log/app/app.log > /dev/null; done'
```

100 ERROR rida → viimase 1000 rea hulgas on nüüd kindlasti üle 10 payment-ERROR'i. Umbes 1 min pärast (update interval 30s + Server-side processing) *Monitoring → Problems* lehel trigger **Firing**.

Kui lakkad lisamast, vanad error'id liiguvad aknast välja (log-generator kirjutab uusi ridu peale, `tail -1000` läheb edasi), väärtus langeb alla 10 → trigger resolve'ib **ise**.

**See oli "payment errors" trigger**, millele viitame Loki labori [osas 3.6 FINAAL](loki_lab.md#36-finaal-uks-sundmus-kaks-perspektiivi). Hoia see trigger aktiivsena.

### 5.6 Honeypot — sama mehhanism turbe-vaatenurgast

**Eesmärk:** Avad pordi 2222 kuulama, iga ühendus sinna on turvasignaal, Zabbixi trigger läheb tulele **Severity: High**.

UserParameter ei pea olema ainult jõudluse-mõõdik. Lihtsaim honeypot on **avatud port, kuhu keegi "õiges" ei tohi ühenduda**. Iga ühendus on anomaalia.

SSH mon-target'ile:

```bash
ssh <eesnimi>@192.168.35.140
sudo tee /usr/local/bin/honeypot-listen.sh <<'EOF'
#!/bin/bash
while true; do
  nc -lnp 2222 < /dev/null 2>/dev/null && echo "$(date -Iseconds) HIT" >> /var/log/honeypot.log
done
EOF
sudo chmod +x /usr/local/bin/honeypot-listen.sh
sudo touch /var/log/honeypot.log
nohup sudo /usr/local/bin/honeypot-listen.sh &
```

Skript avab pordi 2222 ja iga ühenduse kohta kirjutab rea `HIT` faili. Teenust seal tegelikult pole — port on lõks.

UserParameter mis loendab HIT-e (parameetrita seekord):

```bash
sudo tee -a /etc/zabbix/zabbix_agentd.d/applog.conf <<'EOF'
UserParameter=honeypot.hits, wc -l < /var/log/honeypot.log
EOF
sudo systemctl restart zabbix-agent
exit
```

UI-s (`mon-target` host):

- **Item:** `Honeypot hits`, key `honeypot.hits`, Numeric unsigned, 15s
- **Trigger:**
  - Name: `Honeypot hit detected on {HOST.NAME}`
  - Severity: **High**
  - Expression: `last(/mon-target/honeypot.hits)>0`

Miks **High**, mitte Warning nagu payment-error'itel? Payment-error'id juhtuvad mingis määras — **tavaline müra**. Honeypot-hit on definitsiooni järgi **anomaalia** — ei tohi kunagi juhtuda. `last() > 0` ja `High` ütleb "iga üks löök ongi probleem".

**Testi:**

```bash
nc -zv 192.168.35.140 2222
```

1 min → Zabbixis *Problems* lehel trigger **Firing** Severity **High**.

### 5.7 User macros — paroolid item'itest välja

**Eesmärk:** Mõistad, kuidas hoida tundlikud andmed **Zabbixi UI-s**, mitte konfi-failis.

Osa 5.3 konfis kirjutasime rada kõvasti: `/var/log/app/app.log`. Aga mis kui tootmises on see tee teistsugune host'ide lõikes? Mis kui shell-käsus on **parool** (nt `-u root -p Monitor2026!`)? Siis parool on:

1. Agent konfi failis kettal
2. Git'is (kui sa committid)
3. Backup'is
4. Audit-logis

**User macro** on Zabbixi mehhanism: väärtus **UI-s**, võti itemi/trigger'i tekstis. Server asendab võtme enne agendile saatmist.

*Data collection → Hosts → `mon-target` → Macros* tab → *Add*:

| Macro | Value | Type |
|-------|-------|------|
| `{$APP.LOG.PATH}` | `/var/log/app/app.log` | Text |
| `{$APP.DB.PASSWORD}` | `secret_123` | **Secret text** |

Item'i võtmes saad kasutada `applog.errors[{$APP.SERVICE}]` jne.

**Secret text** peidab väärtuse UI-s ja audit-logis. Ava Macros tab uuesti — Secret väärtust ei näe enam, on ainult tärnid.

💭 **Mõtle:** UserParameter võimaldab mis tahes shell-käsku mõõdikuks muuta. Mis on selle **turvarisk**? (Vihje: kui ründaja saab agent-konfi kirjutada, mis on tema vaba käe ulatus?) Kuidas hallatakse sinu tööl paroole ja tokeneid monitooringu kontekstis — Vault, env-muutujad, failid?

---

## ✅ Lõpukontroll

Kui kõik allpool on linnutatud, oled Zabbix-labi läbinud:

**Baas (osad 1–2):**
- [ ] `docker compose ps` (`~/paev2/zabbix/`) näitab 4 konteinerit `Up`, MySQL `(healthy)`
- [ ] Sisse Zabbix UI-sse `http://192.168.35.12X:8080`, parool vahetatud `Monitor2026!`

**Hostid ja trigger (osa 3):**
- [ ] `docker-agent` ja `mon-target` mõlemad ZBX-roheline
- [ ] Template `Linux by Zabbix agent` andis ~300 item'it ja dashboardi ilma käsitööta
- [ ] Stressiga nägid triggeri `Pending → Firing → Resolved` tsüklit

**HTTP Agent (osa 4):**
- [ ] `nginx-web` host eksisteerib ilma interface'ita
- [ ] Master item `Nginx status raw` näitab *Latest data*-s teksti
- [ ] Kaks dependent item'it (`Active connections`, `Requests total`) tagastavad numbrilised väärtused

**UserParameter (osa 5):**
- [ ] `zabbix_get -k "applog.errors[payment]"` tagastab numbri
- [ ] Payment-errors trigger läks `Firing` ja lahenes
- [ ] Honeypot-trigger läks `Firing` kui tegid `nc -zv 192.168.35.140 2222`

**Jätka:** [Labor: Loki](loki_lab.md) — logide stack, LogQL, FINAAL (sama sündmus, kaks perspektiivi).

---

## 🚀 Lisaülesanded

Neli suunda edasi minemiseks, kui Zabbix-osa jõudsid ette.

### LLD + oma template (Low-Level Discovery)

Osa 5 tegid `applog.errors[payment]` käsitsi. Aga teenuseid on 5, raskusastmeid 3 = 15 kombinatsiooni. LLD avastab need automaatselt.

Discovery-skript mon-target'il:

```bash
ssh <eesnimi>@192.168.35.140
sudo tee /usr/local/bin/applog-discovery.sh <<'EOF'
#!/bin/bash
tail -n 5000 /var/log/app/app.log 2>/dev/null \
  | grep -oE '\[(INFO|WARN|ERROR)\] \[[a-z]+\]' \
  | sort -u \
  | awk '
    BEGIN { printf "[" }
    NR > 1 { printf "," }
    {
      sev = $1; svc = $2
      gsub(/[\[\]]/, "", sev); gsub(/[\[\]]/, "", svc)
      printf "{\"{#SEVERITY}\":\"%s\",\"{#SERVICE}\":\"%s\"}", sev, svc
    }
    END { print "]" }
  '
EOF
sudo chmod +x /usr/local/bin/applog-discovery.sh
sudo tee -a /etc/zabbix/zabbix_agentd.d/applog.conf <<'EOF'
UserParameter=applog.discovery, /usr/local/bin/applog-discovery.sh
EOF
sudo systemctl restart zabbix-agent
exit
```

Kontrolli: `docker exec zabbix-server zabbix_get -s 192.168.35.140 -k applog.discovery` → peab tagastama valiidse JSON-i.

UI-s loo template `App Log Monitoring`:

- Discovery rule: `applog.discovery`, 2m
- Item prototype: `applog.count[{#SEVERITY},{#SERVICE}]`
- Trigger prototype
- Filter: ainult ERROR ja WARN

Lingi template mon-target host'iga. 2–3 min → ~10 uut item'it tekib automaatselt.

### Discord-i teavitused

*Alerts → Media types → Discord* → lisa webhook URL  
*Users → Admin → Media → Discord*  
*Alerts → Actions → Create action* (severity ≥ Warning, send to Admin via Discord, + recovery operation)

Testi error-tormiga (osa 5.5) — sõnum peaks tulema Discord-kanalisse.

### Trigger-hysteresis — õiges-valesti kõikumine

Probleemi sissetulek: `last() > 10`  
Probleemi lahenemine: `last() < 5`

Hoiab ära triggeri õiges-valesti kõikumise lävendi ümber (nt väärtus võnkub 9 ja 11 vahel).

### Zabbix Proxy — labori VM kui proxy taga

Lisa compose-faili `zabbix-proxy-sqlite3:ubuntu-7.0.25` teenus. Registreeri proxy UI-s (*Administration → Proxies*). Sea mon-target-web sellest läbi (*Host → Monitored by proxy*).

Vaata loengust §5 — miks see **tootmises vältimatu** on (DMZ, filiaalid, WAN-i latency).

---

## 🏢 Enterprise lisateemad

Järgnevad teemad on tootmiskeskkondadele. Iga teema on iseseisev — vali mis sinu tööle relevantsed on.

??? note "Zabbix HA — kõrgkäideldavus Docker Compose'is"

    Alates Zabbix 6.0 on natiivne HA sisseehitatud — ei vaja Pacemaker'it ega Corosync'i. Kaks (või enam) Zabbix Server'it jagavad sama MySQL-i, üks on **aktiivne**, teised **standby**.

    **Lisa teine server:**

    ```yaml
      zabbix-server-2:
        image: zabbix/zabbix-server-mysql:ubuntu-7.0.25
        container_name: zabbix-server-2
        depends_on:
          mysql:
            condition: service_healthy
        environment:
          DB_SERVER_HOST: mysql
          MYSQL_DATABASE: zabbix
          MYSQL_USER: zabbix
          MYSQL_PASSWORD: zabbix_pwd
          ZBX_SERVER_NAME: zabbix-server-2
          TZ: Europe/Tallinn
        restart: unless-stopped
    ```

    `zabbix_server.conf` mõlemas serveris:

    ```
    HANodeName=zabbix-server-1    # või -2
    NodeAddress=zabbix-server:10051
    ```

    **Testi failover:**

    ```bash
    docker compose up -d zabbix-server-2
    # Reports → System information → HA cluster → 2 sõlme
    docker stop zabbix-server
    # ~30s → zabbix-server-2 võtab üle (active)
    docker start zabbix-server
    # server-1 läheb standby
    ```

    Tootmises: DB-kiht vajab ka HA-d (PostgreSQL + Patroni või MariaDB + Galera). See on eraldi projekt.

    **Loe edasi:**

    - [Zabbix HA dokumentatsioon](https://www.zabbix.com/documentation/7.0/en/manual/concepts/server/ha)
    - [HA runtime commands](https://www.zabbix.com/documentation/7.0/en/manual/concepts/server/ha#runtime-commands)

??? note "Zabbix Proxy — monitooring üle WAN-i"

    Kui sul on filiaalid, DMZ või pilveinfra, ei saa agent'id alati otse Server'iga rääkida. Proxy kogub andmeid **lokaalselt** ja edastab Server'ile.

    ```
    [Filiaal A]                    [Peakontor]
    Agent → Proxy-A ──── WAN ────→ Zabbix Server
    Agent →                         ↑
                                    MySQL
    [Filiaal B]
    Agent → Proxy-B ──── WAN ────→
    ```

    **Lisa compose-faili:**

    ```yaml
      zabbix-proxy:
        image: zabbix/zabbix-proxy-sqlite3:ubuntu-7.0.25
        container_name: zabbix-proxy
        environment:
          ZBX_PROXYMODE: 0                    # 0=active, 1=passive
          ZBX_HOSTNAME: proxy-local
          ZBX_SERVER_HOST: zabbix-server
          TZ: Europe/Tallinn
        ports:
          - "10061:10051"
        restart: unless-stopped
    ```

    UI-s: *Administration → Proxies → Create proxy* → Name: `proxy-local`, Mode: Active.

    Host'i lisamisel: *Monitored by proxy → proxy-local*.

    **Zabbix 7.0 Proxy groups:** mitu proxy't ühes grupis — kui üks kukub, teised võtavad host'id automaatselt üle.

    **Loe edasi:**

    - [Proxy dokumentatsioon](https://www.zabbix.com/documentation/7.0/en/manual/distributed_monitoring/proxies)
    - [Proxy groups (7.0)](https://www.zabbix.com/documentation/7.0/en/manual/distributed_monitoring/proxy_groups)

??? note "SNMP monitooring — võrguseadmed, kaamerad, printerid"

    Switchile, ruuterile, kaamerale, printerile ei installi Zabbix agent'it. Need räägivad SNMP-d.

    **Lisa host SNMP interface'iga:**

    - Interface Type: **SNMP**
    - IP: seadme IP
    - SNMP version: `SNMPv2`
    - SNMP community: `public`
    - Templates: `Net Cisco IOS by SNMP` (või `Generic by SNMP`)

    Template toob kaasa interface'ide LLD, liikluse graafikud, uptime, error counter'id.

    **Testi ilma päris seadmeta — snmpsim:**

    ```bash
    docker run -d --name snmpsim -p 161:161/udp xeemetric/snmp-simulator
    ```

    Lisa Zabbix host'iks VM IP (`192.168.35.12X`), port 161.

    **OID-de uurimine:**

    ```bash
    docker exec zabbix-server snmpwalk -v2c -c public 192.168.35.12X .1.3.6.1.2.1.1
    ```

    **Loe edasi:**

    - [SNMP monitooring Zabbixis](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/snmp)
    - [SNMP OID tree](http://www.oid-info.com/cgi-bin/display?tree=.1.3.6.1.2.1)
    - [Community templates (SNMP)](https://github.com/zabbix/community-templates/tree/main/Network_Devices)

??? note "Agent ↔ Server PSK krüpteerimine"

    Tootmises ei saada agent andmeid selgetekstina. TLS-PSK on lihtsaim viis krüpteerida.

    **Genereeri PSK:**

    ```bash
    openssl rand -hex 32 > /tmp/zabbix_agent.psk
    ```

    **Agent konfis:**

    ```
    TLSConnect=psk
    TLSAccept=psk
    TLSPSKIdentity=PSK-agent-01
    TLSPSKFile=/etc/zabbix/zabbix_agent.psk
    ```

    **UI-s** host → *Encryption* tab → PSK → Identity + PSK väärtus.

    `zabbix_get` ilma PSK-ta ei tööta:

    ```bash
    docker exec zabbix-server zabbix_get -s zabbix-agent -k agent.ping \
      --tls-connect psk --tls-psk-identity "PSK-agent-01" --tls-psk-file /tmp/agent.psk
    ```

    **Loe edasi:**

    - [Encryption dokumentatsioon](https://www.zabbix.com/documentation/7.0/en/manual/encryption)
    - [PSK vs Certificate](https://www.zabbix.com/documentation/7.0/en/manual/encryption/using_pre_shared_keys)

??? note "Zabbix API + Ansible — masshost'ide haldus"

    2000 host'i käsitsi lisamine on mõttetu. Zabbix JSON-RPC API + Ansible teevad selle minutitega.

    **Token'i saamine:**

    ```bash
    curl -s -X POST http://192.168.35.12X:8080/api_jsonrpc.php \
      -H "Content-Type: application/json" \
      -d '{
        "jsonrpc": "2.0",
        "method": "user.login",
        "params": {"username": "Admin", "password": "Monitor2026!"},
        "id": 1
      }'
    ```

    **Ansible playbook (host'ide masslisamine):**

    ```yaml
    - hosts: localhost
      collections:
        - community.zabbix
      tasks:
        - name: Lisa host Zabbixisse
          community.zabbix.zabbix_host:
            server_url: "http://192.168.35.12X:8080"
            login_user: Admin
            login_password: Monitor2026!
            host_name: "server-{{ item }}"
            host_groups: [Linux servers]
            link_templates: [Linux by Zabbix agent]
            interfaces:
              - type: agent
                main: 1
                ip: "192.168.35.{{ item }}"
          loop: "{{ range(140, 145) | list }}"
    ```

    **Loe edasi:**

    - [Zabbix API dokumentatsioon](https://www.zabbix.com/documentation/7.0/en/manual/api)
    - [Ansible Zabbix collection](https://docs.ansible.com/ansible/latest/collections/community/zabbix/)

??? note "Audit log + SLA raportid (compliance)"

    GDPR, NIS2, Eesti Pank, audit — **kes mida muutis** ja **mis on uptime**?

    **Audit log:** *Reports → Audit log* — iga muudatus logitud (kes, millal, mida). Filter: Resource type, Action, User. API kaudu CSV-sse eksporditav.

    **SLA (Zabbix 7.0 sisseehitatud):**

    *Services → SLA → Create SLA:*
    - Name: `Production servers 99.9%`
    - SLO: `99.9`, Schedule: `24x7`
    - Service tags: `env = production`

    *Services → Services* loo teenuse puu (nt `Production → Web tier → App tier`). *Reports → SLA report* näitab uptime %-i.

    **Maintenance windows** — planeeritud hooldus ei riku SLA-d: *Data collection → Maintenance → Create* → Type: "With data collection" (kogub, ei teavita).

    **Loe edasi:**

    - [SLA dokumentatsioon](https://www.zabbix.com/documentation/7.0/en/manual/it_services/sla)
    - [Audit log](https://www.zabbix.com/documentation/7.0/en/manual/web_interface/frontend_sections/reports/audit)
    - [Maintenance](https://www.zabbix.com/documentation/7.0/en/manual/maintenance)

---

<details>
<summary><strong>Veaotsing + allikad (peida/ava)</strong></summary>

## Veaotsing

| Probleem | Esimene kontroll |
|----------|------------------|
| MySQL `unhealthy` | `free -h` — kas RAM piisab? `docker compose logs mysql` näitab täpse vea |
| Zabbix Server ei käivitu | MySQL polnud valmis. Kontrolli `depends_on: condition: service_healthy` on paigas |
| zabbix-web "Database is not available" | MySQL pole veel healthy — oota 30s, refresh |
| UI-sse ei pääse (timeout) | Port 8080 blokeeritud? `curl -v http://localhost:8080` VM-i seest |
| Host'i ZBX punane | 1) Host name UI-s **täpselt** = `ZBX_HOSTNAME` konfis. 2) Connect to DNS vs IP kontrolli |
| `zabbix_get` ebaõnnestub | `docker exec zabbix-server ping zabbix-agent` — kas konteiner-nimega leiab? |
| `ZBX_NOTSUPPORTED` | UserParameter süntaksiviga — `sudo cat /etc/zabbix/zabbix_agentd.d/applog.conf` |
| Trigger ei lähe `Firing` | *Latest data* — kas item väärtus tegelikult ületab lävendi? Oled unustanud oota-aega (pending period)? |
| HTTP Agent timeout | `curl -v http://192.168.35.141:8080/stub_status` otse serverist — kas endpoint vastab üldse? |
| Dependent item tühi | Master item *Test* nupp — kas master tagastab oodatud väljundi? Regex'i *Test value*-s kontrolli |

## 📚 Allikad

| Allikas | URL |
|---------|-----|
| Zabbix 7.0 manuaal | [zabbix.com/documentation/7.0](https://www.zabbix.com/documentation/7.0/en/manual) |
| UserParameters | [zabbix.com/.../userparameters](https://www.zabbix.com/documentation/7.0/en/manual/config/items/userparameters) |
| Low-Level Discovery | [zabbix.com/.../low_level_discovery](https://www.zabbix.com/documentation/7.0/en/manual/discovery/low_level_discovery) |
| HTTP Agent | [zabbix.com/.../http](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/http) |
| Trigger expressions | [zabbix.com/.../expression](https://www.zabbix.com/documentation/7.0/en/manual/config/triggers/expression) |
| Discord integration | [zabbix.com/integrations/discord](https://www.zabbix.com/integrations/discord) |

**Versioonid:** Zabbix 7.0.25 LTS, MySQL 8.0, Zabbix agent 2 (7.0+).

</details>

--8<-- "_snippets/abbr.md"
