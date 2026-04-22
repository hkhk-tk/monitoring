# Kaasaegne IT-süsteemide monitooring ja jälgitavus

**Täienduskoolitus** · 26 akadeemilist tundi · 5 laupäeva · Haapsalu KHK · 2026

---

## Ajakava

| Päev | Kuupäev | Kell | Teemad |
|------|---------|------|--------|
| 1 | 18. aprill | 10:00–14:30 | Monitooringu alused + Prometheus + Grafana |
| 2 | 25. aprill | 10:00–14:30 | Zabbix + Loki |
| 3 | 9. mai | 10:00–14:30 | Elastic Stack (ELK) |
| 4 | 23. mai | 10:00–14:30 | TICK Stack + Kesksed logimissüsteemid |
| 5 | 6. juuni | 10:00–14:30 | Tempo + OpenTelemetry + LGTM tervik + Trendid |

## Laborikeskkond

Igal osalejal on isiklik virtuaalmasin (4GB RAM, Docker eelinstallitud):

```
mon-<sinu-nimi>       — sinu Docker host (192.168.5.12X)
mon-target            — jagatud Linux server (192.168.5.140)
mon-target-web        — jagatud veebiserver (192.168.5.141)
```

Ligipääs: `ssh student@192.168.5.12X` (parool jagatakse kohapeal)

## Kuidas me töötame

Iga teema on ehitatud üles tsüklitena:

1. **Probleem** — reaalse olukorra kirjeldus (5 min)
2. **Käed külge** — Docker Compose üles, konfig tehtud (25 min)
3. **Mini-teooria** — nüüd selgitame miks see nii töötab (10 min)
4. **Väljakutse** — iseseisvalt lahendatav ülesanne (10 min)

Teooria tuleb **pärast** praktikat, mitte enne. Iga päev alustame ja lõpetame lühikese aruteluga.

## Mida monitoorime

Kaks jagatud target-masinat simuleerivad "tootmiskeskkonda":

- **mon-target** — Linux server kus jooksevad teenused ja genereeritakse logisid (sh vigaseid)
- **mon-target-web** — Nginx veebiserver kus tekivad HTTP vead ja aeglased päringud

Koolitaja tekitab jooksvalt probleeme — teie ülesanne on need oma monitooringust leida.

## Päevade ülevaade

### Päev 1: Prometheus + Grafana
Metrics-sammas. Prometheus kogub mõõdikuid, Grafana visualiseerib. Lõpuks on teil töötav dashboard alertidega.

### Päev 2: Zabbix + Loki
Agent-based monitoring (Zabbix) + logi-sammas (Loki). Grafanas näete nii metrikaid kui logisid koos.

### Päev 3: Elastic Stack
Alternatiivne logimislahendus. Elasticsearch indekseerib, Logstash töötleb, Kibana visualiseerib. Võrdlus Lokiga.

### Päev 4: TICK Stack + laiem pilt
Ajaridade monitooring (InfluxDB) + ülevaade Opensearch, Graylog, Kafka — millal mida kasutada?

### Päev 5: LGTM tervik + Tulevik
Tempo lisamine traces-sambana. Kogu LGTM stack: metrics↔logs↔traces navigeerimine Grafanas. Observability trendid 2026.

---

*Koolitaja: Maria Talvik · maria.talvik@haapsalu.kutsehariduskeskus.ee*
