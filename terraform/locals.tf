locals {
  name_prefix = "concur-test"

  common_tags = {
    Project     = local.name_prefix
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
