# Päev 2: Zabbix — kõik-ühes seiresüsteem

**Kestus:** ~2,5 tundi iseseisvat lugemist  
**Eeldused:** [Päev 1: Prometheus + Grafana](paev1-loeng.md) loetud, Linux CLI põhitõed, võrgunduse alused  
**Versioonid laboris:** Zabbix 7.0.6 LTS, MySQL 8.0, Zabbix agent 2 (7.0+)  
**Viited:** [zabbix.com/documentation/7.0](https://www.zabbix.com/documentation/7.0/en/manual) · [Zabbix 8.0 roadmap](https://www.zabbix.com/roadmap) · [Performance tuning](https://www.zabbix.com/documentation/current/en/manual/appendix/performance_tuning)

---

## Õpiväljundid

Pärast selle materjali läbitöötamist osaleja:

1. **Selgitab** Zabbixi arhitektuuri — server, agent, frontend, DB, proksi — ja iga komponendi vastutusala
2. **Eristab** Host, Item, Trigger ja Action mõisteid ning näeb kuidas need matrjoškana üksteist ehitavad
3. **Valib** aktiivse ja passiivse agendi vahel ning põhjendab valikut itemi tüübi ja tulemüüri kontekstist
4. **Selgitab** History ja Trends vahet ning mõistab miks History=0 tähendab triggerite kadumist
5. **Teostab** NVPS-põhiseid mahuarvutusi ja hindab andmebaasi suurust ette
6. **Kirjeldab** housekeeperi töö, selle piiranguid ja partitsioneerimise rolli suurtes süsteemides
7. **Analüüsib** proksi rolli, Zabbix 7.0+ proxy gruppe ning HA klastri toimimist ja piiranguid
8. **Seostab** Zabbix 8 põhimuudatusi (OTel, log-observability, ClickHouse) laiema vaatluse (observability) liikumisega

---

## 1. Miks Zabbix?

Eile vaatasime Prometheust — moodsa cloud-native maailma meetrikakogujat. Pull-mudel, deklaratiivne konfiguratsioon koodifailides, Kubernetes-esimene mõtteviis. Täna oleme teisel pool spektrit.

Zabbix sündis 1998. aastal Läti Ülikoolis Alexei Vladišev'i diplomitööna. Esimene avalik versioon ilmus 2001. Rohkem kui 25 aastat ajalugu — mitte tähenduses "aegunud", pigem tähenduses "käinud läbi sada tootmiskeskkonda ja õppinud hakkama saama kõige imelikuma reaalsusega". Zabbix on klassikaline kõikehõlmav monitooringutööriist. Agendid, SNMP, IPMI, JMX, VMware, SQL, ICMP, SSH, Telnet, HTTP — ühest kohast konfigureerid kogu ettevõtte ja lõpuks on kõik silmade all.

Eestis on Zabbix laialt kasutuses. Telia, Swedbank, maksu- ja tolliamet, enamus riigiasutusi, ülikoolid — kus tahes vaatad, seal ta on. Kuna Zabbix on open-source koos enterprise-tasemel kvaliteediga ja Läti päritolu (seega lokaalne tugi), on ta Baltikumis kodus nagu kala vees.

**Zabbix vs Prometheus** — mõlemad on head tööriistad, aga erinevate ülesannete jaoks:

| Aspekt | Zabbix | Prometheus |
|--------|--------|------------|
| Paradigma | Push ja pull (mõlemad) | Pull |
| Konfig | Frontend/DB (klik-klõps) | YAML failid (koodina) |
| Andmemudel | Klassikaline relatsioonne DB | Aegridade TSDB |
| Tugev külg | Infrastruktuur, mitut protokolli | Mikroteenused, service discovery |
| Päringukeel | Triggeri funktsioonid | PromQL |
| HA | Alates 6.0 natiivne | Föderatsioon + Thanos/Mimir |
| Agendid | Kõik-ühes paketid | Per-teenus exporterid |

Reaalses maailmas kasutatakse sageli *mõlemaid*. Zabbix teenindab traditsioonilise IT-infra nõuded — võrguseadmed, virtualisatsioon, fileserverid, UPS-id, printerid. Prometheus tegeleb konteinerplatvormidega. Mõlemad voolavad Grafanasse ja keegi ei peagi valima.

---

## 2. Arhitektuur — neli komponenti

Zabbixi süda koosneb neljast osast. Igaüks vastab ühe lihtsa küsimuse eest.

**Zabbix Server** on aju. Võtab vastu andmeid, hindab triggereid, genereerib probleeme, saadab hoiatusi. Kirjutatud C-s, jookseb Linuxi teenusena. Üks protsess aga mitu lõime — pollerid, trapperid, housekeeper, alerter, igaüks oma tööga.

**Zabbix Database** on mälu. Tavaliselt MySQL/MariaDB või PostgreSQL. Siin on *kõik* — nii konfiguratsioon (millised hostid on jälgitud, millised triggerid kehtivad) kui ka ajalooandmed. See on ühtlasi Zabbixi peamine pudelikael. Kui jätate tänasest ühe asja meelde, siis see: **Zabbixi jõudlusprobleemid lahendatakse 90% ulatuses andmebaasi tasemel.**

**Zabbix Frontend** on nägu. PHP-põhine veebiliides, tavaliselt Apache või Nginx taga. Räägib sama DB-ga, mis server. Kasutaja klikib siin — serveriga ei tohi segi ajada.

**Zabbix Agent** on käed ja jalad. Jookseb iga jälgitava masina peal, kogub andmeid lokaalsest süsteemist ja saadab serverile. Kaks paralleelset versiooni on elus — **Agent 1** (C-s kirjutatud, stabiilne klassika) ja **Agent 2** (Go-s kirjutatud, uus, moodulitega). Tootmises kohtad mõlemaid.

Viies komponent — **Zabbix Proxy** — tuleb mängu, kui on vaja jälgida asju kaugvõrgus, piiratud internetiühendusega harukontorites või serverit koormuse alt välja võtta. Proksi kogub andmeid kohapeal, puhverdab neid vajadusel ja saadab serverile edasi. Proksist rohkem peatselt.

Kriitiline punkt: **Zabbix Server ja DB on tihedalt seotud**. Kui DB jääb hätta, kukub server. Kui server kogub 1000 väärtust sekundis ja DB suudab kirjutada 500 — mahajäämus kasvab, järjekorrad täituvad, andmeid läheb kaduma. Suurem osa Zabbixi häälestamisest ongi tegelikult *andmebaasi* häälestamine.

---

## 3. Andmemudel: Host → Item → Trigger → Action

Zabbixi kogu maailm tugineb neljale kontseptsioonile. Need on nagu matrjoškad — üks on teise sees.

**Host** on "asi mida jälgitakse". Linuxi server, Cisco switch, MikroTik ruuter, VMware ESXi host, MySQL andmebaas, Docker konteineri node — kõik need on hostid. Hostil on IP-aadress, agendiport(id) ja üks või mitu template'i.

**Item** on üks konkreetne mõõtmine sellel hostil. Näiteks `system.cpu.load[all,avg1]` küsib Linuxi load average-i. `net.if.in[eth0]` jälgib võrguliidese sissetulevat liiklust. Üks host sisaldab tüüpiliselt sadu iteme — Linuxi standardtemplate annab ~60 iteme ilma, et sa midagi kirjutaks.

**Trigger** on tingimus, mis kontrollib itemi väärtusi. Näiteks *"kui viimane CPU load ületab 5, siis tõsta häire"*. Kui tingimus täidetakse, trigger "fires" ja tekib **Problem**. Triggerite prioriteedid: `Not classified`, `Information`, `Warning`, `Average`, `High`, `Disaster` — värvid paistavad frontendis kohe silma.

**Action** on see, mis juhtub probleemi tekkimisel. Email, SMS, Slack, webhook, skriptide käivitamine. Actionite kirjeldamine võib olla üsna nüansirikas — reegel stiilis *"saada CTO-le SMS ainult siis kui disaster-probleem kestab üle 10 minuti ja keegi pole seda acknowledge-inud"* on päris tavaline.

Üks pedagoogiline hoiatus enne laborisse minekut. Zabbix 7.0 frontendis on triggerite loomise rada selline: **Data collection → Hosts → leia host → kliki "Triggers" *lingil* (mitte hosti nimel!) → Create trigger**. Kliki hosti *nimel* ja satud hosti settingute redigeerimisse, mitte triggeritele. See on klassikaline komistuskivi — tuletame laboris iseendale mitu korda meelde.

**Template** on juurkontseptsioon, ilma milleta on Zabbix kasutu. Selle asemel, et 500 serveril kõik itemid ükshaaval luua, teed ühe template'i ("Linux by Zabbix agent") ja rakendad 500-le hostile. Muudad template'it — muutused levivad kõigile. Hiiglastes ettevõtetes on template hierarhia mitmekihiline: baas-template + keskkonna-kiht + rolli-kiht + rakenduse-kiht.

---

## 4. Agendid: aktiivne vs passiivne

Eile vaatasime pull-mudelit Prometheuse juures. Zabbix agent toetab mõlemat stiili — ja tootmises kasutatakse sageli korraga mõlemat.

**Passiivne agent** on Zabbixi vaikimisi režiim. Server küsib, agent vastab. See on nagu pull. Eelis tulemüüride seisukohast on lihtne — ainult serveri IP peab saama agendini jõuda, ühes suunas. Probleem on server: tuhande masina küsitlemisel iga paari sekundi järel tekib märgatav overhead.

**Aktiivne agent** töötab vastupidi — agent saadab andmed ise serverile. Esmalt küsib agent serverilt "mida ma pean jälgima" (active check'ide nimekirja), ja siis saadab tulemusi regulaarselt. See on nagu push. Eelis on skaleeruvus — tuhanded agendid edastavad serverile ilma, et server peaks igaühe uksele koputama. Probleem: agent peab serveri IP-ni jõudma (tulemüüri teisele poole), ja kui võrgus on NAT või proksid vahel, on seadistamine keerulisem.

Reaalne valik sõltub itemi tüübist. Madala sagedusega itemid (kettaruum kord tunnis) on tihti passiivsed. Kõrge sagedusega itemid (CPU iga 30 sekundit) on sageli aktiivsed. **Log-failide monitoorimine on alati aktiivne** — passiivne režiim ei toeta log-tail'i üldse.

Oluline piirang edasiseks: Zabbix 7.0+ proksi gruppide kasutamisel on **aktiivne režiim ainus valik**.

---

## 5. History vs Trends — andmete elutsükkel

See on kõige olulisem kontseptsioon, mida tootmiskeskkondades ebakogenud administraatorid tihti ei mõista. Seetõttu läheme aeglaselt.

### Kaks mälu tüüpi

Zabbixil on kaks eraldiseisvat salvestustasandit, mis töötavad eri loogikaga.

**History** on lühiajaline mälu. Iga kogutud väärtus salvestatakse toorkujul. Kui agent saadab CPU load iga 60 sekundi järel, siis history-tabelis on iga 60 sekundi kohta üks rida. See on peen graanulsus — CPU spike kell 14:23:15 on täpselt näha, koos ajatempli ja väärtusega.

**Trends** on pikaajaline mälu. Summeeritud statistika. Iga tunni, iga itemi kohta on *neli* arvu: `min`, `max`, `avg` ja `count`. Üks rida tunnis. See on jäme graanulsus — CPU spike kell 14:23:15 kaob, näed vaid et kella 14:00 ja 15:00 vahel oli maksimum 95%.

### Miks see vahe kriitiline on

Kui organisatsioon hoiab kõike History-na ja pikalt, siis ketta I/O kasvab plahvatuslikult (iga väärtus on DB kirjutamisoperatsioon), DB maht ulatub miljardiastmetesse (varukoopiad muutuvad praktiliselt võimatuks), ja päringud aeglustuvad nii, et graafikud võtavad mitu minutit laadida.

Teises äärmuses — kui hoiad ainult trendi ja paned History=0 — juhtub midagi palju hullemat: **triggerid lõpetavad töötamise**. See on kriitiline punkt. Zabbix hindab triggeri funktsioone (last, avg, max jne) ainult History-põhiselt. History=0 → pole millegi pealt triggerdada. Süsteem kogub aja-andmeid, ei genereeri ühtki hoiatust. See on üks kogenematu administraatori klassikaline viga — taheti "DB-d säästa", saadi süsteem, mis näeb midagi aga ei ütle midagi.

Tootmises tüüpilised väärtused:
- **History**: 7-14 päeva (operatiivseks vaatluseks ja triggerite jaoks)
- **Trends**: 1-5 aastat (mahtude planeerimiseks, SLA-raportiteks, aastaaruanneteks)

### Üks konkreetne nüanss — ümardamine

Trendide keskmise arvutamisel *täisarvuliste* (unsigned) itemite puhul **ümardatakse tulemus alati allapoole**. Kui tunni jooksul on CPU väärtused 0 ja 1, siis trends-is on keskmine 0, mitte 0,5. Ühelt poolt loogiline (täisarv on täisarv). Teiselt poolt halb üllatus, kui sa seda ei tea ja imestad miks aastaraport näitab, et midagi "ei olnudki". Float-tüüpi itemite puhul seda probleemi pole.

### NVPS ja andmemahu planeerimine

Tark administraator arvutab DB suuruse ette, mitte ei avasta pärast, et ketas on täis. Näide:

- 3000 itemi
- Iga item uueneb iga 60 sekundi järel
- **NVPS = 3000 / 60 = 50 väärtust sekundis**

Numbrilise andmetüübi maht on ligikaudu 90 baiti punkti kohta. History 30 päeva jaoks:

```
50 × 3600 × 24 × 30 × 90 ≈ 10,9 GB
```

Trendide maht 5 aasta jaoks (iga tund × iga item × üks rida):

```
3000 × 24 × 365 × 5 × 90 ≈ 11,8 GB
```

**Tekst ja logid maksavad ~500 baiti punkti kohta** — umbes 5-6 korda rohkem kui numbrid. Ja logidele trendi *ei arvutata* — seega logide säilitamiseks on ainus hoob History säilitusperiood. Rusikareegel: pane numbreid igasse nurka, logisid ainult seal kus hädapärast vajalikud.

### Housekeeper ja selle piirid

Zabbix server püüab regulaarselt vanu ridu kustutada — seda teeb sisseehitatud **housekeeper**. See jookseb DB-s rida-realt, kustutades ükshaaval.

Housekeeper töötab hästi — väikestes süsteemides. Kuni umbes 500 NVPS-ni. Üle selle muutub housekeeper kogu süsteemi pudelikaelaks. Miks? Sest rida-realt kustutamine on DB jaoks kallis — läheb läbi indeksid, logib iga kustutamise, fragmenteerib tabeli. Kui kustutada tuleb 10 miljonit rida, on kogu DB hõivatud kustutamisega, ja uusi andmeid ei jõua samal ajal kirjutada. Tekib "100% CPU loop" — housekeeper ei jõua uute andmete pealevooluga sammu pidada.

Lahendus on **tabelite partitsioneerimine**. Jagad history- ja trends-tabelid päevade või kuude põhisteks partitsioonideks. Vanade andmete kustutamine tähendab siis terve partitsiooni kukutamist — üks käsk, sekundijagu aega, ei puuduta ülejäänud andmeid. See on suurte süsteemide standard: partisjoneerimine sisse, housekeeper välja.

**TimescaleDB** on PostgreSQL-i laiendus, mis teeb partitsioneerimise automaatselt ja lisab kompressiooni. Zabbix 5.0+ toetab seda ametlikult. Kui alustad uut paigaldust ja tead, et see kasvab suureks — TimescaleDB on sageli parem valik kui klassikaline MySQL/MariaDB.

---

## 6. Performance — andmebaas on kuningas

Zabbixi jõudlusprobleemid lahendatakse ülekaalukalt andmebaasi tasemel. Siin on asjad, mida peab teadma juba enne esimese Zabbixi püsti panekut.

### Riistvara: SSD on vältimatu

Üks arv tasub meeles pidada: **Enterprise SSD teeb 15 000+ IOPS juhuslikuks lugemiseks, SAS 15K RPM ketas umbes 250, SATA 7200 RPM ~100**. See tähendab, et sama päringu jaoks (näiteks 6-kuu graafiku genereerimine) vajab SSD umbes 1 sekundi, pöörlev ketas 60. Kui NVPS ületab 500-1000, siis SSD pole luksus — see on ainus, mis päästab süsteemi.

RAM-i osas: DB server vajab piisavalt mälu, et indeksid ja kuumandmed mahuks sisse. Liiga väike mälu sunnib DB-d kettale minema — isegi SSD puhul on see 100x aeglasem kui RAM. Tootmises tüüpiline rusikareegel: DB buffer pool ~75% süsteemi RAM-ist (eraldi DB serveri korral).

| Suurus | Seadmed | NVPS | CPU | RAM | DB soovitus |
|--------|---------|------|-----|-----|-------------|
| Väike | <100 | <50 | 2 | 2 GB | MySQL lokaalselt |
| Keskmine | 500 | 500 | 4 | 8 GB | MySQL InnoDB SSD |
| Suur | >1000 | >1000 | 8 | 16-32 GB | RAID10 SSD, eraldi DB server |
| Väga suur | >10000 | >10000 | 16+ | 64+ GB | NVMe RAID, klaster |

### Mida andmebaasi juures häälestada

Detailid kuuluvad paigalduse juhendisse, aga kontseptuaalselt on kolm-neli asja, mida iga tootmise Zabbixi DB juures peab vaatama:

- **Buffer pool** suurus (RAM-i osa, mis hoiab indekseid ja kuumandmeid) — liiga väike tähendab pidevalt kettale pöördumist
- **Kirjutamise sünkroniseerimine** — vaikimisi teeb DB iga tehingu kohta ketta-flushi, mis on aeglane. Zabbixi tööle on aktsepteeritav nõrgem garantii (1 sekundi andmekadu crashi puhul) ja 3-5x kiirem kirjutamine
- **I/O võimekuse parameeter** — ütleb DB-le, kui palju IOPS-i ta võib eeldada (SSD vs HDD puhul täiesti erinev)
- **Logifaili suurus** — peab mahutama vähemalt 1-2 tunni kirjutamisandmed

Kõik need parameetrid on konkreetsete arvudega laboris ja paigaldusjuhendis. Loengus piisab kontseptsiooni mõistmisest.

### Serveri häälestus

`zabbix_server.conf` sisaldab palju konfigureeritavaid protsesse (pollerid, trapperid, history syncerid, pingerid). Üldreegel: **ärge suurendage neid suvaliselt**. Iga lisaprotsess on DB ühendus ja overhead.

Õige lähenemine on diagnostikatsükkel: vaata järjekordade pikkust, vaata protsesside hõivatust. Kui järjekord kasvab pidevalt ja vastav protsess on üle 75% hõivatud — alles siis suurenda. Enne seda on probleem kas DB-s või itemide kogusel. Zabbixi sisemised itemid näitavad seda kohe — nendest räägime peatükis 8.

---

## 7. Skaleerimine: proksid ja HA

Kui üks Zabbix server ei jõua enam kõike kaasa teha, on kaks teed edasi: **proksid** (horisontaalne koormuse jagamine) või **HA klaster** (serveri rikkekindlus). Tootmises on sageli mõlemad korraga.

### Proksi klassikaliselt

Proksi on vahemehhanism — kogub andmeid oma piirkonnast, puhverdab neid kohalikus väikeses DB-s (SQLite või MySQL) ja edastab serverile. Kasulik kolmes tüüpilises olukorras.

Esimene: **geograafiline hajumine**. Tallinna server, proksi Tokyos. Ilma prokseta küsiks server iga 60 sekundi järel sadade Tokyos asuvate masinate käest andmeid üle ookeani. Prokseta: proksi küsib lokaalselt, saadab serverile tihendatud kogumeid.

Teine: **tulemüüriga segmendid**. DMZ-s on 50 seadet, üks proksi pääseb neile, server ei pea üldse DMZ-sse reeglit avama.

Kolmas: **serveri koormuse vähendamine**. 10 000 host ühe serveriga on piiripealne. Jagatud prokside vahel — lihtne.

Proksi ei tee triggerite hindamist — see jääb alati serveri töö. Proksi ainult kogub ja edastab.

### Proxy groups (Zabbix 7.0+)

Zabbix 7.0 tuli välja 2024 ja tõi revolutsiooni — **proksigrupid**. Mitu proksit grupina, koormus jaotub automaatselt, rike tähendab automaatset failoverit. Enne seda pidi proksi HA-d ehitama keerukate välistöövahenditega (Corosync/Pacemaker) — nüüd on see sisseehitatud.

**Koormuse jaotamise loogika** on kahetingimuslik. Zabbix server jaotab hoste ümber ainult siis, kui ühe proksi hostide arv erineb grupi keskmisest vähemalt 10 hosti võrra **JA** faktoriga vähemalt 2x. See topeltlävi on tahtlik — süsteem ei hakka iga väikese muudatuse peale hoste ümber asetama, mis tekitaks tarbetut overheadi.

Näide: grupi keskmine on 5 hosti proksi kohta, ühel proksil 15 — vahe 10 (täidab tingimuse), 15 on 3x suurem kui 5 (täidab faktori). Jaotatakse ümber. Kui aga keskmine on 50 ja ühel proksil 60 — vahe 10, aga faktor ainult 1,2x. Jätame rahule.

**Failover mehhanism.** Proksid saadavad serverile heartbeat-i regulaarse intervalliga (vaikimisi iga minut). Korrektne peatumine → teavitab serverit → hostid jaotatakse kohe ümber. Ootamatu rike → oodatakse failover-perioodi, seejärel kuulutatakse kättesaamatuks. Põhjalik ümberjagamine käivitub alles pärast 10-kordset failover-perioodi, et lühiajaline võrguhäire ei tekitaks massiivset rapsimist.

**Olulised piirangud proxy groupide kasutamisel:**

- **SNMP Trappe ei toetata.** Kui keskkond sõltub SNMP trapidest (näiteks võrguseadmete alarmid), jäta need seadmed tavalisele, grupi välisele proksile
- **Ainult Zabbix Agent 7.0+** töötab proxy groupidega aktiivses režiimis. Vanad agendid ei suuda dünaamiliselt liikuva proksiga suhelda
- **Tulemüür peab lubama agendi → kõik grupi proksid.** Failover-i ajal suunatakse agent teisele proksile. Kui tulemüür ainult ühte ust avab, jääb agent failover-i ajal ripakile
- **Välised skriptid** tuleb käsitsi kopeerida kõigile grupi proksidele identselt
- **VMware monitooringu juures ettevaatust.** Iga grupi proksi peab puhverdama KOGU vCenter'i andmestiku, mis võib vCenterit päringutega üle koormata

### Zabbix Server HA (alates 6.0)

Enne 6.0 pidi HA tegema välise tarkvaraga (Corosync/Pacemaker) — keeruline ja vigaderohke. Alates 6.0 on see sisseehitatud.

Põhimõte on lihtne: mitu Zabbix server protsessi jagavad sama andmebaasi ja saadavad DB-sse "heartbeat"-i iga 5 sekundi järel. Ainult üks on korraga **Active**, ülejäänud on **Standby**. Kui aktiivne lakkab heartbeat-i saatmast, võtab Standby üle.

Üks praktiline nüanss tuleb siin mainida, sest see tüütab paljusid esimesel HA seadistamisel: **frontend tuleb seadistada nii, et see tuvastab aktiivse sõlme dünaamiliselt DB kaudu**, mitte ei osuta fikseeritud IP-le. Kui jätad frontendis ühe serveri IP kõvasti sisse, siis failover-i ajal kaob ka frontend koos ripakile jääva sõlmega. Levinuim HA-seadistuse komistuskivi.

### Andmebaasi HA

Kui Zabbix serveri HA on olemas, aga DB on ühel masinal — pole HA-d. DB on SPOF. MariaDB Galera Cluster või PostgreSQL-i replikatsioon (patroni, repmgr) on standardvastused. Detaile ei lähe siin sügavamale — enamik osalejaid ei hakka DB-klastreid igapäevaselt püstitama. Peamine põhimõte: tõsiseltvõetava HA-paigalduse puhul peab DB kiht olema samuti kõrgkäideldav.

---

## 8. Sisemine diagnostika

Zabbixi oluline omadus: **ta monitoorib iseennast**. On terve hulk sisemisi iteme (internal items), mis näitavad serveri enda olekut reaalajas. Kui Zabbix töötab halvasti, on see esimene koht kust vaatama hakata.

Kolm kõige tähtsamat:

- **`zabbix[queue]`** näitab järjekorras ootavate kontrollide arvu. Peaks olema null. Kui see kasvab pidevalt, sul on andmete viivitus
- **`zabbix[process,<tüüp>,avg,busy]`** näitab konkreetse protsessi (poller, trapper, history syncer) hõivatust protsentides. Üle 75% pidevalt tähendab, et on aeg suurendada
- **`zabbix[wcache,values,all]`** näitab reaalselt saabuvat NVPS-i — kas see vastab sinu plaanile või on midagi oodatust rohkem/vähem

Tee neist eraldi dashboard — **monitori monitori**. Kui keegi küsib "Zabbix on aeglane", annab see dashboard vastuse 10 sekundiga.

---

## 9. Zabbix 8 — kuhu minnakse

Täna kasutad tõenäoliselt Zabbix 7.0 LTS-i, mis ilmus 2024. aasta juunis. Aga tasub teada, mis tuleb, sest **Zabbix 8.0 LTS ilmub sel aastal** (alfa versioon oktoobris 2025, stabiilne 2026 jooksul) ja see ei ole tavaline versiooniuuendus.

Zabbix 8 filosoofia on üleminek "monitooringult" → "täielikule vaatlusele" (observability). Alexei Vladišev on ise öelnud: see on liikumine reaktiivselt seirelt proaktiivsele mõistmisele. See seob Zabbixi otseselt samasse maailma, kus on Prometheus + Grafana + Tempo + Loki, DataDog, Splunk — kogu kursuse teine pool. Seega mõned ideed, mida täna Zabbixi kontekstis puudutame, tulevad nädalate pärast uuesti teiste tööriistade juures tagasi.

### OpenTelemetry natiivne integratsioon

See on **suurim uuendus**. OpenTelemetry (OTel) on avatud standard vaatlusandmete — meetrikate, logide ja jälituste — kogumiseks ja ülekandeks. Tänapäeval on see de facto standard mikroteenuste maailmas. Prometheus, Grafana, Jaeger, Tempo — kõik toetavad seda.

Zabbix 8 hakkab OpenTelemetry andmeid koguma, salvestama ja visualiseerima natiivselt. See tähendab, et sama Zabbix, mis täna jälgib võrguswitche ja UPS-e, saab jälgida ka Kubernetese mikroteenuste jälitusi. Üks tool, üks konfiguratsioon, terve pilt. Day 5 juures vaatame OTel-it eraldi — siis saab see selgemaks.

### Log-based observability

Zabbix 8 analüüsib logisid reaalajas ja **korreleerib neid meetrikatega**. Näiteks: protsessori spike 14:23 + samal hetkel tekkinud NullPointerException logides + aeglane päring DB-s — süsteem näitab need kokku ühel ajateljel. See on territoorium, mida seni on domineerinud Splunk ja Datadog — Zabbix tuleb sinna tasuta ja avatud lähtekoodiga.

### Uued andmehoidlad — ClickHouse ja JSON

Üks suur tehniline samm on **ClickHouse** kui valikuline backend ajaloo jaoks. ClickHouse on kolonn-orienteeritud analüütiline DB, mis on kiirem aegridade ja logide analüütiliste päringute puhul kui klassikaline PostgreSQL või MySQL. Sarnane roll, mis on Elasticsearchil juba 7.0-s, aga ClickHouse on mõõdetult kiirem suurtele mahtudele.

Samas lisandub **JSON andmetüüp** — võimalus salvestada struktureeritud andmeid natiivselt, ilma et peaks neid tekstiks flatteneerima. See on kasulik, kui kogud näiteks REST API vastuseid (Kubernetese pod'i olek, pilve resource'i metadata) ja tahad neist hiljem konkreetseid välju välja tõmmata.

### Scatter Plot widget — seoste avastamine

Hajusdiagramm on uus dashboard-widget, mis kuvab **kahe meetriku seost**. Üks meetrik X-teljel, teine Y-teljel, iga host/ajahetk on üks punkt. Selle jõud on mustrituvastuses: inimaju leiab visuaalselt klastreid ja anomaaliaid sekunditega, tekstiliste logide lugemisel oleks see tunde kestev protsess.

Mõned praktilised näited, mis sobivad osalejatega arutamiseks:

| Stsenaarium | X-telg vs Y-telg | Mida näed |
|-------------|------------------|-----------|
| CPU vs Mälu | CPU koormus vs RAM kasutus | Kas server on "CPU-piiratud" või "RAM-piiratud" |
| Ketas vs latentsus | Ketta kasutus % vs I/O latentsus ms | Ülekoormatud salvestusega serverid |
| Võrk vs vead | Võrguliiklus (bps) vs vigade arv | Vigased kaablid või draiveri probleemid (madal liiklus + kõrge viga) |
| Kiirus vs saadavus | Vastamisaeg vs saadavus % | "Aeglased aga stabiilsed" vs ebakindlad teenused |

Scatter plot toetab ka kombineeritud lävendväärtusi — näiteks "kui X ≥ 80 ja Y ≥ 200, värvi punkt punaseks". Kriitilised hälbed muutuvad visuaalselt karjuvaks.

### GeoMap klasterdamine

Geograafiliselt hajutatud süsteemide haldamisel on peamine probleem **visuaalne müra**. Zabbix 8 lisab GeoMap widget'ile **"Zoom level"** valiku — saad määrata suumitaseme, millest allpool klastrid lagunevad eraldi punktideks. Ettevõtte tasandi vaade jääb puhtaks, detailid ilmuvad alles siis, kui suumid sisse. See on väike UI-parendus, aga suurte taristutega tiimidele kullakaaluga.

### Pärilikud sildid (inherited tags) visuaalse indikaatoriga

Sildid on Zabbixis alati olnud tähtsad filtreerimiseks ja grupeerimiseks. Zabbix 8 lisab UI-sse **lehe/dokumendi ikooni**, mis näitab et silt on pärilik — pärineb template'ist, mitte hostilt endalt. Ikoonita sildid on käsitsi lisatud hosti-spetsiifilised.

See on triaaži jaoks väärtuslik: näed kohe, kas probleem on ühes seadmes või laiemalt kogu mallis ehk sadades seadmetes korraga. Täpselt seda infot vajad esimesena õnnetuse ajal.

### Ülejäänud olulised muudatused

- **NetFlow kogumine + visualiseerimine** — Zabbix astub ametlikult NPMD (Network Performance Monitoring and Diagnostics) kategooriasse
- **Automaatne võrgutopoloogia avastamine** ilma konfiguratsioonita
- **Complex Event Processing (CEP)** mootor — keerukamad sündmuste reeglid ja korrelatsioonid
- **Ametlik mobiilirakendus** (iOS + Android) — push-notifications, probleemide haldus telefonist
- **Inline validation ja UI parendused** — vähem klikke, kiirem frontend
- **Proxy ja proxy group permissions** — granulaarsem juurdepääsukontroll: kes mida näha võib

### Mida see kursuse mõttes tähendab

Zabbix 8 ei ole lihtsalt "Zabbix+1". See paneb Zabbixi otseselt konkurentsi kommertsplatvormidega nagu Splunk, Datadog, New Relic — aga avatud lähtekoodiga. Ja veelgi olulisem — see toob Zabbixi samasse maailma, kus on ülejäänud kaasaegne vaatlemise stack, mida me järgmistel päevadel vaatame. Loki logid, Tempo trace'id, OTel kollektor — kõik see hakkab ka Zabbixiga rääkima.

Traditsioonilist IT-d jälgivad asutused ei pea valima "vana Zabbix vs uus kuum tool". Valik kaob.

---

## 11. Kokkuvõte

Zabbix on suur süsteem, täna puudutasime pinda. Enne laborisse minekut jäta meelde viis asja:

**Host → Item → Trigger → Action on kogu kontseptsioon.** Kõik muu on nende variandid. Template on viies element, mis hoiab asja hallatavaks.

**History hoiab toorandmeid, Trends hoiab tunnipõhise statistika.** Kui paned History=0 et DB-d säästa, kaotad triggerid — süsteem kogub andmeid aga ei hoiata millestki.

**Andmebaas on Zabbixi pudelikael.** SSD, RAM buffer poolile, partitsioneerimine üle 500 NVPS-i. Need kolm põhimõtet mõistetud — katastroof on ära hoitud.

**Proksi skaleerib horisontaalselt, HA klaster tagab rikkekindluse.** 7.0+ proxy groupid on mugavad, aga SNMP trapidega ja vanemate agentitega tuleb ettevaatlik olla.

**Zabbix 8 muudab süsteemi monitooringust täisvaatluse platvormiks.** OpenTelemetry, log korrelatsioon, ClickHouse, scatter plot. See seob Zabbixi kõige sellega, mida järgmistel päevadel vaatame.

Zabbixit kritiseeritakse tihti tema "kitchen sink" lähenemise pärast — teeb kõike, aga eriti midagi. Tegelikult on see tema tugevus. Väga vähe tööriistu katab kogu infrastruktuuri spektrit ühest kohast, ühe konfiguratsiooniga, ühe skillsetiga. 8.0-ga astub ta ka vaatlemise territooriumile. Tulev kümmekond aastat on põnev.

**Järgmine samm:** [Labor: Zabbix](../../labs/02_zabbix_loki/zabbix_lab.md) — ehita Zabbix stack üles, lisa host'id ja template'id, jookse läbi trigger-fire/resolve tsükkel.

---

## Enesekontrolli küsimused

1. Mis vahe on Zabbixi push- ja pull-mudelil? Millal millist eelistada?
2. Miks on history=0 triggerite jaoks kriitiline viga? Mida süsteem kogub ja mida ei kogu?
3. Arvuta: 5000 itemi, iga uueneb 30 sekundi järel. Mis on NVPS? Kui palju ruumi vajab 30 päeva history numbriliste andmete jaoks?
4. Mis on housekeeperi põhiprobleem suurtes keskkondades? Kuidas partitsioneerimine selle lahendab?
5. Milles on Zabbix 7.0 proxy groupide piirangud? Nimeta vähemalt kaks.
6. Kui su rakendus logib JSON-formaadis ja tahad trace id'de põhjal otsida — miks Zabbix ei sobi ja mis sobib paremini?
7. Zabbix 8 toob OpenTelemetry natiivse toe. Mida see praktiliselt tähendab keskkonnas, kus on juba Prometheus?

---

## Allikad

### Primaarne dokumentatsioon

| Allikas | URL |
|---------|-----|
| Zabbix ametlik dokumentatsioon | https://www.zabbix.com/documentation/current/en/manual |
| History ja Trends | https://www.zabbix.com/documentation/current/en/manual/config/items/history_and_trends |
| Housekeeper | https://www.zabbix.com/documentation/current/en/manual/web_interface/frontend_sections/administration/housekeeping |
| Proxy groups (7.0+) | https://www.zabbix.com/documentation/current/en/manual/distributed_monitoring/proxies/ha |
| HA klaster | https://www.zabbix.com/documentation/current/en/manual/concepts/server/ha |

### Zabbix 8

| Allikas | URL |
|---------|-----|
| What's new in Zabbix 8.0 | https://www.zabbix.com/documentation/8.0/en/manual/whatsnew |
| Zabbix roadmap | https://www.zabbix.com/roadmap |
| Zabbix 8.0 ülevaade (initMAX) | https://www.initmax.com/the-new-zabbix-8-0-is-here/ |
| Zabbix 8.0 LTS (Hawatel) | https://hawatel.com/en/blog/zabbix-8-0-lts-a-new-standard-for-monitoring-and-observability/ |

### Jõudlus ja skaleerimine

| Allikas | URL |
|---------|-----|
| Zabbix performance tuning | https://www.zabbix.com/documentation/current/en/manual/appendix/performance_tuning |
| Zabbix blog | https://blog.zabbix.com/ |
| MySQL partitsioneerimise skript | https://github.com/OpensourceICTSolutions/zabbix-mysql-partitioning-perl |
| TimescaleDB ja Zabbix | https://www.timescale.com/blog/tag/zabbix/ |

### Kommuunikatsioon ja ressursid

| Allikas | URL |
|---------|-----|
| Zabbix GitHub | https://github.com/zabbix/zabbix |
| Zabbix ametlikud koolitused | https://www.zabbix.com/training |

**Versioonid (aprill 2026):**
- Zabbix server: 7.0 LTS (tootmine) või 7.4 (uusimad funktsioonid, non-LTS)
- Zabbix 8.0 LTS: alfas (okt 2025), ametlik väljalase 2026
- Zabbix agent 2: 7.0+
- MariaDB: 10.11 LTS või 11.4 LTS
- PostgreSQL: 16 (+TimescaleDB 2.15+)

---

*Järgmine: [Labor: Zabbix](../../labs/02_zabbix_loki/zabbix_lab.md) — Zabbix stack üles, agent + templates + triggers + dashboards*
