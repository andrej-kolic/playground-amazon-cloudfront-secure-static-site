#!/bin/bash

# Deploy script for AWS CloudFormation Static Site
# Usage: ./deploy.sh <action> [environment]
# Arguments:
#   action      - Deployment action: test, oidc, infra, content, outputs
#   environment - Target environment: dev, staging, prod (optional for 'oidc' action)
#
# Special Notes:
#   - The 'oidc' action is a one-time setup that creates GitHub OIDC provider and IAM role
#   - OIDC setup is account-level and doesn't require environment-specific configuration
#   - For OIDC setup, the environment parameter is optional and defaults to 'shared'

SCRIPTS_DIR=$(dirname "$0")
ROOT_DIR=$(dirname "$0")/..

source "$SCRIPTS_DIR/helpers.sh"

# Disable automatic pagination for AWS CLI commands
export AWS_PAGER=""

# Default values
ACTION=${1:-content}
ENVIRONMENT=${2:-dev}
CONFIG_FILE="${ROOT_DIR}/deploy-config.json"


get_config() {
    print_info "Loading configuration for environment: $ENVIRONMENT from $CONFIG_FILE"

    NAME=$(jq -r ".name" "$CONFIG_FILE")
    REGION=$(jq -r ".region" "$CONFIG_FILE")
    GITHUB_ORG=$(jq -r ".github.org" "$CONFIG_FILE")
    GITHUB_REPO=$(jq -r ".github.repo" "$CONFIG_FILE")

    PACKAGE_BUCKET="${NAME}-cf-templates-${REGION}"
    STACK_NAME="${NAME}-${ENVIRONMENT}"
    OIDC_STACK_NAME="${NAME}-github-oidc"

    # Environment-specific config
    if ! jq -e ".environments.${ENVIRONMENT}" "$CONFIG_FILE" > /dev/null 2>&1; then
        print_error "Configuration for environment '${ENVIRONMENT}' not found in .environments of ${CONFIG_FILE}"
        exit 1
    fi

    PARAMETERS=""
    for param in $(jq -r ".environments.${ENVIRONMENT}.parameters | keys[]" "$CONFIG_FILE"); do
        value=$(jq -r ".environments.${ENVIRONMENT}.parameters.${param}" "$CONFIG_FILE")
        PARAMETERS="${PARAMETERS} ${param}=${value}"
    done

    # print variables
    print_debug "Environment: $ENVIRONMENT"
    print_debug "Name: $NAME"
    print_debug "Package Bucket: $PACKAGE_BUCKET"
    print_debug "Stack Name: $STACK_NAME"
    print_debug "OIDC Stack Name: $OIDC_STACK_NAME"
    print_debug "GitHub Org: $GITHUB_ORG"
    print_debug "GitHub Repo: $GITHUB_REPO"
    print_debug "Region: $REGION"
    print_debug "Parameters: $PARAMETERS"
}


package_static() {
    print_info "Packaging static site content..."
    make -C "$ROOT_DIR" package-static
}

package_artifacts() {
    print_info "Packaging artifacts..."
    # Create the package bucket
    aws s3 mb s3://$PACKAGE_BUCKET --region $REGION

    # Package the solution’s artifacts as a CloudFormation template
    if ! aws cloudformation package \
        --region $REGION \
        --template-file ${ROOT_DIR}/templates/main.yaml \
        --s3-bucket $PACKAGE_BUCKET \
        --output-template-file ${ROOT_DIR}/packaged.template
    then
        print_error "Failed to package artifacts"
        exit 1
    fi
}


deploy_oidc() {
    print_info "⚠️  OIDC setup is a one-time, account-level operation."
    print_info "Deploying GitHub OIDC Provider and Role..."
    
    # Check if OIDC provider already exists
    print_debug "Checking for existing OIDC providers..."
    EXISTING_OIDC_ARN=""
    if aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?ends_with(Arn, `token.actions.githubusercontent.com`)].Arn' --output text | grep -q "arn:aws:iam"; then
        EXISTING_OIDC_ARN=$(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?ends_with(Arn, `token.actions.githubusercontent.com`)].Arn' --output text)
        print_debug "Found existing OIDC provider: $EXISTING_OIDC_ARN"
    else
        print_debug "No existing OIDC provider found. Will create a new one."
    fi
    
    # Deploy OIDC stack
    print_debug "Deploying OIDC CloudFormation stack..."
    if ! aws cloudformation deploy \
        --region $REGION \
        --stack-name $OIDC_STACK_NAME \
        --template-file ${ROOT_DIR}/templates/github-oidc.yaml \
        --capabilities CAPABILITY_NAMED_IAM \
        --parameter-overrides \
            GitHubOrg=$GITHUB_ORG \
            GitHubRepo=$GITHUB_REPO \
            Environment=$ENVIRONMENT \
            OIDCProviderArn="$EXISTING_OIDC_ARN" \
        --tags Solution=ACFS3 Environment=$ENVIRONMENT Component=OIDC
    then
        print_error "Failed to deploy OIDC infrastructure"
        exit 1
    fi
    
    # Get the role ARN for output
    GITHUB_ROLE_ARN=$(aws cloudformation describe-stacks \
        --stack-name "$OIDC_STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`GitHubActionsRoleArn`].OutputValue' \
        --output text 2>/dev/null)
    
    print_success "OIDC deployment completed!"
    print_info "Add the following secret to your GitHub repository:"
    print_info "   Name: AWS_ROLE_ARN"
    print_info "   Value: $GITHUB_ROLE_ARN"
    print_info "   Remove the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY secrets (they're no longer needed)"
}


