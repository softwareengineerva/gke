# Create a test secret in Google Secret Manager
resource "google_secret_manager_secret" "test_secret" {
  secret_id = "${local.name_prefix}-test-secret"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "test_secret_value" {
  secret = google_secret_manager_secret.test_secret.id
  secret_data = jsonencode({
    username = "test-user"
    password = "test-password-123"
    database = "test-database"
    message  = "This secret was retrieved using Workload Identity!"
  })
}

# GCP Service Account for test app
resource "google_service_account" "test_app_secrets_reader" {
  account_id   = "${local.name_prefix}-test-app"
  display_name = "Test App Secrets Reader"
}

# Allow GCP SA to read the secret
resource "google_secret_manager_secret_iam_member" "test_app_secret_accessor" {
  secret_id = google_secret_manager_secret.test_secret.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.test_app_secrets_reader.email}"
}

# Bind Kubernetes SA to GCP SA (Workload Identity)
resource "google_service_account_iam_member" "test_app_wi_binding" {
  service_account_id = google_service_account.test_app_secrets_reader.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[secrets-demo/secrets-demo-sa]"
}
