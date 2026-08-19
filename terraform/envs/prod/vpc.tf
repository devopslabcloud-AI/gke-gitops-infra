module "vpc" {
  source = "../../modules/vpc"

  network_name        = "${var.cluster_name}-vpc"
  subnet_name         = "${var.cluster_name}-subnet"
  region              = var.region
  subnet_cidr         = var.subnet_cidr
  pods_range_name     = "pods"
  pods_cidr           = var.pods_cidr
  services_range_name = "services"
  services_cidr       = var.services_cidr
}
