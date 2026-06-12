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

# ── Network ──────────────────────────────────────────────────────────────────

variable "subnet_cidr" {
  description = "CIDR for the main subnet where the TOS VM is placed"
  type        = string
  default     = "10.128.0.0/20"
  # Must be inside 10.0.0.0/8, 172.16.0.0/12, or 192.168.0.0/16.
  # Must not overlap with proxy_subnet_cidr or Kubernetes CIDRs (default pod: 10.244.0.0/16).
}

variable "proxy_subnet_cidr" {
  description = "CIDR for the proxy-only subnet required by the Internal TCP Proxy Load Balancer"
  type        = string
  default     = "10.129.0.0/26"
  # /26 is the minimum allowed size for a proxy-only subnet.
  # This subnet is reserved exclusively for GCP LB proxy instances — do not place VMs here.
  # Must not overlap with subnet_cidr or Kubernetes CIDRs.
}

# ── Compute ──────────────────────────────────────────────────────────────────

variable "vm_name" {
  description = "Name for the TOS primary data node VM"
  type        = string
  default     = "tos-primary"
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
