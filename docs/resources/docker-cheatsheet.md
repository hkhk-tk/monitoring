# Docker Compose lühijuhend

## Põhikäsud

```bash
docker compose up -d          # Käivita kõik teenused taustal
docker compose down            # Peata teenused
docker compose down -v         # Peata + kustuta andmed (volume'id)
docker compose ps              # Näita teenuste staatust
docker compose logs            # Kõigi teenuste logid
docker compose logs -f grafana # Ühe teenuse logid reaalajas
docker compose restart         # Taaskäivita kõik
docker compose pull            # Tõmba uusimad image'id
```

## Diagnostika

```bash
docker ps                           # Kõik jooksvad konteinerid
docker stats                        # CPU/RAM kasutus reaalajas
docker exec -it prometheus sh       # Mine konteineri sisse
docker inspect prometheus           # Konteineri detailid
```

## Pordid

Kui port on kinni:

```bash
sudo ss -tlnp | grep 3000          # Kes kasutab porti 3000?
```

## Levinud probleemid

**"Port already in use"** — eelmine stack jookseb veel:
```bash
docker compose down
```

**"Image not found"** — tõmba image:
```bash
docker compose pull
```

**Konteiner restardib pidevalt** — vaata logisid:
```bash
docker compose logs <teenuse-nimi>
```
