---
title: Materjalide stiilijuhend
---

# Materjalide stiilijuhend (Professor + käsiraamat)

See kursus ei ole “installikursus”. Materjal peab olema korraga:

- **loetav nagu professor räägib** (põhitekst)
- **kasutatav nagu käsiraamat** (kastid, kontrollpunktid, valemid, lingid)

Allpool on reeglid, mille järgi loengud ja labid on kirjutatud.

---

## 1) Kahekihiline struktuur

- **Põhitekst**: jutustav, sujuvate üleminekutega.
- **Käsiraamatukiht**: detailid peidus (kokkupandavad plokid), et leht jääks puhas.

Soovitus: kui detail katkestab lugemise, pane see `<details>` või `???` plokki.

---

## 2) Kastide semantika (admonitions)

Kasuta kaste järjekindlalt, mitte “suvaliselt ilusaks”.

- `!!! abstract`: TL;DR / 4–5 asja, mis päriselt meelde jätta
- `!!! tip`: rusikareegel, kiire valik, “mida teha esimesena”
- `!!! warning`: tüüpiline komistus / vale eeldus
- `!!! danger`: tootmises katastroofne viga (nt `History=0`, kõrge kardinaalsus)
- `??? note`: lisadetail/taust (peidus vaikimisi)

---

## 3) Joonised (Mermaid)

Joonis peab vastama **ühele** küsimusele:

- “millest süsteem koosneb?” (topoloogia)
- “kuidas andmed liiguvad?” (andmevoog)
- “mille järgi valida?” (otsustuspuu)

Reegel: parem 1 lihtne joonis kui 3 keerulist.

---

## 4) Enesekontroll ja allikad

- **Enesekontroll**: vaikimisi peidus (`<details>`), et ei domineeriks lehe lõppu.
- **Vastused**: peidus samas plokis või eraldi `??? note`.
- **Allikad/viited**: peidus (`<details>` või `??? note`) — lehe lõpp ei tohi olla “linkide sein”.

---

## 5) Terminid ja tooltipid

Lühendid (NVPS, LLD, HA, OTel, …) võiks olla seletusega hover tooltipina.

Kasutame ühist sõnastikku: `docs/_snippets/abbr.md` (lisatakse lehe lõppu `--8<-- "_snippets/abbr.md"`).

---

## 6) “AI-lausete” vältimine

Väldi üldistusi stiilis:

- “tänapäeval on see de facto standard…”
- “see on oluline, sest…”

Asenda:

- **konkreetse väitega** (“kui paned X sildiks, tekib Y voogu…”) +
- **konkreetse tagajärjega** (“…indeks paisub, päringud aeglustuvad”).

