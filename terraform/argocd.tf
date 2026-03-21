resource "kubernetes_namespace" "argocd" {
  count = var.enable_argocd ? 1 : 0
  metadata {
    name = "argocd"
    labels = {
      name        = "argocd"
      environment = var.environment
    }
  }
  depends_on = [google_container_node_pool.main]
  
  lifecycle {
    ignore_changes = all
  }
}

resource "helm_release" "argocd" {
  count      = var.enable_argocd ? 1 : 0
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd[0].metadata[0].name

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }
  # High Availability configuration
  set {
    name  = "redis-ha.enabled"
    value = "true"
  }
  set {
    name  = "controller.replicas"
    value = "1"
  }
  set {
    name  = "server.replicas"
    value = "2"
  }
  set {
    name  = "repoServer.replicas"
    value = "2"
  }
  set {
    name  = "applicationSet.replicas"
    value = "2"
  }
  set {
    name  = "server.resources.limits.cpu"
    value = "500m"
  }
  set {
    name  = "server.resources.limits.memory"
    value = "512Mi"
  }
  set {
    name  = "server.resources.requests.cpu"
    value = "250m"
  }
  set {
    name  = "server.resources.requests.memory"
    value = "256Mi"
  }
  set {
    name  = "server.ingress.enabled"
    value = "false"
  }
  set {
    name  = "server.metrics.enabled"
    value = "true"
  }
  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }
  set {
    name  = "repoServer.metrics.enabled"
    value = "true"
  }
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  depends_on = [
    kubernetes_namespace.argocd,
   // kubernetes_cluster_role_binding.terraform_admin
  ]
}
