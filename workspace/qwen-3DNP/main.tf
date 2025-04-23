provider "google" {
  project = "n8n-podman-456718"
  region  = "us-east1"
}

resource "google_storage_bucket" "n8n_database_bucket" {
  name     = "n8n-database-bucket"
  location = "US-EAST1"
}

resource "google_secret_manager_secret" "n8n_secret" {
  secret_id = "n8n-secret"
  replication {
    
  }
}

resource "google_secret_manager_secret_version" "n8n_secret_version" {
  secret     = google_secret_manager_secret.n8n_secret.name
  secret_data = base64encode("")
}

resource "google_service_account" "n8n_sa" {
  account_id   = "n8n-service-account"
  display_name = "N8N Service Account"
}

resource "google_service_account_iam_policy" "n8n_sa_policy" {
  service_account_id = google_service_account.n8n_sa.email

  policy_data = jsonencode({
    bindings = [
      {
        role = "roles/storage.objectAdmin"
        members = [
          "serviceAccount:${google_service_account.n8n_sa.email}"
        ]
      },
      {
        role = "roles/run.invoker"
        members = [
          "allUsers"
        ]
      }
    ]
  })
}

resource "google_cloud_run_service" "n8n" {
  name     = "n8n-service"
  location = "us-east1"

  template {
    spec {
      containers {
        image = "us-east1-docker.pkg.dev/n8n-podman-456718/n8n-podman/n8n:latest"

        ports {
          container_port = 5678
        }

        volume_mounts {
          name       = "n8n-data"
          mount_path = "/home/node/.n8n"
        }

        env {
          name  = "WEBHOOK_URL"
          value = "https://n8n-service-$${PROJECT_ID}-$${REGION}.a.run.app/webhook"
        }

        env {
          name  = "N8N_BASIC_AUTH_ACTIVE"
          value = "true"
        }

        env {
          name  = "N8N_BASIC_AUTH_USER"
          value = "YOUR_USERNAME"
        }

        env {
          name  = "N8N_BASIC_AUTH_PASSWORD"
          value = "YOUR_PASSWORD"
        }

        env {
          name  = "GOOGLE_APPLICATION_CREDENTIALS"
          value = "/var/run/secrets/cloud.google.com/serviceaccount/key.json"
        }

        env {
          name  = "GOOGLE_CLOUD_PROJECT"
          value = "n8n-podman-456718"
        }

        env {
          name  = "GCS_BUCKET_NAME"
          value = google_storage_bucket.n8n_database_bucket.name
        }
      }

      volumes {
        name       = "n8n-data"
        empty_dir  {}
      }

      service_account_name = google_service_account.n8n_sa.email
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }
}