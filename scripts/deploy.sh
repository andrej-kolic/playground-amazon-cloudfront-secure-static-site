#!/bin/bash

SCRIPTS_DIR=$(dirname "$0")
ROOT_DIR=$(dirname "$0")/..

source "$SCRIPTS_DIR/helpers.sh"

# Disable automatic pagination for AWS CLI commands
export AWS_PAGER=""

# Default values
ENVIRONMENT=${1:-dev}
ACTION=${2:-content}
CONFIG_FILE="${ROOT_DIR}/deploy-config.json"


get_config() {
    print_info "Loading configuration for environment: $ENVIRONMENT from $CONFIG_FILE"

    # Shared config
    if ! jq -e "._shared" "$CONFIG_FILE" > /dev/null 2>&1; then
        print_error "Shared configuration not found in ${CONFIG_FILE}"
        exit 1
    fi

    NAME=$(jq -r "._shared.name" "$CONFIG_FILE")
    REGION=$(jq -r "._shared.region" "$CONFIG_FILE")
    GITHUB_ORG=$(jq -r "._shared.github.org" "$CONFIG_FILE")
    GITHUB_REPO=$(jq -r "._shared.github.repo" "$CONFIG_FILE")
    PACKAGE_BUCKET="${NAME}-cf-templates-${REGION}"
    STACK_NAME="${NAME}-${ENVIRONMENT}"
    OIDC_STACK_NAME="${NAME}-github-oidc"

    # Environment-specific config
    if ! jq -e ".${ENVIRONMENT}" "$CONFIG_FILE" > /dev/null 2>&1; then
        print_error "Configuration for environment '${ENVIRONMENT}' not found in ${CONFIG_FILE}"
        exit 1
    fi

    PARAMETERS=""
    for param in $(jq -r ".${ENVIRONMENT}.parameters | keys[]" "$CONFIG_FILE"); do
        value=$(jq -r ".${ENVIRONMENT}.parameters.${param}" "$CONFIG_FILE")
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
    print_info "=== GitHub OIDC Setup for AWS ==="
    print_info ""
    print_info "Deploying GitHub OIDC Provider and Role..."
    
    # Validate GitHub configuration
    if [[ "$GITHUB_ORG" == "null" ]] || [[ "$GITHUB_REPO" == "null" ]] || [[ -z "$GITHUB_ORG" ]] || [[ -z "$GITHUB_REPO" ]]; then
        print_error "GitHub organization and repository must be configured in deploy-config.json"
        print_error "Expected format:"
        print_error '{
  "_shared": {
    "github": {
      "org": "your-github-org",
      "repo": "your-repo-name"
    }
  }
}'
        exit 1
    fi
    
    print_info "Configuration:"
    print_info "  GitHub Org: $GITHUB_ORG"
    print_info "  GitHub Repo: $GITHUB_REPO"
    print_info "  AWS Region: $REGION"
    print_info "  Stack Name: $OIDC_STACK_NAME"
    print_info ""
    
    # Check AWS credentials
    print_info "Checking AWS credentials..."
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_info "AWS Account ID: $ACCOUNT_ID"
    print_info ""
    
    # Check if OIDC provider already exists
    print_info "Checking for existing OIDC providers..."
    EXISTING_OIDC_ARN=""
    if aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?ends_with(Arn, `token.actions.githubusercontent.com`)].Arn' --output text | grep -q "arn:aws:iam"; then
        EXISTING_OIDC_ARN=$(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?ends_with(Arn, `token.actions.githubusercontent.com`)].Arn' --output text)
        print_info "Found existing OIDC provider: $EXISTING_OIDC_ARN"
    else
        print_info "No existing OIDC provider found. Will create a new one."
    fi
    print_info ""
    
    # Deploy OIDC stack
    print_info "Deploying OIDC CloudFormation stack..."
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
    
    OIDC_PROVIDER_ARN=$(aws cloudformation describe-stacks \
        --stack-name "$OIDC_STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`OIDCProviderArn`].OutputValue' \
        --output text 2>/dev/null)
    
    print_info ""
    print_success "=== OIDC Setup Complete! ==="
    print_info ""
    print_info "GitHub Actions Role ARN:"
    print_info "  $GITHUB_ROLE_ARN"
    print_info ""
    print_info "OIDC Provider ARN:"
    print_info "  $OIDC_PROVIDER_ARN"
    print_info ""
    print_info "=== Next Steps ==="
    print_info ""
    print_info "1. Add the following secret to your GitHub repository:"
    print_info "   Name: AWS_ROLE_ARN"
    print_info "   Value: $GITHUB_ROLE_ARN"
    print_info ""
    print_info "2. Go to: https://github.com/$GITHUB_ORG/$GITHUB_REPO/settings/secrets/actions"
    print_info ""
    print_info "3. Click 'New repository secret' and add the secret"
    print_info ""
    print_info "4. Your GitHub Actions workflows can now use OIDC authentication!"
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
            print_success "OIDC deployment completed!"
            ;;
        "infra")
            check_dependencies
            get_config
            package_static
            package_artifacts
            deploy_infrastructure
            print_success "Infrastructure deployment completed!"
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
            print_info "Available actions: test, oidc, infra, content, outputs"
            exit 1
            ;;
    esac    
}

main
