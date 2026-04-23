# Päev 2 · Labor: Loki

**Kestus:** ~2 tundi (pool päev 2 laborist)  
**Tase:** Keskaste  
**VM:** Sama VM nagu Zabbix laboris. Klassis `ssh <eesnimi>@192.168.35.12X`, VPN-ilt `ssh <eesnimi>@192.168.100.12X`.  
**Eeldused:** [Labor: Zabbix](zabbix_lab.md) läbitud (Zabbix stack, mon-target host, payment errors trigger). [Päev 2: Loki loeng](../../materials/lectures/paev2-loki-loeng.md) loetud.

---

## Miks see labor

Hommikul ehitasid Zabbixi, mis ütleb **"payment teenuses on liiga palju vigu"**. Trigger läheb tulele, sulle tuleb e-kiri. Sa tead et midagi on valesti.

Aga sa ei tea **mida** — mis viga, millal algas, millised päringud kukkusid. Selleks on vaja logisid. Ja kui logifailid on laiali kümnetes VM-ides ja konteinerites, ei aita enam SSH + grep. Vaja on tsentraalset logiteenust, kuhu kõik rakendused oma logid saadavad, ja päringukeelt, millega neid otsida.

Sellest labist tuled välja tööriistaga, mis on **sama sündmuse teine pool**: Zabbix ütleb "on probleem" (trigger), Loki näitab "mis juhtus" (logiread ja graafikud). Finaali jõuame osa 3 lõpus.

---

## 🎯 Õpiväljundid

Labi lõpuks sa oskad:

1. **Kirjutada** LogQL päringuid nelja parseriga (pattern, json, logfmt, filter `|=`) ning valida õige parseri logi formaadi järgi
2. **Ehitada** Loki + Alloy + Grafana stacki kihiti Docker Compose'iga ja testida iga kihti eraldi enne järgmise lisamist
3. **Teisendada** vabatekstilisest logist metrika (`rate`, `count_over_time`) ja ehitada sellest Grafana dashboard
4. **Kasutada** Alloy debug UI-d (`:12345`) ahela silumiseks ja **seostada** sama sündmus Zabbixi triggeri ja Loki graafiku vahel

---

## Labi struktuur

Labor on kolmes osas. Iga osa on ~40 minutit ja lõpeb konkreetse oskusega.

| Osa | Teema | Oskus osa lõpus |
|-----|-------|-----------------|
| 1 | LogQL brauseris | Kirjutad nelja parseriga päringuid ilma oma Lokita |
| 2 | Loki + Alloy + Grafana stack | Sul jookseb oma logihaldus, mida sa mõistad kihihaaval |
| 3 | Logist metrika + FINAAL | Ehitad dashboardi ja ühendad Zabbixi triggeri Loki graafikuga |

Osa 1 on tahvlitöö brauseris — keele õppimine enne tööriista ehitamist. Osa 2 on ehitustöö. Osa 3 ühendab kõik kokku.

---

## Eeltöö

Zabbix stack eelmisest osast peab olema üleval — Loki osa 3 FINAAL sõltub sellest.

```bash
cd ~/paev2/zabbix && docker compose ps
```

!!! tip "Kui `docker compose` ei tööta"
    Mõnes VM-is on Compose vanema nimega. Kasuta `docker-compose` (näiteks `docker-compose ps`).

Neli konteinerit `Up`. Kui ei — [mine tagasi Zabbix labi juurde](zabbix_lab.md).

---

## Osa 1 · LogQL brauseris

**Eesmärk:** Enne kui ehitad oma Loki stacki, harjutad LogQL-i Grafana ametlikul simulaatoril. Pärast seda osa sa **valid parseri logi formaadi järgi** — mitte proovid kõiki järjest.

Miks enne stacki ehitamist? Kaks põhjust. Esiteks — LogQL süntaks on piisavalt omapärane, et seda kohtamata kõike `|=` filtriga teha, mis on aeglane ja ebatäpne. Teiseks — kui hiljem midagi ei tööta, pead teadma kas viga on sinu päringus või konfis. Eraldi harjutamisega teed need kaks asja lahti.

Loeng §7 selgitas neli parserit põhimõtteliselt. Siin näed neid päris ekraanil.

Ava brauseris: <https://grafana.com/docs/loki/latest/query/analyzer/>

### 1.1 Täisteksti filter (`|=`)

**Eesmärk:** Näha, millal `|=` on piisav ja millal eksitab.

`|=` on LogQL-i `grep` — otsib sõne igalt logirealt. Lihtne, aga ei tee vahet, **kus** see sõne on: päris veateates või info-real, kus juhtumisi sõna "error" esineb.

Analüsaatori ülemisest rippmenüüst (**Log format**) vali **logfmt**. Rippmenüü määrab, milliseid näidisandmeid kuvatakse — mitte parserit. Parseri valid ise LogQL päringus.

