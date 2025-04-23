# main.tf (final corrected version)
provider "google" {
  project = "n8n-podman-456718"
  region  = "us-east1"
}

# Enable required services
resource "google_project_service" "services" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com"
  ])
  service = each.key
}

# Artifact Registry
resource "google_artifact_registry_repository" "n8n_repo" {
  location      = "us-east1"
  repository_id = "n8n-podman"
  format        = "DOCKER"
  depends_on    = [google_project_service.services]
}

# Storage Bucket
resource "google_storage_bucket" "n8n_bucket" {
  force_destroy = true
  name                        = "n8n-podman-db-${data.google_project.project.number}"
  location                    = "US-EAST1"
  uniform_bucket_level_access = true
}

# Service Accounts
resource "google_service_account" "n8n_sa" {
  account_id   = "n8n-cloud-run-sa"
  display_name = "N8N Cloud Run Service Account"
}

resource "google_service_account" "cloudbuild_sa" {
  account_id   = "cloudbuild-sa"
  display_name = "Cloud Build Service Account"
}

# IAM Permissions
resource "google_project_iam_member" "storage_access" {
  project = "n8n-podman-456718"
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.n8n_sa.email}"
}

resource "google_project_iam_member" "cloudbuild_sa_roles" {
  for_each = toset([
    "roles/cloudbuild.builds.builder",
    "roles/artifactregistry.writer"
  ])
  project = "n8n-podman-456718"
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild_sa.email}"
}

resource "google_project_iam_member" "cloudrun_sa_roles" {
  project = "n8n-podman-456718"
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.n8n_sa.email}"
}

# Cloud Build Trigger (corrected)
resource "google_cloudbuild_trigger" "n8n_image" {
  name     = "n8n-image-trigger"
  filename = "cloudbuild.yaml"
  
  github {
    owner = "your-github-username"
    name  = "your-repo-name"
    push {
      branch = "^main$"
    }
  }
  
  service_account = google_service_account.cloudbuild_sa.id
  depends_on = [
    google_project_service.services,
    google_artifact_registry_repository.n8n_repo,
    google_project_iam_member.cloudbuild_sa_roles
  ]
}

# Time delay for IAM propagation
resource "time_sleep" "iam_propagation" {
  depends_on = [
    google_project_iam_member.storage_access,
    google_project_iam_member.cloudrun_sa_roles
  ]
  create_duration = "120s"
}

# Cloud Run Service
resource "google_cloud_run_service" "n8n_service" {
  name     = "n8n-service"
  location = "us-east1"

  template {
    spec {
      service_account_name = google_service_account.n8n_sa.email
      containers {
        image = "${google_artifact_registry_repository.n8n_repo.location}-docker.pkg.dev/${google_artifact_registry_repository.n8n_repo.project}/${google_artifact_registry_repository.n8n_repo.repository_id}/n8n:latest"
        
        env {
          name  = "N8N_DATABASE_TYPE"
          value = "sqlite"
        }
        env {
          name  = "N8N_DATABASE_SQLITE_DATABASE"
          value = "/data/n8n.sqlite"
        }
        env {
          name  = "GCS_BUCKET_NAME"
          value = google_storage_bucket.n8n_bucket.name
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
  
  depends_on = [
    time_sleep.iam_propagation,
    google_cloudbuild_trigger.n8n_image
  ]
}

# Public access
resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloud_run_service.n8n_service.location
  service  = google_cloud_run_service.n8n_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

data "google_project" "project" {}
