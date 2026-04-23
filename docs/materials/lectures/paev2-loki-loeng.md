# Päev 2: Grafana LGTM stack ja Loki

**Kestus:** ~45 minutit iseseisvat lugemist  
**Eeldused:** [Päev 2: Zabbix](paev2-loeng.md) loetud, Prometheus ja Grafana põhitõed ([Päev 1](paev1-loeng.md))  
**Versioonid laboris:** Loki 3.7.1, Grafana 12.4.3, Alloy 1.15.1  
**Viited:** [grafana.com/docs/loki](https://grafana.com/docs/loki/latest/) · [Grafana Alloy](https://grafana.com/docs/alloy/latest/) · [LogQL](https://grafana.com/docs/loki/latest/query/)

---

## 1. Kust me pooleli jäime

Hommikul vaatasime Zabbixit — IT-maastiku vana tööhobust, mis on olnud tootmises 25 aastat. Zabbixi tugevus on laius: ühest kohast jälgid servereid, võrguseadmeid, rakendusi ja kõigele sellele sama UI-ga teed ka alertid ja dashboardid. Arhitektuuriliselt on see aga monoliit — üks server, üks andmebaas, kõik ühes kastis. See mudel töötab ideaalselt tuttavas maailmas, kus sul on nimeldi 500 serverit ja iga server on pikaealine.

Pilvepõhises maailmas see mudel kipub murduma. Kubernetes-klastris võib pod elada 30 sekundit, käivituda teises sõlmes, vahetada nime, kaduda lõplikult. Sel ajal surub ta välja viiskümmend megabaiti logisid, mida sul tegelikult vaja oleks näha. Klassikaline monitooringusüsteem, mille paradigma on "lisa host, lingi template", ei oska selliste lühiajaliste asjadega midagi peale hakata. Vaja on teistsugust lähenemist.

Päev üks loengus nägime ka Grafanat, aga ainult ühes rollis — visualiseerimiskihina, mis võtab andmeid Prometheuselt ja joonistab graafikuid. Mainisin möödaminnes akronüümi LGTM, aga läksin sealt mööda. Pärastlõunal tuleme selle juurde tagasi ja vaatame, mida see päriselt tähendab, ehitades laborisse selle pere logihaldustööriista — **Loki**.

---

## 2. LGTM-pinu

Akronüüm tähistab nelja Grafana Labsi projekti: **Loki** hoolitseb logide, **Grafana** visualiseerimise, **Tempo** jälgede ja **Mimir** meetrikate eest. Mimir on sisuliselt Prometheus steroididega — täielikult PromQL-ühilduv, aga ühe klastri sees hallab miljardeid aktiivseid aegridu seal, kus üksik Prometheus jookseb mõne miljoni peal kokku. Tempo teeb sama asja jälgimise poolel, millest räägime päev viiel.

Need neli on sama meeskonna — Grafana Labsi, eesotsas CTO Tom Wilkie'ga — toode ja neid ühendab sama filosoofia: indekseeri vähem, salvesta odavalt, skaleeri horisontaalselt. Sel põhjusel on ka akronüüm "pinu", mitte "neli tööriista". Nende päris väärtus tuleb välja siis, kui nad töötavad koos.

### Korrelatsiooni kolmik

Mõtle, kuidas käib klassikaline tõrkeotsing traditsioonilises infras. Zabbix näitab, et mõni server on halb — CPU sada protsenti. Teed masinasse SSH, hakkad `tail -f /var/log/...` jooksutama, näed ridade kaupa veateateid. Aga kas need on probleemi põhjus või tagajärg, sa ei tea. Helistad arendajale, kes süveneb koodi ja otsib trace-ID-d eraldi logiaggregaatorist. Tund hiljem saad lõpuks aru, mis juhtus. Kogu selle aja oli süsteem katki.

LGTM-pinu lubab teistsugust töövoogu. Sa vaatad Grafanas dashboardi ja näed anomaaliat mõõdikute graafikul — Mimir või Prometheus serveerib neid andmeid. Klõpsad ajavahemikul ja hüppad täpselt samasse aega logidesse, mida Loki serveerib. Näed veateadet, millel on trace-ID. Klõpsad sellel ja avaneb jälituse vaade, mida teenindab Tempo — näed kogu päringu teed läbi mikroteenuste ja koha, kus see seiskus. Kõik ühes UI-s, ilma tabivahetuseta.

Inseneride keeles öelduna langeb MTTR (mean time to recovery) sedasi oluliselt, sest sa ei pea enam kolme tööriista vahel orienteeruma. Just see korrelatsiooni võimalus on see, mis teeb LGTM-pinust rohkem kui neli eraldi tööriista. Ilma korrelatsioonita oleks see lihtsalt nelja paketi kollektsioon. Grafana ise on kogu asja juures oluline detail: see on **ainus koht**, kust kasutaja midagi näeb. Kõik ülejäänud komponendid on päringuallikad, Grafana on koht, kus need päringud kokku tulevad.

### Self-hosted või Grafana Cloud

Iga sysadmin peab kunagi selle otsuse tegema. Self-hosted variandil — ehk siis Loki ja kaaslased omas Kubernetes-klastris — on eelisena täielik andmete kontroll. See on oluline GDPR-i, tundlike andmete ja siseeeskirjade seisukohast. Kulu on sul nähtav ja juhitav, maksad ainult infrastruktuuri eest. Paindlikkus on täielik — võid kõike tuunida ja muuta. Hind on aga operatiivne vastutus: kui keset ööd kukub ingester, vastutad selle eest sina. Lisaks eeldab see Kubernetese, Helmi, storage ja võrgunduse pädevust.

Grafana Cloud on sama stack hallatud kujul. Paigalduseni minutid, mitte nädalad. Grafana Labs vastutab uptime'i eest. Vahepeal on sul rohkem aega rakenduste jaoks. Miinuseks on see, et andmed lähevad Grafana pilve — privaatsuskaalutlus, mis osade organisatsioonide puhul lükkab selle valiku kohe kõrvale. Kulu põhineb logi- ja meetrikamahul, mis võib kiirelt kasvada viisil, mida on raske ette prognoosida.

Eestis kohtad mõlemat. Bolt ja Wise on enamasti self-hosted, sest nende mastaap on piisavalt suur, et operatiivne tiim oleks nagunii olemas ja kulu oluline. Väiksemad iduettevõtted lähevad tihti Grafana Cloud'iga, sest "lihtsalt töötab" on nende staadiumis olulisem kui kulu optimeerimine. Meie laboris kasutame self-hosted varianti Docker Compose'i peal, sest see annab arusaamise sellest, mis kapoti all toimub.

### Üks oluline tuleviku-otsus

Enne kui Loki juurde sukeldume, väärib üks kontseptsioon äramainimist. **OpenTelemetry** — lühend OTel — on CNCF-i standard, mis defineerib universaalse viisi, kuidas rakendused saadavad logisid, meetrikaid ja jälgi. Põhimõte on lihtne: instrumenteerid oma rakenduse OTel-iga ja seejärel saad samu andmeid saata ükskõik kuhu. Täna Grafana Cloud'i, homme self-hosted Lokile, ülehomme Datadog'i — rakendustes pole vaja midagi muuta, ainult kollektori sihtpunkti.

Grafana Labs tegi siin targa valiku. Nende uus agent, millest §7 räägib, toetab OTel-i natiivselt. See tähendab, et sina sysadminina saad valida tööriistad, ilma et seoksid end aastakümneks ühe tarnijaga. Kui OTel-ühilduv tööriist on valida, vali alati see. See on sinu kindlustuspoliis tuleviku vastu.

!!! tip "LGTM stack — täielik ülevaade"
    Käesolev loeng puudutab LGTM pinu Loki perspektiivist. Kui tahad näha kõiki nelja komponenti (Loki, Grafana, Tempo, Mimir) + Alloy agenti kõrvuti võrreldavana, koos andmevoo-diagrammiga ning pordi- ja protokolli-tabeliga, loe [Grafana Stack — LGTM ülevaade](../../resources/grafana-stack.md). Sealt leiad ka võrdluse teiste kursuse stackidega (Prometheus, Zabbix, ELK, TICK).

---

## 3. Loki kui "Prometheus logide jaoks"

2018. aasta mais, KubeConis San Franciscos, astus Tom Wilkie lavale ja tutvustas uut projekti. Tema kirjeldus on selleks ajaks saanud klassikaks:

> *"Loki: like Prometheus, but for logs."*

See pole turundushüüdlause, vaid arhitektuuriline avaldus. Prometheus töötab nii, et ta kogub iga sihtmärgi kohta mõõdikuid, mis on määratletud siltidega — `job="api"`, `env="prod"`. Sildid on indekseeritud, väärtused on aegrea andmed. Filtreerid siltidega, agregeerid väärtusi.

Loki teeb täpselt sama loogikaga, aga logidega. Ta kogub iga allika kohta logiridu, mis on määratletud samasuguste siltidega — `app="nginx"`, `namespace="prod"`. Sildid lähevad indeksisse, aga logi sisu on lihtsalt tekst, mis pakitakse kokku ja salvestatakse objektisalvestusse. Loki ei indekseeri sellest mitte midagi. Ei kasutajanime, ei IP-aadressi, ei veateksti. **Ainult silte.**

See on vastupidi sellele, kuidas Elasticsearch ja Splunk töötavad. Nende lähenemine on igivana: kui logirida tuleb sisse, tõkestatakse see sõnadeks, iga sõna lisatakse pöördindeksisse, indeks kasvab hiiglaslikuks, hoitakse SSD-l ja vajab palju RAM-i. Kui sul on kümme terabaiti logisid päevas, on Elasticsearchi indeks umbes viisteist terabaiti — suurem kui andmed ise. Sellel on oma põhjus: täistekstiotsing on kohene. Kirjutad otsingukasti sõna ja sekundi pärast on vastus. Aga hind on kõrge — SSD-d, RAM, shard-tuunimise pädevus.

Loki teeb vastupidi. Kui logirida tuleb sisse, eraldatakse sellest ainult sildid. Sildid lähevad väiksesse indeksisse, mille suurus on megabaitides, mitte terabaitides. Ülejäänud rida pakitakse tükiks — tavaliselt umbes megabait pakitult — ja salvestub S3-tüüpi objektisalvestusse, kus gigabait andmeid maksab kuus umbes ühe sendi. Kiire SSD klastri ja S3 vahel on salvestuskulude vahe umbes kahekümnekordne. Meeskonnad, kes on ELK-lt Lokile üle läinud, raporteerivad logihalduse kulude langust kolmekümne viie kuni viiekümne protsendi ulatuses. See on märkimisväärne arv, kui sinu monitooringueelarvest on kuuekohaline summa.

Loogiline küsimus on: kui logi sisu pole indekseeritud, kuidas sa siis otsid? Kuidas leiab Loki "error"-rea ilma indeksita? Vastus on: päringu ajal. Sa kirjutad LogQL-i päringu, mille alguses on siltide filter — näiteks `{app="nginx"}`. Loki leiab siltide järgi õiged logivood. Seejärel avab ta nende voogude tükid — mitte kogu süsteemi tükid, ainult siltidega vastavad — ja skaneerib neid paralleelselt, nagu grep. Kuna skaneerimine käib paralleelselt kümnetes querier-protsessides, on see kiire.

Tingimus on oluline: sa pead teadma siltide põhjal, kust otsida. Kui ütled Lokile "otsi kogu mu kümne terabaidi andmekogust sõna 'timeout'", ta ei rõõmusta ja vastus ei tule kiirelt. Operatiivse silumise jaoks — kus sa tead, millist rakendust uurida ja tahad näha selle vigu — on see ideaalne. Üldise forensika jaoks — "otsi kogu logikogumist suvalist mustrit" — on Loki nõrgem tööriist ja Elasticsearch võidab. See pole Loki puudus, see on **teadlik disain**.

---

## 4. Sildid ja logivood — arhitektuuri süda

Kui kogu Loki juurest peaks meelde jätma ainult ühe kontseptsiooni, siis see on logivoog. Logivoog on logiridade rühm, millel on täpselt sama komplekt silte. Niipea kui mõni silt erineb, tekib uus voog. Kolmest reast `{app="frontend", env="dev"}`, `{app="frontend", env="prod"}` ja `{app="backend", env="prod"}` on juba kolm eraldi voogu, hoolimata sellest, et rakendus on vaid kaks.

Iga voog on Loki jaoks eraldi üksus. Ta kirjutab seda eraldi, pakib eraldi, salvestab eraldi. Süsteem töötab korralikult, kui voogusid on mõistlik arv — tuhandeid, isegi kümneid tuhandeid. Kui neid on miljoneid, hakkab süsteem kiduma. See on põhjus, miks siltide valik on Loki administreerimise **kõige tähtsam otsus**.

Kuldreegel on lihtne: kõik sildid peavad olema piiratud väärtuste hulgast. Keskkond — näiteks `dev`, `staging`, `prod` — on kolm väärtust. See on hea silt. Klaster, kui sul on mitu regiooni, võib olla viis või kümme väärtust. Sobib. Rakenduse nimi, kui sul on kaks tosinat teenust, on endiselt väikese hulga sees. Ka see on hea silt.

Aga niipea kui paned silgiks IP-aadressi, kasutaja ID või trace-ID, lähed raja pealt maha. Iga uus unikaalne IP tekitab uue voo. Kümne tuhande kasutajaga süsteemis on sul üleöö kümme tuhat voogu. Saja tuhandega sada tuhat. Indeks paisub, tükid hakkavad olema killustatud, päringud aeglustuvad, ja lõpuks hakkab Loki uusi logisid tagasi lükkama, sest limit on ületatud.

Seda nähtust nimetatakse kardinaalsuse plahvatuseks ja see on Loki halbus, mille pärast mitmed meeskonnad on ta peale vihastanud ja kirjutanud blogipostitusi pealkirjaga "why we switched back to Elasticsearch". Peaaegu alati on nende probleem olnud sama: nad olid pannud trace-ID või kasutaja-ID sildiks.

### Kardinaalsus arvudes

Kardinaalsus tähendab unikaalsete sildikombinatsioonide arvu, ja see on number, mida Loki administraator peab teadma ja jälgima. Miks see täpselt nii kriitiline on, selgub, kui mõtled, mis juhtub väikeste voogudega. Iga voog salvestatakse eraldi tükkideks, ja ideaalne tüki suurus on umbes megabait pakitult. Kui tükk täitub, kirjutab Loki selle objektisalvestusse.

Nüüd kujutle olukorda, kus sul on kümme tuhat voogu, millest igaüks toodab vaid mõne kilobaidi logisid tunnis. Arvutuses on kogumaht sada megabaiti tunnis — tagasihoidlik. Aga igas voos on üks väike tükk. Kokku kümme tuhat väikest tükki. Iga tükk on eraldi fail S3-s. Iga päring, mis neid puudutab, teeb kümme tuhat HTTP-kutset. Iga tükk võtab ingesteri mälu. Süsteem muutub aeglaseks, hoolimata sellest, et andmete koguhulk on väike.

Praktilised piirid on kogemuslikud: kuni saja gigabaidi päevamahtu võib lubada kuni kümmet tuhat voogu, tera- ja üle selle võib mastaabist lähtudes lubada rohkem. Sada tuhat voogu ei ole eesmärk, see on piir, mida päris suured keskkonnad puudutavad, aga tavaline tootmiskeskkond elab tuhande või kahe tuhandega täiesti õnnelikult. Tehniliselt on siltide arv voo kohta piiratud viieteistkümnega, aga reaalselt toimivates süsteemides on neid viis kuni kaheksa.

### Structured Metadata — Loki 3.0 lahendus

Arendajad põhjendavad sageli kardinaalsuse reegli rikkumist nii: "aga mul on vaja trace-ID järgi otsida, muidu pole OpenTelemetry mõtet". Kuni Loki versioonini 2.x oli vastus ebamugav — kasuta filtrit, mitte silti. Päring näeks välja selline: `{app="api"} |= "trace_id=abc123"`. See töötab, aga on aeglane, sest Loki peab sisu skaneerima.

2024. aasta aprillis ilmus Loki 3.0 ja sellega lahendus — **Structured Metadata**. See on kolmas kategooria metaandmeid, mis elab logirea kõrval, aga mitte indeksis. Ülemisel tasemel on endiselt sildid, mis lähevad indeksisse ja peavad olema väikese kardinaalsusega. Keskmisel tasemel on Structured Metadata — otsitav ja kiire, aga mitte indekseeritud. Alumisel tasemel on logirea sisu, mis on pakitud ja salvestub objektisalvestusse.

See kolmetasandiline mudel lahendab kogu probleemi. Kõrge kardinaalsusega andmed nagu trace-ID, kasutaja-ID ja päringu-ID lähevad nüüd Structured Metadatasse, mitte siltidesse. Kardinaalsuse plahvatuse oht kaob. Kui kavandad 2026. aastal uut Loki-juurutust, pea meeles: trace-ID ei kuulu kunagi silti. Ta kuulub Structured Metadatasse.

---

## 5. Kuidas Loki paigaldatakse

Loki saab paigaldada kolmel viisil. Üks neist on aegumas, mis on oluline teada enne kui hakkad ehitama.

Lihtsaim variant on **monolithic mode**, kus kogu Loki töötab ühes protsessis. Üks binaarfail, kõik sisemised komponendid selle sees. Käivitad ühe Docker Compose'i või ühe Helm-chartiga, ja asi töötab. See sobib keskkondadele, kus logimaht on kuni paarkümmend gigabaiti päevas — arendusjärgus süsteemid, testkeskkonnad, väikesed tootmised, koolitusruumid. Meie laboris kasutame täna just seda režiimi.

Teine variant on **Simple Scalable Deployment** ehk SSD, mis jagab töö kolmeks rolliks: kirjutus, lugemine ja backend. See oli mõeldud vahepealseks variandiks suurte ja väikeste paigalduste vahel. Sobis kuni terabaidile päevas. 2025. aasta märtsis teatas aga Grafana Labs, et SSD režiimi keerukuse ja kasu suhe pole enam mõistlik, ja selle ametlik tugi lõpetatakse enne Loki 4.0 versiooni. Kui kohtad seda dokumentatsioonis või vanemas tutorialis, hoia eemale. Alusta monolithic'uga, kasva vajadusel otse microservices-iks.

Kolmas variant — **microservices mode** — on tootmiskeskkonna standard. Iga komponent jookseb eraldi Kubernetes-deployment'ina ja iga komponenti saab eraldi skaleerida. Kui kirjutamiskoormus kasvab, lisad ingester'eid. Kui päringuid tuleb rohkem, lisad querier'eid. See režiim toetab ka tsoonitundlikku replikatsiooni, mis tähendab, et ingester'id jaotatakse eri Kubernetes-tsoonidesse ja kui üks tsoon kukub, süsteem toimib edasi. Kasuta seda, kui päevamaht ületab terabaidi või kui käideldavus on kriitiline.

### Komponendid, mida näed mikroteenuste režiimis

Isegi kui sa kasutad monolithic-režiimi, töötavad sees samad komponendid — ainult ühe protsessi sees. Kirjutamistee liigub Alloy-agendist gateway kaudu distributor'isse. Distributor on värav: võtab vastu, valideerib, teeb rate limitingut, kontrollib tenant-ID-d ja suunab logi siltide räsimise põhjal õigele ingester'ile. Ingester ise on süsteemi süda — ta puhverdab logid mälus, pakib neid tükkideks, replikeerib tüüpiliselt kolme eksemplari ja kui tükk on valmis, kirjutab S3-sse.

Lugemistee käib teistpidi. Grafana esitab päringu, mis läheb läbi gateway query frontend'ile. Frontend tükeldab päringu väiksemateks — kui sa küsid viimase kahekümne nelja tunni andmeid, jagatakse see kahekümne neljaks paralleelseks tunni-päringuks. Query scheduler paneb need järjekorda ja jaotab querier'ite vahel. Querier teeb tegeliku töö: küsib andmeid nii ingester'itelt (kõige värskem, mis on veel mälus) kui ka S3-st (vanemad tükid), teeb deduplikatsiooni (sest tükid on replikeeritud) ja tagastab tulemuse.

Taustaprotsessidest on oluline eraldi mainida compactor'it. See käib regulaarselt üle kõigist tükkidest, ühendab väiksed tükid suuremateks, optimeerib indeksit ja kustutab vanu andmeid vastavalt säilituspoliitikale. Ilma compactor'ita paisub S3 killustunud väikeste failide hunnikuks ja päringute jõudlus langeb. Teine oluline taustaprotsess on ruler, mis täidab alertimise ja recording-reegleid — täpselt samal loogikal nagu Prometheuses. Sellega saad kirjutada reegli, mis ütleb: kui viimase viie minuti jooksul on rohkem kui sada `level=error` rida, saada hoiatus.

---

## 6. Logide agent — Promtail on läinud, tule Alloy

Aastaid oli Loki standardagent **Promtail** — lihtne ja väikese jalajäljega binaar, mis lugedi logifaile üles ja saatis need Lokile. See oli lihtne ja töötas hästi. 2024. aastal teatas Grafana Labs aga, et Promtail läheb feature-freeze seisu ja tulevik on **Grafana Alloy**.

Alloy on universaalne telemeetria-kollektor. Üks ja sama agent kogub kõik kolm asja — logisid, meetrikaid ja jälgi. Ta põhineb OpenTelemetry Collectori komponentidel, aga pakub lisaks Grafana maailmas testitud konfiguratsiooni ja komponente, mis kohanduvad just Loki, Mimiri ja Tempo jaoks optimaalselt. Kui ehitad täna uut süsteemi, kasuta Alloy'd. Kui sul on vana Promtail-deployment, töötab see edasi, aga tasub migratsioon plaanima hakata. Grafana pakub ametlikku migratsiooni dokumenti, mis konverteerib Promtail'i YAML-konfi Alloy HCL-sarnaseks konfiks.

Laboris tänane Alloy-konfig on väga lihtne: kolm plokki, mis lubavad lugeda logifaile konkreetsest kataloogist ja saata need Lokile. Aga sama agent skaleerub tootmises ka meetrikate kogumisele Prometheuse või Mimiri jaoks ning jälgede vastuvõtule OpenTelemetry protokollis. Kolm eraldi agenti — Promtail, node_exporter ja otel-collector — asenduvad ühe Alloy-konteineriga. See on oluline administreerimise lihtsustus: üks agent, üks konfig, üks protsess, mida hoida silma peal.

---

## 7. LogQL — päringukeel lühidalt

LogQL on PromQL-i vend. Kui PromQL on sul kuidagi tuttav, siis LogQL-iga saad hakkama umbes veerand tunniga. Keel on teadlikult üles ehitatud nii, et Prometheuse kasutajal oleks tunne "oh, seda ma oskan".

Kõige lihtsam päring on voo valik: `{app="nginx", env="prod"}`. See tagastab kõik logiread, mille sildikomplekt vastab täpselt sellele filtrile. Sealt edasi saad lisada tekstifiltreid. `|= "error"` tähendab "sisaldab sõna error", `!= "healthcheck"` tähendab "ei sisalda" ja `|~ "5[0-9]{2}"` teeb regex-otsingu, millega saad näiteks tabada HTTP viievõti-koodid.

Aga tekstifiltri piirang on sama mis grep-i puhul — see on aeglane ja ebatäpne. Kui su logid on struktureeritud formaadis, tasub kasutada parserit. LogQL-il on neid neli. **JSON-parser** võtab struktureeritud logid ja teeb iga väljast eraldi muutuja — pärast `| json` saad kirjutada `status_code >= 500`. **Logfmt** teeb sama asja logfmt-vorminguga (võti=väärtus paarid), mis on väga levinud Go-rakendustes. **Pattern** on vabateksti-parser, millega saad määrata mustri ja nimetada kohad, kust väljad välja võtta — näiteks `| pattern "<_> [<level>] <_>"` võtab ERROR-i nurksulgudest. **Regexp** on viimane variant, kui miski muu ei sobi — töötab alati, aga aeglaselt ja on vigaderohke.

Parseri valik sõltub logi formaadist. Kui logi näeb välja nagu `{"level":"error","user":"ann"}`, kasuta `json`. Kui ta on kujul `level=error user=ann duration=42ms`, kasuta `logfmt`. Kui ta on vabatekst aga stabiilse struktuuriga — näiteks `2026-04-25 10:23 ERROR user=ann failed` — kasuta `pattern`. Ja kui struktuuri üldse pole, alles siis vali `regexp`.

Siin läheb aga asi päriselt huvitavaks. LogQL võimaldab logidest teha meetrikuid PromQL-sarnase süntaksiga. Kirjutad `rate({app="nginx"} |= "error" [5m])` ja saad "error-ridu sekundis viimase viie minuti jooksul" — täpselt nagu oleks see Prometheuse counter. Võid grupeerida siltide järgi: `topk(5, sum by (app) (rate({env="prod"} |~ "5[0-9]{2}" [1h])))` annab viis suurimat 5xx-vigade allikat viimase tunni jooksul. Logidest saab number, numbrist saab graafik, graafikust saab alert. Laboris teeme seda osas 3.4, kui muudame payment-teenuse veaarvu graafikuks ja dashboard-paneeliks.

---

## 8. Loki versus ELK — millal kumba valida

Ei ole õiget ja valet tööriista, on sobiv ja sobimatu konteksti jaoks. Loki ja Elasticsearch on mõlemad head tööriistad, aga nad on head **erinevate ülesannete** jaoks.

Loki sobib hästi siis, kui sul on juba Grafana või Prometheus kasutuses — integratsioon on sujuv ja korrelatsiooni kolmik töötab kohe. Sobib hästi operatiivse silumise jaoks, kus sa tead millist rakendust uurid ja otsid sealt põhjust. Sobib, kui eelarve on piiratud ja logihulk kasvab — kolmkümmend viis kuni viiskümmend protsenti kulude kokkuhoidu pole väike. Sobib Kubernetese keskkonda, kuhu ta on sisuliselt sündinud.

Elasticsearch sobib hästi siis, kui teed turvaforensikat ja pead otsima suvalisi mustreid kogu andmekogust, mitte ainult teatud rakenduse omast. Sobib, kui süvaanalüüs on peamine kasutusviis — agregatsioonid, keerukamad päringud, aja jooksul mustrite leidmine. Sobib, kui vajad mittetehnilist UI-d, sest Kibana on logide jaoks oluliselt parem kui Grafana. Ja sobib alati, kui compliance-nõue dikteerib täisteksti indekseerimise — mõned regulatiivsed raamistikud, eriti finantssektoris, eeldavad seda sõnaselgelt.

Paljudes ettevõtetes leiad mõlemad **paralleelselt**. Loki igapäevaseks operatiivseks tööks DevOps-tiimi käes, Elasticsearch eraldi platvormina turvatiimile. See pole raiskamine, see on mõistlik tööjaotus. Kumbki tööriist on hea omas kohas, ja mõlema paralleelne kasutamine annab mõlema eelised.

---

## 9. Üks hoiatus — Helm-chart'ide džungel

Kui otsid Google'ist "loki helm chart", leiad kolm erinevat nime ja kaks neist on surnud. See on piisavalt levinud komistuskivi, et seda tasub eraldi mainida.

Ainus elav ja aktiivselt arendatav chart on `grafana/loki`. See toetab Loki 3.0+ versioone ja on see, mida peaksid kasutama. Teised kaks — `grafana/loki-stack` ja `grafana/loki-distributed` — on mõlemad surnud või suremas. Esimene on ametlikult deprecated, teine on hooldamata ja seisab Loki 2.9.0 peal, mis on juba aegunud.

Eriline hoiatus tuleks siia lisada, kui kasutad `values.yaml` genereerimiseks suurt keelemudelit nagu ChatGPT või Claude. Mudelite treeningandmed sisaldavad vanu tutoriaale ja nad pakuvad sageli `loki-stack`-i näidiseid, mis olid kolm aastat tagasi standardvalik. Nüüd need ei tööta Loki 3.0+ maailmas. Kui mudel annab sulle chart'i nime, kontrolli alati, et see on `grafana/loki` ja mitte miski muu. Ametlik dokumentatsioon on õigem kui mudeli vastus.

---

## 10. Kokkuvõte

Loki lugu on huvitav, sest see pole esimene logihaldussüsteem ega parim kõigis mõõdetavustes — aga ta tegi ühe asja õigesti. Ta küsis, mida tegelikult logidest vaja on, ja vastas, et enamikes kasutuslugudes on vaja operatiivselt küsida "mis rakenduses ja millal midagi juhtus". Ülejäänu — täistekstiotsing suvalise mustriga, pikaajaline forensika — on teiste tööriistade pärusmaa.

Sellest vastusest tuli disain, mis indekseerib ainult silte. Sellest tuli odav salvestus S3-l ja kolmekümne viie kuni viiekümne protsendi võit ELK-i ees. Sellest tuli sõltuvus siltide distsipliinist, mis on esmane põhjus, miks Loki-juurutused valesti lähevad. Siltide kardinaalsus on kogu süsteemi tähtsaim haldussuurus. IP-aadressid, trace-ID-d ja kasutaja-ID-d ei kuulu siltidesse kunagi — Loki 3.0 Structured Metadata andis nendele eraldi koha.

Paigaldus-ja komponendipoolt on mõistlik alustada monolithic-režiimiga ja kasvada mikroteenuste peale, kui päevamaht jõuab terabaidini. SSD-režiim, mis vahepeal oli populaarne, on aegumas. Helm-chartidest on elus ainult `grafana/loki`. Agent on täna Alloy, mitte Promtail, ja see valik lahendab lisaks logidele ka meetrikate ja jälgimise kogumise.

Loki on noor ja areneb kiiresti. Tänane best practice võib aastaga muutuda — Bloom-filtrid, Structured Metadata, Alloy — kõik tulid viimase kahe aasta jooksul. Seetõttu on oluline eelistada ametlikku dokumentatsiooni blogidele, ja blogisid LLM-ide vastustele. Ajalugu on seda tehniliste teemade puhul alati öelnud, aga Loki puhul eriti.

Järgmine samm on [Labor: Loki](../../labs/02_zabbix_loki/loki_lab.md). Ehitame seal Loki + Alloy + Grafana stacki, kirjutame LogQL päringuid ja seome kokku Zabbix labori tulemustega nii, et sama sündmust näed kahest perspektiivist — Zabbix ütleb "on probleem", Loki näitab "mis juhtus".

---

## Enesekontrolli küsimused

<details>
<summary><strong>Küsimused + vastused (peida/ava)</strong></summary>

1. Kui Loki ei indekseeri logi sisu, kuidas ta siis "error"-rea leiab? Milline on sellise päringu jõudluse piirang?
2. Selgita, miks `trace_id` ei tohi olla Loki silt. Mis juhtub, kui sa ta siiski sildiks paned?
3. Mis on erinevus Structured Metadata ja siltide vahel? Millal kumba kasutada?
4. Sul on uus juurutus: ~50 GB logisid päevas, üks meeskond, Kubernetes. Millise paigaldusrežiimi valid ja miks?
5. Miks on SSD paigaldusrežiim aegumas?
6. Kirjuta LogQL päring: Nginx 5xx-vigade määr sekundis viimase 5 minuti jooksul, rakenduse järgi grupeeritud.
7. Millal eelistad Loki, millal ELK? Nimeta kaks konkreetset stsenaariumi kummagi jaoks.

??? note "Vastused (peida/ava)"
    1) Loki leiab "error"-rea kas täisteksti filtriga (`|= "error"`) või parseri ja filtri kombinatsiooniga pärast pattern- või logfmt-parsimist. Piirang on selles, et kui filtreerid ainult sisu järgi, peab Loki rohkem tükke skaneerima ja see muutub aeglasemaks, mida vähem siltidega enne kitsendasid. Seetõttu on esimene soovitus alati: alusta kitsast silifiltrist, siis alles tekstifilter.

    2) `trace_id` on kõrge kardinaalsusega — peaaegu iga logirea kohta unikaalne. Kui paned sildiks, tekib "stream explosion": kümme tuhat päringut päevas tähendab kümme tuhat eraldi voogu, indeks paisub, ingester mälu täitub, päringud aeglustuvad ja lõpuks hakkab Loki tagasi lükkama uusi logisid, sest limit on ületatud. Õige koht on Structured Metadata (Loki 3.0+).

    3) Sildid on indekseeritud, peavad olema madala kardinaalsusega (kuni umbes sada unikaalset väärtust) ja neid kasutatakse voogude valikuks päringu alguses. Structured Metadata on otsitav ja kiire, aga ei indekseerita — seal võib olla kõrge kardinaalsus (trace-ID, kasutaja-ID). Reegel: sildid on dimensioonid (millises rakenduses, millises keskkonnas), Structured Metadata on detailid (milline konkreetne päring).

    4) Viiekümne gigabaidi juures päevas on monolithic piiripealne — ametlik soovitus on kuni kahekümne GB. Kui kasv on ootuspärane ja tahate paar aastat edasi minna, kavanda kohe microservices Helm-chart'iga (`grafana/loki`). Kui maht on stabiilne ja meeskond ei taha Kubernetese keerukust, jää monolithic'uga ja vajadusel migreerid hiljem.

    5) SSD oli vahepealne variant monolithic ja microservices vahel. Praktikas tuli välja, et ta on keerulisem kui monolithic (kolm rolli hallata) ja ei skaleeru nii hästi kui microservices (ei saa iga komponenti eraldi skaleerida). Kasu-keerukuse suhe ei õigusta teda enam, seetõttu Grafana Labs soovitab otse monolithicu ja microservices'i vahel hüpata.

    6) 
       ```logql
       sum by (app) (
         rate(
           {job="nginx"}
             | pattern `<_> <_> <_> <_> <_> <status> <_>`
             | status =~ "5.."
             [5m]
         )
       )
       ```

    7) **Loki:** operatiivne silumine konkreetse rakenduse kontekstis, odavam logikiht piiratud eelarvega meeskondadele, Kubernetese natiivsus, Grafana-keskne stack. **ELK:** turvaforensika suvaliste mustrite järgi, keerukad agregatsioonid ja analüütika, mittetehnilise kasutaja UI Kibanaga, compliance-nõue täisteksti indekseerimiseks.

