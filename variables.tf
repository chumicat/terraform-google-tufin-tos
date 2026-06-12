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

variable "create_vpc" {
  description = "true = create a new VPC; false = reference an existing VPC by vpc_name"
  type        = bool
  default     = true
  # When true, create_subnet must also be true.
  # A newly created VPC cannot contain a pre-existing subnet.
  # This constraint is validated in network.tf.
}

variable "create_subnet" {
  description = "true = create a new subnet; false = reference an existing subnet by subnet_name"
  type        = bool
  default     = true
  # Cannot be false when create_vpc is true — validated in network.tf.
}

variable "vpc_name" {
  description = "Name of the VPC to create (create_vpc=true) or reference (create_vpc=false)"
  type        = string
  default     = "tos-vpc"
}

variable "subnet_name" {
  description = "Name of the subnet to create (create_subnet=true) or reference (create_subnet=false)"
  type        = string
  default     = "tos-subnet"
}

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

variable "vcpu" {
  description = "Number of vCPUs for the TOS VM (assembles e2-custom-<vcpu>-<memory_mb>)"
  type        = number
  default     = 20
  # TOS Aurora minimum: 20 vCPU / 80 GB RAM.
  # Must be an even number; GCP rejects odd counts for e2-custom.
}

variable "memory_mb" {
  description = "Memory in MB for the TOS VM (assembles e2-custom-<vcpu>-<memory_mb>)"
  type        = number
  default     = 81920 # 80 GB — TOS Aurora minimum
  # Must be a multiple of 256 MB.
}

variable "os_image_family" {
  description = "GCP image family for the TOS VM OS"
  type        = string
  default     = "rocky-linux-9-optimized-gcp"
  # Resolves to the latest image in the family at apply time.
  # Tufin requires Rocky Linux 9.7+.
}

variable "os_image_project" {
  description = "GCP project that publishes the OS image family"
  type        = string
  default     = "rocky-linux-cloud"
}

variable "boot_disk_size_gb" {
  description = "Size in GB of the boot disk (OS + TOS data)"
  type        = number
  default     = 650
  # TOS Aurora minimum: 625 GB SSD. 650 GB for small Buffer. /opt: min 400 GB; /var: min 200 GB; /tmp: min 25 GB
}

variable "etcd_disk_size_gb" {
  description = "Size in GB of the dedicated etcd SSD (separate from boot disk)"
  type        = number
  default     = 50
  # K3S etcd is sensitive to disk latency — keep this on a dedicated pd-ssd. min 50 GB
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
