# =============================================================================
# GKE CLUSTER WITH SURGE UPGRADE CONFIGURATION
# =============================================================================
# This Terraform configuration manages both control plane and node pool upgrades
# with a SINGLE `terraform apply`. The upgrade process is fully automated by GKE.
#
# HOW A SINGLE `terraform apply` EXECUTES THE UPGRADE:
# =============================================================================
# When you change `cluster_version` (min_master_version) or node pool `version` and run apply:
#
# STEP 1: Control Plane Upgrade (if needed)
#   - GKE upgrades the control plane during the maintenance window
#   - Regional clusters: No downtime (3 replicas upgraded sequentially)
#   - Zonal clusters: ~5 minutes of API server downtime
#   - Terraform waits for completion before proceeding to node pools
#
# STEP 2: Node Pool Surge Upgrades (per pool, in parallel)
#   For EACH node pool with max_surge=1 and max_unavailable=0:
#   ┌─────────────────────────────────────────────────────────────────────┐
#   │ Iteration 1 (automatic, no extra apply needed):                    │
#   │   ├── Create surge node #1 (new version)  [3→4 nodes total]        │
#   │   ├── Cordon and drain old node #1                                 │
#   │   ├── Delete old node #1                    [4→3 nodes total]       │
#   │   └── Wait for stability (pods ready, health checks pass)          │
#   ├─────────────────────────────────────────────────────────────────────┤
#   │ Iteration 2 (automatic, no extra apply needed):                    │
#   │   ├── Create surge node #2 (new version)  [3→4 nodes total]        │
#   │   ├── Cordon and drain old node #2                                 │
#   │   ├── Delete old node #2                    [4→3 nodes total]       │
#   │   └── Wait for stability                                            │
#   ├─────────────────────────────────────────────────────────────────────┤
#   │ Iteration 3 (automatic, no extra apply needed):                    │
#   │   ├── Create surge node #3 (new version)  [3→4 nodes total]        │
#   │   ├── Cordon and drain old node #3                                 │
#   │   ├── Delete old node #3                    [4→3 nodes total]       │
#   │   └── Upgrade complete for this pool!                               │
#   └─────────────────────────────────────────────────────────────────────┘
#
#   All node pools upgrade IN PARALLEL. Total time: ~15-45 minutes depending
#   on pod disruption budgets and application startup times.
# =============================================================================

