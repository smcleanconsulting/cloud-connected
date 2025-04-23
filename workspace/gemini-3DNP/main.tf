# --- Provider Configuration & Version Requirements ---
terraform {
  required_version = ">= 1.3" # Recommend using a recent Terraform version

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0" # Use a recent provider version
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  # --- Recommended: Terraform Backend Configuration (Example using GCS) ---
  # backend "gcs" {
  #   bucket = "your-terraform-state-bucket-name" # CHANGE TO YOUR GCS BUCKET FOR TF STATE
  #   prefix = "n8n/terraform.tfstate"
  # }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# --- Variables ---
variable "project_id" {
  description = "Your Google Cloud project ID"
  type        = string
  default     = "n8n-podman-456718" # Ensure this is correct
}

variable "region" {
  description = "The Google Cloud region for deployment"
  type        = string
  default     = "us-east1"
}

variable "artifact_registry_repo_name" {
  description = "Name of the Artifact Registry repository"
  type        = string
  default     = "n8n-podman"
}

variable "gcs_bucket_name_prefix" {
  description = "Prefix for the GCS bucket name"
  type        = string
  default     = "n8n-data" # Shorter prefix is fine
}

variable "cloud_run_service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = "n8n-service"
}

variable "dedicated_service_account_name" {
  description = "Name for the dedicated service account for Cloud Run"
  type        = string
  default     = "n8n-cloudrun-sa"
}

# --- Data Sources ---
data "google_project" "project" {}

# --- Resource: Random ID for Bucket Name ---
# Ensures global uniqueness for the GCS bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4 # Creates an 8-character hex suffix
}

# --- Resource: Enable Necessary APIs ---
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "cloudbuild.googleapis.com",       # Used implicitly by Cloud Run builds/deploys
    "secretmanager.googleapis.com",    # Good practice for managing secrets
    "serviceusage.googleapis.com",     # Needed to manage services
    "cloudresourcemanager.googleapis.com" # Often needed for IAM bindings
  ])
  project            = var.project_id
  service            = each.key
  disable_on_destroy = false # Keep APIs enabled after destroy
}

# --- Resource: Dedicated Service Account for Cloud Run ---
resource "google_service_account" "n8n_sa" {
  depends_on = [google_project_service.apis["iam.googleapis.com"]]
  project      = var.project_id
  account_id   = var.dedicated_service_account_name
  display_name = "N8N Cloud Run Service Account"
}

# --- Resource: Artifact Registry Repository ---
resource "google_artifact_registry_repository" "n8n_repo" {
  depends_on = [google_project_service.apis["artifactregistry.googleapis.com"]]
  project       = var.project_id
  location      = var.region
  repository_id = var.artifact_registry_repo_name
  description   = "n8n container image repository"
  format        = "DOCKER"
}

# --- Resource: GCS Bucket for Persistent Data ---
resource "google_storage_bucket" "n8n_data_bucket" {
  depends_on = [google_project_service.apis["storage.googleapis.com"]]
  project       = var.project_id
  name          = "${var.gcs_bucket_name_prefix}-${var.project_id}-${random_id.bucket_suffix.hex}"
  location      = var.region
  force_destroy = false
  uniform_bucket_level_access = true
  lifecycle {
    prevent_destroy = true
  }
}

# --- IAM: Grant Dedicated SA necessary permissions ---
resource "google_project_iam_member" "n8n_sa_artifact_reader" {
  depends_on = [google_artifact_registry_repository.n8n_repo]
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = google_service_account.n8n_sa.member
}

resource "google_storage_bucket_iam_member" "n8n_sa_gcs_access" {
  depends_on = [google_storage_bucket.n8n_data_bucket]
  bucket = google_storage_bucket.n8n_data_bucket.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.n8n_sa.member
}

# --- Resource: Cloud Run Service ---
resource "google_cloud_run_v2_service" "n8n_service" {
  depends_on = [
    google_project_service.apis["run.googleapis.com"],
    google_artifact_registry_repository.n8n_repo,
    google_storage_bucket.n8n_data_bucket,
    google_service_account.n8n_sa,
    google_project_iam_member.n8n_sa_artifact_reader,
    google_storage_bucket_iam_member.n8n_sa_gcs_access
  ]

  project  = var.project_id
  location = var.region
  name     = var.cloud_run_service_name

  template {
    service_account = google_service_account.n8n_sa.email
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"
    # startup_cpu_boost = true

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.n8n_repo.repository_id}/n8n:latest"
      ports { container_port = 5678 }
      resources {
        limits = { cpu = "1000m", memory = "1Gi" }
      }
      volume_mounts {
        name       = "n8n-data-volume"
        mount_path = "/home/node/.n8n"
      }
      # Add ENV VARS here if needed
    } # End of containers block

    # --- CORRECTED Volume Definition using BLOCK syntax ---
    volumes { # <--- This is a BLOCK declaration for ONE volume
      name = "n8n-data-volume" # Argument: name of this volume

      # Nested BLOCK defining the type and configuration (CSI)
      csi {
        driver = "gcsfuse.run.googleapis.com" # Argument: CSI driver name
        # readOnly = false # Argument: Optional bool
        volume_attributes = { # Argument: map of attributes for the driver
          bucketName = google_storage_bucket.n8n_data_bucket.name
          # "implicitDirs" = "true" # Example optional attribute
        }
      } # End of nested 'csi' block
    } # --- End of 'volumes' block ---
    # --- To add more volumes, add more 'volumes {...}' blocks here ---

    scaling {
      min_instance_count = 0
      # CRITICAL WARNING: max_instance_count = 1 is vital for SQLite on GCS FUSE
      max_instance_count = 1
    }

  } # End of template block

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
} # End of Cloud Run resource

# --- IAM: Allow Public Access (REMOVE FOR PRODUCTION) ---
resource "google_cloud_run_v2_service_iam_member" "allow_public_access" {
  depends_on = [google_cloud_run_v2_service.n8n_service]
  project  = google_cloud_run_v2_service.n8n_service.project
  location = google_cloud_run_v2_service.n8n_service.location
  name     = google_cloud_run_v2_service.n8n_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# --- Outputs ---
output "n8n_service_url" {
  description = "URL of the deployed n8n Cloud Run service"
  value       = google_cloud_run_v2_service.n8n_service.uri
}

output "gcs_data_bucket_name" {
  description = "Name of the GCS bucket used for n8n persistence"
  value       = google_storage_bucket.n8n_data_bucket.name
}

output "cloud_run_service_account_email" {
  description = "Email of the dedicated service account used by Cloud Run"
  value       = google_service_account.n8n_sa.email
}