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

Pärast seda loengut oskad:

- **Selgitada**, miks Zabbix on Eestis ja Lätis valdav seiretööriist
- **Nimetada** Zabbixi kolm põhikomponenti ja nende rollid
- **Kirjeldada** nelja mõistet — Host, Item, Trigger, Action — ja seda, kuidas need moodustavad ahela "mõõtmisest häireni"
- **Põhjendada**, miks Template on Zabbixis nii tähtis
- **Valida** passiivse ja aktiivse agendi vahel
- **Selgitada**, millal lisandub pildile proxy

---

## 1. Kust Zabbix tuleb

1998. aastal kirjutas Läti Ülikooli tudeng Alexei Vladišev diplomitöö raames sisemise seiretööriista. Esimene avalik versioon ilmus 2001, esimene stabiilne 2004. Algus oli tagasihoidlik — Riia üks tudeng, üks idee.

Nüüd, 25 aastat hiljem, on Zabbix üks maailma kasutatumaid avatud lähtekoodiga monitooringutööriistu. Ja kuna ta sündis Riias, on ta Baltikumis eriti kodus. Eestis kasutavad teda Telia, Swedbank, Maksu- ja Tolliamet, enamus riigiasutusi ja ülikoolid. Kui sa lähed Eesti IT-sse tööle, puutud Zabbixiga kokku — see pole küsimus "kas", see on küsimus "millal".

Miks just tema? Kolm põhjust. **Avatud lähtekood** — kood on GitHubis, litsents on vaba (alates 7.0 AGPL-3.0). **Lätlastest kogukond** — lokaalne tugi, eestikeelne UI tugi, konverentsid siinsamas Riias. Ja **kõikehaaravus** — üks Zabbix jälgib nii Linux-servereid kui Cisco ruutereid kui vana HP printerit kui tänapäevaseid Docker-konteinereid. Sa ei vaja iga uue seadme jaoks uut tööriista.

Eilesest teed võrdlust lihtsa vastandusega. **Prometheus on loodud mikroteenuste ja Kubernetese maailma jaoks.** Zabbix on loodud **kogu infrastruktuuri jaoks** — serverid, võrguseadmed, printerid, UPS-id. Need ei võistle — paljudes Eesti ettevõtetes töötavad nad kõrvuti: Zabbix jälgib taristut, Prometheus jälgib rakendusi, mõlemad voolavad samasse Grafanasse.

---

## 2. Zabbixi kolm põhikomponenti

Et Zabbix töötaks, on vaja kolme asja koos. See on kõige olulisem pilt, mida sa sellest loengust kaasa võtad — kui sa tead, kes mida teeb, on kõik järgnev loogiline.

**Zabbix Server** on aju. Ta võtab vastu mõõdikuid, otsustab, kas miski on viga, ja saadab häireid. Kui süsteemis midagi juhtub, teab seda esimesena Server.

**Andmebaas** on mälu. MySQL, MariaDB või PostgreSQL. Siin on **kaks asja korraga**: Zabbixi enda konfiguratsioon (milliseid seadmeid jälgid, millised on häirete reeglid) ja kogu ajalooline mõõtmisandmestik (mis CPU-koormus oli kolmapäeval kell 14:23).

**Frontend** on nägu. PHP veebirakendus, mida sa brauseris kasutad. Siit klikid nupule "lisa uus seade", vaatad graafikuid, seadistad häireid.

Pane tähele üht huvitavat asja selle arhitektuuri juures: **Frontend räägib otse andmebaasiga, mitte Server'iga.** Kui sa UI-s midagi muudad, kirjutab Frontend muudatuse kohe DB-sse. Server märkab muudatust järgmisel korral kui ta oma konfiguratsiooni andmebaasist üle loeb. See tähendab, et Server ja Frontend saavad elada eraldi masinates, isegi eraldi andmekeskustes — nad ei vaja otsest ühendust, ainult sama DB-d.

Kolme komponendi kõrval on **veel kaks**, mida me ka kohtame. Esiteks **Agent** — väike programm, mis jookseb jälgitaval seadmel (serveris, VM-is) ja saadab sealt mõõtmisi. Teiseks **Proxy** — abiline, kes kogub andmeid ühes võrgusegmendis ja edastab need Server'ile; teda kasutatakse suuremates paigaldustes. Proxy jätame §7 juurde, Agent võtame järgmises peatükis lahti.

