# Päev 4: TICK Stack — Labor

*Tuleb 23. mail*

---

!!! info "Ettevalmistus"
    Puhasta eelmine stack: `cd ~/paev3 && docker compose down -v`

!!! abstract "TL;DR"
    Päev 4 eesmärk on näha alternatiivset metrics‑mõtlemist (InfluxDB/Telegraf) ja siduda see “kesksed logimissüsteemid” suurema pildiga: millal mis tööriist on mõistlik.

---

## Eesmärk

Selle labori lõpuks osaleja:
- seab TICK stacki üles ja näeb andmeid dashboardil
- mõistab, mis on Telegrafi roll (agent/collector)
- oskab sõnastada, kus TICK sobitub vs Prometheus

---

## Labistruktuur (skelett)

1. Stack üles (compose)
2. Andmete kogumine (Telegraf)
3. Influx query / dashboard
4. Võrdlus Prometheusega (andmemudel, query, retention)

---

<details>
<summary><strong>Veaotsing + allikad (peida/ava)</strong></summary>

## Veaotsing

- `docker compose ps` / `docker compose logs <teenus>` on esimene samm
- Kui andmeid ei tule, kontrolli Telegrafi konfiguratsiooni ja ühendusi

## Allikad

- InfluxDB docs: <https://docs.influxdata.com/>
- Telegraf: <https://docs.influxdata.com/telegraf/>

</details>

--8<-- "_snippets/abbr.md"
