# Päev 2: Zabbix + Loki

**25. aprill 2026 · 10:00–14:30**

Kaks teemat: agent-põhine monitooring (Zabbix) ja logide käsitlemine (Loki). Klassis jõuame põhiosad, ülejäänu lõpetad kodus — labijuhend kannab ise.

---

## Päeva kava

| Aeg | Kestus | Tegevus | Materjal |
|-----|--------|---------|----------|
| 10:00–10:15 | 15 min | Avamine, päev 1 kordamine | — |
| 10:15–12:15 | 2h | Zabbix lab (Osad 1–5) | [zabbix_lab.md](zabbix_lab.md) |
| 12:15–12:45 | 30 min | Paus | — |
| 12:45–14:15 | 1h 30min | Loki lab (Osad 1–5) | [loki_lab.md](loki_lab.md) |
| 14:15–14:30 | 15 min | Kokkuvõte + kodutöö juhised | — |

**Kodutöö:** Zabbix Osad 6–7 (LLD + Discord) ja Loki Osad 6–8 (Nginx RED, alerting, correlation).

---

## Õpiväljundid kogu päeva kohta

Pärast päev 2 osaleja oskab:

1. **Eristada kolme monitooringu-maailma** — metrikad (Prometheus, päev 1), agent-põhine (Zabbix), logid (Loki) — ja valida probleemile sobiva tööriista
2. **Seadistada Zabbixi hosti** — stack, agent, template, item, trigger
3. **Kirjutada oma monitooringu-mõõdiku** custom skriptina (UserParameter)
4. **Lasta Zabbixil ise avastada** mida jälgida (LLD autodiscovery)
5. **Koguda ja päringutada logisid** Lokiga (LogQL filter, regex, parse)
6. **Teisendada logi numbriks** (rate, count_over_time) — logi kui metrika allikas
7. **Ehitada alert mustri pealt** — mitte numbri, vaid teksti

---

## Struktuur

```
02_zabbix_loki/
├── README.md                   ← See fail
├── zabbix_lab.md               ← Zabbix labor
├── zabbix/
│   ├── docker-compose.yml      ← Zabbix stack
│   └── config/
│       ├── applog.conf         ← UserParameter näide
│       └── discover-services.sh ← LLD skript
├── loki_lab.md                 ← Loki labor
└── loki/
    ├── docker-compose.yml      ← Loki + Promtail + Grafana
    └── config/
        ├── loki-config.yml
        └── promtail-config.yml
```

---

## Eeltööd — enne laupäeva

Osa infrastruktuurist peab enne labi olema valmis (koolitaja poolel):

- [ ] `mon-target` peal peab töötama Zabbix agent pordil 10050. Kontrollida: `docker exec zabbix-server zabbix_get -s 192.168.35.140 -k agent.ping` peab tagastama `1`.
- [ ] Discord server ja kanal `#alerts`, webhook URL valmis.
- [ ] Testi, et kogu stack käivitub `mon-maria` masinal 4GB RAM piires — esimene VM on sinu testkoht.

Kõik osalejad puhastavad päev 1 stack'i enne laupäeva: `cd ~/paev1 && docker compose down -v`.
