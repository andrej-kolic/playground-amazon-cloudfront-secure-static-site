# GitHub OIDC Setup for AWS CloudFormation Static Site

This guide explains how to set up OpenID Connect (OIDC) authentication for GitHub Actions to deploy AWS resources without storing long-lived credentials.

## Prerequisites

- AWS CLI configured with admin permissions for initial setup
- GitHub repository with Actions enabled
- Admin access to the AWS account

## Setup Methods

### Method 1: GitHub Actions Workflow (Recommended)

1. **Go to your GitHub repository**
2. **Navigate to Actions tab**
3. **Find "Setup GitHub OIDC Provider" workflow**
4. **Click "Run workflow"**
5. **Check the confirmation box** (acknowledges this is a one-time setup)
6. **Run the workflow**
7. **Copy the Role ARN** from the workflow output
8. **Add it as repository secret** named `AWS_ROLE_ARN`

> **Important**: For the initial OIDC setup, you need AWS access keys with admin permissions configured as repository secrets (`AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`). After setup is complete, you can remove these secrets as they're no longer needed.

### Method 2: Local Script

Alternatively, run the setup locally:

```bash
# Deploy OIDC infrastructure (environment parameter is optional for OIDC)
./scripts/deploy.sh oidc
```

This will:
- Create a GitHub OIDC Provider (if one doesn't exist)
- Create an IAM Role with necessary permissions
- Output the Role ARN and setup instructions

## What the Setup Creates

The OIDC setup is a **one-time, account-level operation** that creates:

1. **GitHub OIDC Identity Provider** (if not already present)
   - Allows GitHub Actions to authenticate with AWS
   - Account-wide resource (one per AWS account)

2. **IAM Role for GitHub Actions**
   - Repository-specific role for secure access
   - Configured with necessary CloudFormation permissions
   - Scoped to your specific GitHub repository

## Configuration

The OIDC setup uses configuration from `deploy-config.json`:

```json
{
  "_shared": {
    "name": "your-project-name",
    "region": "us-east-1",
    "github": {
      "org": "your-github-username", 
      "repo": "your-repo-name"
    }
  }
}
```

## Deployment Workflows

After OIDC setup, use the **"Deploy Static Website"** workflow with these actions:

- **infra**: Deploy CloudFormation infrastructure
- **content**: Deploy static content to S3

> **Note**: The `oidc` action has been moved to its own dedicated workflow to avoid confusion with environment-specific deployments.

## Security Features

- **Short-lived tokens**: No long-lived AWS credentials stored in GitHub
- **Repository-scoped**: Tokens only work for the specified repository
- **Branch-specific**: Can be configured for specific branches/environments
- **Minimal permissions**: IAM role follows principle of least privilege

## Troubleshooting

### OIDC Provider Already Exists

If an OIDC provider already exists, the script automatically detects and uses it. This is normal and expected.

### Permission Issues

Ensure the IAM role has the necessary permissions for:
- CloudFormation operations
- S3 bucket management
- CloudFront operations
- ACM certificate management

### Token Validation Errors

Check that:
- The repository name matches exactly in the configuration
- The GitHub organization/username is correct
- The workflow has the correct permissions set

## Manual Cleanup

To remove OIDC resources:

```bash
aws cloudformation delete-stack --stack-name your-project-name-github-oidc --region us-east-1
```

## References

- [AWS IAM OIDC Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS Actions Configure Credentials](https://github.com/aws-actions/configure-aws-credentials)
