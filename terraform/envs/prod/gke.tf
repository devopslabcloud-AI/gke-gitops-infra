module "gke" {
  source = "../../modules/gke"

  project_id           = var.project_id
  cluster_name         = var.cluster_name
  region               = var.region
  env                  = var.env
  network              = module.vpc.network_name
  subnetwork           = module.vpc.subnet_name
  pods_range_name      = module.vpc.pods_range_name
  services_range_name  = module.vpc.services_range_name
  master_ipv4_cidr     = var.master_ipv4_cidr
  node_service_account = module.iam.node_sa_email
  machine_type         = var.machine_type
  min_nodes            = var.min_nodes
  max_nodes            = var.max_nodes
}

# Docker image registry for the microservice.
resource "google_artifact_registry_repository" "apps" {
  location      = var.region
  repository_id = "apps"
  description   = "Container images for microservices"
  format        = "DOCKER"
}
