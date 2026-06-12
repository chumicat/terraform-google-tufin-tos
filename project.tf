# ── API Enablement ────────────────────────────────────────────────────────────
# Ensures required APIs are active in the existing project.
# disable_on_destroy = false: APIs remain enabled after terraform destroy,
# preventing accidental disruption to other workloads in the same project.

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "cloudresourcemanager" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = false
}
