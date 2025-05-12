variable "project_id" {
  description = "The Google Cloud project ID"
  type        = string
}

variable "region" {
  description = "The Google Cloud region where resources will be created"
  type        = string
  default     = "us-east1"
}

variable "billing_account_id" {
  description = "The ID of the billing account (format: XXXXXX-XXXXXX-XXXXXX)"
  type        = string
  # Validation removed to allow flexibility in format
}

variable "budget_name" {
  description = "The name of the budget"
  type        = string
  default     = "Auto-Detach Budget"
}

variable "budget_amount" {
  description = "The budget amount in USD"
  type        = string
  default     = "100"
}

variable "exclusion_list" {
  description = "Comma-separated list of projects that should never have billing detached"
  type        = string
  default     = ""
}

variable "allowed_overage_pct" {
  description = "Percentage by which the cost can exceed the budget before billing is detached"
  type        = string
  default     = "10"
}