#!/bin/bash
# WireGuard Key Generation Script for AWS ECS
# This script generates WireGuard keys and saves them to SSM Parameter Store

set -e

# Configuration from environment variables
SSM_PREFIX="${SSM_PREFIX:-/ephem-vpn}"
AWS_REGION="${AWS_REGION:-us-east-1}"
KEY_ALGORITHM="${KEY_ALGORITHM:-curve25519}"
KEY_PURPOSE="${KEY_PURPOSE:-wireguard-server}"

echo "Generating WireGuard server keys..."
echo "SSM Prefix: $SSM_PREFIX"
echo "AWS Region: $AWS_REGION"
echo "Key Algorithm: $KEY_ALGORITHM"
echo "Key Purpose: $KEY_PURPOSE"

# Generate server private key
echo "Generating private key..."
SERVER_PRIVATE_KEY=$(wg genkey)
echo "Generated private key"

# Generate server public key from private key
echo "Generating public key..."
SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)
echo "Generated public key"

# Base64 encode the keys to avoid newline issues
echo "Encoding keys in base64..."
SERVER_PRIVATE_KEY_B64=$(echo -n "$SERVER_PRIVATE_KEY" | base64 -w 0)
SERVER_PUBLIC_KEY_B64=$(echo -n "$SERVER_PUBLIC_KEY" | base64 -w 0)

echo "Keys encoded in base64"

# Save to SSM Parameter Store
echo "Saving keys to SSM Parameter Store..."

# Save base64 versions (used by containers)
aws ssm put-parameter \
    --name "${SSM_PREFIX}/wg/server-private-key-b64" \
    --value "$SERVER_PRIVATE_KEY_B64" \
    --type "SecureString" \
    --region "$AWS_REGION" \
    --overwrite \
    --description "WireGuard server private key (base64 encoded) for $KEY_PURPOSE"

aws ssm put-parameter \
    --name "${SSM_PREFIX}/wg/server-public-key-b64" \
    --value "$SERVER_PUBLIC_KEY_B64" \
    --type "String" \
    --region "$AWS_REGION" \
    --overwrite \
    --description "WireGuard server public key (base64 encoded) for $KEY_PURPOSE"

# Also save plain versions for compatibility and API usage
aws ssm put-parameter \
    --name "${SSM_PREFIX}/wg/server-private-key" \
    --value "$SERVER_PRIVATE_KEY" \
    --type "SecureString" \
    --region "$AWS_REGION" \
    --overwrite \
    --description "WireGuard server private key (plain) for $KEY_PURPOSE"

aws ssm put-parameter \
    --name "${SSM_PREFIX}/wg/server-public-key" \
    --value "$SERVER_PUBLIC_KEY" \
    --type "String" \
    --region "$AWS_REGION" \
    --overwrite \
    --description "WireGuard server public key (plain) for $KEY_PURPOSE"

# Save metadata
aws ssm put-parameter \
    --name "${SSM_PREFIX}/wg/server-key-metadata" \
    --value "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|$KEY_ALGORITHM|$KEY_PURPOSE" \
    --type "String" \
    --region "$AWS_REGION" \
    --overwrite \
    --description "WireGuard server key metadata (timestamp|algorithm|purpose)"

echo "✓ WireGuard server keys generated and saved to SSM"
echo "Private key SSM: ${SSM_PREFIX}/wg/server-private-key"
echo "Public key SSM: ${SSM_PREFIX}/wg/server-public-key"
echo "Private key B64 SSM: ${SSM_PREFIX}/wg/server-private-key-b64"
echo "Public key B64 SSM: ${SSM_PREFIX}/wg/server-public-key-b64"
echo "Metadata SSM: ${SSM_PREFIX}/wg/server-key-metadata"
