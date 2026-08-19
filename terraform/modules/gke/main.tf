# Regional cluster => the control plane and nodes are spread across the
# zones in the region. That is the "multi-zone / highly available" part.
resource "google_container_cluster" "primary" {
  name     = var.cluster_name
  location = var.region

  # Best practice: never use the default node pool. Remove it and manage
  # our own pool below so we control autoscaling, machine type, etc.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  networking_mode = "VPC_NATIVE"
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Workload Identity: lets a Kubernetes ServiceAccount act as a Google
  # service account WITHOUT storing any JSON key inside the cluster.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  release_channel {
    channel = "REGULAR"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_ipv4_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  addons_config {
    http_load_balancing        { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # Set to true in real production so a fat-finger apply can't delete it.
  deletion_protection = false
}

# Managed node pool with cluster autoscaler (min..max nodes PER ZONE).
resource "google_container_node_pool" "primary_nodes" {
  name     = "${var.cluster_name}-np"
  location = var.region
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"
    image_type   = "COS_CONTAINERD"

    # Least-privilege node SA (created in the iam module).
    service_account = var.node_service_account
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    # Required for Workload Identity to work on the nodes.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = { env = var.env }
    tags   = ["gke-node", var.cluster_name]

    metadata = { disable-legacy-endpoints = "true" }
  }
}