Kirjuta päringu kasti:

```logql
{job="analyze"} |= "error"
```

Klõpsa Run query. Rohelised read sobivad, hallid ei sobi.

**Vaata hoolega tulemusi.** Näed, et mõned rohelised read on tegelikult `level=info` — seal on sõna "error" sisus, mitte level-väljas. `|=` ei tee vahet.

See on `|=` piirang: ta otsib sõne, mitte struktureeritud välja.

### 1.2 Logfmt parser

**Eesmärk:** Filtreerida **välja järgi**, mitte sõne järgi.

Logfmt on vorming `level=error service=auth duration=42ms`. Iga väli on võti-väärtus paar. Kui päring teab vormingut, saad filtreerida semantiliselt.

```logql
{job="analyze"} | logfmt | level = "error"
```

Klõpsa Run. Nüüd ei ole ühtki info-rida tulemustes, isegi kui sisus esineb sõna "error". Filter töötab välja `level` järgi, mitte teksti järgi.

Võrdle eelmise päringuga: `|= "error"` vastas 12 rida (näitena), `| logfmt | level = "error"` vastas 4. Kaheksa rida oli **valepositiivset**.

### 1.3 Pattern parser

**Eesmärk:** Võtta väljad struktureerimata tekstist (Apache access log, Nginx error log, Java stack trace).

Loeng §7 nimetas pattern-i kui "kõige praktilisema" parseri, sest tootmises olevate logide enamik pole logfmt ega JSON. Pattern lubab sul määrata mustri ja nimetada kohad, kust väljad välja võtta.

Rippmenüüst vali **unstructured**. Päring:

```logql
{job="analyze"} | pattern `<_> <user> <_>` | user =~ "kling.*"
```

Klõpsa Run.

Süntaks: `<_>` tähendab "ignoreeri see koht", `<user>` tähendab "võta see koht välja ja nimeta teda `user`-iks". Mustrist tuleb uus label `user`, mida saad järgneva filtriga (`| user =~ "kling.*"`) kasutada.

Tulemused: ainult read, kus kasutajanimi algab "kling"-iga.

### 1.4 JSON parser

**Eesmärk:** Kui logi on JSON, võtta kõik väljad automaatselt.

Rippmenüüst vali **json**. Päring:

```logql
{job="analyze"} | json | status_code = "500"
```

Klõpsa Run.

`| json` lahkab kogu rea: ülemise taseme väljad tulevad otse labeliteks, sisestatud (`user.id`) muutub `user_id`-ks. Edasised filtrid töötavad iga välja peal, nagu oleks see label alguses olemas olnud.

### 1.5 Parseri valik — otsustuspuu

Sa oled nüüd näinud kõiki nelja. Mis millal sobib?

| Logi välja näeb välja nagu | Parser |
|----------------------------|--------|
| `{"level":"error","user":"ann"}` | `json` |
| `level=error user=ann duration=42ms` | `logfmt` |
| `2026-04-25 10:23 ERROR user=ann failed` (vabatekst, aga stabiilse struktuuriga) | `pattern` |
| Täiesti ebastandardne tekst | `regexp` |
| Ainult üks kord teed kiiret otsingut | `\|=` |

Regexp on viimane variant — aeglane, vigaderohke. Kui pattern läheb tööle, kasuta seda.

💭 **Mõtle:** Sinu töö logid — mis formaadis need on? Kui sul on olemas süsteem, mis logib struktureerimata teksti ja te tahate hakata teda monitoorima, kas saaksid panna rakenduse JSON-i logima? Mis oleks selle hind ja tulu?

---

## Osa 2 · Loki + Alloy + Grafana stack

**Eesmärk:** Ehitad nelja komponendiga stacki — **Loki** (logide salvestus ja päringumootor), **log-generator** (testandmete allikas), **Alloy** (logide kogumisagent), **Grafana** (UI). Ehitad **kihiti** — iga teenus lisatakse alles siis, kui eelmine on testitud.

Miks kihiti, mitte terve compose-fail korraga? Kui midagi ei tööta, pead teadma **millises lülis** viga on. Kui käivitad kõik korraga ja näed "Grafana ei näita logisid" — võib olla viga Lokis, Alloys, datasource'i URL-is, Grafana-konteineris. Kihiti ehitatult on iga veaallikas eraldi testitud.

```bash
mkdir -p ~/paev2/loki/config && cd ~/paev2/loki
```

!!! info "Miks Alloy, mitte Promtail"
    Loeng §10 selgitas — Promtail on feature-freeze'is (aprill 2026), Alloy on Grafana ametlik soovitus. Alloy võimaldab sama agendiga koguda logid, meetrikad ja jäljed. Laboris kasutame ainult logide osa, aga sama agent skaleerub tootmises ka Mimirile ja Tempole.

