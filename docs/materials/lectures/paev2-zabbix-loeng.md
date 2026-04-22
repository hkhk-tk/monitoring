# Päev 2: Zabbix — agent-põhine monitooring

**Kestus:** ~20 minutit iseseisvat lugemist
**Eeldused:** Päev 1 (Prometheus pull-mudel, Grafana, PromQL alused)
**Versioonid laboris:** Zabbix 7.0.6 LTS, MySQL 8.0
**Viited:** [zabbix.com/documentation/7.0](https://www.zabbix.com/documentation/7.0/en/manual) · [Zabbix blog](https://blog.zabbix.com/)

---

## Õpiväljundid

Pärast selle materjali läbitöötamist osaleja:

1. **Eristab** Zabbixi agent-mudelit Prometheuse pull-mudelist ja põhjendab millal kumbagi eelistada
2. **Kirjeldab** Zabbixi nelja komponendi rolle ja nende omavahelisi seoseid
3. **Selgitab** item'ide, trigger'ite ja template'ite seoseid Zabbixi andmemudelis
4. **Mõistab** UserParameter'i kui laiendusmehanismi ja Low-Level Discovery printsiipe
5. **Hindab** Zabbixi positsiooni 2026. aasta monitoorimismaastikul

---

## 1. Push vs Pull — kaks filosoofiat

Eile ehitasid Prometheuse, mis **küsib** ise andmeid sihtmärkidelt (pull). Zabbix teeb vastupidi — **agent saadab** andmeid serverile (push). Mõlemad on õiged. Mõlemad on 2026. aastal laialdaselt kasutusel. Erinevus on filosoofiline.

### Pull-mudel (Prometheus)

Prometheus otsustab ise, millal andmeid koguda. `scrape_interval: 15s` — iga 15 sekundi järel küsib ta igalt sihtmärgilt `/metrics` endpoint'i. Kui sihtmärk ei vasta, on see kohe näha: `up == 0`.

See sobib hästi **dünaamilistes keskkondades** — Kubernetes pod'id tekivad ja kaovad, service discovery leiab need automaatselt. Prometheus ei pea teadma, mis serverid on olemas — ta avastab need ise.

### Push-mudel (Zabbix)

Zabbix agent jookseb igal masinal ja saadab andmeid serverile. Agent teab oma masina kohta kõike — ta on seal kohal, jookseb root'ina (või peaaegu), tal on ligipääs süsteemifailidele, protsessitabelile, riistvara sensoritele.

See sobib hästi **stabiilsetes keskkondades** — 500 serverit, mis ei vahetu iga päev. Tööstusautomaatika, võrguseadmed (SNMP), Windows-serverid, printer'id — kõik, mis seisab paigal ja vajab sügavat monitoorimist.

### Millal kumbagi?

| Kriteerium | Prometheus | Zabbix |
|-----------|-----------|--------|
| Kubernetes, konteinerid | Esimene valik | Võimalik, aga keeruline |
| 500 Linux/Windows serverit | Võimalik | Esimene valik |
| SNMP seadmed (switchid, printerid) | Ei sobi | Sisseehitatud |
| Infrastruktuuri autoscaling | Pull + service discovery | Agent tuleb installida |
| Windows monitooring | windows_exporter | Natiivne agent |
| Compliance/audit | Piiratud | Põhjalik audit log |

Eestis kohtad mõlemat. Bolt ja Wise kasutavad Prometheust (Kubernetes). Telia, Elisa, pangad kasutavad sageli Zabbixit (sadu stabiilset serverit). Paljudel on mõlemad korraga.

---

## 2. Zabbixi arhitektuur

Zabbix koosneb neljast komponendist. Erinevalt Prometheusest, kus kõik on ühes binaarfailis, on Zabbix modulaarne.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Zabbix Web  │────▶│Zabbix Server │────▶│    MySQL      │
│  (PHP+Nginx) │     │  (C daemon)  │     │  (andmebaas)  │
│  port 8080   │     │  port 10051  │     │  port 3306    │
└──────────────┘     └──────┬───────┘     └──────────────┘
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
        ┌──────────┐  ┌──────────┐  ┌──────────┐
        │ Agent 1  │  │ Agent 2  │  │ Agent N  │
        │ port     │  │ port     │  │ port     │
        │ 10050    │  │ 10050    │  │ 10050    │
        └──────────┘  └──────────┘  └──────────┘
```

**MySQL** hoiab konfiguratsiooni (host'id, template'id, trigger'id) ja ajaloolisi andmeid (mõõdikute väärtused). Zabbixi andmemudel on relatsioonilises andmebaasis, mitte TSDB-s nagu Prometheus. See tähendab et Zabbix saab teha keerulisi päringuid andmete vahel, aga suure andmemahuga on MySQL aeglasem kui spetsiaalne aegrea andmebaas.

**Server** on peamine komponent — küsib agent'idelt andmeid (passive check), võtab vastu andmeid agent'idelt (active check), arvutab trigger'eid, saadab hoiatusi. See on C-s kirjutatud daemon mis vajab märkimisväärset RAMi suurte installatsioonide puhul.

**Web** on PHP+Nginx veebiliides. Erinevalt Grafanast, mis on ainult visualiseering, on Zabbix Web ka konfiguratsioonitööriist — host'ide lisamine, template'ite loomine, trigger'ite seadistamine kõik tehakse läbi UI (või API).

**Agent** jookseb igal monitooritaval masinal. Ta teeb kahte asja: vastab serveri päringutele (passive — server küsib, agent vastab) ja saadab andmeid ise (active — agent saadab, server kuulab). Laboris kasutame passive-mudelit.

---

## 3. Zabbixi andmemudel

Zabbix andmemudel on hierarhiline ja päris erinev Prometheuse label-põhisest lähenemisest.

### Host

Host on monitooritav objekt — server, switch, printer, rakendus. Igal host'il on üks või mitu interface'i (Agent, SNMP, IPMI, JMX) mis määravad kuidas Zabbix temaga räägib.

### Template

Template on item'ite, trigger'ite, graafikute ja discovery-reeglite kogum mida saab host'ile külge panna. `Linux by Zabbix agent` sisaldab ~300 item'it (CPU, mälu, ketas, võrk) ja ~50 trigger'it. Template'id on korduvkasutatavad — ühte muudatust saad rakendada sajale host'ile korraga.

Prometheuses pole template kontseptsiooni — dashboard'id ja alert'id on eraldi failides. Zabbixi template ühendab kõik ühte pakki.

### Item

Item on üks konkreetne mõõdik. `system.cpu.util[,idle]` tagastab CPU idle protsendi. Iga item'il on tüüp (kuidas andmeid kogutakse), võti (key), intervall ja andmetüüp.

Zabbixi item'ide tüübid on palju laiemad kui Prometheus'e üks formaat:

| Tüüp | Kuidas töötab | Kasutus |
|------|--------------|---------|
| Zabbix agent | Agent kogub, server küsib | Süsteemi meetrikad |
| HTTP agent | Server teeb HTTP päringu | API-d, veebiteenused |
| SNMP agent | SNMP poll | Võrguseadmed |
| Dependent item | Tuletatud teisest item'ist | Üks päring → mitu mõõdikut |
| Zabbix trapper | Agent saadab ise (push) | CI/CD, skriptid, batch-tööd |
| Calculated | Valem teistest item'itest | Tuletatud mõõdikud |

### Trigger

Trigger on avaldis mis hindab item'i väärtust ja otsustab kas probleem on. `last(/host/system.cpu.util[,idle]) < 20` — kui idle CPU on alla 20%, on probleem. Trigger'il on severity (Information → Warning → Average → High → Disaster) ja olekud (OK → PROBLEM).

Erinevus Prometheusest: Prometheuses on alerting rule eraldi YAML-failis. Zabbixi trigger on osa template'ist ja hallatakse UI-st.

### Action

Trigger tuvastab probleemi, action reageerib. Action ütleb: "kui trigger severity on ≥ Warning, saada Discord webhook". Actions'is on conditions (millal käivitada), operations (mida teha) ja recovery operations (mida teha kui probleem laheneb).

---

## 4. UserParameter — miks see on oluline

Zabbixi sisseehitatud item'id katavad süsteemi meetrikaid hästi. Aga iga organisatsioon vajab **oma spetsiifilisi** mõõdikuid — rakenduse logidest error'ite lugemine, honeypot'i tabamuste arv, deployment'i versioon, andmebaasi custom päring.

UserParameter on lihtne mehhanism: ühe rea konfiguratsioon ütleb agent'ile "kui server küsib võtit X, käivita shell-käsk Y ja tagasta tulemus".

```
UserParameter=minu.moodic, käsk-mis-tagastab-numbri
```

See muudab Zabbixi lõputult laiendatavaks. Iga skript, iga programm, iga üherealine mis tagastab numbri või teksti — saab Zabbixi mõõdikuks. Laboris ehitame mitu näidet scaffolding-stiilis, alustades triviaalsest ja jõudes päris rakenduseni.

---

## 5. Low-Level Discovery (LLD)

Kujuta ette: sul on 5 rakendust, igaühel 3 logi taset (INFO, WARN, ERROR). See on 15 item'it. Käsitsi loomine töötab. Aga kui rakendusi on 50? Või kui uus rakendus lisandub pidevalt?

LLD lahendab selle. Agent tagastab JSON-i mis kirjeldab avastatud objekte. Zabbix loob iga avastatud objekti jaoks item'i ja trigger'i automaatselt, kasutades **prototüüpe**.

```
Agent tagastab:
[
  {"{#SERVICE}":"payment", "{#SEVERITY}":"ERROR"},
  {"{#SERVICE}":"auth", "{#SEVERITY}":"ERROR"},
  ...
]

Zabbix loob automaatselt:
  - applog.count[ERROR,payment] → item + trigger
  - applog.count[ERROR,auth] → item + trigger
  - ... iga kombinatsiooni jaoks
```

Uue teenuse lisandumisel (nt `shipping`) avastab Zabbix selle järgmisel discovery-tsüklil ja loob item'id automaatselt. Eemaldatud teenuse item'id kustutatakse pärast retention-perioodi.

Prometheuses sama efekt saavutatakse `relabel_configs` ja service discovery kaudu, aga kontseptsioon on erinev. Zabbix LLD on eksplitsiitne — sa kirjutad discovery-skripti ja prototüübid. Prometheus on implitsiitne — mõõdikud tekivad eksporteritest automaatselt.

---

## 6. Zabbix 2026 — kus ta seisab?

Zabbix on 25 aastat vana (asutatud 2001, Aleksei Vladyšev, Läti). Versioon 7.0 LTS (2024) tõi kaasa olulisi uuendusi: uuendatud UI, Prometheus'e mõõdikute import, paremad API-d, cloud-native tugi.

DB-Engines edetabelis on Zabbix monitooringu kategoorias endiselt populaarseim agent-põhine lahendus. Prometheus on kasvanud kiiresti (eriti Kubernetes-maailmas), aga Zabbix domineerib endiselt traditsioonilises IT-s.

Eesti tööturul kohtad mõlemat. Paljud ettevõtted kasutavad Zabbixit infrastruktuuri jaoks ja Prometheust konteinerite jaoks — need ei ole konkurendid, vaid täiendavad teineteist.

---

## Allikad

| Allikas | URL | Miks oluline |
|---------|-----|--------------|
| Zabbix 7.0 manuaal | [zabbix.com/documentation/7.0](https://www.zabbix.com/documentation/7.0/en/manual) | Ametlik allikas |
| UserParameters | [zabbix.com/.../userparameters](https://www.zabbix.com/documentation/7.0/en/manual/config/items/userparameters) | Laboris kasutusel |
| Low-Level Discovery | [zabbix.com/.../low_level_discovery](https://www.zabbix.com/documentation/7.0/en/manual/discovery/low_level_discovery) | LLD prototüübid |
| HTTP Agent | [zabbix.com/.../http](https://www.zabbix.com/documentation/7.0/en/manual/config/items/itemtypes/http) | Dependent items |
| Zabbix API | [zabbix.com/.../api](https://www.zabbix.com/documentation/7.0/en/manual/api) | Automatiseerimine |
| Community templates | [github.com/zabbix/community-templates](https://github.com/zabbix/community-templates) | Valmis template'id |

---

*Järgmine: [Zabbix labor](../labs/02_zabbix_loki/zabbix_lab.md)*