</details>

---

## Allikad

??? note "Allikad (peida/ava)"
    **Ametlik dokumentatsioon:**

    - Grafana Loki: <https://grafana.com/docs/loki/latest/>
    - Loki arhitektuur: <https://grafana.com/docs/loki/latest/get-started/architecture/>
    - Paigaldusrežiimid: <https://grafana.com/docs/loki/latest/get-started/deployment-modes/>
    - LogQL: <https://grafana.com/docs/loki/latest/query/>
    - Siltide parimad tavad: <https://grafana.com/docs/loki/latest/get-started/labels/>
    - Structured Metadata: <https://grafana.com/docs/loki/latest/get-started/labels/structured-metadata/>
    - Grafana Alloy: <https://grafana.com/docs/alloy/latest/>
    - Helm chart (ametlik): <https://github.com/grafana/loki/tree/main/production/helm/loki>

    **Teooria ja kontekst:**

    - KubeCon 2018 Loki tutvustus (Tom Wilkie): <https://www.youtube.com/results?search_query=loki+tom+wilkie+kubecon+2018>
    - Loki 3.0 release post: <https://grafana.com/blog/2024/04/09/grafana-loki-3.0-release/>
    - "How we designed Loki" (Tom Wilkie): <https://grafana.com/blog/2018/12/12/loki-prometheus-inspired-open-source-logging-for-cloud-natives/>
    - Promtail → Alloy migratsioon: <https://grafana.com/docs/alloy/latest/tasks/migrate/from-promtail/>

    **Laboris testitud versioonid (aprill 2026):** Loki 3.7.1, Grafana 12.4.3, Alloy 1.15.1.

---

*Järgmine: [Labor: Loki](../../labs/02_zabbix_loki/loki_lab.md) — ehitame Loki + Alloy + Grafana stacki ja teeme LogQL päringuid.*

--8<-- "_snippets/abbr.md"
