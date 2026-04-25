---
tags:
  - Zabbix
  - Monitooring
  - Day2
---

# Päev 2: Zabbix

**Kursus:** Kaasaegne IT-süsteemide monitooring ja jälgitavus  
**Kestus:** ~45 minutit lugemist  
**Eeldused:** Päev 1 (Prometheus + Grafana) läbitud  

---

## Õpiväljundid

Selle peatüki lõpuks oskad:

- **Selgitada**, miks Zabbix on Eestis ja Lätis valdav seiretööriist
- **Nimetada** Zabbixi kolm põhikomponenti ja nende rollid
- **Kirjeldada** nelja mõistet — Host, Item, Trigger, Action — ja seda, kuidas need moodustavad ahela "mõõtmisest häireni"
- **Põhjendada**, miks Template on Zabbixis nii tähtis
- **Valida** passiivse ja aktiivse agendi vahel
- **Selgitada**, millal lisandub pildile proxy

---

## 1. Kust Zabbix tuleb

1998. aastal kirjutas Läti Ülikooli tudeng Alexei Vladišev diplomitöö raames sisemise seiretööriista. Esimene avalik versioon ilmus 2001, esimene stabiilne 2004. Algus oli tagasihoidlik — Riia üks tudeng, üks idee.

Nüüd, 25 aastat hiljem, on Zabbix üks levinumaid avatud lähtekoodiga monitooringutööriistu. Kuna ta sündis Riias, on ta Baltikumis eriti kodus. Eestis kasutavad teda Telia, Swedbank, Maksu- ja Tolliamet, enamik riigiasutusi ja ülikoole. Kui sa lähed Eesti IT-sse tööle, puutud Zabbixiga tõenäoliselt kokku — pigem on küsimus "millal" kui "kas".

Miks just tema? Kolm põhjust. **Avatud lähtekood** — kood on GitHubis, litsents on vaba (alates 7.0 AGPL-3.0). **Lätlastest kogukond** — lokaalne tugi, eestikeelne UI tugi, konverentsid siinsamas Riias. Ja **lai haare** — üks Zabbix jälgib nii Linux-servereid, Cisco ruutereid, vana HP printerit kui tänapäevaseid Docker-konteinereid. Iga uue seadme jaoks ei pea uut tööriista otsima.

Eilsest saad võtta võrdluse lihtsa vastandusega. **Prometheus on mikroteenuste ja Kubernetese maailma tööriist.** Zabbix on mõeldud **kogu infrastruktuuri jaoks** — serverid, võrguseadmed, printerid, UPS-id. Need ei ole konkurendid: paljudes Eesti ettevõtetes töötavad nad koos. Zabbix jälgib taristut, Prometheus rakendusi, mõlema andmed jõuavad Grafanasse.

---

## 2. Zabbixi kolm põhikomponenti

Et Zabbix töötaks, on vaja kolme komponenti korraga.

**Zabbix Server** on aju. Ta võtab vastu mõõdikuid, otsustab, kas miski on viga, ja saadab häireid. Kui süsteemis midagi juhtub, on tema see, kes sellest esimesena teadlik on.

**Andmebaas** on mälu. MySQL, MariaDB või PostgreSQL. Siin on koos kaks asja: Zabbixi enda konfiguratsioon (milliseid seadmeid jälgid, millised on häirete reeglid) ja kogu ajalooline mõõtmisandmestik (mis CPU koormus oli kolmapäeval kell 14:23).

**Frontend** on nägu. PHP veebirakendus, mida kasutad brauseris. Siit lisad uue seadme, vaatad graafikuid, seadistad häireid.

Oluline nüanss: **Frontend räägib otse andmebaasiga, mitte Serveriga.** Kui UI-s midagi muudad, kirjutab Frontend muudatuse otse DB-sse. Server loeb oma konfiguratsiooni DB-st kindla intervalliga uuesti sisse. See tähendab, et Server ja Frontend võivad elada eri masinates, isegi eri andmekeskustes — neil on vaja ainult ligipääsu samale andmebaasile.

