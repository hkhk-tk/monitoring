# Päev 5: Tempo + OpenTelemetry — Labor

*Tuleb 6. juunil*

---

!!! info "Ettevalmistus"
    Puhasta eelmine stack: `cd ~/paev4 && docker compose down -v`
    Selle päeva lõpuks on kogu LGTM stack koos — metrics, logs, traces ühes Grafanas.

!!! abstract "TL;DR"
    Päev 5 eesmärk on lisada **traces‑sammas**: OpenTelemetry → Tempo → Grafana. Lõpuks saad ühest UI-st liikuda metric → log → trace.

---

## Eesmärk

Selle labori lõpuks osaleja:
- seab Tempo + OTel Collectori üles
- näeb trace’e Grafanas ja oskab leida “kus aeg kulus”
- seob trace‑ID logidega (vähemalt ühe lihtsa korrelatsiooni)

---

## Labistruktuur (skelett)

1. Stack üles (Tempo + OTel collector + demo app)
2. Traces ingest (OTLP)
3. Grafana: trace vaade + latency analüüs
4. Korrelatsioon: metric → log → trace

---

<details>
<summary><strong>Veaotsing + allikad (peida/ava)</strong></summary>

## Veaotsing

- Kui trace’e ei tule, kontrolli OTLP endpointi (`4317/4318`) ja OTel collectori logisid
- Kui Tempo on “down”, vaata storage/ports ja `docker compose logs tempo`

## Allikad

- Tempo docs: <https://grafana.com/docs/tempo/latest/>
- OpenTelemetry docs: <https://opentelemetry.io/docs/>
- OTLP: <https://opentelemetry.io/docs/specs/otlp/>

</details>

--8<-- "_snippets/abbr.md"
