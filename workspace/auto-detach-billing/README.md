# Automatic GCP Billing Detachment 

This project automatically detaches billing from Google Cloud Platform (GCP) projects when cost thresholds are exceeded. It uses Cloud Functions (Gen2) triggered by Pub/Sub messages sent from budget alerts.

## Problem Statement

When working with Google Cloud Platform, it's important to keep costs under control. While budget alerts notify you when spending reaches certain thresholds, they don't automatically stop charges from accumulating. This project solves that problem by automatically detaching billing from projects when they exceed their budget, effectively stopping all billable services.

## Solution Architecture

The solution uses the following components:

1. **Cloud Billing Budgets**: Set up to monitor costs and send alerts when thresholds are exceeded
2. **Pub/Sub**: Receives budget alert notifications 
3. **Cloud Functions (Gen2)**: Executes when triggered by Pub/Sub messages, detaching billing from specified projects
4. **Cloud Billing API**: Used by the Cloud Function to detach billing from projects

### Flow

1. Budget alert is triggered and sends a notification to a Pub/Sub topic
2. Pub/Sub triggers the Cloud Function
3. The Cloud Function extracts project information from the message
4. The function evaluates conditions (exclusion list, threshold amount) 
5. If conditions are met, the function detaches billing from the project

## Prerequisites

- Google Cloud Platform account
- A GCP project with billing enabled
- `gcloud` CLI installed and configured
- Required APIs enabled:
  - Cloud Functions API
  - Cloud Build API
  - Pub/Sub API
  - Cloud Billing API

## Setup Instructions

### 1. Enable Required APIs

```bash
gcloud services enable cloudfunctions.googleapis.com cloudbuild.googleapis.com pubsub.googleapis.com cloudbilling.googleapis.com
```

### 2. Create a Pub/Sub Topic

```bash
gcloud pubsub topics create billing-alerts
```

### 3. Deploy the Cloud Function

Clone this repository:

```bash
git clone https://github.com/your-username/gcp-billing-detachment.git
cd gcp-billing-detachment
```

Deploy the Cloud Function:

```bash
gcloud functions deploy detach-billing \
    --gen2 \
    --runtime=python312 \
    --region=REGION \
    --source=. \
    --entry-point=detach_billing \
    --trigger-topic=billing-alerts
```

Replace `REGION` with your desired region (e.g., `us-east1`).

### 4. Set Up Required Permissions

Get your project details:

```bash
PROJECT_ID=$(gcloud config get-value project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
```

Grant project level permissions:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/billing.projectManager"
```

Get your billing account ID:

```bash
BILLING_ACCOUNT=$(gcloud billing projects describe $PROJECT_ID --format="value(billingAccountName)")
```

Grant billing account level permissions:

```bash
gcloud billing accounts add-iam-policy-binding $BILLING_ACCOUNT \
    --member="serviceAccount:$SERVICE_ACCOUNT" \
    --role="roles/billing.admin"
```

### 5. Create a Budget with Alerts

1. Go to the [Billing section](https://console.cloud.google.com/billing) of the Google Cloud Console
2. Select your billing account
3. Click on "Budgets & alerts"
4. Click "Create Budget"
5. Set up your budget with appropriate amounts and thresholds
   - Set the budget amount (e.g., $5, $100, etc.)
   - Set threshold percentages (e.g., 50%, 80%, 100%)
6. Under "Manage notifications":
   - Check "Connect a Pub/Sub topic to this budget"
   - Select the Pub/Sub topic you created earlier (`billing-alerts`)
7. Save the budget

## Customization

### Exclusion List

You can create an exclusion list of projects that should never have their billing detached. This is useful for critical infrastructure. Set the `EXCLUSION_LIST` environment variable when deploying the function:

```bash
gcloud functions deploy detach-billing \
    --gen2 \
    --runtime=python312 \
    --region=REGION \
    --source=. \
    --entry-point=detach_billing \
    --trigger-topic=billing-alerts \
    --set-env-vars=EXCLUSION_LIST="critical-project-1,critical-project-2"
```

### Allowed Overage Percentage

By default, the function allows spending to exceed the budget by 10% before detaching billing. You can customize this with the `ALLOWED_OVERAGE_PCT` environment variable:

```bash
gcloud functions deploy detach-billing \
    --gen2 \
    --runtime=python312 \
    --region=REGION \
    --source=. \
    --entry-point=detach_billing \
    --trigger-topic=billing-alerts \
    --set-env-vars=ALLOWED_OVERAGE_PCT=5
```

## Testing

### Manual Testing

You can test the function by manually publishing a message to the Pub/Sub topic:

```bash
# Test with a cost that exceeds the budget
gcloud pubsub topics publish billing-alerts --message='{"costAmount": 6, "budgetAmount": 5, "projectId": "your-project-id"}'
```

### Verify Billing Status

Check if billing was successfully detached:

```bash
gcloud billing projects describe your-project-id
```

If billing was detached, you should see:
```
billingAccountName: ''
billingEnabled: false
```

### Reattach Billing for Testing

After testing, you can reattach billing to continue using your project:

```bash
gcloud billing projects link your-project-id --billing-account=your-billing-account-id
```

## Deploying to Production

When deploying to a production environment, consider the following:

1. **Test thoroughly in a non-critical project**: Make sure the function works as expected before deploying it to critical projects.

2. **Add critical projects to the exclusion list**: Ensure that essential projects are never accidentally detached.

3. **Set up monitoring**: Implement monitoring to be notified when the function executes.

4. **Implement a notification system**: Set up email or other notifications when billing is detached.

5. **Document the process for reattaching billing**: Make sure all team members know how to restore billing if needed.

## Troubleshooting

### Billing Not Detaching

If billing is not being detached when expected:

1. **Check the function logs**: Use `gcloud functions logs read detach-billing --gen2` to see if the function is being triggered.

2. **Verify permissions**: Make sure the service account has the correct permissions.

3. **Test with a manual Pub/Sub message**: Try publishing a message directly to the topic to bypass the budget alert.

### Function Deployment Issues

If you have issues deploying the function:

1. **Check API enablement**: Make sure all required APIs are enabled.

2. **Check for quota limits**: Ensure you have not reached any quota limits.

3. **Try a different region**: Some issues can be regional, try deploying to a different region.

## License

[MIT License](LICENSE)