### 2.1 Loki — logide salvestus ja päringud

**Eesmärk:** Loki konteiner jookseb ja vastab `ready` päringule. Grafanat ja Alloy't veel pole.

Loki vajab konfi: kus salvestab chunke, millise skeemi versiooniga, kas autentimine on. Laboris kasutame lihtsaimat — lokaalne filesystem, auth väljas, single-node.

```bash
cat > config/loki-config.yml << 'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  instance_addr: 127.0.0.1
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: 2024-01-01
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  allow_structured_metadata: true
EOF
```

Konfi võtmed:

- `auth_enabled: false` — single-tenant, ühe "nime" all
- `storage.filesystem` — chunks lähevad konteineri `/loki/chunks` kausta (mis tuleb volume'ist)
- `schema: v13` — stabiilne skeem (2026). Vanemates tutorialides näed `v11` — need on vananenud
- `allow_structured_metadata: true` — Loki 3.x feature

Tootmises asenduks filesystem S3-ga, auth oleks sees, replikatsioonifaktor >1. Siin on fookus päringukeelel, mitte kõrgkäideldavusel.

Loo `docker-compose.yml`:

```yaml
services:
  loki:
    image: grafana/loki:3.7.1
    container_name: loki
    ports:
      - "3100:3100"
    volumes:
      - ./config/loki-config.yml:/etc/loki/local-config.yaml
      - loki-data:/loki
    command: -config.file=/etc/loki/local-config.yaml
    restart: unless-stopped

volumes:
  loki-data:
  grafana-data:
  app-logs:
```

Kolm volume'i on deklareeritud ette, kuigi kasutuses praegu vaid `loki-data`. Põhjus: `volumes:` sektsioon on faili lõpus, kõik korraga — et me ei peaks iga teenuse lisamisel uuesti alla scrollima.

**Testi kohe:**

```bash
docker compose up -d loki
sleep 10
curl -s http://localhost:3100/ready
```

Vastus `ready`. Kui ei — `docker compose logs loki`. Loki tagastab `ready` alles kui sisemine initsialiseerimine on läbi (tavaliselt 5–10s).

Edasi ei lähe enne, kui see töötab. Kui järgmistes sammudes "ei näe logisid", on kiusatus süüdistada Alloy't — aga kui Loki pole ready, pole mõtet Alloy't süüdistada.

### 2.2 Log-generator — testandmed

**Eesmärk:** Saad logifaili, mis kasvab. Ilma selleta ei saa Alloy't ega Lokit testida.

Tootmises tuleksid logid päris rakendusest. Laboris simuleerime: busybox-konteiner, mis kirjutab iga sekund ühe rea struktuuriga `[TIMESTAMP] [LEVEL] [SERVICE] duration=... trace_id=...`.

Lisa `services:` alla:

```yaml
  log-generator:
    image: busybox:latest
    container_name: log-generator
    command:
      - sh
      - -c
      - |
        mkdir -p /var/log/app
        SERVICES="payment auth api database cache"
        LEVELS="INFO INFO INFO INFO INFO WARN ERROR"
        while true; do
          S=$(echo $SERVICES | tr " " "\n" | shuf -n1)
          L=$(echo $LEVELS | tr " " "\n" | shuf -n1)
          LATENCY=$((RANDOM % 500))
          echo "$(date -Iseconds) [$L] [$S] duration=${LATENCY}ms trace_id=$RANDOM" >> /var/log/app/app.log
          sleep 1
        done
    volumes:
      - app-logs:/var/log/app
    restart: unless-stopped
```

`LEVELS` loend on 5 INFO + 1 WARN + 1 ERROR. See simuleerib päris jaotust — enamik logisid on informatiivsed, ERROR on haruldane. Kui teeksime `LEVELS="INFO WARN ERROR"`, oleks 33% vigu — see ei õpeta mitte midagi tootmisliku käitumise kohta.

**Testi kohe:**

```bash
docker compose up -d log-generator
sleep 5
docker exec log-generator tail -3 /var/log/app/app.log
```

Näed 3 rida kujul `2026-04-25T10:23:41+03:00 [ERROR] [payment] duration=245ms trace_id=12345`. Kui näed, volume on OK ja Alloy saab hiljem neid lugeda.

### 2.3 Alloy — logide kogumisagent

**Eesmärk:** Alloy loeb `app-logs` volume'it ja saadab read Loki HTTP API-le. Pärast seda lüli sul on `log-generator → Alloy → Loki` ahel täielik.

Alloy konfig on **HCL-sarnane plokk-süntaks**, mitte YAML (Promtail kasutas YAML-i). Iga komponent on oma plokk, plokid seotakse `forward_to` viidetega. See on graaf, mitte konveier — saad lisada hargnemisi ja kombineerida allikaid.

```bash
cat > config/config.alloy << 'EOF'
local.file_match "applog" {
  path_targets = [
    {
      __path__ = "/var/log/app/*.log",
      job      = "applog",
    },
  ]
}

loki.source.file "applog" {
  targets    = local.file_match.applog.targets
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
EOF
```

Kolm komponenti, ahela järjekorras:

1. `local.file_match "applog"` — ütleb, millised failid otsida (`/var/log/app/*.log`) ja mis label nende read saavad (`job="applog"`)
2. `loki.source.file "applog"` — **loeb** faile, haldab positsioonide-andmestikku (et restart'i korral mitte kaduma minna) ja tuvastab failide rotatsiooni
3. `loki.write "default"` — saadab read Loki HTTP API-le

`forward_to = [loki.write.default.receiver]` ütleb: "mis siit tuleb, vii sinna". See on koht, kus saaksid tootmises lisada teise `loki.write` (teise Loki-klastri jaoks) või `otelcol.receiver.loki` (OpenTelemetry collector'i jaoks) — üks allikas, kaks sihtkohta.

Lisa `services:` alla:

```yaml
  alloy:
    image: grafana/alloy:v1.15.1
    container_name: alloy
    volumes:
      - ./config/config.alloy:/etc/alloy/config.alloy
      - app-logs:/var/log/app:ro
    command:
      - run
      - /etc/alloy/config.alloy
      - --server.http.listen-addr=0.0.0.0:12345
    ports:
      - "12345:12345"
    depends_on:
      - loki
    restart: unless-stopped
```

Kaks kohta väärib tähelepanu:

- `app-logs:/var/log/app:ro` — **read-only**. Alloy peab ainult lugema, mitte kirjutama. Kui kogemata kirjutaks, läheks positsioonide-andmestik katki.
- **Port 12345** — Alloy sisseehitatud debug UI. Brauseris `http://192.168.35.12X:12345` näed komponentide graafi visuaalselt. See on Alloy oluline eelis Promtail'i ees — silumine ei käi logidest, vaid brauserist.

**Testi kohe:**

```bash
docker compose up -d alloy
sleep 10
docker compose logs alloy | tail -5
```

Alloy logis peab olema `component "loki.source.file.applog" started` ja **mitte ühtki** `error` või `level=error` rida.

💡 **Kui `connection refused` Loki'sse:** Loki pole veel ready. Oota 15s ja `docker restart alloy`. Alloy on Promtail'ist sallivam — jätkab teiste komponentide käivitamist ja proovib Loki'le hiljem uuesti saata.

### 2.4 Grafana — UI ja päringud

**Eesmärk:** Pärast seda lüli sa **näed oma Lokis** logisid Grafanas. Sel hetkel kogu ahel `log-generator → Alloy → Loki → Grafana` töötab.

Grafana on päev 1-st tuttav. Siin on ainult **uus instants** pordil 3001 — et päev 1 Grafanaga (port 3000) konflikti ei oleks, kui mõlemad stackid on üleval.

Lisa `services:` alla:

```yaml
  grafana:
    image: grafana/grafana:12.4.3
    container_name: grafana-loki
    ports:
      - "3001:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=monitoring2026
    volumes:
      - grafana-data:/var/lib/grafana
    restart: unless-stopped
```

```bash
docker compose up -d grafana
```

Brauseris `http://192.168.35.12X:3001`, login `admin` / `monitoring2026`.

**Lisa Loki datasource:**

*Connections → Data sources → Add data source → Loki*  
URL: `http://loki:3100`  
*Save & test* → **roheline ✅**

💡 **Kui datasource on punane:** URL on `http://loki:3100`, **mitte** `http://localhost:3100`. Grafana jookseb konteineris — konteineri jaoks `localhost` on Grafana ise. Loki on teine konteiner, Docker-võrgu DNS-nimi on `loki`. See on **kõige sagedasem esimene viga** Loki datasource'i seadistamisel.

**Esimene päring:**

*Explore* → Data source: Loki → Code view:

```logql
{job="applog"}
```

Run query. Näed ridu tekkimas.

Mis just toimus ahelas:

1. log-generator kirjutas rea faili (`/var/log/app/app.log`)
2. Alloy märkas uut rida (positsioonide-andmestik)
3. Alloy saatis rea HTTP POST-iga Lokisse (`http://loki:3100/loki/api/v1/push`)
4. Loki salvestas chunki + indekseeris labeli `job="applog"`
5. Grafana küsis LogQL päringuga neid read
6. Sa näed ekraanil

Kogu teekond on 1–3 sekundit.

**Ava nüüd ka Alloy debug UI** (`http://192.168.35.12X:12345`) ja vaata komponentide graafi. Näed kõiki kolme plokki omavahel seotuna. Kui tootmises midagi ei tööta, on see esimene koht kuhu vaadata.

💭 **Mõtle:** Kujuta ette, et tootmises on 5 rakendust ja igaühel oma logifail. Kuidas muudaksid Alloy konfiguratsiooni, et kõik viis oleks Lokis eraldi `job` label'iga? Vaata `local.file_match` komponendi plokki — kas kopeeriksid teda 5 korda, või leiaksid mõne parema viisi?

### 2.5 Kontrollpunkt osa 2 lõpus

Enne osa 3-le minekut veendu et:

- [ ] `docker compose ps` näitab nelja konteinerit `Up` (loki, log-generator, alloy, grafana-loki)
- [ ] Grafana datasource Loki on roheline
- [ ] `{job="applog"}` näitab Explore's ridu
- [ ] Alloy debug UI (port 12345) näitab komponentide graafi

Kui miski ei tööta, veaotsingu tabel on labi lõpus.

---

## Osa 3 · Logist metrika + FINAAL

**Eesmärk:** Muudad vabateksti-logi **struktureeritud andmeteks** (pattern parser), sealt **ajas muutuvaks numbriks** (`rate()`), sealt **dashboardi paneeliks**. Finaalis ühendad Zabbixi triggeri Loki graafikuga — kaks perspektiivi ühele sündmusele.

Siiamaani vaatasid logisid kui ridu. See osa näitab Loki **tõelist trumpi** — sama andmetest saab nii otsingu kui metrika. Ilma Lokita oleks sul vaja **kahte** süsteemi (logid + metrikad). Lokiga üks.

### 3.1 Pattern — struktuuri lisamine

**Eesmärk:** Logirida muutub struktuuriks, mida saad filtreerida.

Meie logirida: `2026-04-25T10:23:41+03:00 [ERROR] [payment] duration=245ms trace_id=12345`

Grafana Explore's:

```logql
{job="applog"} | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<_>`
```

Klõpsa rea peal — näed labeleid `level`, `service`, `duration` (`trace_id` jätsime `<_>`-ga välja).

Enne pattern-it oli logi Loki jaoks **üks string**. Pärast on tal struktuur. Järgnevad päringud saavad filtreerida välja järgi, mitte sõne järgi.

### 3.2 Filter pärast pattern-it

**Eesmärk:** Kitsas filtreerimine välja järgi, mitte tekstiotsingu järgi.

```logql
{job="applog"} | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<_>` | level="ERROR" | service="payment"
```

Ainult payment-teenuse error'id. Lisafiltrit saad ketti panna:

```logql
{job="applog"} | pattern `<_> [<level>] [<service>] duration=<duration>ms trace_id=<_>` | service="api" | duration > 300
```

API teenuse aeglased päringud (>300ms), sõltumata level'ist.

**Proovi ise:** kirjuta päring, mis toob välja `cache` teenuse WARN-read, mille `duration < 100`.

### 3.3 Label disain — miks pattern ei tee kõike automaatselt labeliks

**Eesmärk:** Mõistad miks `level` on label, aga `duration` ei tohi olla.

Pattern parsis välja neli välja: `level`, `service`, `duration`, `trace_id`. Aga ainult kaks esimest on **mõistlikud labelid**. Miks?

Loeng §6 selgitas kardinaalsust. Kokkuvõte:

| Väli | Unikaalseid väärtusi | Label-kandidaat? |
|------|---------------------|------------------|
| `level` | 3 (INFO, WARN, ERROR) | ✅ Jah |
| `service` | 5 (payment, auth, api, database, cache) | ✅ Jah |
| `duration` | ~500 erinevat numbrit | ❌ Liiga palju |
| `trace_id` | unikaalne iga rea kohta | ❌ Kardinaalsuse plahvatus |

Reegel: label'iks ainult väljad, mille unikaalsete väärtuste arv on piiratud (kuni ~100). `duration` ja `trace_id` jäävad sisu osaks.

Pattern parser on siin **päringu-aja** tööriist — võtab struktuuri välja käesoleva päringu jaoks. Labelit, mis läheb Loki indeksisse, pattern ei tekita. Nii on see ohutu — saad struktuuri mugavuse ilma indeksi plahvatuseta.

<details>
<summary>🔧 Edasijõudnule: labelid kirjutus-ajal (Alloy <code>loki.process</code>)</summary>

Tootmises, kui teatud väli on **stabiilne ja madala kardinaalsusega** (nt `level`, `service`), on kasulik teha temast **püsiv label** kirjutus-ajal. Siis ei pea iga päring pattern'it kordama ja filter `{level="ERROR"}` kasutab indeksit otse.

Alloy konfis lisad `loki.process` komponendi ahelasse:

```hcl
loki.source.file "applog" {
  targets    = local.file_match.applog.targets
  forward_to = [loki.process.applog.receiver]
}

loki.process "applog" {
  forward_to = [loki.write.default.receiver]

  stage.regex {
    expression = `\[(?P<level>\w+)\] \[(?P<service>\w+)\]`
  }

  stage.labels {
    values = {
      level   = "",
      service = "",
    }
  }
}
```

Nüüd on ahel `source.file → process → write`, mitte `source.file → write`. `stage.regex` leiab `level` ja `service` tekstist, `stage.labels` teeb neist Loki labelid.

Laboris teeme parsimise päringu-ajal (lihtsam ehitada). Tootmises Alloy-kihis (kiiremad päringud, kui teed neid tihti).

</details>

### 3.4 `rate()` — logi muutub metrikaks

**Eesmärk:** Ridade loendamine muutub aegrea graafikuks, mis näeb välja nagu Prometheus.

Siiamaani olid logid **ridade voog**. `rate()` teeb neist **numbrid sekundis**:

```logql
sum by (service) (
  rate(
    {job="applog"}
      | pattern `<_> [<level>] [<service>] <_>`
      | level="ERROR"
      [5m]
  )
)
```

Explore's vali **Time series** view. Näed graafikut — iga teenus oma joonega, X-telg on aeg, Y-telg on ERROR-read sekundis.

Päringu lugemine kihiti (väljastpoolt sisse):

1. `{job="applog"}` — kõik applog-voog
2. `| pattern ...` — lisa struktuur, et saada `level` ja `service`
3. `| level="ERROR"` — ainult ERROR read
4. `[5m]` — vaata ridu viimase 5 minuti akna kohta
5. `rate(...)` — ridu sekundis selles aknas
6. `sum by (service)` — grupeeri teenuse kaupa, liitke

Tulemus on funktsionaalselt identne Prometheus'e `rate(http_errors_total[5m])`-iga. Erinevus: **andmeallikas on logirida**, mitte counter.

See on Loki võti legacy rakenduste juurde, mis ei ekspordi metrikaid, aga logivad tekstina. Vana Java rakendus `catalina.out` failiga? Loki teeb temast metrika.

### 3.5 Dashboard — päringud muutuvad "tooteks"

**Eesmärk:** Salvestatud paneelid, mis avanevad ilma päringut uuesti kirjutamata.

Explore on ad hoc uurimiseks. Dashboard on igapäevatöö.

*Dashboards → New → Add visualization → Loki datasource*:

**Paneel 1 — "ERRORs per service"**. Päring eelmisest sammust (`rate()` + `sum by (service)`). Visualiseering: **Time series**.

**Paneel 2 — "Log volume by level"**:

```logql
sum by (level) (
  count_over_time(
    {job="applog"} | pattern `<_> [<level>] [<_>] <_>` [1m]
  )
)
```

Visualiseering: **Bar chart**.

Miks kaks erinevat funktsiooni (`rate` vs `count_over_time`)?

- `rate()` annab **ridu sekundis** — sujuv graafik, sobib trendide jaoks
- `count_over_time()` annab **ridade koguarvu aknas** — diskreetne number, sobib "viimase minuti jooksul oli 47 ERROR rida" tüüpi vaatesse

Salvesta dashboard nimega `App monitoring`.

### 3.6 FINAAL — üks sündmus, kaks perspektiivi

**Eesmärk:** Tekitad error-tormi, mida **Zabbix näeb triggerina** ja **Loki näeb graafikul** — samal ajal. See on kogu kahe labi mõte kokku pandud.

!!! warning "Tähtis — kaks erinevat logifaili"
    Zabbix agent loeb mon-target'il `/var/log/app/app.log` (päris VM-i fail). Alloy loeb sinu VM-il konteineri volume'i `app-logs` (log-generator'i toodetu). Need on **kaks eraldi faili**. Et mõlemas tekiks torm, tuleb kirjutada mõlemasse. Tootmises oleks üks logifail ja üks agent-ahel kirjutaks ning loeks — labor jätab ehitusblokid eraldi, et saaksid kihte mõista.

Tekita torm korraga mõlemas kohas:

```bash
# 1. Zabbix-pool — mon-target'i päris logifail
ssh <eesnimi>@192.168.35.140 \
  'for i in $(seq 1 200); do echo "$(date -Iseconds) [ERROR] [payment] Spam_$i" | sudo tee -a /var/log/app/app.log > /dev/null; done'

# 2. Loki-pool — log-generator konteineri volume
for i in $(seq 1 200); do
  docker exec log-generator sh -c \
    "echo \"$(date -Iseconds) [ERROR] [payment] Spam_$i\" >> /var/log/app/app.log"
done
```

Ava kaks brauseri tabi:

1. **Zabbix**: `http://192.168.35.12X:8080` → *Monitoring → Problems* → `Too many payment errors` trigger **Firing** (loodi [Zabbix labori osa 5.4-s](zabbix_lab.md#54-item-trigger))
2. **Loki Grafana**: `http://192.168.35.12X:3001` → Dashboard `App monitoring` → payment-rea piik

Sama sündmus, kaks tööriista, kaks perspektiivi:

- **Zabbix ütleb "on probleem"** — trigger läks tulele, tuli ka e-kiri (kui seadistasid Discord-i)
- **Loki näitab "mis juhtus"** — päris logiread, mis põhjustasid triggeri, ajajoonel. Klõpsad panelile ja näed konkreetsed `Spam_1`, `Spam_2` ... read

See on **oluline töövoog tootmises**: alert ei räägi sulle **mida teha**, räägib ainult et midagi on. Logid räägivad mida. Ilma mõlemata on sul kas "hele lamp ilma infota" (ainult alert) või "info ilma alert'ita" (ainult logid — aga keegi ei vaata neid jooksvalt).

💭 **Lõpureflektsioon:** Sul on nüüd kolm tööriista ühes päevas — Prometheus (päev 1: pull-metrikad), Zabbix (päev 2 hommikul: agent + template), Loki (päev 2 pärastlõunal: logid). Võta **üks konkreetne probleem** oma tööst (reaalne süsteem, mida tunned). Kuidas ehitaksid monitooringu nendest kolmest? Kumb on esmane? Mida kummaltki ootad?

---

## ✅ Lõpukontroll

Kui kõik need on märgitud, sa oled labi läbinud:

**Osa 1:**
- [ ] Oskad kirjutada LogQL päringu kõigi nelja parseriga (pattern, json, logfmt, `|=`)
- [ ] Oskad selgitada, millal `|=` on eksitav

**Osa 2:**
- [ ] `docker compose ps` (`~/paev2/loki/`) näitab 4 konteinerit `Up`
- [ ] Grafana Loki datasource roheline
- [ ] `{job="applog"}` näitab logisid Explore's
- [ ] Alloy debug UI näitab komponentide graafi

**Osa 3:**
- [ ] Pattern parser toob logist välja `level`, `service`, `duration`
- [ ] Dashboard `App monitoring` salvestatud, vähemalt 2 paneeli
- [ ] **FINAAL**: sinu error-torm on korraga nähtav Zabbixi *Problems* lehel ja Loki dashboardil

---

## 🚀 Lisaülesanded

Kui jõudsid ette, siin on neli suunda edasi liikumiseks.

### Nginx accesslog + RED meetrika

Lisa `log-generator` konteinerisse nginx-stiilis accesslogi genereerimine. Lisa Alloy konfi teine `local.file_match` ja `loki.source.file` komponent `job="nginx"` jaoks. Ehita RED dashboard:

- **R**ate — päringuid sekundis
- **E**rrors — `status =~ "5.."` rate
- **D**uration — `sum by (path)` kaupa

### Logi-baasil alert

Grafana → *Alerting → Alert rules → New*. Päring: `rate({job="applog"} | pattern ... | level="ERROR" | service="payment" [2m]) > 0.1`. Saada Discord'i (seadistasid Zabbix labori lisaülesandes).

### Metric → log korrelatsioon dashboardil

Dashboardi paneelis *Data links → Add link*. Teeb graafikul klõpsu → avab Explore sama teenuse logides. Üks klõps graafikult konkreetsetesse logiridadesse.

### Multi-source Alloy

Lisa Alloy konfi **teine** `local.file_match` komponent (teine logiallikas, nt `/var/log/nginx/*.log`). Suuna mõlemad sama `loki.write.default`-ile, aga lisa ka **teine** `loki.write` komponent — mis saadaks samad read ka teise sihtkohta (nt faili `/tmp/backup.log` `local.file_output`-ga). Üks allikas, kaks sihtkohta. See on Alloy graaf-struktuuri võti.

---

## 🏢 Enterprise lisateemad

Järgnevad teemad on tootmiskeskkondadele. Igaüks on iseseisev — vali need, mis sinu tööle relevantsed on.

??? note "Loki: retention, multi-tenancy ja S3 salvestus"

    Tootmises ei hoita logisid lõputult kohalikul kettal.

    **Retention (logide eluiga):**

    ```yaml
    limits_config:
      retention_period: 168h    # 7 päeva

    compactor:
      working_directory: /loki/compactor
      retention_enabled: true
      delete_request_store: filesystem
    ```

    **Multi-tenancy (mitme meeskonna logid eraldi):**

    ```yaml
    auth_enabled: true
    ```

    Alloy saadab `X-Scope-OrgID` header'i:

    ```hcl
    loki.write "team_backend" {
      endpoint {
        url = "http://loki:3100/loki/api/v1/push"
        headers = {
          "X-Scope-OrgID" = "team-backend",
        }
      }
    }
    ```

    Grafana datasource'is: HTTP Headers → `X-Scope-OrgID: team-backend`. Iga meeskond näeb ainult oma logisid.

    **S3/MinIO salvestus:**

    ```yaml
    common:
      storage:
        s3:
          endpoint: minio:9000
          bucketnames: loki-chunks
          access_key_id: minioadmin
          secret_access_key: minioadmin
          insecure: true
          s3forcepathstyle: true
    ```

    **Loe edasi:**

    - [Loki retention](https://grafana.com/docs/loki/latest/operations/storage/retention/)
    - [Multi-tenancy](https://grafana.com/docs/loki/latest/operations/multi-tenancy/)
    - [S3 storage](https://grafana.com/docs/loki/latest/storage/)

??? note "Alloy: OpenTelemetry, traces ja mõõdikud samas agendis"

    Laboris kasutasime Alloy'd ainult logide jaoks. Alloy oskab kolme sammast (logid, meetrikad, traces) korraga.

    **Meetrikad Prometheusele:**

    ```hcl
    prometheus.scrape "node" {
      targets = [
        {__address__ = "mon-target:9100"},
      ]
      forward_to = [prometheus.remote_write.default.receiver]
    }

    prometheus.remote_write "default" {
      endpoint {
        url = "http://prometheus:9090/api/v1/write"
      }
    }
    ```

    **OTel traces vastuvõtt ja Tempo saatmine:**

    ```hcl
    otelcol.receiver.otlp "default" {
      grpc { endpoint = "0.0.0.0:4317" }
      http { endpoint = "0.0.0.0:4318" }

      output {
        traces = [otelcol.exporter.otlp.tempo.input]
      }
    }

    otelcol.exporter.otlp "tempo" {
      client {
        endpoint = "tempo:4317"
        tls { insecure = true }
      }
    }
    ```

    Üks Alloy-konteiner ehitab terve LGTM-pinu kirjutuspoole. Kolm eraldi agenti (Promtail + node_exporter + otel-collector) asendatud ühega.

    **Loe edasi:**

    - [Alloy komponentide nimekiri](https://grafana.com/docs/alloy/latest/reference/components/)
    - [OpenTelemetry Alloy's](https://grafana.com/docs/alloy/latest/collect/opentelemetry-to-lgtm-stack/)
    - [Migreerimine Promtail'ist](https://grafana.com/docs/alloy/latest/tasks/migrate/from-promtail/)

---

<details>
<summary><strong>Veaotsing + allikad (peida/ava)</strong></summary>

## Veaotsing

| Probleem | Esimene kontroll |
|----------|------------------|
| `curl /ready` ei anna `ready` | Oota 15s, Loki init. Kui jätkub — `docker compose logs loki` |
| Alloy `connection refused` Lokisse | Loki pole ready — `docker restart alloy` |
| Alloy komponendid "unhealthy" | Ava debug UI port 12345 — vea tekst on seal |
| Grafana Loki datasource punane | URL peab olema `http://loki:3100`, **mitte** `localhost` |
| Explore tühi — `{job="applog"}` ei näita midagi | 1) `docker exec log-generator tail -3 /var/log/app/app.log` — kas fail kasvab? 2) Alloy debug UI — kas komponendid rohelised? |
| `rate()` tagastab 0 | Time range liiga kitsas — vali "Last 15 min" |
| Mõlemad stackid aeglased | `free -h` — 4GB piir. Peata üks ajutiselt. |
| Alloy ei loe logifaile | `docker logs alloy` — permission? `app-logs:/var/log/app:ro` mount OK? |
| FINAAL: Zabbix firing, Loki ei näita | Unustasid teise `docker exec log-generator` käsu. Vaata osa 3.6. |

## 📚 Allikad

| Allikas | URL |
|---------|-----|
| Loki dokumentatsioon | [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/) |
| LogQL spetsifikatsioon | [grafana.com/.../query](https://grafana.com/docs/loki/latest/query/) |
| Pattern parser | [grafana.com/.../pattern](https://grafana.com/docs/loki/latest/query/log_queries/#pattern) |
| LogQL simulaator | [grafana.com/.../analyzer](https://grafana.com/docs/loki/latest/query/analyzer/) |
| Grafana Alloy | [grafana.com/docs/alloy](https://grafana.com/docs/alloy/latest/) |
| Labelite parimad tavad | [grafana.com/.../labels](https://grafana.com/docs/loki/latest/get-started/labels/) |

**Versioonid:** Loki 3.7.1, Alloy 1.15.1, Grafana 12.4.3.

</details>

--8<-- "_snippets/abbr.md"