Üks punkt, mida tasub kohe kirja panna: **Zabbix konfiguratsioon elab andmebaasis.** Eile Prometheuses oli konfiguratsioon YAML-failis. Sa said selle Git-i panna, versioonihaldust teha. Zabbixis ei saa — kogu konfiguratsioon, iga host, iga template, iga trigger on DB-ridades. Sellel on tagajärjed:

- Backup teed DB-dump-iga
- Kui Docker Compose'i juures unustad volume'i defineerida, kaotad kogu oma töö esimese `docker compose down` järel
- Versioonihaldust saab teha ainult eksport/import XML/JSON-ina (töövahend on olemas, aga see pole Git)

Laboris seepärast alustame `docker-compose.yml`-i faili esimese reaga, mis defineerib MySQL-i volume'i — et meie töö ei kaoks.

---

## 3. Neli mõistet: Host → Item → Trigger → Action

Siin tuleb Zabbixi süda. Kui sa tead neid nelja mõistet ja nende järjekorda, siis oled sa Zabbixi põhimõtteliselt aru saanud. Kõik muu on detailid.

Ma seletan neid ahela kaudu — nii nagu nad päriselt omavahel suhtlevad kui mingi probleem tekib.

### Host — mida me jälgime

**Host** on asi, mida jälgitakse. Üks server. Üks virtuaalmasin. Üks ruuter. Üks andmebaas. Üks printer.

Host'il on nimi (nt `mon-target`), IP-aadress või DNS-nimi (nt `192.168.35.140`) ja vähemalt üks viis, kuidas Server temaga räägib — nn **interface**. Interface ütleb: "kasuta Zabbix agent'i port 10050 kaudu" või "kasuta SNMP-d port 161 kaudu".

Laboris loome kaks Host'i: `docker-agent` (Docker konteiner, kus jookseb Zabbix Agent) ja `mon-target` (päris virtuaalmasin).

### Item — üks konkreetne mõõtmine

**Item** on üks konkreetne mõõdik ühe Host'i kohta. "CPU keskmine koormus viimase minuti jooksul." "Vaba mälu baitides." "Kas Nginx teenus töötab (1/0)." Iga selline number või jaatus-eitus on üks Item.

Item'il on neli tähtsat asja: nimi (inimesele loetav — "CPU load (1min average)"), võti ehk key (Zabbixi jaoks — `system.cpu.load[all,avg1]`), tüüp (numbriline, tekstiline, loogiline) ja intervall (kui tihti uuendatakse — nt iga 60 sekundi tagant).

Tüüpilisel Linux-serveril võib olla 100-300 Item'it. Sa ei tee neid käsitsi — selle eest hoolitseb **Template**, millest §4.

### Trigger — tingimus, mis ütleb "midagi on valesti"

**Trigger** on tingimus Item'i väärtuste peal. Näiteks: "kui CPU keskmine koormus viimase 5 minuti jooksul on üle 90%, on midagi valesti".

Trigger'il on **avaldis** — see matemaatiline-tõeväärtuslik tingimus. Meie näites:

```
avg(/mon-target/system.cpu.util,5m) > 90
```

Loe nii: "mon-target'i CPU utilisatsiooni 5 minuti keskmine on suurem kui 90". Kui see on tõsi, läheb Trigger **Firing** olekusse. Kui mitte — **Resolved** või **OK**.

Trigger'il on ka **raskusaste** — Information, Warning, Average, High, Disaster. See ütleb, kui tõsine asi on. Information on infoks, Disaster äratab öösel.

### Action — mis juhtub, kui Trigger läheb tulele

**Action** on reegel selle kohta, mis juhtub, kui Trigger läheb Firing olekusse. Saada email. Saada Slack-sõnum. Helista telefoni PagerDuty kaudu. Käivita skript.

Laboris me Action'it ei seadista — piisab kui näeme UI-s Trigger'i. Tootmises seadistad Action'i alati, sest monitooringust pole mõtet kui keegi ei saa teada, et midagi valesti on.

### Ahel kokku

Paneme kogu loo kokku konkreetse näitega:

1. **Host** on `mon-target` — virtuaalmasin IP-ga `192.168.35.140`
2. **Item** on `system.cpu.util` — CPU utilisatsioon protsentides, uueneb iga 60 sekundi tagant
3. **Trigger** jälgib seda Item'it: kui 5-minuti keskmine ületab 90%, läheb tulele
4. **Action** saadab Trigger'i tulekul e-kirja: "mon-target on hädas"

See ahel — mõõdik → tingimus → reaktsioon — on kogu Zabbixi loogika. Iga üksik häire, mille sa tootmises näed, on sündinud sellest samast mustrist.

---

## 4. Template — miks ta on Zabbixis nii tähtis

Kui sul on üks server, saad kõik Item'id käsitsi teha. Paar klõpsu, ongi korras. Aga tootmises on sul tavaliselt **mitte üks server, vaid 50, 500 või 5000**. Igaühele samu mõõdikuid käsitsi teha oleks võimatu.

**Template** lahendab selle. Template on **valmis Item'ite, Trigger'ite ja graafikute komplekt**, mis on loodud üks kord ja rakendub paljudele Host'idele.

Protsess näeb välja nii. Keegi on kunagi loonud Template nimega `Linux by Zabbix agent`. Selles Template'is on ~300 Item'it (CPU, mälu, ketas, võrk, protsessid, teenused), ~50 Trigger'it ja paar valmisdashboard. Sina võtad oma serveri, lingid selle Template'iga — ja minuti pärast on serveril kõik 300 mõõdikut olemas, kõik 50 häire-tingimust olemas, dashboard valmis. Üks klõps.

Kui sul on 500 serverit, lingid sama Template'i iga serveriga. Iga server saab need 300 mõõdikut ja 50 Trigger'it. Kui järgmine kuu avastad, et üks Trigger on liiga tundlik — muudad lävendi Template'is ja muudatus **levib automaatselt kõigile 500-le serverile**. Ilma Template'ita peaksid sa selle muudatuse tegema 500 korda ja ühe või kaks korda unustaksid ära.

Zabbix tarnib umbes 300 valmistemplate'i — operatsioonisüsteemidele, võrguseadmetele (Cisco, MikroTik, HP, Juniper), andmebaasidele, rakendustele. See on üks põhjus, miks inimesed ütlevad, et Zabbixis saad midagi jälgima hakata "out of the box" — paned serverile agendi peale, lingid Template'i, 30 sekundi pärast näed graafikuid.

Laboris kasutame `Linux by Zabbix agent` Template'i oma kahele Host'ile. Hiljem, osas 5, teeme **oma Item'i** (UserParameter kaudu) — sellest saab hiljem oma Template'i tükk, kui tahad seda korrutada mitmele serverile.

---

## 5. Agent — kes andmeid kogub

Agent on väike programm, mis jookseb jälgitaval masinal ja kogub sealt mõõdikuid. Meie labori virtuaalmasinatel on Agent juba paigaldatud — koolitaja pani Ansible'iga peale, seepärast alguses me teda ise ei install.

Agendist tasub teada kahte asja. Esiteks, et neid on **kaks versiooni**. Teiseks, et Agent võib **andmeid kaht moodi saata**.

### Agent 1 ja Agent 2

**Agent 1** on klassikaline versioon, C-keeles kirjutatud, olemas alates Zabbixi algusaegadest. Lihtne, stabiilne, väikese mäluvajadusega.

**Agent 2** on uuem (alates 2019), Go-keeles kirjutatud. Selle peamine eelis on **pluginate süsteem** — tal on sisseehitatud pluginad MySQL-ile, PostgreSQL-ile, Dockerile, Redisele, MongoDB-le jt. Agent 1 puhul pead välja mõtlema, kuidas MySQL-i statistikat koguda (tihti shell-skriptidega); Agent 2 teeb seda natiivselt üle ühe konfiguratsiooni.

Standardse Linux-serveri jaoks töötavad mõlemad. Uutes paigaldustes eelistatakse Agent 2, sest see on tulevikukindlam ja vähem "nokitsemise" vajadusega integratsioonide puhul. Meie laboris kasutame **Agent 2**.

### Passiivne ja aktiivne režiim

