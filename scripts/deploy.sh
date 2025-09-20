#!/bin/bash

# Deploy script for AWS CloudFormation Static Site
# Usage: ./deploy.sh <action> [environment]

SCRIPTS_DIR=$(dirname "$0")
ROOT_DIR=$(dirname "$0")/..

source "$SCRIPTS_DIR/helpers.sh"

# Disable automatic pagination for AWS CLI commands
export AWS_PAGER=""

# Default values
ACTION=${1:-content}
ENVIRONMENT=${2:-dev}
CONFIG_FILE="${ROOT_DIR}/deploy-config.json"

get_aws_account_id() {
    print_info "Checking AWS credentials..."
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2> /dev/null)
    if [ -z "$ACCOUNT_ID" ]; then
        print_error "AWS credentials not configured. Please run 'aws configure' first."
        exit 1
    fi
    print_debug "AWS Account ID: $ACCOUNT_ID"
}

get_config() {
    print_info "Loading configuration for environment: $ENVIRONMENT from $CONFIG_FILE"

    # Global config
    NAME=$(jq -r ".name" "$CONFIG_FILE")
    REGION=$(jq -r ".region" "$CONFIG_FILE")

    # Environment-specific config
    if ! jq -e ".environments.${ENVIRONMENT}" "$CONFIG_FILE" > /dev/null 2>&1; then
        print_error "Configuration for environment '${ENVIRONMENT}' not found in .environments of ${CONFIG_FILE}"
        exit 1
    fi

    PARAMETERS="ProjectName=${NAME} Environment=${ENVIRONMENT}"
    for param in $(jq -r ".environments.${ENVIRONMENT}.parameters | keys[]" "$CONFIG_FILE"); do
        value=$(jq -r ".environments.${ENVIRONMENT}.parameters.${param}" "$CONFIG_FILE")
        PARAMETERS="${PARAMETERS} ${param}=${value}"
    done

    # Derived values
    PACKAGE_BUCKET="${NAME}-cf-templates-${ACCOUNT_ID}-${REGION}"
    STACK_NAME="${NAME}-${ENVIRONMENT}"

    # print variables
    print_debug "Environment: $ENVIRONMENT"
    print_debug "Name: $NAME"
    print_debug "Package Bucket: $PACKAGE_BUCKET"
    print_debug "Stack Name: $STACK_NAME"
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
        --output-template-file ${ROOT_DIR}/packaged.template; then
        print_error "Failed to package artifacts"
        exit 1
    fi
}

deploy_infrastructure() {
    print_info "Deploying infrastructure..."
    if ! aws cloudformation deploy \
        --region $REGION \
        --stack-name $STACK_NAME \
        --template-file ${ROOT_DIR}/packaged.template \
        --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
        --parameter-overrides $PARAMETERS \
        --tags Solution=$NAME Environment=$ENVIRONMENT; then
        print_error "Failed to deploy infrastructure"
        exit 1
    fi
    print_success "Infrastructure deployment completed!"
}

get_stack_outputs() {
    print_info "Retrieving stack outputs..."

    if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
        print_error "Failed to retrieve stack information"
        exit 1
    fi

    BUCKET_NAME=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`S3BucketRootName`].OutputValue' \
        --output text 2> /dev/null)

    DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CFDistributionId`].OutputValue' \
        --output text 2> /dev/null)

    WEBSITE_URL=$(aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CloudFrontDomainName`].OutputValue' \
        --output text 2> /dev/null)

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

validate_template() {
    print_info "Validating CloudFormation template..."

    for template in ${ROOT_DIR}/templates/*.yaml; do
        if [ -f "$template" ]; then
            print_debug "Validating $template"
            aws cloudformation validate-template \
                --template-body file://$template \
                --region "$REGION"
        fi
    done

    print_success "Template validation successful!"
}

print_help() {
    print_info "Usage: $0 <action> [environment]"
    print_info ""
    print_info "Available actions:"
    print_info "  help     - Show this help message"
    print_info "  validate - Validate template"
    print_info "  infra    - Deploy infrastructure"
    print_info "  content  - Deploy website content"
    print_info "  outputs  - Display stack outputs"
    print_info ""
    print_info "See deploy-config.json for available environments"
}

main() {
    check_dependencies
    get_aws_account_id
    get_config

    # Execute action
    case $ACTION in
        "help")
            print_help
            ;;
        "validate")
            validate_template
            ;;
        "infra")
            package_static
            package_artifacts
            deploy_infrastructure
            ;;
        "content")
            sync_site_content
            invalidate_cloudfront_cache
            print_success "Content deployment completed!"
            ;;
        "outputs")
            get_stack_outputs
            ;;
        *)
            print_error "Unknown action: $ACTION"
            print_help
            exit 1
            ;;
    esac
}

main
