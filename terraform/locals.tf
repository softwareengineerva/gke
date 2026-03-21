locals {
  name_prefix = "concur-test"

  common_tags = {
    project     = local.name_prefix
    environment = var.environment
    managedby   = "terraform"
  }
}