Siin tuleb üks kontseptsioon, mida paljud alguses segamini ajavad. Agent võib andmeid saata Server'ile kahel erineval moel.

**Passiivne agent** töötab nii: Server küsib, Agent vastab. Server ütleb "palun anna mulle CPU load", Agent vastab "0.45". Server küsib järgmise mõõdiku, Agent vastab. Algatus on Server'i käes.

**Aktiivne agent** töötab vastupidi: Agent küsib Server'ilt ühe korra "mida ma pean jälgima?", saab nimekirja, ja edasi kogub ja **saadab ise**. Algatus on Agent'i käes.

Erinevus on oluline, sest **tulemüür**. Passiivne agent vajab, et Server pääseks tema juurde (Server → Agent suund avatud). See sobib sisevõrgus, kus kõik on samas segmendis. Aga kui Agent on näiteks DMZ-s, pilves või NAT-i taga, kuhu Server lihtsalt ei saa, siis peab Agent ise Server'i poole pöörduma (Agent → Server suund) — see on aktiivne režiim.

Kuidas otsustada? Lihtne reegel: **kui kõik on samas võrgus ja tulemüür ei sega, kasuta passiivset.** Lihtsam nii Agent'i konfis (paar rida) kui Zabbixi UI-s. Kui võrk on keerulisem — NAT, DMZ, erinevad VPC-d — kasuta aktiivset. Üks erand, mida tasub mäletada: **logifailide jälgimine käib ainult aktiivses režiimis**, sest Agent peab hoidma lugemispositsiooni failis.

Laboris kasutame **passiivset**. Meie labori virtuaalmasinad on kõik samas võrgus, tulemüür ei sega.

---

## 6. Mida Zabbix saab ka ilma agendita

Üks Zabbixi tugevusi on, et ta ei nõua igal seadmel agenti. Paljusid asju saab ta jälgida **otse**, sest need juba räägivad mingit standardset protokolli.

**SNMP** — võrguseadmete (ruuterid, switchid) ammune keel. Iga Cisco, MikroTik, HP, Juniper seade räägib SNMP-d. Zabbix küsib otse: "mis interfaceid sul on, palju liiklust läbi läks, mis uptime on?" Seadmele midagi installeerida ei ole vaja.

**HTTP** — kui rakendusel on endpoint, mis väljastab JSON-i või midagi parsitavat (nt Nginxi `/stub_status`), Zabbix küsib URL-i ja võtab vastusest välja numbrid.

**IPMI** — serveri enda riistvara BMC kaudu (temperatuur, toiteallika olek, ventilaatorid).

**JMX** — Java rakendused.

**VMware API** — vCenter ja ESXi hostid otse, ilma agendita.

Miks see oluline on? Prometheuses on igaühe jaoks eraldi **exporter** — programm, mis tõlgib seadme keele Prometheuse keelde. Kui tahad jälgida Nginxi, jooksutad `nginx-prometheus-exporter`. Jälgid MySQL-i — `mysqld_exporter`. Jälgid ruutereid — `snmp_exporter`. Iga exporter on eraldi konteiner, eraldi asi mida hooldada, uuendada, ümber pöörata.

Zabbixis on see kõik **sisse ehitatud**. Selle hinnaga, et Zabbixi Server ise on suurem, ja konfiguratsioon käib UI-s, mitte failides. Aga tüüpiline Zabbix-stack on komponente-arvuliselt **väiksem** kui vastav Prometheus-stack.

Laboris kasutad seda osas 4 — Nginxi stub_status endpoint'i lood Zabbixi HTTP Agent tüüpi Item'iga, ilma eraldi exporter'ita.

---

## 7. Proxy — millal üks Server enam ei piisa

Üks Zabbix Server saab enamasti hakkama 1000-10000 Host'iga. Aga on kolm olukorda, kus tuleb käibele **Proxy** — ja need pole seotud suurusega, vaid **võrgu kujuga**.

**Geograafiline kaugus.** Peakontor Tallinnas, Server Tallinnas. Filiaal Tokyos, 50 seadet. Ilma Proxy'ta küsib Server iga mõne sekundi tagant iga Tokyo seadme käest andmeid — üle ookeani. Iga väike päring ja vastus peab WAN-i mööda rändama. Kulu kasvab, latency kasvab, Server tööhõive kasvab. **Proxy Tokyos** kogub andmeid lokaalselt, puhverdab ja saadab Server'ile **kokku pandud pakidena** harvemini. Ressursside sääst on märkimisväärne.

