# TODO — Monitooringu täienduskoolitus

## Enne laupäeva 18.04 (KRIITILINE)

### Infrastruktuur
- [ ] Kontode tellimine koolilt (email saadetud?)
- [ ] `terraform.tfvars` — osalejate nimed sisestada
- [ ] Cloud-init template kontrollida Proxmoxis (VM 9000)
- [ ] `terraform apply` — 7 osaleja VM + 2 target VM üles
- [ ] `ansible-playbook setup.yml` — Docker, node_exporter, zabbix-agent, logi-generaator
- [ ] Testi `mon-maria` VM — Docker Compose päev 1 töötab?
- [ ] Testi mon-target — node_exporter :9100, zabbix-agent, logid /var/log/app.log
- [ ] Testi mon-target-web — nginx :80, stub_status :8080, node_exporter :9100

### Google Classroom
- [ ] Loo kursus "Monitooring ja jälgitavus 2026"
- [ ] Lisa osalejad (kui kontod tehtud)
- [ ] Lisa MkDocs saidi link
- [ ] Lisa tervitusteade + VM info
- [ ] Lisa päev 1 materjal

### Materjal (päev 1)
- [x] Docker Compose fail (Prometheus + Grafana + Node Exporter + Alertmanager)
- [x] Prometheus konfig (prometheus.yml) — target'id: localhost + mon-target + mon-target-web
- [x] Alertmanager konfig
- [x] Alert rules
- [x] Labori juhend (lab.md)
- [ ] MkDocs build ja deploy (GitHub Pages)

---

## Enne 25.04 (päev 2)
- [ ] Zabbix Docker Compose
- [ ] Loki + Promtail Docker Compose
- [ ] Zabbix labori juhend
- [ ] Loki labori juhend
- [ ] ELK päeva eeltöö (päev 3 Compose valmis)

## Enne 09.05 (päev 3)
- [ ] ELK Docker Compose
- [ ] ELK labori juhend
- [ ] VM RAM tõstmine 6GB-le (ELK päev)

## Enne 23.05 (päev 4)
- [ ] TICK Docker Compose
- [ ] TICK labori juhend
- [ ] Opensearch/Graylog/Kafka demo-materjalid
- [ ] VM RAM tagasi 4GB-le

## Enne 06.06 (päev 5)
- [ ] Tempo + OTel Collector Docker Compose (LGTM tervik)
- [ ] Tempo labori juhend
- [ ] Trendid 2026 slaidimaterjal
- [ ] Tagasiside vorm
