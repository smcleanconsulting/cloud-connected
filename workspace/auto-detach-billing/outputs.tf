output "function_url" {
  description = "The URL of the deployed Cloud Function"
  value       = google_cloudfunctions2_function.billing_detachment_function.service_config[0].uri
}

output "pubsub_topic" {
  description = "The Pub/Sub topic for budget alerts"
  value       = google_pubsub_topic.budget_alerts.id
}

output "budget_name" {
  description = "The name of the created budget"
  value       = google_billing_budget.budget.display_name
}

output "function_service_account" {
  description = "The service account used by the Cloud Function"
  value       = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}