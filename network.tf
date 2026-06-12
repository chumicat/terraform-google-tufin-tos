# ── Validation ────────────────────────────────────────────────────────────────
# Catches the invalid combination create_vpc=true + create_subnet=false at
# plan time before any resource is created or modified.

resource "terraform_data" "network_mode_validation" {
  lifecycle {
    precondition {
      condition     = !(var.create_vpc && !var.create_subnet)
      error_message = "create_vpc = true requires create_subnet = true. A newly created VPC cannot contain a pre-existing subnet."
    }
  }
}

# ── Locals ─────────────────────────────────────────────────────────────────────
# Resolves VPC and subnet references regardless of create/reference mode.
# try() returns the first expression that does not error — when a resource has
# count = 0 its index [0] errors, so try() falls through to the data source.

locals {
  vpc_name        = try(google_compute_network.vpc[0].name, data.google_compute_network.existing[0].name)
  vpc_id          = try(google_compute_network.vpc[0].id, data.google_compute_network.existing[0].id)
  subnet_id       = try(google_compute_subnetwork.main[0].id, data.google_compute_subnetwork.existing[0].id)
  subnet_ip_range = try(google_compute_subnetwork.main[0].ip_cidr_range, data.google_compute_subnetwork.existing[0].ip_cidr_range)
}

# ── Data Sources (reference existing) ─────────────────────────────────────────
# Created only when the corresponding create_ flag is false.
# On destroy, data sources are never deleted — they are read-only references.

data "google_compute_network" "existing" {
  count = var.create_vpc ? 0 : 1
  name  = var.vpc_name
}

data "google_compute_subnetwork" "existing" {
  count  = var.create_subnet ? 0 : 1
  name   = var.subnet_name
  region = var.region
}

# ── VPC ────────────────────────────────────────────────────────────────────────
# Created only when create_vpc = true.
# Custom-mode VPC — subnets are defined explicitly, not auto-generated per region.

resource "google_compute_network" "vpc" {
  count                   = var.create_vpc ? 1 : 0
  name                    = var.vpc_name
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute]
}

# ── Main Subnet ────────────────────────────────────────────────────────────────
# Created only when create_subnet = true.
# The TOS VM is placed in this subnet.
# CIDR is configurable via var.subnet_cidr — ignored when referencing existing.

resource "google_compute_subnetwork" "main" {
  count         = var.create_subnet ? 1 : 0
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = local.vpc_id
}

# ── Proxy-Only Subnet ──────────────────────────────────────────────────────────
# Always created — this is a GCP-specific requirement for the Internal TCP Proxy
# Load Balancer and will not pre-exist in any customer environment.
# purpose = REGIONAL_MANAGED_PROXY marks it exclusively for LB proxy instances.
# Minimum allowed size is /26. No VMs should be placed here.

resource "google_compute_subnetwork" "proxy_only" {
  name          = "tos-proxy-subnet"
  ip_cidr_range = var.proxy_subnet_cidr
  region        = var.region
  network       = local.vpc_id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# ── Firewall: SSH via IAP ──────────────────────────────────────────────────────
# SSH is accessed through GCP Cloud Shell using gcloud compute ssh, which
# tunnels through Identity-Aware Proxy (IAP) rather than connecting directly.
# IAP always originates from the fixed range 35.235.240.0/20 — no personal
# IP variable is needed. Direct external SSH is intentionally not permitted.
# Cloud Shell command: gcloud compute ssh <vm-name> --zone <zone> --tunnel-through-iap

resource "google_compute_firewall" "allow_ssh" {
  name    = "tos-allow-ssh"
  network = local.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["tos-node"]
}

# ── Firewall: nginx Ingress ────────────────────────────────────────────────────
# Required by Tufin — opens nodePort 31443 which TOS exposes for WebUI/API.
# The LB health check and the LB-to-VM traffic both arrive on this port.
# Tag "allow-nginx-ingress" must also be applied to the VM instance.

resource "google_compute_firewall" "allow_nginx_ingress" {
  name    = "tos-allow-nginx-ingress"
  network = local.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["31443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-nginx-ingress"]
}

# ── Firewall: LB Proxy → VM ────────────────────────────────────────────────────
# Allows the proxy-only subnet to reach all active TOS nodePorts on the VM.
# GCP Internal TCP Proxy LB forwards traffic from the proxy subnet, so this
# rule is required even though external traffic enters through the LB frontend.

resource "google_compute_firewall" "allow_proxy_to_vm" {
  name    = "tos-allow-proxy-to-vm"
  network = local.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["31443", "31514", "32514", "31099"]
  }

  source_ranges = [google_compute_subnetwork.proxy_only.ip_cidr_range]
  target_tags   = ["tos-node"]
}

# ── Firewall: GCP Health Check Probers ────────────────────────────────────────
# GCP health checkers originate from these fixed IP ranges — do not change them.
# Without this rule the LB health check will always fail and no traffic is forwarded.
# See: https://cloud.google.com/load-balancing/docs/health-checks#firewall_rules

resource "google_compute_firewall" "allow_health_checks" {
  name    = "tos-allow-health-checks"
  network = local.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["31443"]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = ["tos-node"]
}

# ── Firewall: TCP Syslog (optional) ───────────────────────────────────────────
# Created only when var.enable_tcp_syslog = true.
# Opens ports 601 (unencrypted) and 6514 (TLS) for devices sending TCP syslog.
# These ports are fronted by the LB — see lb.tf for the forwarding rules.

resource "google_compute_firewall" "allow_syslog_tcp" {
  count   = var.enable_tcp_syslog ? 1 : 0
  name    = "tos-allow-syslog-tcp"
  network = local.vpc_name

  allow {
    protocol = "tcp"
    ports    = ["601", "6514"]
  }

  source_ranges = [var.syslog_source_cidr]
  target_tags   = ["tos-node"]
}

# ── Firewall: UDP Syslog (optional) ───────────────────────────────────────────
# Created only when var.enable_udp_syslog = true.
# GCP Load Balancers cannot forward UDP, so UDP syslog must be sent directly
# to the VM's external IP on nodePort 30514 — it bypasses the LB entirely.
# Restrict var.syslog_source_cidr to your device subnets rather than 0.0.0.0/0.

resource "google_compute_firewall" "allow_syslog_udp" {
  count   = var.enable_udp_syslog ? 1 : 0
  name    = "tos-allow-syslog-udp"
  network = local.vpc_name

  allow {
    protocol = "udp"
    ports    = ["30514"]
  }

  source_ranges = [var.syslog_source_cidr]
  target_tags   = ["tos-node"]
}
