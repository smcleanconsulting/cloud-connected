# Cloud Provider Authorization Guide

This guide explains how to authorize AWS CLI and Google Cloud SDK in your cloud workstation environment.

## AWS CLI Authorization

### Method 1: Using AWS Configure (Interactive)

1. Run the AWS configure command:
   ```bash
   aws configure
   ```

2. Enter the following information when prompted:
   - AWS Access Key ID
   - AWS Secret Access Key
   - Default region name (e.g., us-west-2)
   - Default output format (json, text, or yaml)

3. This creates configuration files in the `~/.aws` directory.

### Method 2: Manual Configuration

1. Create the credentials file:
   ```bash
   mkdir -p ~/.aws
   cat > ~/.aws/credentials << EOF
   [default]
   aws_access_key_id = YOUR_ACCESS_KEY
   aws_secret_access_key = YOUR_SECRET_KEY
   EOF
   ```

2. Create the config file:
   ```bash
   cat > ~/.aws/config << EOF
   [default]
   region = us-west-2
   output = json
   EOF
   ```

### Method 3: Environment Variables

```bash
export AWS_ACCESS_KEY_ID=YOUR_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=YOUR_SECRET_KEY
export AWS_DEFAULT_REGION=us-west-2
```

### Verify AWS Configuration

```bash
aws sts get-caller-identity
```

## Google Cloud SDK Authorization

### Method 1: Interactive Login

1. Run the login command:
   ```bash
   gcloud auth login
   ```

2. Follow the URL provided and authenticate in your browser.

3. Set your default project:
   ```bash
   gcloud config set project YOUR_PROJECT_ID
   ```

### Method 2: Service Account Key

1. Copy your service account key to the container.

2. Authenticate using the key:
   ```bash
   gcloud auth activate-service-account --key-file=/path/to/key.json
   ```

3. Set your default project:
   ```bash
   gcloud config set project YOUR_PROJECT_ID
   ```

### Verify Google Cloud Configuration

```bash
gcloud auth list
gcloud config list
```

## Working with Multiple Profiles

### AWS Multiple Profiles

Add profiles to `~/.aws/credentials`:
```
[default]
aws_access_key_id = DEFAULT_ACCESS_KEY
aws_secret_access_key = DEFAULT_SECRET_KEY

[production]
aws_access_key_id = PROD_ACCESS_KEY
aws_secret_access_key = PROD_SECRET_KEY
```

Use a specific profile:
```bash
aws s3 ls --profile production
```

### Google Cloud Multiple Configurations

Create and switch between configurations:
```bash
gcloud config configurations create prod
gcloud config set account user@example.com
gcloud config set project prod-project-id
```

List and switch configurations:
```bash
gcloud config configurations list
gcloud config configurations activate prod
```

## Security Best Practices

1. Use IAM roles/service accounts with minimal permissions
2. Regularly rotate access keys
3. Never commit credentials to version control
4. Consider using AWS IAM Identity Center (SSO) for AWS access
5. For production environments, use temporary credentials or instance profiles