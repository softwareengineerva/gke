output "node_pool_versions" {
  description = "Current node pool versions"
  value = {
    (google_container_node_pool.main.name) = google_container_node_pool.main.version
  }
}

output "upgrade_status" {
  description = "Instructions for monitoring upgrade"
  value = <<-EOT
    To monitor the upgrade process:
    
    1. Watch node status:
       kubectl get nodes -w
    
    2. Watch pod evictions:
       kubectl get pods --all-namespaces -o wide -w
    
    3. Monitor GKE operations:
       gcloud container operations list --filter="status=RUNNING"
    
    4. Check node pool status:
       gcloud container node-pools list --cluster=${var.cluster_name} --region=${var.region}
    
    Note: Upgrades happen during maintenance window: ${var.maintenance_start_time} to ${var.maintenance_end_time} UTC
  EOT
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = google_compute_network.main.id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = var.vpc_cidr
}

output "private_subnet_ids" {
  description = "List of IDs of private subnets"
  value       = [google_compute_subnetwork.main.id]
}

output "public_subnet_ids" {
  description = "List of IDs of public subnets"
  value       = [google_compute_subnetwork.main.id]
}

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = [google_compute_router_nat.nat.id]
}

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = "Cloud Router provides NAT"
}

output "cluster_id" {
  description = "The ID/name of the GKE cluster"
  value       = google_container_cluster.main.id
}

output "cluster_arn" {
  description = "The ARN/ID of the cluster"
  value       = google_container_cluster.main.id
}

output "cluster_endpoint" {
  description = "Endpoint for your Kubernetes API server"
  value       = google_container_cluster.main.endpoint
}

output "cluster_version" {
  description = "The Kubernetes server version for the cluster"
  value       = google_container_cluster.main.master_version
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the cluster"
  value       = "GKE manages cluster firewall rules"
}

output "cluster_iam_role_arn" {
  description = "IAM role ARN of the cluster"
  value       = "GKE uses Workload Identity"
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded certificate data required to communicate with the cluster"
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "cluster_oidc_issuer_url" {
  description = "The URL on the cluster OIDC Issuer"
  value       = "https://container.googleapis.com/v1/projects/${var.project_id}/locations/${var.region}/clusters/${var.cluster_name}"
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC Provider"
  value       = "GKE uses Workload Identity"
}

output "node_group_id" {
  description = "node group ID"
  value       = google_container_node_pool.main.id
}

output "node_group_arn" {
  description = "ARN of the Node Group"
  value       = google_container_node_pool.main.id
}

output "node_group_status" {
  description = "Status of the node group"
  value       = "ACTIVE"
}

output "node_security_group_id" {
  description = "Security group ID attached to the nodes"
  value       = "GKE manages node firewall rules"
}

output "node_iam_role_arn" {
  description = "IAM role ARN for worker nodes"
  value       = google_service_account.node.email
}

output "configure_kubectl" {
  description = "Configure kubectl: run the following command to update your kubeconfig"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --region ${var.region} --project ${var.project_id}"
}

output "argocd_admin_password_command" {
  description = "Command to retrieve ArgoCD admin password"
  value       = var.enable_argocd ? "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d" : "ArgoCD not enabled"
}

output "argocd_server_service_command" {
  description = "Command to get ArgoCD server service details"
  value       = var.enable_argocd ? "kubectl get service -n argocd argocd-server" : "ArgoCD not enabled"
}

output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = "GKE uses native GCE PD CSI"
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = "GKE uses native Ingress"
}

output "test_app_secrets_role_arn" {
  description = "IAM role ARN for test app secrets access"
  value       = google_service_account.test_app_secrets_reader.email
}

output "test_secret_arn" {
  description = "ARN of the test secret"
  value       = google_secret_manager_secret.test_secret.id
}

output "test_secret_name" {
  description = "Name of the test secret"
  value       = google_secret_manager_secret.test_secret.name
}

output "postgres_secrets_csi_role_arn" {
  description = "IAM role ARN for PostgreSQL Secrets Store CSI access"
  value       = google_service_account.postgres_secrets_csi_role.email
}

output "postgres_user_secret_id" {
  description = "ID of PostgreSQL user secret"
  value       = google_secret_manager_secret.postgres_user.id
}

output "postgres_pass_secret_id" {
  description = "ID of PostgreSQL password secret"
  value       = google_secret_manager_secret.postgres_pass.id
}

output "postgres_db_secret_id" {
  description = "ID of PostgreSQL database secret"
  value       = google_secret_manager_secret.postgres_db.id
}

output "fluent_bit_role_arn" {
  description = "IAM role ARN for Fluent Bit"
  value       = var.enable_fluent_bit ? google_service_account.fluent_bit[0].email : null
}

output "cluster_autoscaler_role_arn" {
  description = "IAM role ARN for Cluster Autoscaler"
  value       = "GKE has built-in autoscaling"
}
