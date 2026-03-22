variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "shc-labs"
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = "concur-test-gke"
}

variable "cluster_version" {
  description = "GKE cluster version"
  type        = string
  default     = "1.28"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "pod_cidr" {
  description = "CIDR block for Pods"
  type        = string
  default     = "10.1.0.0/16"
}

variable "service_cidr" {
  description = "CIDR block for Services"
  type        = string
  default     = "10.2.0.0/20"
}

variable "node_group_instance_types" {
  description = "Instance types for the node group"
  type        = list(string)
  default     = ["e2-standard-2"]
}

variable "node_group_min_size" {
  description = "Minimum nodes in pool"
  type        = number
  default     = 1
}

variable "node_group_max_size" {
  description = "Maximum nodes in pool"
  type        = number
  default     = 3
}

variable "node_group_desired_size" {
  description = "Desired nodes in pool"
  type        = number
  default     = 2
}

variable "maintenance_start_time" {
  description = "Maintenance window start time (UTC)"
  type        = string
  default     = "2025-03-23T02:00:00Z"
}

variable "maintenance_end_time" {
  description = "Maintenance window end time (UTC)"
  type        = string
  default     = "2025-03-23T06:00:00Z"
}

variable "enable_argocd" {
  description = "Enable ArgoCD"
  type        = bool
  default     = true
}

variable "enable_fluent_bit" {
  description = "Enable Fluent Bit"
  type        = bool
  default     = true
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.7.12"
}

variable "postgres_username" {
  description = "PostgreSQL username"
  type        = string
  default     = "postgres"
  sensitive   = true
}

variable "postgres_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
}

variable "postgres_database" {
  description = "PostgreSQL database name"
  type        = string
  default     = "testdb"
}
