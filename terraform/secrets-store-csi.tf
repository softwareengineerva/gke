resource "helm_release" "secrets_store_csi_driver" {
  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  namespace  = "kube-system"
  version    = "1.4.7"

  skip_crds = true

  set {
    name  = "enableSecretRotation"
    value = "true"
  }
  
  set {
    name  = "rotationPollInterval"
    value = "120s"
  }
  
  set {
    name  = "syncSecret.enabled"
    value = "true"
  }

  depends_on = [google_container_node_pool.main]
}

resource "null_resource" "csi_gcp_provider" {
  triggers = {
    # Re-run if the helm release changes
    driver_version = helm_release.secrets_store_csi_driver.version
  }

  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${var.cluster_name} --region ${var.region} --project ${var.project_id} && kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/secrets-store-csi-driver-provider-gcp/main/deploy/provider-gcp-plugin.yaml"
  }

  depends_on = [helm_release.secrets_store_csi_driver]
}
