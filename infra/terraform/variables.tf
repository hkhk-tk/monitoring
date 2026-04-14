# ============================================================
# Proxmox ühendus
# ============================================================
variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API URL"
}

variable "proxmox_api_token" {
  type        = string
  sensitive   = true
  description = "Proxmox API token (root@pam!terraform=<secret>)"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key cloud-init jaoks"
}

# ============================================================
# Proxmox node ja template
# ============================================================
variable "target_node" {
  type        = string
  default     = "marianodea"
  description = "Proxmox node kuhu VM-id luuakse (marianodea või marianodeb)"
}

variable "template_id" {
  type        = number
  default     = 9000
  description = "Cloud-init template VM ID"
}

# ============================================================
# Osalejad
# ============================================================
variable "osalejad" {
  type        = list(string)
  description = "Osalejate nimed (kasutajatunnused) — 6 osalejat + koolitaja"
}

# ============================================================
# Osaleja VM-ide specs
# ============================================================
variable "osaleja_ram" {
  type        = number
  default     = 4096
  description = "Osaleja VM RAM (MB). 4GB piisab, ELK päeval võib tõsta 6GB."
}

variable "osaleja_cpu" {
  type        = number
  default     = 2
  description = "Osaleja VM CPU tuumade arv"
}

variable "osaleja_disk" {
  type        = number
  default     = 40
  description = "Osaleja VM ketta suurus (GB)"
}

variable "osaleja_ip_start" {
  type        = number
  default     = 120
  description = "Esimese osaleja VM IP viimane oktett (192.168.X.<see>)"
}

# ============================================================
# Target VM-ide specs
# ============================================================
variable "target_ram" {
  type        = number
  default     = 1024
  description = "Target VM RAM (MB)"
}

variable "target_cpu" {
  type        = number
  default     = 1
  description = "Target VM CPU tuumade arv"
}

variable "target_disk" {
  type        = number
  default     = 10
  description = "Target VM ketta suurus (GB)"
}

variable "target_ip" {
  type        = number
  default     = 140
  description = "mon-target IP viimane oktett"
}

variable "target_web_ip" {
  type        = number
  default     = 141
  description = "mon-target-web IP viimane oktett"
}
