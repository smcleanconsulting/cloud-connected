variable "project_id" {
  description = "The GCP project ID"
  default     = "n8n-podman-456718"
}

variable "region" {
  description = "The GCP region to deploy resources"
  default     = "us-east1"
}

variable "artifact_repo" {
  description = "The Artifact Registry repository name"
  default     = "n8n-podman"
}

variable "gcs_bucket_name" {
  description = "GCS bucket name for n8n SQLite database"
  default     = "n8n-podman-456718-sqlite-db"
}

variable "n8n_image_name" {
  description = "Name for the n8n Docker image"
  default     = "n8n-gcs"
}

variable "n8n_image_tag" {
  description = "Tag for the n8n Docker image"
  default     = "latest"
}

variable "service_name" {
  description = "Name of the Cloud Run service"
  default     = "n8n-workflow"
}

variable "n8n_port" {
  description = "Port that n8n listens on"
  default     = 5678
}

variable "n8n_memory" {
  description = "Memory allocation for n8n Cloud Run service"
  default     = "1Gi"
}

variable "n8n_cpu" {
  description = "CPU allocation for n8n Cloud Run service"
  default     = "1"
}