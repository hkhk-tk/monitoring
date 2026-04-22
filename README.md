# Kaasaegne IT-süsteemide monitooring ja jälgitavus — Täienduskoolitus

**26 akadeemilist tundi** · 5 laupäeva · Haapsalu KHK · Aprill–Juuni 2026

## Kursuse ülevaade

| Päev | Kuupäev | Teemad |
|------|---------|--------|
| 1 | 18.04 | Monitooringu alused + Prometheus + Grafana |
| 2 | 25.04 | Zabbix + Loki (LGTM logs-kiht) |
| 3 | 09.05 | Elastic Stack (ELK) |
| 4 | 23.05 | TICK Stack + Kesksed logimissüsteemid |
| 5 | 06.06 | Tempo + OpenTelemetry + LGTM tervik + Trendid 2026 |

## Repo struktuur

```
docs/               # MkDocs sisu (loengud, labid, ressursid)
  labs/              # Labori juhendid per päev
  materials/         # Loengumaterjalid
  resources/         # Juhendid, lisamaterjalid
infra/               # Infrastruktuuri kood
  terraform/         # Proxmox VM-ide provisioning
  ansible/           # VM-ide konfiguratsioon (Docker, paketid)
```

## Infrastruktuur

Iga osaleja saab ühe Proxmox VM-i (8GB RAM, 4 CPU, 50GB disk), kuhu on Ansible abil installitud Docker. Kõik monitooringu stackid jooksevad Docker Compose'iga.

### VM-ide ülesseadmine

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Muuda terraform.tfvars: lisa osalejate nimed, SSH võti jne

terraform init
terraform plan
terraform apply

# Ansible konfiguratsioon
cd ../ansible
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml
```

### VM-ide kustutamine (pärast kursust)

```bash
cd infra/terraform
terraform destroy
```

## Veebileht

Materjalid on saadaval MkDocs veebilehena:

```bash
pip install mkdocs-material mkdocs-git-revision-date-localized-plugin
mkdocs serve
```

## Litsents

Õppematerjalid: CC BY-SA 4.0
Kood: MIT