Kolme põhikomponendi kõrval on **veel kaks**, millega puutud samuti kokku. **Agent** — väike programm, mis jookseb jälgitaval seadmel (server, VM) ja saadab sealt mõõdikuid. **Proxy** — abiline, kes kogub andmeid ühes võrgusegmendis ja edastab need Serverile; teda kasutatakse suuremates või jaotatud paigaldustes. Proxy juurde jõuame §7-s, Agentist räägime järgmisena.

Üks asi, mis tasub kohe ära märkida: **Zabbixi konfiguratsioon elab andmebaasis.** Eile Prometheuses oli konfiguratsioon YAML-failis, mida said Git-i panna ja versioonihalduses hoida. Zabbixis on kogu konfiguratsioon — iga host, template, trigger — DB ridadena. Sellel on tagajärjed:

- Backup teed DB dump'iga
- Kui Docker Compose’i juures unustad volume’i defineerida, kaob esimese `docker compose down` järel kogu töö
- Versioonihaldust saab teha eksport/import mehhanismiga (XML/JSON), mitte otse Git-ist

Laboris alustame `docker-compose.yml` failis MySQL-i volume’ist — et sinu töö ei kaoks.

---

## 3. Neli mõistet: Host → Item → Trigger → Action

Siin on Zabbixi südamik. Kui need neli mõistet ja nende seosed on selged, on põhimõte käes. Ülejäänu on peenhäälestus.

Vaatame neid järjest, nii nagu probleemisituatsioonis päriselt juhtub.

### Host — mida me jälgime

**Host** on jälgitav asi. Üks server. Üks virtuaalmasin. Üks ruuter. Üks andmebaas. Üks printer.

Hostil on nimi (nt `mon-target`), IP-aadress või DNS-nimi (nt `192.168.35.140`) ja vähemalt üks viis, kuidas Server temaga räägib — nn **interface**. Interface ütleb näiteks: "kasuta Zabbix agendi porti 10050" või "kasuta SNMP-d port 161".

Laboris loome kaks hosti: `docker-agent` (Docker konteiner, kus jookseb Zabbix Agent) ja `mon-target` (virtuaalmasin).

### Item — üks konkreetne mõõtmine

**Item** on üks mõõdik ühe hosti kohta. "CPU keskmine koormus viimase minuti jooksul." "Vaba mälu baitides." "Kas Nginx teenus töötab (1/0)." Iga selline number või tõeväärtus on eraldi item.

Itemil on neli olulist omadust: nimi (inimloetav — "CPU load (1min average)"), võti ehk key (Zabbixi jaoks — `system.cpu.load[all,avg1]`), tüüp (numbriline, tekstiline, loogiline) ja intervall (kui tihti seda värskendatakse, nt iga 60 sekundi järel).

Tüüpilisel Linux-serveril on 100–300 item’it. Neid ei looda käsitsi ükshaaval — selleks on **Template**, millest §4.

### Trigger — tingimus, mis ütleb "midagi on valesti"

**Trigger** on tingimus item’i väärtuste peal. Näiteks: "kui CPU keskmine koormus viimase 5 minuti jooksul on üle 90%, loeme selle probleemiks".

Triggeril on **avaldis** — see loogiline/matemaatiline tingimus. Meie näide:

```text
avg(/mon-target/system.cpu.util,5m) > 90
```

Loe: "mon-target’i CPU utilisatsiooni 5 minuti keskmine on suurem kui 90". Kui see on tõsi, läheb trigger **Firing** olekusse. Kui tingimus enam ei kehti, on ta **Resolved** või **OK**.

Triggeril on ka **raskusaste** — Information, Warning, Average, High, Disaster. See määrab, kui tõsine olukord on. Information on pigem teavituseks, Disaster on see, mis äratab öösel.

### Action — mis juhtub, kui trigger käivitub

**Action** on reegel selle kohta, mida teha, kui trigger Firing olekusse läheb. Saada e-kiri. Saada Slacki sõnum. Helista PagerDuty kaudu telefoni. Käivita skript.

Laboris me action’eid eraldi ei seadista — UI-s triggeri nägemisest piisab. Päriselus on action’id vältimatud; monitooringust pole kasu, kui keegi häireid ei näe.

