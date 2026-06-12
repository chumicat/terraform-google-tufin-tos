# ── Project ─────────────────────────────────────────────────────────────────

variable "project_id" {
  description = "ID of the existing GCP project to deploy into"
  type        = string
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the VM instance"
  type        = string
  default     = "us-central1-a"
}

# ── Compute ──────────────────────────────────────────────────────────────────

variable "vm_name" {
  description = "Name for the TOS primary data node VM"
  type        = string
  default     = "tos-primary"
}

variable "admin_ip_cidr" {
  description = "Your admin IP in CIDR notation for SSH access (e.g. 1.2.3.4/32)"
  type        = string
}

# ── Optional features ─────────────────────────────────────────────────────────

variable "enable_tcp_syslog" {
  description = "Add TCP syslog LB ports (601 unencrypted, 6514 TLS) and firewall rules"
  type        = bool
  default     = false
}

variable "enable_opm" {
  description = "Add OPM device LB port (9099)"
  type        = bool
  default     = false
}

variable "enable_udp_syslog" {
  description = "Add UDP syslog firewall rule — direct to VM on port 30514 (LB cannot handle UDP)"
  type        = bool
  default     = false
}

variable "syslog_source_cidr" {
  description = "Source CIDR allowed to send syslog (used when any syslog flag is true)"
  type        = string
  default     = "0.0.0.0/0"
}
