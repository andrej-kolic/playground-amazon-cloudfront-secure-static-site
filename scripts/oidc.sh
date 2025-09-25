#!/bin/bash

# OIDC setup script for AWS CloudFormation Static Site
# Usage: ./oidc.sh
#
# This script sets up GitHub OIDC provider and IAM role for GitHub Actions authentication.
# This is a one-time, account-level operation that enables GitHub Actions to deploy
# infrastructure without storing AWS credentials in GitHub secrets.

SCRIPTS_DIR=$(dirname "$0")
ROOT_DIR=$(dirname "$0")/..

source "$SCRIPTS_DIR/helpers.sh"

# Disable automatic pagination for AWS CLI commands
export AWS_PAGER=""

CONFIG_FILE="${ROOT_DIR}/deploy-config.json"

get_oidc_config() {
    print_info "Loading OIDC configuration from $CONFIG_FILE"

    # Global config
    PROJECT_NAME=$(jq -r ".project_name" "$CONFIG_FILE")
    REGION=$(jq -r ".region" "$CONFIG_FILE")

    # OIDC config
    OIDC_ARN=$(jq -r ".oidc.oidc_arn" "$CONFIG_FILE")
    GITHUB_ORG=$(jq -r ".oidc.github_org" "$CONFIG_FILE")
    GITHUB_REPO=$(jq -r ".oidc.github_repo" "$CONFIG_FILE")

    # Derived values
    OIDC_STACK_NAME="${PROJECT_NAME}-github-oidc"

    # Print variables for debugging
    print_debug "Project Name: $PROJECT_NAME"
    print_debug "OIDC Stack Name: $OIDC_STACK_NAME"
    print_debug "GitHub Org: $GITHUB_ORG"
    print_debug "GitHub Repo: $GITHUB_REPO"
    print_debug "Region: $REGION"
    print_debug "OIDC ARN: $OIDC_ARN"
}

deploy_oidc() {
    print_info "⚠️  OIDC setup is a one-time, account-level operation."
    print_info "Deploying GitHub OIDC Provider and IAM Role..."

    if [ -z "$OIDC_ARN" ]; then
        print_debug "No existing OIDC provider ARN provided. A new OIDC provider will be created."
    else
        print_debug "Using provided existing OIDC provider ARN: $OIDC_ARN"
    fi

    print_debug "Deploying OIDC CloudFormation stack..."
    local PARAMETERS=(
        "ProjectName=$PROJECT_NAME"
        "GitHubOrg=$GITHUB_ORG"
        "GitHubRepo=$GITHUB_REPO"
        "OIDCProviderArn=$OIDC_ARN"
    )

    if ! aws cloudformation deploy \
        --region "$REGION" \
        --stack-name "$OIDC_STACK_NAME" \
        --template-file "${ROOT_DIR}"/templates/github-oidc.yaml \
        --capabilities CAPABILITY_NAMED_IAM \
        --parameter-overrides "${PARAMETERS[@]}" \
        --tags Solution="$PROJECT_NAME" Component=OIDC; then
        print_error "Failed to deploy OIDC infrastructure"
        exit 1
    fi

    # Get the role ARN for output
    GITHUB_ROLE_ARN=$(aws cloudformation describe-stacks \
        --stack-name "$OIDC_STACK_NAME" \
        --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey==\`GitHubActionsRoleArn\`].OutputValue" \
        --output text 2> /dev/null)

    print_success "OIDC deployment completed!"
    print_info "Add the following secret to your GitHub repository:"
    print_info "   Name: AWS_ROLE_ARN"
    print_info "   Value: $GITHUB_ROLE_ARN"
    print_info "   Remove the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY secrets (they're no longer needed)"
}

main() {
    check_dependencies
    get_oidc_config
    deploy_oidc
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
