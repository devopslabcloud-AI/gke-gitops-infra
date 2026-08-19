variable "project_id"           { type = string }
variable "cluster_name"         { type = string }
variable "region"               { type = string }
variable "env"                  { type = string }
variable "network"              { type = string }
variable "subnetwork"           { type = string }
variable "pods_range_name"      { type = string }
variable "services_range_name"  { type = string }
variable "master_ipv4_cidr"     { type = string }
variable "node_service_account" { type = string }

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "disk_size_gb" {
  type    = number
  default = 50
}

variable "min_nodes" {
  type    = number
  default = 1
}

variable "max_nodes" {
  type    = number
  default = 4
}

variable "authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = [{
    cidr_block   = "0.0.0.0/0"
    display_name = "all"
  }]
}
