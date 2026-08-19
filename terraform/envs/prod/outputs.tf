output "cluster_name" {
  value = module.gke.cluster_name
}

output "region" {
  value = var.region
}

output "get_credentials_command" {
  description = "Run this to point kubectl at the new cluster"
  value       = "gcloud container clusters get-credentials ${module.gke.cluster_name} --region ${var.region} --project ${var.project_id}"
}

output "artifact_registry_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.apps.repository_id}"
}

output "app_gsa_email" {
  value = module.iam.app_gsa_email
}

output "ci_sa_email" {
  value = module.iam.ci_sa_email
}

output "wif_provider_name" {
  value = module.iam.wif_provider_name
}
