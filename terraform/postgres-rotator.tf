# Service Account for the Cloud Function
resource "google_service_account" "postgres_rotator" {
  account_id   = "${local.name_prefix}-postgres-rotator"
  display_name = "Postgres Rotator Cloud Function SA"
}

# Grant access to read the secrets
resource "google_secret_manager_secret_iam_member" "rotator_user_accessor" {
  secret_id = google_secret_manager_secret.postgres_user.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.postgres_rotator.email}"
}

resource "google_secret_manager_secret_iam_member" "rotator_pass_accessor" {
  secret_id = google_secret_manager_secret.postgres_pass.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.postgres_rotator.email}"
}

resource "google_secret_manager_secret_iam_member" "rotator_db_accessor" {
  secret_id = google_secret_manager_secret.postgres_db.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.postgres_rotator.email}"
}

# Grant access to add new versions to the postgres_pass secret
resource "google_secret_manager_secret_iam_member" "rotator_pass_adder" {
  secret_id = google_secret_manager_secret.postgres_pass.id
  role      = "roles/secretmanager.secretVersionManager"
  member    = "serviceAccount:${google_service_account.postgres_rotator.email}"
}

# Source Code bucket
resource "random_id" "bucket_prefix" {
  byte_length = 8
}

resource "google_storage_bucket" "function_source" {
  name                        = "${local.name_prefix}-function-source-${random_id.bucket_prefix.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
}

# Package function source code
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../cloud-functions/postgres-rotator"
  output_path = "${path.module}/../cloud-functions/postgres-rotator.zip"
}

resource "google_storage_bucket_object" "function_zip" {
  name   = "postgres-rotator-${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_zip.output_path
}

# Serverless VPC Access Connector
resource "google_vpc_access_connector" "connector" {
  name          = "${local.name_prefix}-vpc-cx"
  region        = var.region
  network       = google_compute_network.main.name
  ip_cidr_range = "10.8.0.0/28"
  min_instances = 2
  max_instances = 3
}

# The Cloud Function
resource "google_cloudfunctions2_function" "postgres_rotator" {
  name        = "${local.name_prefix}-postgres-rotator"
  location    = var.region
  description = "Rotates PostgreSQL password"

  build_config {
    runtime     = "python311"
    entry_point = "rotate_postgres_password"
    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_zip.name
      }
    }
  }

  service_config {
    max_instance_count = 1
    available_memory   = "256Mi"
    timeout_seconds    = 60
    
    vpc_connector                 = google_vpc_access_connector.connector.id
    vpc_connector_egress_settings = "PRIVATE_RANGES_ONLY"
    
    service_account_email = google_service_account.postgres_rotator.email

    environment_variables = {
      DB_HOST        = "10.0.0.250"
      DB_PORT        = "5432"
      DB_USER_SECRET = google_secret_manager_secret.postgres_user.id
      DB_NAME_SECRET = google_secret_manager_secret.postgres_db.id
    }
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.secret_rotation.id
    retry_policy   = "RETRY_POLICY_DO_NOT_RETRY"
  }
}
