terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.10.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.10.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4.0"
    }
  }
  required_version = ">= 1.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
  # Add user_project_override to handle billing budget creation
  user_project_override = true
  billing_project       = var.project_id
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  # Add user_project_override to handle billing budget creation
  user_project_override = true
  billing_project       = var.project_id
}

# Enable required APIs
resource "google_project_service" "required_apis" {
  for_each = toset([
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "pubsub.googleapis.com",
    "cloudbilling.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "eventarc.googleapis.com",
    "billingbudgets.googleapis.com"
  ])

  service            = each.key
  disable_on_destroy = false
  timeouts {
    create = "30m"
    update = "40m"
  }
}

# Get project details
data "google_project" "project" {
  project_id = var.project_id
  depends_on = [google_project_service.required_apis["cloudresourcemanager.googleapis.com"]]
}

# Create Pub/Sub topic for budget alerts
resource "google_pubsub_topic" "budget_alerts" {
  name       = "billing-alerts"
  project    = var.project_id
  depends_on = [google_project_service.required_apis["pubsub.googleapis.com"]]
}

# Create a Cloud Storage bucket for function code
resource "google_storage_bucket" "function_bucket" {
  name                        = "${var.project_id}-function-code"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true
  depends_on                  = [google_project_service.required_apis["artifactregistry.googleapis.com"]]
}

# Create a ZIP archive of the function code
data "archive_file" "function_zip" {
  type        = "zip"
  source_dir  = "${path.module}/function"
  output_path = "${path.module}/function.zip"
}

# Upload the function code to the bucket
resource "google_storage_bucket_object" "function_code" {
  name   = "function-${data.archive_file.function_zip.output_md5}.zip"
  bucket = google_storage_bucket.function_bucket.name
  source = data.archive_file.function_zip.output_path
}

# Deploy the Cloud Function
resource "google_cloudfunctions2_function" "billing_detachment_function" {
  name        = "detach-billing"
  location    = var.region
  description = "Automatically detaches billing when budget thresholds are exceeded"
  
  build_config {
    runtime     = "python312"
    entry_point = "detach_billing"
    source {
      storage_source {
        bucket = google_storage_bucket.function_bucket.name
        object = google_storage_bucket_object.function_code.name
      }
    }
  }

  service_config {
    max_instance_count    = 1
    min_instance_count    = 0
    available_memory      = "256Mi"
    timeout_seconds       = 60
    
    environment_variables = {
      EXCLUSION_LIST      = var.exclusion_list
      ALLOWED_OVERAGE_PCT = var.allowed_overage_pct
    }
    
    ingress_settings      = "ALLOW_ALL"
    all_traffic_on_latest_revision = true
  }

  event_trigger {
    trigger_region = var.region
    event_type     = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic   = google_pubsub_topic.budget_alerts.id
    retry_policy   = "RETRY_POLICY_RETRY"
  }

  depends_on = [
    google_project_service.required_apis["cloudfunctions.googleapis.com"],
    google_project_service.required_apis["run.googleapis.com"],
    google_project_service.required_apis["eventarc.googleapis.com"],
    google_pubsub_topic.budget_alerts
  ]
}

# Grant the Cloud Functions service account the project-level permission
resource "google_project_iam_member" "project_billing_manager" {
  project = var.project_id
  role    = "roles/billing.projectManager"
  member  = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"

  depends_on = [
    data.google_project.project,
    google_cloudfunctions2_function.billing_detachment_function
  ]
}

# Grant the Cloud Functions service account the billing account-level permission
resource "google_billing_account_iam_member" "billing_admin" {
  billing_account_id = var.billing_account_id
  role               = "roles/billing.admin"
  member             = "serviceAccount:${data.google_project.project.number}-compute@developer.gserviceaccount.com"

  depends_on = [
    data.google_project.project,
    google_cloudfunctions2_function.billing_detachment_function
  ]
}

# Create a budget with alerts for the project
resource "google_billing_budget" "budget" {
  billing_account = var.billing_account_id
  display_name    = var.budget_name
  
  budget_filter {
    projects = ["projects/${data.google_project.project.number}"]
  }
  
  amount {
    specified_amount {
      currency_code = "USD"
      units         = var.budget_amount
    }
  }

  threshold_rules {
    threshold_percent = 0.5  # 50% alert
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.8  # 80% alert
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0  # 100% alert
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    pubsub_topic = google_pubsub_topic.budget_alerts.id
  }

  depends_on = [
    google_pubsub_topic.budget_alerts,
    google_project_service.required_apis["cloudbilling.googleapis.com"],
    google_project_service.required_apis["billingbudgets.googleapis.com"]
  ]
}