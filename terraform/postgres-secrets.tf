# PostgreSQL credentials in separate secrets to avoid JSON parsing issues with CSI driver
resource "google_secret_manager_secret" "postgres_user" {
  secret_id = "${local.name_prefix}-postgres-user"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "postgres_user_value" {
  secret      = google_secret_manager_secret.postgres_user.id
  secret_data = var.postgres_username
}

data "google_project" "project" {}

resource "google_pubsub_topic" "secret_rotation" {
  name = "${local.name_prefix}-secret-rotation"
}

resource "google_pubsub_topic_iam_member" "secret_rotation_publisher" {
  topic  = google_pubsub_topic.secret_rotation.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-secretmanager.iam.gserviceaccount.com"
}

resource "google_secret_manager_secret" "postgres_pass" {
  secret_id = "${local.name_prefix}-postgres-pass"
  replication {
    auto {}
  }
  
  topics {
    name = google_pubsub_topic.secret_rotation.id
  }

  rotation {
    next_rotation_time = "2026-04-21T00:00:00Z" # Using 30 days from 2026-03-22
    rotation_period    = "2592000s" # 30 days
  }
}

resource "google_secret_manager_secret_version" "postgres_pass_value" {
  secret      = google_secret_manager_secret.postgres_pass.id
  secret_data = var.postgres_password
}

resource "google_secret_manager_secret" "postgres_db" {
  secret_id = "${local.name_prefix}-postgres-db"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "postgres_db_value" {
  secret      = google_secret_manager_secret.postgres_db.id
  secret_data = var.postgres_database
}

# GCP Service Account for PostgreSQL
resource "google_service_account" "postgres_secrets_csi_role" {
  account_id   = "${local.name_prefix}-postgres-sa"
  display_name = "PostgreSQL Secrets CSI SA"
}

# Allow GCP SA to read all three secrets
resource "google_secret_manager_secret_iam_member" "postgres_user_accessor" {
  secret_id = google_secret_manager_secret.postgres_user.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.postgres_secrets_csi_role.email}"
}

resource "google_secret_manager_secret_iam_member" "postgres_pass_accessor" {
  secret_id = google_secret_manager_secret.postgres_pass.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.postgres_secrets_csi_role.email}"
}

resource "google_secret_manager_secret_iam_member" "postgres_db_accessor" {
  secret_id = google_secret_manager_secret.postgres_db.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.postgres_secrets_csi_role.email}"
}

# Bind Kubernetes SA to GCP SA (Workload Identity)
resource "google_service_account_iam_member" "postgres_wi_binding" {
  service_account_id = google_service_account.postgres_secrets_csi_role.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[postgres/postgres-sa]"
}
