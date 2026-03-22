provider "google" {
  project = var.project_id
  region  = var.region
  # Increase timeout for long-running upgrades
  request_timeout = "60m"
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  # Increase timeout for long-running upgrades
  request_timeout = "60m"
}

# Fetch GKE cluster config
data "google_client_config" "default" {}

# Kubernetes provider
provider "kubernetes" {
  host                   = "https://${google_container_cluster.main.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
  # Add this to handle when cluster doesn't exist
  ignore_annotations = [
    "^autopilot\\.gke\\.io\\/.*",
    "^kubectl\\.kubernetes\\.io\\/.*"
  ]  
}

# Helm provider
provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.main.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.main.master_auth[0].cluster_ca_certificate)
  }
}
