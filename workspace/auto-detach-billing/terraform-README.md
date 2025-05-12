# GCP Billing Detachment - Terraform Configuration

This folder contains Terraform configuration to automatically set up the GCP billing detachment solution. It creates and configures all the necessary resources, including:

- Required API enablement
- Pub/Sub topic for budget alerts
- Cloud Functions Gen2 deployment
- IAM permissions at project and billing account levels
- Budget alerts configuration

## Prerequisites

- Terraform 1.0 or later
- Google Cloud SDK installed and configured
- Appropriate permissions to:
  - Create resources in the target project
  - Manage IAM permissions for the project
  - Manage IAM permissions for the billing account

## Structure

The Terraform configuration consists of the following files:

- `main.tf` - Main Terraform configuration file
- `variables.tf` - Variable definitions
- `outputs.tf` - Output definitions
- `terraform.tfvars` - Variable values (you'll need to create this from the example)
- `function/` - Directory containing the Cloud Function code

## Setup

1. Clone this repository:

```bash
git clone https://github.com/your-username/gcp-billing-detachment.git
cd gcp-billing-detachment/terraform
```

2. Create a `terraform.tfvars` file with your specific values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

3. Edit the `terraform.tfvars` file with your specific values:

```
project_id         = "your-project-id"
region             = "us-east1"
billing_account_id = "01ABCD-123456-789012"
budget_name        = "Auto-Detach Budget"
budget_amount      = "100"  # $100 USD
exclusion_list     = "critical-project-1,critical-project-2"
allowed_overage_pct = "10"  # 10%
```

## Usage

1. Initialize Terraform:

```bash
terraform init
```

2. Preview the changes:

```bash
terraform plan
```

3. Apply the changes:

```bash
terraform apply
```

4. To destroy the resources when no longer needed:

```bash
terraform destroy
```

## Customization

### Modify Budget Amount

To change the budget amount, update the `budget_amount` variable:

```hcl
# In terraform.tfvars
budget_amount = "500"  # $500 USD
```

### Add Projects to Exclusion List

To add projects to the exclusion list (projects that should never have billing detached), update the `exclusion_list` variable:

```hcl
# In terraform.tfvars
exclusion_list = "critical-project-1,critical-project-2,another-important-project"
```

### Change Allowed Overage Percentage

To change the percentage by which costs can exceed the budget before billing is detached, update the `allowed_overage_pct` variable:

```hcl
# In terraform.tfvars
allowed_overage_pct = "5"  # 5%
```

## Outputs

After successfully applying the Terraform configuration, you'll see the following outputs:

- `function_url` - The URL of the deployed Cloud Function
- `pubsub_topic` - The Pub/Sub topic for budget alerts
- `budget_name` - The name of the created budget
- `function_service_account` - The service account used by the Cloud Function

## Testing

To test the function, you can publish a message to the Pub/Sub topic:

```bash
gcloud pubsub topics publish billing-alerts --message='{"costAmount": 110, "budgetAmount": 100, "projectId": "your-project-id"}'
```

## Notes

- The budget is configured with alerts at 50%, 80%, and 100% thresholds, sending notifications to the Pub/Sub topic.
- The Cloud Function is configured with minimum 0 and maximum 1 instances to optimize costs.
- The function will automatically detach billing when the cost exceeds the budget by the specified overage percentage.
- Projects listed in the exclusion list will never have their billing detached.