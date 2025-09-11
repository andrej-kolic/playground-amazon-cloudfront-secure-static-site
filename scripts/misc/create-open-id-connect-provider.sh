#!/bin/bash

echo "Creating GitHub OIDC Provider in AWS IAM"

aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1 \
    --client-id-list sts.amazonaws.com

echo "✅ GitHub OIDC Provider created successfully!"