**Eraldatud võrgusegmendid.** DMZ-s on 50 seadet. Turvapoliitika ütleb: sisevõrgust DMZ-sse pääseb ainult teatud portidele, teatud IP-de jaoks. Kui iga seade peab eraldi Server'iga rääkima, tähendab see 50 tulemüürireeglit. Üks reegel seadme kohta, audit'i jaoks painaja. **Proxy DMZ-s** — üks tulemüürireegel (Proxy → Server). Agendid räägivad Proxy'ga lokaalselt, Proxy räägib Server'iga üle tulemüüri.

**Offline-taluvus.** Proxy'l on oma väike andmebaas. Kui WAN kukub 2 tunniks ära, Proxy jätkab andmete kogumist ja puhverdamist kohalikku DB-sse. Kui ühendus tuleb tagasi, saadab ta kogu puhverdatud ajaloo Server'ile — mitte midagi ei lähe kaduma. Ilma Proxy'ta oleks 2 tundi auku andmestikus.

Proxy ei tee **Trigger'ite hindamist** — see jääb alati Server'i tööks. Proxy ainult kogub ja edastab. See on oluline mõista, sest kui tahad kauges asukohas ka **lokaalset häiret** ilma Server'ita, siis Proxy seda ei anna — selleks on vaja teisi tööriistu.

Laboris Proxy't me kohe ei püsti pane — see on lisaülesanne. Aga saa aru: niipea kui sul on tootmises mitu võrgusegmenti või mitu asukohta, **tuleb Proxy kohe käibele**. See pole "suurtele" ettevõtetele reserveeritud, see on arhitektuurivalik.

---

## 8. Mida teed tänases laboris

Teeme kõike, millest siin räägitud. Labor on **kihtidena** — iga kiht toob ühe uue asja lahti.

**Osa 1** — Ehitad stacki. MySQL → Server. Üks asi korraga, iga kiht testitud enne järgmist. See on tark harjumus, sest kui midagi valesti läheb, tead täpselt millises kihis.

**Osa 2** — Lisad Frontend'i ja esimese Agent'i. Saad brauserist Zabbixi sisse. Vaheta vaikimisi parool kohe — see on esimene tootmis-refleks.

**Osa 3** — Lisad kaks Host'i, lingid Template'i, vaatad kuidas Trigger läheb tulele ja naaseb. Kõik neli mõistet §3-st saavad lihast ja luust.

**Osa 4** — HTTP Agent + Dependent items. Üks URL-i päring, mitu mõõdikut välja võetud. See on muster, mida tootmises tihti kasutad.

**Osa 5** — Oma Item shell-käsust (UserParameter). Nüüd saad kõike, mida Linux shell oskab, Zabbixi mõõdikuks muuta. Lõpetame turbe-näitega — honeypot port 2222, iga puudutus on häire.

Kõik neli §3 mõistet ja §4 Template-kontseptsioon tulevad päeva jooksul korduvalt tagasi. Passiivse Agent'i seadistus on osas 2. Ilma-agendita monitooring (HTTP) on osas 4. Proxy't labori põhiosas ei tee, aga lisaülesannetes on kirjeldatud.

---

## 9. Kokkuvõte

Viis asja, mida loengust kaasa võta:

**1. Kolm komponenti.** Zabbix Server (aju) + andmebaas (mälu) + Frontend (nägu). Frontend räägib DB-ga, mitte Server'iga — see on nüanss, mida paljud esmakordsed Zabbixi kasutajad ei märka.

**2. Konfiguratsioon on DB-s.** See on põhimõtteline erinevus Prometheusest. Backup on DB-dump. Docker Compose'i volume'it kaotades kaob kogu su töö.

**3. Host → Item → Trigger → Action.** Neli mõistet, mille ümber kogu Zabbix keerleb. Õpi need pähe.

**4. Template on pääsemine.** 500 serverit, 300 mõõdikut igaüks — ilma Template'ita tööd ei tee. Zabbix tarnib ~300 valmis-Template'i, sinu oma võid ise lisada.

