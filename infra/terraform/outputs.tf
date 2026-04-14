# ============================================================
# IP-aadresside kokkuvõte
# ============================================================
output "osaleja_ips" {
  description = "Osalejate VM-ide IP-aadressid"
  value = {
    for name, vm in proxmox_virtual_environment_vm.osaleja :
    name => {
      admin     = "192.168.100.${var.osaleja_ip_start + index(var.osalejad, name)}"
      classroom = "192.168.5.${var.osaleja_ip_start + index(var.osalejad, name)}"
    }
  }
}

output "target_ips" {
  description = "Target VM-ide IP-aadressid"
  value = {
    "mon-target"     = "192.168.100.${var.target_ip}"
    "mon-target-web" = "192.168.100.${var.target_web_ip}"
  }
}

# ============================================================
# Ansible inventory faili genereerimine
# ============================================================
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/hosts.yml.tpl", {
    osalejad       = var.osalejad
    osaleja_ip_start = var.osaleja_ip_start
    target_ip      = var.target_ip
    target_web_ip  = var.target_web_ip
  })
  filename = "${path.module}/../ansible/inventory/hosts.yml"
}
