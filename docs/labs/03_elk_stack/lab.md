# Päev 3: Elastic Stack — Labor

*Tuleb 9. mail*

---

!!! info "Ettevalmistus"
    Puhasta eelmine stack: `cd ~/paev2 && docker compose down -v`
    ELK vajab rohkem mälu — VM RAM tõstetakse 6GB-le.

!!! abstract "TL;DR"
    Päev 3 eesmärk on ehitada ELK‑põhine logikiht ja võrrelda seda Loki lähenemisega (indeks, otsing, kulud, kasutusjuht).

---

## Eesmärk

Selle labori lõpuks osaleja:
- seab ELK stacki üles ja näeb logisid Kibanas
- teeb 2–3 tüüpilist otsingut/filtrit
- oskab selgitada, millal ELK on õigustatud vs millal Loki on lihtsam/odavam

---

## Labistruktuur (skelett)

1. Keskkonna kontroll (VM RAM, Docker, kettaruum)
2. Stack üles (compose)
3. Logide sissevõtt (ingest)
4. Otsing + visualiseerimine (Kibana)
5. Võrdlus Lokiga (mille eest maksad / mida võidad)

---

<details>
<summary><strong>Veaotsing + allikad (peida/ava)</strong></summary>

## Veaotsing

- Kui ELK ei käivitu, esimene kontroll: `docker compose ps` ja `docker compose logs <teenus>`
- Kui mälu otsas, kontrolli `free -h` ja peata teised stackid

## Allikad

- Elastic Stack docs: <https://www.elastic.co/guide/index.html>
- Kibana Query Language (KQL): <https://www.elastic.co/guide/en/kibana/current/kuery-query.html>

</details>

--8<-- "_snippets/abbr.md"