**5. Passiivne sisevõrgus, aktiivne keerulises võrgus.** Agent saab mõlemad. Logifailide jälgimine on alati aktiivne.

Nüüd laborisse.

---

## Küsimused enesetestiks

<details>
<summary><strong>Küsimused (vastused all)</strong></summary>

1. Miks on Zabbix Baltikumis eriti levinud?
2. Nimeta Zabbixi kolm põhikomponenti ja iga rolli ühe lausega.
3. Miks Frontend räägib DB-ga, mitte Server'iga? Mis see annab?
4. Selgita oma sõnadega Host → Item → Trigger → Action ahelat.
5. Sul on 200 Linux-serverit, kõik vajavad sama 150 mõõdikut. Miks Template olemasolu on vajalik, mitte mugavusfunktsioon?
6. Passiivne või aktiivne Agent: (a) server samas võrgus, (b) Agent DMZ-s, (c) logifaili jälgimine?
7. Mis kolm olukorda sunnivad sind Proxy't lisama?

??? note "Vastused"

    1) Ta sündis Riias (Alexei Vladišev, Läti Ülikool). Lokaalne tugi, eestikeelne UI tugi, geograafiline lähedus kogukonnaga. Eestis kasutavad teda Telia, Swedbank, Maksu- ja Tolliamet, enamus riigiasutusi.

    2) **Server** võtab vastu mõõdikuid, hindab Trigger'eid, saadab häireid. **Andmebaas** hoiab konfiguratsiooni ja ajalugu. **Frontend** on veebiliides, kust klikiga seadistad ja vaatad.

    3) Frontend kirjutab muudatused DB-sse, Server loeb DB-st regulaarselt oma konfi üle. See annab paindlikkust: Frontend ja Server saavad elada eraldi masinates, isegi eraldi andmekeskustes. Suurtes keskkondades mitu Frontend'i load balancer'i taga.

    4) **Host** on jälgitav asi (server, ruuter). **Item** on üks konkreetne mõõdik sellel Host'il (CPU load). **Trigger** on tingimus Item'i peal (kui load > 90%). **Action** on reaktsioon Trigger'i tulekul (saada email). Ahel: mõõdik → tingimus → reaktsioon.

    5) 200 × 150 = 30 000 Item'it. Käsitsi lisamine praktiliselt võimatu. Lisaks: kui lävendit ühel Trigger'il muudad, peaks 200 korral muutma → ühe unustad. Template'iga: lisad 1 kord, lingid 200-le, muudad ühes kohas, levib kõigile.

    6) (a) passiivne — lihtsam. (b) aktiivne — Server ei pääse DMZ-sse, Agent pöördub ise Server'i poole. (c) aktiivne — logifaili jälgimine käib ainult aktiivses režiimis, sest Agent peab hoidma lugemispositsiooni.

    7) (1) Geograafiline kaugus — Proxy kogub lokaalselt, saadab pakkidena üle WAN-i. (2) Eraldatud võrgusegmendid (DMZ, pilv) — üks tulemüürireegel selle asemel, et iga Agent'i jaoks eraldi. (3) Offline-taluvus — Proxy puhverdab kui WAN kukub, saadab kõik tagasi kui ühendus taastub.

</details>

---

## Allikad

| Allikas | URL |
|---------|-----|
| Zabbix 7.0 manuaal | <https://www.zabbix.com/documentation/7.0/en/manual> |
| Zabbix arhitektuur | <https://www.zabbix.com/documentation/7.0/en/manual/concepts> |
| Zabbix Agent vs Agent 2 | <https://www.zabbix.com/documentation/7.0/en/manual/concepts/agent2> |
| Proxy | <https://www.zabbix.com/documentation/7.0/en/manual/distributed_monitoring/proxies> |
| Zabbix 7.0 release announcement | <https://blog.zabbix.com/zabbix-7-0-everything-you-need-to-know/28210/> |
| Zabbix Wikipedia | <https://en.wikipedia.org/wiki/Zabbix> |

**Versioonid:** Zabbix 7.0.25 LTS, Zabbix Agent 2 (7.0+), MySQL 8.0.

---

*Järgmine: [Labor: Zabbix](../../labs/02_zabbix_loki/zabbix_lab.md)*

--8<-- "_snippets/abbr.md"
