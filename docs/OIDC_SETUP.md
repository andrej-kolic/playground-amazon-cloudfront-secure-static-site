# GitHub OIDC Setup for AWS CloudFormation Static Site

This guide explains how to set up OpenID Connect (OIDC) authentication for GitHub Actions to deploy AWS resources without storing long-lived credentials.

## Prerequisites

- AWS CLI configured with appropriate permissions
- GitHub repository with Actions enabled
- Admin access to the AWS account

## Setup Steps

### 1. Deploy OIDC Resources

First, deploy the GitHub OIDC Provider and IAM Role:

```bash
# Deploy OIDC infrastructure
./scripts/deploy.sh dev oidc
```

This will:
- Validate your GitHub configuration
- Check AWS credentials and show account info  
- Create a GitHub OIDC Provider (if one doesn't exist)
- Create an IAM Role with necessary permissions
- Output the Role ARN and detailed setup instructions

### 2. Configure GitHub Repository Secrets

1. Go to your GitHub repository
2. Navigate to **Settings** > **Secrets and variables** > **Actions**
3. Add a new repository secret:
   - **Name**: `AWS_ROLE_ARN`
   - **Value**: The Role ARN output from the previous step

### 3. GitHub Actions Workflow

The workflow is already configured to use OIDC. Each job includes:

```yaml
permissions:
  id-token: write  # Required for OIDC
  contents: read   # Required for checkout

steps:
  - name: Configure AWS credentials using OIDC
    uses: aws-actions/configure-aws-credentials@v4
    with:
      role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
      role-session-name: github-actions-{environment}
      aws-region: us-east-1
```

### 4. Deployment Options

You can now deploy using GitHub Actions with three actions:

- **oidc**: Deploy/update OIDC resources
- **infra**: Deploy CloudFormation infrastructure
- **content**: Deploy static content to S3

## Configuration

The OIDC setup uses configuration from `deploy-config.json`:

```json
{
  "_shared": {
    "name": "aw1",
    "region": "us-east-1",
    "github": {
      "org": "andrej-kolic",
      "repo": "playground-amazon-cloudfront-secure-static-site"
    }
  }
}
```

## Security Features

- **Short-lived tokens**: No long-lived AWS credentials stored in GitHub
- **Repository-scoped**: Tokens only work for the specified repository
- **Branch-specific**: Can be configured for specific branches/environments
- **Minimal permissions**: IAM role follows principle of least privilege

## Troubleshooting

### OIDC Provider Already Exists Error

If you get an error about the OIDC provider already existing, the script will automatically detect and use the existing provider.

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
aws cloudformation delete-stack --stack-name aw1-github-oidc --region us-east-1
```

## References

- [AWS IAM OIDC Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html)
- [GitHub Actions OIDC](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- [AWS Actions Configure Credentials](https://github.com/aws-actions/configure-aws-credentials)
