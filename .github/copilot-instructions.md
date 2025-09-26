# AI Coding Agent Instructions

## Project Overview

This is a **CloudFormation-based AWS solution** for deploying secure static websites with CloudFront, S3, and ACM certificates. The architecture uses nested CloudFormation stacks and supports multi-environment deployments via GitHub Actions with OIDC authentication.

## Architecture & Components

### Core Stack Structure

- **Main template**: `templates/main.yaml` - orchestrates three nested stacks
- **Custom Resource stack**: Creates S3 buckets for static content storage
- **ACM Certificate stack**: Manages SSL/TLS certificates (must be in us-east-1)
- **CloudFront stack**: Distribution with security headers and origin access control

### Key Design Patterns

- **Nested stacks**: Each component is isolated in its own template for modularity
- **Resource dependencies**: Stacks pass outputs as inputs (e.g., Certificate ARN → CloudFront)
- **Environment isolation**: Each environment gets its own CloudFormation stack
- **Security-first**: Uses OAC (Origin Access Control), security headers, and HTTPS-only

## Configuration System

### Environment Configuration

All environments are defined in `deploy-config.json`:

```json
{
  "project_name": "project-name",
  "oidc": {
    "oidc_arn": "",
    "github_org": "github-username",
    "github_repo": "repo-name"
  },
  "environments": {
    "dev": { "parameters": { "SubDomain": "dev", "CreateApex": "no" } },
    "prod": { "parameters": { "SubDomain": "www", "CreateApex": "yes" } }
  }
}
```

**Critical**: `CreateApex=yes` only for production to create apex domain alias (example.com)

### Parameter Naming Convention

- `ProjectName`: Used for resource naming and tagging (lowercase, hyphenated, 3-20 chars)
- `Environment`: dev/staging/prod - affects resource names and deployment behavior
- `DomainName`: Apex domain (example.com)
- `SubDomain`: Prefix for full domain (www → www.example.com)

## Deployment Workflows

### Script-Based Deployment

#### Main deployment script (`scripts/deploy.sh`)

```bash
./scripts/deploy.sh <action> [environment]
```

**Actions**:

- `infra` - Deploy CloudFormation infrastructure
- `content` - Sync `www/` to S3 and invalidate CloudFront cache
- `outputs` - Display stack outputs (bucket names, distribution ID, URLs)
- `validate` - Validate CloudFormation templates
- `help` - Display usage information

#### OIDC setup script (`scripts/oidc.sh`)

```bash
./scripts/oidc.sh
```

One-time GitHub OIDC setup (account-level, creates IAM role for GitHub Actions)

**Key Implementation Details**:

- Uses `jq` to parse `deploy-config.json`
- Creates template package bucket: `{project_name}-cf-templates-{account-id}-{region}`
- Stack naming: `{project_name}-{environment}` (e.g., `mysite-dev`)
- OIDC stack naming: `{project_name}-github-oidc`

### GitHub Actions Integration

- **OIDC Authentication**: No long-lived AWS keys stored in GitHub
- **Environment-specific deployments**: Triggered by workflow_dispatch or branch pushes
- **Concurrency control**: Prevents conflicting deployments to same environment
- **Dual-action support**: Separate `infra` and `content` deployments

### Content Deployment Pattern

1. **Sync**: `aws s3 sync ./www/ s3://bucket --delete` - uploads website files
2. **Invalidate**: `aws cloudfront create-invalidation --paths "/*"` - clears cache

## File Organization Conventions

### Template Structure

```
templates/
├── main.yaml           # Master template with nested stacks
├── custom-resource.yaml # S3 buckets for static content storage
├── acm-certificate.yaml # SSL certificate management
├── cloudfront-site.yaml # CDN distribution with security headers
└── github-oidc.yaml    # GitHub Actions authentication setup
```

### Resource Naming Pattern

- **Stacks**: `{ProjectName}-{Environment}` (e.g., `mysite-dev`)
- **S3 Buckets**: Auto-generated with stack-specific suffixes (`-s3bucketroot-`, `-s3bucketlogs-`)
- **IAM Roles**: `{ProjectName}-github-actions-role`

### Content Structure

- `www/` - Static website files (HTML, CSS, assets)
- `scripts/` - Deployment and helper scripts
  - `deploy.sh` - Main deployment script
  - `oidc.sh` - OIDC setup script
  - `helpers.sh` - Shared utility functions (logging, dependency checks)

## Development Workflows

### Local Development Commands

```bash
# Validate CloudFormation templates
./scripts/deploy.sh validate

# Deploy infrastructure changes
./scripts/deploy.sh infra dev

# Deploy content updates only
./scripts/deploy.sh content dev

# View stack information
./scripts/deploy.sh outputs dev

# Get help information
./scripts/deploy.sh help
```

### Making Changes

**Infrastructure changes**: Modify templates in `templates/`, then run `infra` action
**Content changes**: Update files in `www/`, then run `content` action
**Configuration changes**: Update `deploy-config.json`, may require `infra` redeploy

### Security Headers Customization

Modify `ResponseHeadersPolicy` in `templates/cloudfront-site.yaml` to adjust:

- Content-Security-Policy
- Strict-Transport-Security
- X-Frame-Options, X-Content-Type-Options, etc.

## Critical Dependencies & Constraints

- **Region lock**: Templates must deploy to `us-east-1` (ACM certificate requirement)
- **Domain prerequisites**: Must have Route 53 hosted zone in same AWS account
- **OIDC setup**: Required once per AWS account for GitHub Actions authentication
- **CLI tools**: Requires `jq`, `make`, and AWS CLI configured locally for script deployment

## GitHub Actions Architecture  

- **Composite Action**: `.github/actions/deploy/action.yaml` encapsulates deployment logic
- **Branch-based triggers**: `develop` → dev, `main/master` → staging, manual → prod
- **Concurrency control**: Uses workflow + branch + environment + action for unique group naming
- **Environment gates**: Uses GitHub environment protection rules for production deployments

## Troubleshooting Patterns

**Stack deployment failures**: Check CloudFormation events, often certificate validation issues
**Content not updating**: Verify S3 sync and CloudFront invalidation completed
**OIDC authentication errors**: Ensure GitHub secrets `AWS_ROLE_ARN` is set correctly
**Domain resolution issues**: Verify hosted zone configuration and DNS propagation
