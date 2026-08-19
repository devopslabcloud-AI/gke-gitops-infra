output "node_sa_email" {
  value = google_service_account.gke_nodes.email
}

output "app_gsa_email" {
  value = google_service_account.app.email
}

output "ci_sa_email" {
  value = google_service_account.ci.email
}

output "wif_provider_name" {
  value = google_iam_workload_identity_pool_provider.github.name
}
