project_id  = "shc-labs"
region      = "us-central1"
environment = "dev"

cluster_name    = "concur-test-gke"
cluster_version = "1.28"

vpc_cidr     = "10.0.0.0/16"
pod_cidr     = "10.1.0.0/16"
service_cidr = "10.2.0.0/20"

node_group_instance_types = ["e2-standard-2"]
node_group_min_size       = 2
node_group_max_size       = 6
node_group_desired_size   = 4

enable_argocd                   = true
enable_fluent_bit               = true
enable_secrets_store_csi_driver = true

argocd_chart_version                       = "7.7.12"
secrets_store_csi_driver_chart_version     = "1.4.7"
gcp_secrets_manager_provider_chart_version = "1.5.0"

postgres_username = "postgres"
postgres_password = "CHANGE_ME"
postgres_database = "testdb"
