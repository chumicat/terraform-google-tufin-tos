# ── VM ────────────────────────────────────────────────────────────────────────

output "vm_name" {
  description = "Name of the TOS primary VM"
  value       = google_compute_instance.tos_primary.name
}

output "vm_internal_ip" {
  description = "Private IP address of the TOS VM (use for internal access)"
  value       = google_compute_instance.tos_primary.network_interface[0].network_ip
}

output "vm_external_ip" {
  description = "Ephemeral external IP of the TOS VM (used for outbound internet; not the LB address)"
  value       = google_compute_instance.tos_primary.network_interface[0].access_config[0].nat_ip
}

output "ssh_command" {
  description = "Cloud Shell command to SSH into the TOS VM via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.tos_primary.name} --zone ${var.zone} --tunnel-through-iap"
}

# ── Load Balancer ──────────────────────────────────────────────────────────────

output "lb_ip" {
  description = "Internal IP address of the HTTPS load balancer forwarding rule"
  value       = google_compute_forwarding_rule.https.ip_address
}

output "tos_ui_url" {
  description = "TOS WebUI URL via the internal load balancer"
  value       = "https://${google_compute_forwarding_rule.https.ip_address}"
}