### Ahel kokku

Paneme näite ritta:

1. **Host**: `mon-target` — virtuaalmasin IP-ga `192.168.35.140`  
2. **Item**: `system.cpu.util` — CPU utilisatsioon protsentides, uuendub iga 60 sekundi järel  
3. **Trigger**: jälgib seda item’it; kui 5 minuti keskmine ületab 90%, läheb käima  
4. **Action**: saadab triggeri käivitumisel e-kirja: "mon-target on hädas"

See ahel — mõõdik → tingimus → reaktsioon — on Zabbixi loogika lühivorm. Iga tootmises nähtav häire on variatsioon sellest samast mustrist.

---

## 4. Template — miks ta Zabbixis nii keskne on

Ühe serveri puhul võiks kõik item’id käsitsi teha. Mõni klõps, ja töö on tehtud. Päriselus on sul aga **mitu kümmet või sada** serverit. Igaühele samu mõõdikuid käsitsi konfigureerida ei ole realistlik.

**Template** lahendab selle probleemi. Template on **valmis item’ite, trigger’ite ja graafikute komplekt**, mis on loodud ühe korra ja mida saab rakendada paljudele hostidele.

Näide. Keegi on loonud template’i `Linux by Zabbix agent`. Selles on umbes 300 item’it (CPU, mälu, ketas, võrk, protsessid, teenused), umbes 50 trigger’it ja mõned valmis dashboard’id. Sina seod oma serveri selle template’iga — ja mõne minuti pärast on serveril kõik need mõõdikud ja häiretingimused olemas, graafikud koos.

Kui sul on 500 serverit, seod sama template’i kõigiga. Iga server saab need samad 300 item’it ja 50 trigger’it. Kui kuu aja pärast selgub, et üks trigger on liiga tundlik, muudavad seda ühes kohas — template’is — ja muudatus jõuab automaatselt kõigi 500 serverini. Ilma template’ita peaksid sama muudatust tegema 500 korda käsitsi.

Zabbixiga tuleb kaasa umbes 300 valmis template’it — operatsioonisüsteemide, võrguseadmete (Cisco, MikroTik, HP, Juniper), andmebaaside ja rakenduste jaoks. Seetõttu ongi tihti nii, et uue asja jälgimine käib väga kiiresti: paned agenti, seod template’i, ja graafikud ilmuvad.

Laboris kasutame `Linux by Zabbix agent` template’it mõlema hosti peal. Hiljem, osas 5, teeme **oma item’i** (UserParameter’i kaudu) — sellest saaks hiljem üks kild sinu enda template’ist, kui tahad seda mitmel serveril korrata.

---

## 5. Agent — kes andmeid kogub

Agent on väike programm, mis jookseb jälgitaval masinal ja kogub sealt mõõdikuid. Meie labori virtuaalmasinatel on agent juba olemas — koolitaja pani ta Ansible’iga peale, seega paigaldust me eraldi ei läbi.

Agendi juures tasub teada kahte asja. Esiteks, et neid on **kaks põlvkonda**. Teiseks, et agent võib **andmeid kahel viisil saata**.

### Agent 1 ja Agent 2

**Agent 1** on klassikaline versioon, C-keeles, olemas Zabbixi algusaegadest. Lihtne, stabiilne, väikese jalajäljega.

**Agent 2** on uuem (alates 2019), kirjutatud Go-s. Selle suur pluss on **pluginate süsteem** — sisseehitatud tugi MySQL-ile, PostgreSQL-ile, Dockerile, Redisele, MongoDB-le jne. Agent 1 puhul tuli näiteks MySQL-i statistika kogumiseks ise skripte kirjutada; Agent 2 oskab seda konfiguraatsiooni abil.

Tavalise Linux-serveri jaoks töötavad mõlemad. Uutes paigaldustes eelistatakse tavaliselt Agent 2, sest see on paindlikum ja vajab vähem "nokitsemist" integratsioonide juures. Laboris kasutame **Agent 2**.

### Passiivne ja aktiivne režiim

