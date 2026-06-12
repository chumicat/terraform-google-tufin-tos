# Internal TCP Proxy Load Balancer for TOS Aurora
# ─────────────────────────────────────────────────────────────────────────────
# GCP Internal TCP Proxy LB sits inside the VPC and forwards TCP connections to
# the TOS VM nodePorts. It requires the proxy-only subnet created in network.tf.
#
# Port map (frontend → K3S nodePort):
#   443  → 31443   HTTPS / WebUI / API          (always)
#   601  → 31514   TCP syslog unencrypted        (enable_tcp_syslog = true)
#   6514 → 32514   TCP syslog TLS                (enable_tcp_syslog = true)
#   9099 → 31099   OPM device protocol           (enable_opm = true)
#
# UDP syslog (30514) cannot use a load balancer — GCP LBs do not support UDP.
# It is handled by a direct firewall rule in network.tf.
#
# Each active port needs its own backend service + target proxy + forwarding rule
# because GCP TCP Proxy LB maps one proxy to one backend service.

# ── Unmanaged Instance Group ───────────────────────────────────────────────────
# Wraps the single TOS VM so it can be registered as a backend.
# named_port entries map symbolic names to nodePorts; backend services reference
# these names via port_name. Dynamic blocks add optional ports only when their
# feature flag is true, keeping the group clean when features are disabled.

resource "google_compute_instance_group" "tos" {
  name      = "tos-primary-group"
  zone      = var.zone
  instances = [google_compute_instance.tos_primary.self_link]

  named_port {
    name = "https"
    port = 31443
  }

  dynamic "named_port" {
    for_each = var.enable_tcp_syslog ? [1] : []
    content {
      name = "syslog-tcp"
      port = 31514
    }
  }

  dynamic "named_port" {
    for_each = var.enable_tcp_syslog ? [1] : []
    content {
      name = "syslog-tls"
      port = 32514
    }
  }

  dynamic "named_port" {
    for_each = var.enable_opm ? [1] : []
    content {
      name = "opm"
      port = 31099
    }
  }
}

# ── Regional Health Check ──────────────────────────────────────────────────────
# TCP probe on nodePort 31443 — shared by all backend services.
# GCP health checkers originate from 130.211.0.0/22 and 35.191.0.0/16;
# the firewall rule allowing these is in network.tf (allow_health_checks).

resource "google_compute_region_health_check" "tos" {
  name   = "tos-health-check"
  region = var.region

  tcp_health_check {
    port = 31443
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# HTTPS  443 → nodePort 31443  (always enabled)
# ═══════════════════════════════════════════════════════════════════════════════

resource "google_compute_region_backend_service" "https" {
  name                  = "tos-https-backend"
  region                = var.region
  protocol              = "TCP"
  port_name             = "https"
  load_balancing_scheme = "INTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_region_health_check.tos.id]

  backend {
    group          = google_compute_instance_group.tos.id
    balancing_mode = "UTILIZATION"
  }
}

resource "google_compute_region_target_tcp_proxy" "https" {
  name            = "tos-https-proxy"
  region          = var.region
  backend_service = google_compute_region_backend_service.https.id
}

resource "google_compute_forwarding_rule" "https" {
  name                  = "tos-https"
  region                = var.region
  ip_protocol           = "TCP"
  port_range            = "443"
  target                = google_compute_region_target_tcp_proxy.https.id
  network               = local.vpc_id
  subnetwork            = local.subnet_id
  load_balancing_scheme = "INTERNAL_MANAGED"
}

# ═══════════════════════════════════════════════════════════════════════════════
# TCP Syslog unencrypted  601 → nodePort 31514  (enable_tcp_syslog = true)
# ═══════════════════════════════════════════════════════════════════════════════

resource "google_compute_region_backend_service" "syslog_tcp" {
  count = var.enable_tcp_syslog ? 1 : 0

  name                  = "tos-syslog-tcp-backend"
  region                = var.region
  protocol              = "TCP"
  port_name             = "syslog-tcp"
  load_balancing_scheme = "INTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_region_health_check.tos.id]

  backend {
    group          = google_compute_instance_group.tos.id
    balancing_mode = "UTILIZATION"
  }
}

resource "google_compute_region_target_tcp_proxy" "syslog_tcp" {
  count = var.enable_tcp_syslog ? 1 : 0

  name            = "tos-syslog-tcp-proxy"
  region          = var.region
  backend_service = google_compute_region_backend_service.syslog_tcp[0].id
}

resource "google_compute_forwarding_rule" "syslog_tcp" {
  count = var.enable_tcp_syslog ? 1 : 0

  name                  = "tos-syslog-tcp"
  region                = var.region
  ip_protocol           = "TCP"
  port_range            = "601"
  target                = google_compute_region_target_tcp_proxy.syslog_tcp[0].id
  network               = local.vpc_id
  subnetwork            = local.subnet_id
  load_balancing_scheme = "INTERNAL_MANAGED"
}

# ═══════════════════════════════════════════════════════════════════════════════
# TCP Syslog TLS  6514 → nodePort 32514  (enable_tcp_syslog = true)
# ═══════════════════════════════════════════════════════════════════════════════

resource "google_compute_region_backend_service" "syslog_tls" {
  count = var.enable_tcp_syslog ? 1 : 0

  name                  = "tos-syslog-tls-backend"
  region                = var.region
  protocol              = "TCP"
  port_name             = "syslog-tls"
  load_balancing_scheme = "INTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_region_health_check.tos.id]

  backend {
    group          = google_compute_instance_group.tos.id
    balancing_mode = "UTILIZATION"
  }
}

resource "google_compute_region_target_tcp_proxy" "syslog_tls" {
  count = var.enable_tcp_syslog ? 1 : 0

  name            = "tos-syslog-tls-proxy"
  region          = var.region
  backend_service = google_compute_region_backend_service.syslog_tls[0].id
}

resource "google_compute_forwarding_rule" "syslog_tls" {
  count = var.enable_tcp_syslog ? 1 : 0

  name                  = "tos-syslog-tls"
  region                = var.region
  ip_protocol           = "TCP"
  port_range            = "6514"
  target                = google_compute_region_target_tcp_proxy.syslog_tls[0].id
  network               = local.vpc_id
  subnetwork            = local.subnet_id
  load_balancing_scheme = "INTERNAL_MANAGED"
}

# ═══════════════════════════════════════════════════════════════════════════════
# OPM  9099 → nodePort 31099  (enable_opm = true)
# ═══════════════════════════════════════════════════════════════════════════════

resource "google_compute_region_backend_service" "opm" {
  count = var.enable_opm ? 1 : 0

  name                  = "tos-opm-backend"
  region                = var.region
  protocol              = "TCP"
  port_name             = "opm"
  load_balancing_scheme = "INTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_region_health_check.tos.id]

  backend {
    group          = google_compute_instance_group.tos.id
    balancing_mode = "UTILIZATION"
  }
}

resource "google_compute_region_target_tcp_proxy" "opm" {
  count = var.enable_opm ? 1 : 0

  name            = "tos-opm-proxy"
  region          = var.region
  backend_service = google_compute_region_backend_service.opm[0].id
}

resource "google_compute_forwarding_rule" "opm" {
  count = var.enable_opm ? 1 : 0

  name                  = "tos-opm"
  region                = var.region
  ip_protocol           = "TCP"
  port_range            = "9099"
  target                = google_compute_region_target_tcp_proxy.opm[0].id
  network               = local.vpc_id
  subnetwork            = local.subnet_id
  load_balancing_scheme = "INTERNAL_MANAGED"
}
