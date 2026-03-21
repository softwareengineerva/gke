# GCP Service Account for Fluent Bit
resource "google_service_account" "fluent_bit" {
  count        = var.enable_fluent_bit ? 1 : 0
  account_id   = "${local.name_prefix}-fluent-bit"
  display_name = "Fluent Bit Service Account"
}

resource "google_project_iam_member" "fluent_bit_log_writer" {
  count   = var.enable_fluent_bit ? 1 : 0
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.fluent_bit[0].email}"
}

# Bind Kubernetes SA to GCP SA (Workload Identity)
resource "google_service_account_iam_member" "fluent_bit_wi_binding" {
  count              = var.enable_fluent_bit ? 1 : 0
  service_account_id = google_service_account.fluent_bit[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[logging/fluent-bit]"
}
