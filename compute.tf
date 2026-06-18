# ── Project Data Source ────────────────────────────────────────────────────────
# Fetches project metadata — specifically the project number required to build
# the default Compute Engine service account email at plan time.
# Format: {project_number}-compute@developer.gserviceaccount.com

data "google_project" "project" {}

# ── OS Image ───────────────────────────────────────────────────────────────────
# Pins to a specific image name rather than resolving the latest from a family.
# Using a family would pick up Rocky 9.8+ automatically, which is not yet
# validated with TOS Aurora. Pin to a known-good 9.7 image instead.

data "google_compute_image" "tos" {
  name    = var.os_image_name
  project = var.os_image_project
}

# ── Locals ─────────────────────────────────────────────────────────────────────
# machine_type: assembled from vcpu + memory_mb so users can tune either axis
# without knowing the e2-custom naming convention.
# default_sa: GCP default Compute SA, constructed from the project number.

locals {
  machine_type = "e2-custom-${var.vcpu}-${var.memory_mb}"
  default_sa   = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}

# ── etcd Disk ──────────────────────────────────────────────────────────────────
# Dedicated SSD for K3S etcd — isolates etcd I/O latency from OS and TOS data.
# K3S etcd is sensitive to disk performance; a shared boot disk risks timeouts.

resource "google_compute_disk" "etcd" {
  name = "${var.vm_name}-etcd"
  type = "pd-ssd"
  zone = var.zone
  size = var.etcd_disk_size_gb
}

# ── TOS Primary Data Node ─────────────────────────────────────────────────────
# Single VM running TOS Aurora (K3S-based). Minimum spec: 20 vCPU / 80 GB RAM /
# 600 GB SSD boot + 50 GB etcd SSD.
#
# External IP model: GCP routes outbound internet traffic via the attached
# external IP. The VM OS never sees this IP — only its private RFC-1918 address
# appears on the NIC. No Cloud NAT is required.
#
# --primary-vip external: TOS flag that skips MetalLB VIP management for both
# the primary VIP and syslog VIP, delegating addressing to the GCP LB.

resource "google_compute_instance" "tos_primary" {
  name         = var.vm_name
  machine_type = local.machine_type
  zone         = var.zone

  # tos-node:           matched by SSH, health-check, proxy→VM firewall rules
  # allow-nginx-ingress: matched by the nginx ingress firewall rule (port 31443)
  tags = ["tos-node", "allow-nginx-ingress"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.tos.self_link
      size  = var.boot_disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = local.subnet_id

    # Attaches an ephemeral external IP for outbound internet access.
    # STANDARD tier: routes via Google's edge PoP nearest the region.
    # Remove this block and add Cloud NAT (nat.tf) if an external IP is undesirable.
    access_config {
      network_tier = "STANDARD"
    }
  }

  service_account {
    email = local.default_sa
    scopes = [
      # Minimum scopes matching the GCP Console default + what TOS requires.
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring.write",
      "https://www.googleapis.com/auth/service.management.readonly",
      "https://www.googleapis.com/auth/servicecontrol",
      "https://www.googleapis.com/auth/trace.append",
    ]
  }

  shielded_instance_config {
    # Secure Boot is disabled — Rocky Linux 9 optimized images are not signed
    # with a key in GCP's Secure Boot database by default.
    enable_secure_boot          = false
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  scheduling {
    on_host_maintenance = "MIGRATE" # live-migrate on host maintenance events
    provisioning_model  = "STANDARD"
  }

  reservation_affinity {
    type = "ANY_RESERVATION" # use any available reservation; no pre-purchased required
  }

  # ── Startup Script ─────────────────────────────────────────────────────────
  # GCP runs initialize.sh automatically at each boot as root via the metadata
  # server. Execution is split into two phases separated by a kernel-upgrade
  # reboot. Sentinel files prevent re-running completed phases:
  #   /etc/tufin-init-phase1-done — Phase 1 complete (pre-reboot)
  #   /etc/tufin-init-done        — Phase 2 complete (post-reboot, fully ready)
  # Monitor: gcloud compute instances get-serial-port-output <vm> --zone <zone>
  # Full log on VM: /var/log/tufin-init.log
  metadata = {
    # All keys read by initialize.sh at runtime via the GCP metadata server.
    # Empty string values cause the corresponding step to be skipped.
    "tos-package-url" = var.tos_package_url
    "tos-package-dir" = var.tos_package_dir
    "timezone"        = var.timezone
    "ntp-server"      = var.ntp_server
  }

  # replace() strips Windows CRLF line endings that occur when Terraform runs
  # on Windows and file() reads initialize.sh with \r\n. Bash on Linux treats
  # the \r as part of the command, breaking the shebang and every line.
  metadata_startup_script = replace(file("${path.module}/initialize.sh"), "\r\n", "\n")

  depends_on = [
    google_project_service.compute,
    terraform_data.network_mode_validation,
  ]
}

# ── etcd Disk Attachment ───────────────────────────────────────────────────────
# Attached as a SEPARATE resource (not inside google_compute_instance) so that
# Terraform creates the VM first — giving the boot disk SCSI unit 0 (sda) —
# and then hot-attaches the etcd disk, which lands at SCSI unit 1 (sdb).
#
# If attached_disk were declared inside the VM block, GCP would assign both
# disks simultaneously and the etcd disk would claim sda instead of the boot disk.
# The startup script's wait loop handles the brief gap between VM start and
# this attachment completing.

resource "google_compute_attached_disk" "etcd" {
  disk        = google_compute_disk.etcd.id
  instance    = google_compute_instance.tos_primary.id
  device_name = "${var.vm_name}-etcd"
  mode        = "READ_WRITE"
  zone        = var.zone
}
