output "service_url" {
  value       = google_cloud_run_v2_service.n8n_service.uri
  description = "The URL of the deployed n8n service"
}

output "gcs_bucket_url" {
  value       = "gs://${var.gcs_bucket_name}"
  description = "The GCS bucket URL for n8n database"
}

output "artifact_repo_url" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}"
  description = "The Artifact Registry repository URL"
}

output "n8n_credentials" {
  value       = "Username: admin, Password: changeme"
  description = "Default credentials for n8n (please change in production)"
}