Agent saab andmeid Serverile saata kahel moel.

**Passiivne agent**: Server küsib, Agent vastab. Server ütleb: "anna CPU koormus", Agent vastab `0.45`. Server küsib järgmise mõõdiku jne. Algatus on Serveri käes.

**Aktiivne agent**: Agent küsib Serverilt korra: "mida ma pean jälgima?" — saab nimekirja, ja hakkab siis ise regulaarselt tulemusi Serverile saatma. Algatus on agendi käes.

Erinevus on oluline just **tulemüüri** mõttes. Passiivse agendi puhul peab Server saama Agentini (suund Server → Agent). See sobib sisevõrgus, kus kõik on samas segmendis ja tulemüür ei sega. Kui Agent on DMZ-s, pilves või NAT-i taga, kuhu Server otse ei pääse, peab Agent ise Serveri poole pöörduma (Agent → Server) — see ongi aktiivne režiim.

Lihtne valikureegel: **kui kõik on samas võrgus ja tulemüür ei sega, kasuta passiivset.** Agent’i konfis ja UI-s on see veidi sirgjoonelisem. Kui võrk on keerulisem — NAT, DMZ, eraldi VPC-d — kasuta aktiivset. Üks erand, mida tasub meeles pidada: **logifailide jälgimine käib ainult aktiivses režiimis**, sest Agent peab pidama meeles, kust kohast failis lugemine pooleli jäi.

Laboris kasutame **passiivset** režiimi. Labori virtuaalmasinad on samas võrgus ja tulemüür ei sega.

---

## 6. Mida Zabbix saab ka ilma agendita

Zabbixi tugevus on ka see, et ta ei nõua igal seadmel agenti. Paljusid asju saab jälgida **otse**, sest need juba räägivad standardselt protokolli.

Näited:

- **SNMP** — võrguseadmete (ruuterid, switchid) klassikaline keel. Cisco, MikroTik, HP, Juniper — kõik oskavad SNMP-d. Zabbix küsib: "mis interface’id sul on, kui palju liiklust, mis uptime?" Seadmele midagi juurde installida ei ole vaja.
- **HTTP** — kui rakendusel on endpoint, mis väljastab JSON-i või muud hästi parsitavat (nt Nginxi `/stub_status`), saab Zabbix sealt ise numbrid välja võtta.
- **IPMI** — serveri riistvara BMC (temperatuur, toiteallika olek, ventilaatorid).
- **JMX** — Java rakendused.
- **VMware API** — vCenter ja ESXi hostid otse, ilma agendita.

Prometheuse maailmas on iga sellise asja jaoks eraldi **exporter** — programm, mis tõlgib seadme keele Prometheuse mõõdikuteks. Nginxi jaoks `nginx-prometheus-exporter`, MySQL-i jaoks `mysqld_exporter`, ruuterite jaoks `snmp_exporter`. Iga exporter on eraldi protsess või konteiner, eraldi asi, mida haldada.

Zabbixis on suur osa sellest **Serverisse sisse ehitatud**. Vastutasuks on Zabbix Server ise "raskem" ja konfigureerimine käib failide asemel UI kaudu. Aga tüüpiline Zabbixi stack on komponentide arvu mõttes **lihtsam** kui samaväärne Prometheuse stack.

Laboris kasutad seda osas 4 — Nginxi `stub_status` endpoint’ist teed Zabbixi HTTP Agent tüüpi item’i, ilma eraldi exporter’ita.

---

## 7. Proxy — millal ühest Serverist ei piisa

Üks Zabbix Server saab tavaliselt jälgida kuskil 1000–10 000 hosti. Aga on kolm olukorda, kus on vaja lisada **Proxy** — ja need on seotud pigem võrgutopoloogiaga kui puhta mahuga.

**Geograafiline kaugus.** Peakontor Tallinnas, Server Tallinnas. Filiaal Tokyos, 50 seadet. Ilma Proxyta küsib Server iga mõne sekundi tagant iga Tokyo seadme käest andmeid üle ookeani. Iga väike päring ja vastus liigub WAN-i mööda. Latency, kulu ja Serveri koormus kasvavad. **Proxy Tokyos** kogub andmed kohapeal kokku, puhverdatud info saadetakse Serverile harvemini suuremate pakkidena.

