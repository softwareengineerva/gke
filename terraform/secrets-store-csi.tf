resource "helm_release" "secrets_store_csi_driver" {
  count      = var.enable_secrets_store_csi_driver ? 1 : 0
  name       = "secrets-store-csi-driver"
  repository = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart      = "secrets-store-csi-driver"
  version    = var.secrets_store_csi_driver_chart_version
  namespace  = "kube-system"

  set {
    name  = "syncSecret.enabled"
    value = "true"
  }
  set {
    name  = "enableSecretRotation"
    value = "true"
  }
  set {
    name  = "rotationPollInterval"
    value = "120s"
  }

  depends_on = [
    google_container_node_pool.main
  ]
}

resource "helm_release" "gcp_secrets_manager_provider" {
  count      = var.enable_secrets_store_csi_driver ? 1 : 0
  name       = "secrets-provider-gcp"
  repository = "https://raw.githubusercontent.com/GoogleCloudPlatform/secrets-store-csi-driver-provider-gcp/main/charts"
  chart      = "secrets-store-csi-driver-provider-gcp"
  version    = var.gcp_secrets_manager_provider_chart_version
  namespace  = "kube-system"

  depends_on = [
    helm_release.secrets_store_csi_driver
  ]
}
