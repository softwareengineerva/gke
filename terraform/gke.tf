resource "google_container_cluster" "main" {
  provider            = google-beta
  name                = var.cluster_name
  location            = var.region
  deletion_protection = false

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.main.self_link
  subnetwork = google_compute_subnetwork.main.self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = "pod-ranges"
    services_secondary_range_name = "service-ranges"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  secret_manager_config {
    enabled = true
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  resource_labels = local.common_tags
}

resource "google_container_node_pool" "main" {
  name       = "${var.cluster_name}-node-pool"
  cluster    = google_container_cluster.main.name
  location   = var.region
  node_count = var.node_group_desired_size

  autoscaling {
    min_node_count = var.node_group_min_size
    max_node_count = var.node_group_max_size
  }

  node_config {
    machine_type = var.node_group_instance_types[0]

    service_account = google_service_account.node.email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      environment = var.environment
    }

    resource_labels = local.common_tags
  }

  lifecycle {
    ignore_changes = [ node_count ]
  }
}