resource "google_container_cluster" "main" {
  provider            = google-beta
  name                = var.cluster_name
  location            = var.region
  deletion_protection = false

  # =========================================================================
  # CONTROL PLANE VERSION MANAGEMENT
  # =========================================================================
  # When you change this value and run terraform apply, GKE will:
  # 1. Upgrade the control plane to the specified version
  # 2. For regional clusters: No API downtime (3 replicas upgraded sequentially)
  # 3. For zonal clusters: ~5 minutes of API server unavailability
  # 4. Wait for control plane to be healthy before proceeding
  # 
  # To upgrade: Change this value (e.g., from "1.29" to "1.30") and run apply
  min_master_version = var.cluster_version

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.main.self_link
  subnetwork = google_compute_subnetwork.main.self_link

  ip_allocation_policy {
    cluster_secondary_range_name  = google_compute_subnetwork.main.secondary_ip_range[0].range_name
    services_secondary_range_name = google_compute_subnetwork.main.secondary_ip_range[1].range_name
  }

  # =========================================================================
  # MAINTENANCE WINDOW - Controls WHEN upgrades can occur
  # =========================================================================
  # Without this, GKE may upgrade at any time. With this configured,
  # upgrades only happen during the specified window.
  # 
  # For zero-downtime upgrades, set this to your off-peak hours.
  maintenance_policy {
    recurring_window {
      start_time = var.maintenance_start_time
      end_time   = var.maintenance_end_time
      recurrence = "FREQ=DAILY"  # Repeat daily to meet 48h/32d requirement
    }
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

  # =========================================================================
  # LIFECYCLE MANAGEMENT
  # =========================================================================
  lifecycle {
    # Prevent accidental deletion of production cluster
    prevent_destroy = true
    
    # Ignore changes to node count as we manage it per node pool
    ignore_changes = [
      initial_node_count,
    ]
  }

  # Terraform will wait for cluster to be ready
  timeouts {
    create = "30m"
    update = "30m"  # Extended timeout for control plane upgrades
    delete = "30m"
  }
}

resource "google_container_node_pool" "main" {
  name       = "${var.cluster_name}-node-pool"
  cluster    = google_container_cluster.main.name
  location   = var.region

  # =========================================================================
  # NODE VERSION MANAGEMENT
  # =========================================================================
  # When you change this value and run terraform apply, GKE will:
  # 1. Check if node version needs upgrade (if version < control plane)
  # 2. Execute surge upgrade based on settings below
  # 3. Create new nodes, drain old ones, delete old nodes
  # 4. Repeat until all nodes are upgraded
  # 
  # To upgrade: Change this value (e.g., from "1.29" to "1.30") and run apply
  version = var.node_version

  node_count = var.node_group_desired_size

  autoscaling {
    min_node_count = var.node_group_min_size
    max_node_count = var.node_group_max_size
  }

  # =========================================================================
  # SURGE UPGRADE CONFIGURATION - The "Script Replacement"
  # =========================================================================
  # This is the key to zero-downtime upgrades WITHOUT custom scripts.
  # When you run terraform apply, GKE automatically executes the upgrade
  # using these parameters.
  #
  # HOW SURGE UPGRADE WORKS WITH max_surge=1 AND max_unavailable=0:
  # -------------------------------------------------------------------------
  # | Step | Action                              | Node Count |
  # |------|-------------------------------------|------------|
  # | 0    | Initial state (3 nodes old version) | 3          |
  # | 1    | Create surge node (new version)     | 4          |
  # | 2    | Cordon and drain old node           | 4 (1 cordoned) |
  # | 3    | Delete old node                     | 3          |
  # | 4    | Repeat steps 1-3 for each old node  | 3→4→3→...  |
  # | End  | All nodes on new version            | 3          |
  # -------------------------------------------------------------------------
  #
  # You do NOT need to run terraform apply multiple times. GKE handles
  # the entire iteration automatically.
  upgrade_settings {
    # max_surge: Number of additional nodes created during upgrade
    #   - 1 = Creates 1 extra node before draining old ones
    #   - Higher values = faster upgrades but more resource consumption
    max_surge = 1
    
    # max_unavailable: Number of nodes that can be offline during upgrade
    #   - 0 = Zero nodes taken offline until new ones are ready
    #   - Critical for zero-downtime upgrades
    max_unavailable = 0
    
    # strategy: Must be "SURGE" for this behavior
    strategy = "SURGE"
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

  # =========================================================================
  # MANAGEMENT CONFIGURATION
  # =========================================================================
  management {
    # auto_upgrade: MUST be false when using manual surge upgrades
    # If true, GKE might upgrade outside your control and conflict with Terraform
    auto_upgrade = false
    
    # auto_repair: True = GKE automatically repairs unhealthy nodes
    auto_repair = true
  }

  # =========================================================================
  # LIFECYCLE MANAGEMENT
  # =========================================================================
  lifecycle {
    # Prevent accidental deletion
    prevent_destroy = true
    
    # Ignore changes that happen during surge upgrades
    # This prevents Terraform from trying to "fix" the node count
    # during an ongoing upgrade operation
    ignore_changes = [
      node_count,          # Surge upgrades temporarily change node count
      initial_node_count,  # Initial count is only for creation
    ]
  }

  # =========================================================================
  # TIMEOUTS
  # =========================================================================
  timeouts {
    create = "30m"
    update = "60m"  # Extended timeout for surge upgrades (3 nodes * 15 min each)
    delete = "30m"
  }

  # Terraform will wait for node pool to be ready
  depends_on = [google_container_cluster.main]
}

# -----------------------------------------------------------------------------
# OPTIONAL: HELPER SCRIPT FOR CREDENTIALS
# -----------------------------------------------------------------------------
resource "local_file" "get_credentials" {
  filename = "get-cluster-credentials.sh"
  content  = <<-EOT
    #!/bin/bash
    # Run this script to authenticate kubectl with your cluster
    
    gcloud container clusters get-credentials ${var.cluster_name} \\
        --region ${var.region} \\
        --project ${var.project_id}
    
    echo "Connected to cluster: $(kubectl config current-context)"
    echo "Control plane version: $(kubectl version -o json | jq -r .serverVersion.gitVersion)"
    echo "Node versions:"
    kubectl get nodes -o wide
  EOT
  
  depends_on = [google_container_cluster.main]
}
