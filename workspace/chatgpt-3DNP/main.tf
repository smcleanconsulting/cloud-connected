provider "google" {
  project = "n8n-podman-456718"
  region  = "us-east1"
}

# Enable required APIs
resource "google_project_service" "required" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "storage.googleapis.com",
    "cloudbuild.googleapis.com"
  ])
  service = each.value
}

# Artifact Registry for Docker images
resource "google_artifact_registry_repository" "n8n_repo" {
  location      = "us-east1"
  repository_id = "n8n-podman"
  format        = "DOCKER"
}

# GCS bucket for future use (not yet used in Cloud Run)
resource "google_storage_bucket" "sqlite_bucket" {
  name          = "n8n-sqlite-storage"
  location      = "US"
  force_destroy = true
}

# Cloud Run Service Account
resource "google_service_account" "n8n_sa" {
  account_id   = "n8n-cloud-run"
  display_name = "n8n Cloud Run SA"
}

# IAM binding for access to GCS
resource "google_project_iam_member" "sa_storage_access" {
  project = "n8n-podman-456718"
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.n8n_sa.email}"
}

# Deploy to Cloud Run (without persistent SQLite)
resource "google_cloud_run_service" "n8n" {
  name     = "n8n"
  location = "us-east1"

  template {
    spec {
      containers {
        image = "us-east1-docker.pkg.dev/n8n-podman-456718/n8n-podman/n8n:latest"

        env {
          name  = "N8N_BASIC_AUTH_ACTIVE"
          value = "true"
        }

        env {
          name  = "N8N_BASIC_AUTH_USER"
          value = "admin"
        }

        env {
          name  = "N8N_BASIC_AUTH_PASSWORD"
          value = "supersecurepassword"
        }

        env {
          name  = "DB_SQLITE_DATABASE"
          value = "/home/node/.n8n/database.sqlite"
        }
      }

      service_account_name = google_service_account.n8n_sa.email
    }
  }

  autogenerate_revision_name = true

  traffic {
    percent         = 100
    latest_revision = true
  }
}