**Eraldatud võrgusegmendid.** DMZ-s on 50 seadet. Turvapoliitika lubab sisevõrgust DMZ-sse ainult kindlad portid ja sihtkohad. Kui iga seade peaks eraldi Serveriga suhtlema, tähendaks see kümneid tulemüürireegleid. **Proxy DMZ-s** tähendab ühte reeglit (Proxy → Server). Agendid räägivad Proxyga lokaalselt, Proxy räägib Serveriga läbi tulemüüri.

**Offline-taluvus.** Proxy’l on oma väike andmebaas. Kui WAN kukub näiteks kaheks tunniks ära, kogub Proxy andmeid edasi ja salvestab need lokaalselt. Kui ühendus taastub, saadab Proxy puhverdatud ajaloo Serverile; andmetesse ei jää auke.

Proxy ei tee **triggerite hindamist** — see jääb alati Serveri ülesandeks. Proxy kogub ja edastab. Kui on vaja kauges asukohas ka ilma Serverita kohapeal häiret tekitada, tuleb vaadata teisi tööriistu.

Laboris Proxy’t kohe püsti ei pane — see on pigem lisaülesanne. Mõte on oluline: niipea kui tootmises tekivad eri võrgusegmendid või asukohad, on Proxy reaalne valik, mitte ainult "suurte" ettevõtete mure.

---

## 8. Mida teed tänases laboris

Labor kordab kõike, millest juttu oli, praktilise nurga alt. Ehitame **kihtidena** — iga kiht lisab ühe uue idee.

**Osa 1** — Ehitad stack’i. MySQL → Server. Üks komponent korraga, iga kiht enne järgmise lisamist läbi proovitud. Nii on vea puhul lihtne aru saada, kus see tekib.

**Osa 2** — Lisad Frontendi ja esimese Agendi. Pääsed brauserist Zabbixisse. Muudad kohe vaikimisi parooli — tüüpiline tootmisrefleks.

**Osa 3** — Lisad kaks hosti, seod template’i, vaatad, kuidas trigger käivitub ja maha rahuneb. Kõik neli mõistet §3-st muutuvad konkreetseks.

**Osa 4** — HTTP Agent + dependent items. Üks HTTP päring, mitu mõõdikut vastusest välja võetud. Muster, mida päriselus tihti kasutatakse.

**Osa 5** — Oma item shell-käsust (UserParameter). Kõik, mida Linuxi shell oskab, saab muuta Zabbixi mõõdikuks. Lõpus lihtne turbenäide — port 2222 kui honeypot, iga puudutus on häire.

Kõik neli §3 mõistet ja §4 template’i idee korduvad päeva jooksul mitu korda. Passiivse agendi seadistus on osas 2. Ilma agendita monitooring (HTTP) on osas 4. Proxy tuleb mängu lisaülesannetes.

---

## 9. Kokkuvõte

Viis asja, mis sellest loost meelde jätta:

**1. Kolm komponenti.** Zabbix Server (aju) + andmebaas (mälu) + Frontend (nägu). Frontend räägib DB-ga, mitte Serveriga — see lubab Serveri ja Frontendi eri masinatesse paigutada.

**2. Konfiguratsioon on DB-s.** See on põhiline erinevus Prometheusest. Backup tehakse DB dump’iga. Kui Docker Compose’i juures volume’i unustad, kaob kogu töö.

**3. Host → Item → Trigger → Action.** Neli mõistet, mille ümber Zabbix keerleb. Pane need endale selgelt paika.

**4. Template hoiab sind elus.** Sajad serverid ja sajad mõõdikud per server — ilma template’ita ei ole see hallatav. Zabbixiga tuleb kaasa hulk valmis template’e, oma võid ise juurde teha.

**5. Passiivne sisevõrgus, aktiivne keerulisemas võrgus.** Agent toetab mõlemat. Logifailide jälgimine on erand, mis nõuab alati aktiivset režiimi.

