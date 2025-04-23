# Specify the required provider for Google Cloud
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

# Configure the Google Cloud provider with your project and region
provider "google" {
  project = "n8n-podman-456718"
  region  = "us-east1"
}

# Enable necessary APIs for Cloud Run and Artifact Registry
resource "google_project_service" "cloudrun_api" {
  service = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "artifactregistry_api" {
  service = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

# Create a Cloud Run service to deploy the n8n application
resource "google_cloud_run_service" "n8n_service" {
  name     = "n8n-service"
  location = "us-east1"

  template {
    spec {
      containers {
        image = "us-east1-docker.pkg.dev/n8n-podman-456718/n8n-podman/n8n:latest"

        # Set environment variables for n8n
        env {
          name  = "N8N_PORT"
          value = "5678"
        }
        env {
          name  = "N8N_HOST"
          value = "0.0.0.0"
        }
        env {
          name  = "N8N_RUNNERS_ENABLED"
          value = "true"
        }
        env {
          name  = "N8N_PATH"
          value = "/"
        }
        # Allocate sufficient resources to prevent startup failures
        resources {
          limits = {
            cpu    = "1000m"  # 1 vCPU
            memory = "512Mi"  # 512 MB memory
          }
        }
        # Explicitly set the port Cloud Run should use
        ports {
          container_port = 5678
        }
      }
      # Increase the timeout for container startup to handle slow initialization
      timeout_seconds = 300
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  # Enable public access (or restrict as needed)
  autogenerate_revision_name = true

  depends_on = [
    google_project_service.cloudrun_api,
    google_project_service.artifactregistry_api
  ]
}

# Optional: Set IAM policy to make the service publicly accessible (adjust as needed)
resource "google_cloud_run_service_iam_member" "n8n_public_access" {
  service  = google_cloud_run_service.n8n_service.name
  location = google_cloud_run_service.n8n_service.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}