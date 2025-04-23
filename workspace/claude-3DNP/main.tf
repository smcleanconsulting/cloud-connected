terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "artifact_registry" {
  project = var.project_id
  service = "artifactregistry.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

resource "google_project_service" "cloud_run" {
  project = var.project_id
  service = "run.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

resource "google_project_service" "iam" {
  project = var.project_id
  service = "iam.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

resource "google_project_service" "storage" {
  project = var.project_id
  service = "storage.googleapis.com"

  disable_dependent_services = true
  disable_on_destroy         = false
  
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Check if bucket exists using a null_resource and local-exec
resource "null_resource" "check_bucket_exists" {
  provisioner "local-exec" {
    command = "gsutil ls -b gs://${var.gcs_bucket_name} && echo 'EXISTS' > bucket_status.txt || echo 'NOT_EXISTS' > bucket_status.txt"
  }
}

# Read the result of the check
data "local_file" "bucket_status" {
  depends_on = [null_resource.check_bucket_exists]
  filename   = "${path.module}/bucket_status.txt"
}

locals {
  bucket_exists = data.local_file.bucket_status.content == "EXISTS\n"
}

# Create a GCS bucket for the SQLite database if it doesn't exist
resource "google_storage_bucket" "n8n_db_bucket" {
  name          = var.gcs_bucket_name
  location      = var.region
  force_destroy = false
  
  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  depends_on = [google_project_service.storage]
}

# Check if artifact repository exists using null_resource and local-exec
resource "null_resource" "check_repo_exists" {
  provisioner "local-exec" {
    command = <<-EOT
      gcloud artifacts repositories list --location=${var.region} --filter="repository_id=${var.artifact_repo}" --format="value(repository_id)" | grep -q "^${var.artifact_repo}$" && echo 'EXISTS' > repo_status.txt || echo 'NOT_EXISTS' > repo_status.txt
    EOT
  }
  depends_on = [google_project_service.artifact_registry]
}

# Read the result of the check
data "local_file" "repo_status" {
  depends_on = [null_resource.check_repo_exists]
  filename   = "${path.module}/repo_status.txt"
}

locals {
  repo_exists = data.local_file.repo_status.content == "EXISTS\n"
}

# Create Artifact Registry repository if it doesn't exist
resource "google_artifact_registry_repository" "n8n_repo" {
  location      = var.region
  repository_id = var.artifact_repo
  description   = "Docker repository for n8n workflows"
  format        = "DOCKER"

  depends_on = [google_project_service.artifact_registry]
}

# Use data source to reference existing service account
data "google_service_account" "existing_n8n_service_account" {
  account_id = "n8n-service-account"
}

# Grant GCS access to the service account
resource "google_storage_bucket_iam_member" "n8n_gcs_access" {
  bucket = var.gcs_bucket_name
  role   = "roles/storage.admin"
  member = "serviceAccount:${data.google_service_account.existing_n8n_service_account.email}"
  
  depends_on = [
    google_storage_bucket.n8n_db_bucket,
    null_resource.check_bucket_exists
  ]
}

# Local exec to build and push Docker image
resource "null_resource" "build_and_push_image" {
  triggers = {
    dockerfile_hash = filesha256("${path.module}/Dockerfile")
    startup_hash    = filesha256("${path.module}/startup.sh")
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Configure Docker for Artifact Registry
      gcloud auth configure-docker ${var.region}-docker.pkg.dev --quiet
      
      # Build the Docker image
      docker build -t ${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/${var.n8n_image_name}:${var.n8n_image_tag} .
      
      # Push to Artifact Registry
      docker push ${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/${var.n8n_image_name}:${var.n8n_image_tag}
    EOT
  }

  depends_on = [
    google_project_service.artifact_registry,
    null_resource.check_repo_exists
  ]
}

# Cloud Run service for n8n
resource "google_cloud_run_v2_service" "n8n_service" {
  name     = var.service_name
  location = var.region
  
  template {
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/${var.n8n_image_name}:${var.n8n_image_tag}"
      
      resources {
        limits = {
          memory = var.n8n_memory
          cpu    = var.n8n_cpu
        }
      }
      
      env {
        name  = "GCS_BUCKET"
        value = var.gcs_bucket_name
      }
      
      env {
        name  = "N8N_PORT"
        value = var.n8n_port
      }
      
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      
      # Add authentication to protect the n8n instance
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
        value = "changeme"  # Consider using a secret manager for production
      }
      
      ports {
        container_port = var.n8n_port
      }
    }
    
    service_account = data.google_service_account.existing_n8n_service_account.email
    
    timeout = "300s"
  }

  traffic {
    percent = 100
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
  }
  
  depends_on = [
    null_resource.build_and_push_image,
    google_project_service.cloud_run
  ]
}

# Make the Cloud Run service publicly accessible
resource "google_cloud_run_service_iam_member" "public_access" {
  location = google_cloud_run_v2_service.n8n_service.location
  service  = google_cloud_run_v2_service.n8n_service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}