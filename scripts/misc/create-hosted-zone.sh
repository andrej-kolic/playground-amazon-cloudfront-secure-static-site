#!/bin/bash

# Script to create a Route53 hosted zone for your domain
# Run this once to create the hosted zone, then use the nameservers at your domain provider

# Disable automatic pagination for AWS CLI commands
export AWS_PAGER=""

set -e

# Configuration
DOMAIN_NAME=${1:-"example.com"}

echo "Creating Route53 hosted zone for domain: $DOMAIN_NAME"

# Create hosted zone
HOSTED_ZONE_ID=$(aws route53 create-hosted-zone \
    --name "$DOMAIN_NAME" \
    --caller-reference "$(date +%s)" \
    --hosted-zone-config Comment="Main hosted zone for $DOMAIN_NAME" \
    --query 'HostedZone.Id' \
    --output text)

# Clean up the hosted zone ID (remove /hostedzone/ prefix)
HOSTED_ZONE_ID=${HOSTED_ZONE_ID#/hostedzone/}

echo "✅ Hosted zone created successfully!"
echo "Hosted Zone ID: $HOSTED_ZONE_ID"
echo ""

# Get nameservers
echo "📋 Nameservers for your domain provider:"
aws route53 get-hosted-zone \
    --id "$HOSTED_ZONE_ID" \
    --query 'DelegationSet.NameServers' \
    --output table

echo ""
echo "🔧 Next steps:"
echo "1. Configure these nameservers at your domain provider"
echo "2. Wait for DNS propagation (can take up to 48 hours)"
echo "3. Use this Hosted Zone ID when deploying your environments: $HOSTED_ZONE_ID"
echo ""
echo "💡 You can save this Hosted Zone ID in your deploy-config.json file"
