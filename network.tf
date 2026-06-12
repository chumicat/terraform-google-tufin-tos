# ── VPC ────────────────────────────────────────────────────────────────────────
# Custom-mode VPC — subnets are created explicitly below rather than
# auto-generated per region, giving full control over CIDR ranges.

resource "google_compute_network" "vpc" {
  name                    = "tos-vpc"
  auto_create_subnetworks = false
  depends_on              = [google_project_service.compute]
}

# ── Main Subnet ────────────────────────────────────────────────────────────────
# The TOS VM is placed in this subnet.
# CIDR is configurable via var.subnet_cidr (default 10.128.0.0/20).
# Ensure it does not overlap with the proxy-only subnet or Kubernetes CIDRs.

resource "google_compute_subnetwork" "main" {
  name          = "tos-subnet"
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
}

# ── Proxy-Only Subnet ──────────────────────────────────────────────────────────
# Required by GCP for Internal TCP Proxy Load Balancers.
# GCP allocates proxy instances from this subnet to front the LB — no VMs go here.
# purpose = REGIONAL_MANAGED_PROXY marks it exclusively for LB use.
# Minimum size is /26. CIDR is configurable via var.proxy_subnet_cidr.

resource "google_compute_subnetwork" "proxy_only" {
  name          = "tos-proxy-subnet"
  ip_cidr_range = var.proxy_subnet_cidr
  region        = var.region
  network       = google_compute_network.vpc.id
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
  network = google_compute_network.vpc.name

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
  network = google_compute_network.vpc.name

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
  network = google_compute_network.vpc.name

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
  network = google_compute_network.vpc.name

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
  network = google_compute_network.vpc.name

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
  network = google_compute_network.vpc.name

  allow {
    protocol = "udp"
    ports    = ["30514"]
  }

  source_ranges = [var.syslog_source_cidr]
  target_tags   = ["tos-node"]
}
