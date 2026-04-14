# Monitooringu täienduskoolitus — Proxmox VM-id
# 7 osaleja VM-i + 2 jagatud target VM-i

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.70"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = var.proxmox_api_token
  insecure  = true
  ssh {
    agent = true
  }
}

# ============================================================
# Osaleja VM-id — igaüks saab oma Docker hosti
# ============================================================
resource "proxmox_virtual_environment_vm" "osaleja" {
  for_each = toset(var.osalejad)

  name      = "mon-${each.key}"
  node_name = var.target_node

  clone {
    vm_id = var.template_id
    full  = true
  }

  cpu {
    cores = var.osaleja_cpu
    type  = "host"
  }

  memory {
    dedicated = var.osaleja_ram
  }

  disk {
    datastore_id = "local-lvm"
    size         = var.osaleja_disk
    interface    = "scsi0"
  }

  # Admin võrk (SSH, VPN, koolitaja ligipääs)
  network_device {
    bridge = "vmbr0"
  }

  # Klassiruumi võrk (osalejate brauseripääs)
  network_device {
    bridge = "vmbr1"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.100.${var.osaleja_ip_start + index(var.osalejad, each.key)}/24"
        gateway = "192.168.100.1"
      }
    }
    ip_config {
      ipv4 {
        address = "192.168.5.${var.osaleja_ip_start + index(var.osalejad, each.key)}/24"
      }
    }
    user_account {
      username = "student"
      keys     = [var.ssh_public_key]
    }
  }

  tags = ["monitoring", "taiendus", "osaleja", each.key]
}

# ============================================================
# Target VM — jagatud Linux server, tekitab probleeme
# node_exporter, zabbix-agent, logid, vigased teenused
# ============================================================
resource "proxmox_virtual_environment_vm" "target" {
  name      = "mon-target"
  node_name = var.target_node

  clone {
    vm_id = var.template_id
    full  = true
  }

  cpu {
    cores = var.target_cpu
    type  = "host"
  }

  memory {
    dedicated = var.target_ram
  }

  disk {
    datastore_id = "local-lvm"
    size         = var.target_disk
    interface    = "scsi0"
  }

  network_device {
    bridge = "vmbr0"
  }

  network_device {
    bridge = "vmbr1"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.100.${var.target_ip}/24"
        gateway = "192.168.100.1"
      }
    }
    ip_config {
      ipv4 {
        address = "192.168.5.${var.target_ip}/24"
      }
    }
    user_account {
      username = "student"
      keys     = [var.ssh_public_key]
    }
  }

  tags = ["monitoring", "taiendus", "target"]
}

# ============================================================
# Target-web VM — Nginx + PostgreSQL, veebileht mida monitoorida
# HTTP check'id, slow query logid, 500 error'id
# ============================================================
resource "proxmox_virtual_environment_vm" "target_web" {
  name      = "mon-target-web"
  node_name = var.target_node

  clone {
    vm_id = var.template_id
    full  = true
  }

  cpu {
    cores = var.target_cpu
    type  = "host"
  }

  memory {
    dedicated = var.target_ram
  }

  disk {
    datastore_id = "local-lvm"
    size         = var.target_disk
    interface    = "scsi0"
  }

  network_device {
    bridge = "vmbr0"
  }

  network_device {
    bridge = "vmbr1"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "192.168.100.${var.target_web_ip}/24"
        gateway = "192.168.100.1"
      }
    }
    ip_config {
      ipv4 {
        address = "192.168.5.${var.target_web_ip}/24"
      }
    }
    user_account {
      username = "student"
      keys     = [var.ssh_public_key]
    }
  }

  tags = ["monitoring", "taiendus", "target", "web"]
}
