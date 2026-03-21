# Create PostgreSQL credentials secret in Google Secret Manager
resource "google_secret_manager_secret" "postgres_credentials" {
  secret_id = "${local.name_prefix}-postgres-creds"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "postgres_credentials_value" {
  secret = google_secret_manager_secret.postgres_credentials.id
  secret_data = jsonencode({
    username = var.postgres_username
    password = var.postgres_password
    database = var.postgres_database
  })
}

# GCP Service Account for PostgreSQL
resource "google_service_account" "postgres_secrets_csi_role" {
  account_id   = "${local.name_prefix}-postgres-sa"
  display_name = "PostgreSQL Secrets CSI SA"
}

# Allow GCP SA to read the PostgreSQL secret
resource "google_secret_manager_secret_iam_member" "postgres_secret_accessor" {
  secret_id = google_secret_manager_secret.postgres_credentials.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.postgres_secrets_csi_role.email}"
}

# Bind Kubernetes SA to GCP SA (Workload Identity)
resource "google_service_account_iam_member" "postgres_wi_binding" {
  service_account_id = google_service_account.postgres_secrets_csi_role.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[postgres/postgres-sa]"
}