---

## Küsimused enesetestiks

<details>
<summary><strong>Küsimused (vastused all)</strong></summary>

1. Miks on Zabbix Baltikumis eriti levinud?  
2. Nimeta Zabbixi kolm põhikomponenti ja kirjelda iga rolli ühe lausega.  
3. Miks Frontend räägib DB-ga, mitte Serveriga? Mida see võimaldab?  
4. Selgita oma sõnadega Host → Item → Trigger → Action ahelat.  
5. Sul on 200 Linux-serverit, kõik vajavad sama 150 mõõdikut. Miks on template vajalik, mitte lihtsalt mugavusfunktsioon?  
6. Passiivne või aktiivne agent: (a) server samas võrgus, (b) agent DMZ-s, (c) logifaili jälgimine?  
7. Mis kolm olukorda toovad Proxy mängu?  

??? note "Vastused"

    1) Zabbix sündis Riias (Alexei Vladišev, Läti Ülikool). Lähedus annab tugevama kohaliku kogukonna, konverentsid, tõlked ja esimesed referentskliendid (Telia, Swedbank, MTA, riigiasutused).

    2) **Server** võtab vastu mõõdikuid, hindab triggereid ja saadab häireid. **Andmebaas** hoiab konfiguratsiooni ja ajalugu. **Frontend** on veebiliides, kust seadistad ja vaatad seiret.

    3) Frontend kirjutab muudatused DB-sse, Server loeb oma konfiguratsiooni sealt aeg-ajalt uuesti sisse. Nii saavad Server ja Frontend olla eri masinates, neid võib skaleerida eraldi (nt mitu Frontendi load balanceri taga).

    4) **Host** on jälgitav objekt (server, ruuter). **Item** on üks konkreetne mõõdik selle hosti kohta (nt CPU load). **Trigger** on tingimus item’i peal (nt kui load > 90%). **Action** on reageerimine (nt e-kiri). Ahel: mõõdik → tingimus → reaktsioon.

    5) 200 × 150 = 30 000 item’it. Käsitsi lisamine on ebarealistlik. Lisaks: kui ühe triggeri lävendit muudad, peaksid seda tegema 200 korda — viga on garanteeritud. Template’iga muudad ühes kohas ja kõik 200 serverit saavad muudatuse.

    6) (a) passiivne — lihtsam ja otsekohesem. (b) aktiivne — Server ei pääse DMZ-sse, agent pöördub ise Serveri poole. (c) aktiivne — logifaili jälgimiseks peab agent ise faile lugema ja asukohta meeles pidama.

    7) (1) Geograafiline kaugus — Proxy kogub andmeid kohapeal ja saadab need harvemini üle WAN-i. (2) Eraldatud võrgusegmendid (DMZ, pilv) — üks tulemüürireegel Proxyle, mitte kümneid reegleid iga agendi jaoks. (3) Offline-taluvus — Proxy puhverdab katkestuse ajal andmed ja saadab need hiljem Serverile.

</details>

---

## Allikad

| Allikas                     | URL |
|-----------------------------|-----|
| Zabbix 7.0 manuaal          | <https://www.zabbix.com/documentation/7.0/en/manual> |
| Zabbix arhitektuur          | <https://www.zabbix.com/documentation/7.0/en/manual/concepts> |
| Zabbix Agent vs Agent 2     | <https://www.zabbix.com/documentation/7.0/en/manual/concepts/agent2> |
| Proxy                       | <https://www.zabbix.com/documentation/7.0/en/manual/distributed_monitoring/proxies> |
| Zabbix 7.0 release announcement | <https://blog.zabbix.com/zabbix-7-0-everything-you-need-to-know/28210/> |
| Zabbix Wikipedia            | <https://en.wikipedia.org/wiki/Zabbix> |

**Versioonid:** Zabbix 7.0.25 LTS, Zabbix Agent 2 (7.0+), MySQL 8.0.

---

*Järgmine: [Labor: Zabbix](../../labs/02_zabbix_loki/zabbix_lab.md)*

--8<-- "_snippets/abbr.md"
