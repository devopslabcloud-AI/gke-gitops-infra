variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  default     = "us-central1"
  description = "Region for the regional (multi-zone) GKE cluster"
}

variable "env" {
  type    = string
  default = "prod"
}

variable "cluster_name" {
  type    = string
  default = "gitops-gke"
}

# --- Networking CIDRs ---
variable "subnet_cidr" {
  type    = string
  default = "10.10.0.0/20"
}

variable "pods_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "services_cidr" {
  type    = string
  default = "10.30.0.0/20"
}

variable "master_ipv4_cidr" {
  type    = string
  default = "172.16.0.0/28"
}

# --- Node pool sizing ---
variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "min_nodes" {
  type    = number
  default = 1
}

variable "max_nodes" {
  type    = number
  default = 4
}

# --- Workload Identity for the app ---
variable "app_gsa_name" {
  type    = string
  default = "microservice-app"
}

variable "k8s_namespace" {
  type    = string
  default = "microservice"
}

variable "k8s_sa_name" {
  type    = string
  default = "microservice-sa"
}

# --- GitHub (for keyless CI via WIF) ---
variable "github_owner" {
  type        = string
  description = "Your GitHub org or username"
}

variable "app_repo_name" {
  type    = string
  default = "gke-microservice-app"
}