deploy_infrastructure() {
    print_info "Deploying infrastructure..."
    if ! aws cloudformation deploy \
        --region $REGION \
        --stack-name $STACK_NAME \
        --template-file ${ROOT_DIR}/packaged.template \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --parameter-overrides $PARAMETERS \
        --tags Solution=ACFS3 Environment=$ENVIRONMENT
    then
        print_error "Failed to deploy infrastructure"
        exit 1
    fi
    print_success "Infrastructure deployment completed!"
}


get_stack_outputs() {
    print_info "Retrieving stack outputs..."

    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &>/dev/null; then
        print_error "Failed to retrieve stack information"
        exit 1
    fi

    BUCKET_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`S3BucketRootName`].OutputValue' \
        --output text 2>/dev/null)

    DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CFDistributionId`].OutputValue' \
        --output text 2>/dev/null)

    WEBSITE_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDomainName`].OutputValue' \
        --output text 2>/dev/null)

    if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" = "None" ]; then
        print_warning "Could not retrieve bucket name from stack outputs"
    else
        print_info "Bucket Name: $BUCKET_NAME"
    fi

    if [ -z "$DISTRIBUTION_ID" ] || [ "$DISTRIBUTION_ID" = "None" ]; then
        print_warning "Could not retrieve distribution ID from stack outputs"
    else
        print_info "Distribution ID: $DISTRIBUTION_ID"
    fi

    if [ -z "$WEBSITE_URL" ] || [ "$WEBSITE_URL" = "None" ]; then
        print_warning "Could not retrieve website URL from stack outputs"
    else
        print_info "Website URL: https://$WEBSITE_URL"
    fi
}


sync_site_content() {
    print_info "Syncing site content to S3..."

    # Replace this with your actual site build/output directory
    SITE_DIR="./www"

    # Get the S3 bucket name from CloudFormation outputs
    BUCKET_NAME=$(aws cloudformation describe-stacks \
        --region $REGION \
        --stack-name $STACK_NAME \
        --query "Stacks[0].Outputs[?OutputKey=='S3BucketRoot'].OutputValue" \
        --output text)

    if [ -z "$BUCKET_NAME" ]; then
        print_error "Could not retrieve S3 bucket name from stack outputs."
        exit 1
    fi

    print_info "BUCKET_NAME: $BUCKET_NAME"

    aws s3 sync "$SITE_DIR" "s3://$BUCKET_NAME" --delete

    print_success "Site content synced to s3://$BUCKET_NAME"
}


invalidate_cloudfront_cache() {
    print_info "Invalidating CloudFront cache..."

    # Get the CloudFront Distribution ID from CloudFormation outputs
    local DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
        --region $REGION \
        --stack-name $STACK_NAME \
        --query "Stacks[0].Outputs[?OutputKey=='CFDistributionId'].OutputValue" \
        --output text)

    if [ -z "$DISTRIBUTION_ID" ]; then
        print_error "Could not retrieve CloudFront Distribution ID from stack outputs."
        exit 1
    fi

    print_info "DISTRIBUTION_ID: $DISTRIBUTION_ID"

    # Invalidate all objects (you can change the path as needed)
    aws cloudfront create-invalidation \
        --distribution-id "$DISTRIBUTION_ID" \
        --paths "/*"

    print_success "CloudFront cache invalidation requested."
}


main() {
    # Check AWS credentials
    print_info "Checking AWS credentials..."
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    if [ -z "$ACCOUNT_ID" ]; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    print_debug "AWS Account ID: $ACCOUNT_ID"

    # Execute action
    case $ACTION in
        "test")
            check_dependencies
            get_config
            print_success "Test action completed successfully."
            ;;
        "oidc")
            check_dependencies
            get_config
            deploy_oidc
            ;;
        "infra")
            check_dependencies
            get_config
            package_static
            package_artifacts
            deploy_infrastructure
            ;;
        "content")
            check_dependencies
            get_config
            sync_site_content
            invalidate_cloudfront_cache
            print_success "Content deployment completed!"
            ;;
        "outputs")
            check_dependencies
            get_config
            get_stack_outputs
            ;;
        *)
            print_error "Unknown action: $ACTION"
            print_info "Usage: $0 <action> [environment]"
            print_info "Available actions:"
            print_info "  test     - Test configuration and dependencies"
            print_info "  oidc     - Setup GitHub OIDC provider (one-time, account-level)"
            print_info "  infra    - Deploy infrastructure"
            print_info "  content  - Deploy website content"
            print_info "  outputs  - Display stack outputs"
            print_info "Available environments: dev, staging, prod"
            exit 1
            ;;
    esac    
}

main
