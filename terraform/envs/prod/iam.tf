module "iam" {
  source = "../../modules/iam"

  project_id    = var.project_id
  cluster_name  = var.cluster_name
  app_gsa_name  = var.app_gsa_name
  k8s_namespace = var.k8s_namespace
  k8s_sa_name   = var.k8s_sa_name
  github_owner  = var.github_owner
  app_repo_name = var.app_repo_name
}
