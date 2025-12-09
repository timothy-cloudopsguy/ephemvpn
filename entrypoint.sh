#!/bin/bash
set -e

echo "Starting Ephemeral VPN container..."

# Configuration
SSM_PREFIX="${SSM_PREFIX:-/ephem-vpn}"
AWS_REGION="${AWS_REGION:-us-east-1}"
API_PORT="${API_PORT:-8000}"
DNS_NAME="${DNS_NAME:-}"
ROUTE53_HOSTED_ZONE_ID="${ROUTE53_HOSTED_ZONE_ID:-}"

# Function to update Route53 DNS record with public IP
update_dns_record() {
    local dns_name="$1"
    local hosted_zone_id="$2"

    echo "Detecting public IP address..."
    # Get public IP using multiple fallback methods
    PUBLIC_IP=""
    for method in "http://checkip.amazonaws.com" "http://icanhazip.com" "http://ifconfig.me"; do
        PUBLIC_IP=$(curl -s --connect-timeout 5 --max-time 10 "$method" 2>/dev/null | tr -d '[:space:]')
        if [[ $PUBLIC_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "Detected public IP: $PUBLIC_IP"
            break
        fi
    done

    if [ -z "$PUBLIC_IP" ]; then
        echo "ERROR: Could not detect public IP address"
        return 1
    fi

    echo "Updating Route53 DNS record for $dns_name with IP $PUBLIC_IP..."

    # Create the Route53 change batch to UPSERT (overwrite) the A record with single IP
    cat > /tmp/route53-change.json << EOF
{
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$dns_name",
                "Type": "A",
                "TTL": 60,
                "ResourceRecords": [
                    {
                        "Value": "$PUBLIC_IP"
                    }
                ]
            }
        }
    ]
}
EOF

    # Submit the change to Route53
    CHANGE_ID=$(aws route53 change-resource-record-sets \
        --hosted-zone-id "$hosted_zone_id" \
        --change-batch file:///tmp/route53-change.json \
        --region "$AWS_REGION" \
        --query 'ChangeInfo.Id' \
        --output text)

    if [ $? -eq 0 ] && [ -n "$CHANGE_ID" ]; then
        echo "Route53 change submitted successfully. Change ID: $CHANGE_ID"
        echo "DNS record $dns_name will be updated to $PUBLIC_IP"
        # Clean up temp file
        rm -f /tmp/route53-change.json
        return 0
    else
        echo "ERROR: Failed to update Route53 DNS record"
        rm -f /tmp/route53-change.json
        return 1
    fi
}

# Update DNS record if configured
if [ -n "$DNS_NAME" ] && [ -n "$ROUTE53_HOSTED_ZONE_ID" ]; then
    echo "DNS configuration found - updating Route53 record..."
    if update_dns_record "$DNS_NAME" "$ROUTE53_HOSTED_ZONE_ID"; then
        echo "✓ DNS record updated successfully"
    else
        echo "✗ Failed to update DNS record - continuing with VPN startup"
    fi
else
    echo "DNS configuration not provided - skipping Route53 update"
fi

# Function to get SSM parameter
get_ssm_param() {
    local param_name="$1"
    local default_value="$2"

    local value
    value=$(aws ssm get-parameter --name "${param_name}" --region "${AWS_REGION}" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || echo "")

    if [ -n "$value" ]; then
        echo "Retrieved ${param_name} from SSM" >&2
        echo "${value}"
    else
        echo "Parameter ${param_name} not found in SSM, using default" >&2
        echo "${default_value}"
    fi
}

# Function to put SSM parameter
put_ssm_param() {
    local param_name="$1"
    local value="$2"

    aws ssm put-parameter \
        --name "${param_name}" \
        --value "${value}" \
        --type "SecureString" \
        --region "${AWS_REGION}" \
        --overwrite
    echo "Stored ${param_name} in SSM"
}

# Generate or retrieve API key
echo "Setting up API key..."
API_KEY=$(get_ssm_param "${SSM_PREFIX}/master-api-key" "$(openssl rand -hex 32)")
if [ "$(get_ssm_param "${SSM_PREFIX}/master-api-key" "notfound")" = "notfound" ]; then
    put_ssm_param "${SSM_PREFIX}/master-api-key" "${API_KEY}"
fi
export API_KEY="${API_KEY}"

# Function to get binary SSM parameter (base64 encoded)
get_ssm_binary_param() {
    local param_name="$1"
    local output_file="$2"

    local encoded_value
    encoded_value=$(aws ssm get-parameter \
        --name "${param_name}" \
        --region "${AWS_REGION}" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || echo "")

    if [ -n "${encoded_value}" ]; then
        echo "${encoded_value}" | base64 -d > "${output_file}"
        return 0
    else
        return 1
    fi
}

# Function to put binary SSM parameter (base64 encoded)
put_ssm_binary_param() {
    local param_name="$1"
    local file_path="$2"

    local encoded_value
    encoded_value=$(base64 -w 0 "${file_path}")

    aws ssm put-parameter \
        --name "${param_name}" \
        --value "${encoded_value}" \
        --type "SecureString" \
        --region "${AWS_REGION}" \
        --overwrite
    echo "Stored ${param_name} in SSM"
}

# Setup WireGuard keys
echo "Setting up WireGuard keys..."

# Check if WireGuard keys exist in SSM
WG_PRIVATE_KEY_PARAM="${SSM_PREFIX}/wg/server-private-key-b64"
WG_PRIVATE_KEY=$(get_ssm_param "${WG_PRIVATE_KEY_PARAM}" "notfound")

if [ "${WG_PRIVATE_KEY}" = "notfound" ]; then
    echo "WireGuard keys not found in SSM, generating new keys..."

    # Generate WireGuard server private key
    SERVER_PRIVATE_KEY=$(wg genkey)
    echo "Generated WireGuard private key"

    # Generate server public key from private key
    SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)
    echo "Generated WireGuard public key"

    # Save to SSM Parameter Store (keys are already base64-encoded from wg tools)
    echo "Saving WireGuard keys to SSM Parameter Store..."
    put_ssm_param "${SSM_PREFIX}/wg/server-private-key-b64" "$SERVER_PRIVATE_KEY"
    put_ssm_param "${SSM_PREFIX}/wg/server-public-key-b64" "$SERVER_PUBLIC_KEY"

    # Also save plain versions for compatibility and API usage
    put_ssm_param "${SSM_PREFIX}/wg/server-private-key" "$SERVER_PRIVATE_KEY"
    put_ssm_param "${SSM_PREFIX}/wg/server-public-key" "$SERVER_PUBLIC_KEY"

    # Save metadata
    put_ssm_param "${SSM_PREFIX}/wg/server-key-metadata" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")|curve25519|wireguard-server"

    echo "✓ WireGuard server keys generated and saved to SSM"
    WG_PRIVATE_KEY="$SERVER_PRIVATE_KEY"
else
    echo "Loading existing WireGuard keys from SSM..."
fi

# Configure WireGuard server settings for routing all traffic
export WG_PRIVATE_KEY
# export WG_IP="${WG_IP:-10.0.0.1/24}"
# export WG_ROUTES="${WG_ROUTES:-0.0.0.0/0}"
export WG_LISTEN_PORT="${WG_LISTEN_PORT:-51820}"
export WG_MTU="${WG_MTU:-1380}"

# Query SSM for active WireGuard peers and configure environment variables
echo "Querying SSM for active WireGuard peers..."

# Get all user parameters from SSM
USER_PARAMS=$(aws ssm describe-parameters \
    --parameter-filters "Key=Name,Option=BeginsWith,Values=${SSM_PREFIX}/users/" \
    --region "${AWS_REGION}" \
    --query 'Parameters[*].Name' \
    --output text 2>/dev/null || echo "")

if [ -n "$USER_PARAMS" ]; then
    # Extract unique client IDs and check their status
    declare -a ACTIVE_USERS=()
    for param in $USER_PARAMS; do
        echo "Processing parameter: $param"
        # Extract client_id from parameter name (format: /prefix/users/client_id/something)
        client_id=$(echo "$param" | sed -E "s|${SSM_PREFIX}/users/([^/]+)/.*|\1|")

        # Skip if we already processed this client_id
        if [[ " ${ACTIVE_USERS[@]} " =~ " ${client_id} " ]]; then
            echo "Skipping already processed client_id: $client_id"
            continue
        fi

        # Check if user is active
        status_param="${SSM_PREFIX}/users/${client_id}/status"
        status=$(get_ssm_param "$status_param" "inactive")

        if [ "$status" = "active" ]; then
            ACTIVE_USERS+=("$client_id")
        fi
    done

    # Configure peer environment variables
    if [ ${#ACTIVE_USERS[@]} -gt 0 ]; then
        WG_PEERS=""
        peer_index=0

        for client_id in "${ACTIVE_USERS[@]}"; do
            # Get the user's public key
            public_key_param="${SSM_PREFIX}/users/${client_id}/wg-public-key"
            public_key=$(get_ssm_param "$public_key_param" "")

            if [ -n "$public_key" ]; then
                # Assign IP address using the same MD5 logic as main.py
                # This ensures consistency between client config and server peer config
                client_id_hash=$(echo -n "$client_id" | openssl dgst -md5 | awk -F'= ' '{print $2}' | cut -c1-16)
                # Convert hex hash to decimal for modulo operation
                hash_decimal=$((16#${client_id_hash}))
                ip_suffix=$((hash_decimal % 254 + 2))
                peer_ip="10.77.0.${ip_suffix}/32"

                # Set peer environment variables
                export "WG_PEER_${peer_index}_PUBLIC_KEY=$public_key"
                export "WG_PEER_${peer_index}_ALLOWED_IPS=$peer_ip"
                
                echo "Exporting user $client_id to environment variables"
                echo "WG_PEER_${peer_index}_PUBLIC_KEY=$public_key"
                echo "WG_PEER_${peer_index}_ALLOWED_IPS=$peer_ip"

                # Build WG_PEERS list
                if [ -n "$WG_PEERS" ]; then
                    WG_PEERS="${WG_PEERS},${peer_index}"
                else
                    WG_PEERS="$peer_index"
                fi

                echo "Configured peer $peer_index: $client_id -> $peer_ip"

                echo "Incrementing peer index to $peer_index"
                peer_index=$((peer_index + 1))
                echo "New peer index: $peer_index"

            fi
        done

        export WG_PEERS
        echo "Active peers configured: $WG_PEERS"
    else
        echo "No active peers found"
    fi
else
    echo "No user parameters found in SSM"
fi

echo "WireGuard server configuration:"
echo "  Private key: configured (base64 encoded)"
# echo "  Server IP: $WG_IP"
echo "  Routes: $WG_ROUTES"
echo "  Listen port: $WG_LISTEN_PORT"
echo "  MTU: $WG_MTU"
echo "  Active peers: ${WG_PEERS:-none}"

# Key generation is now handled automatically above
# The keygen.sh script is still available for one-shot ECS tasks if needed

# Normal operation mode - WireGuard VPN Server and API
echo "Starting WireGuard VPN Server and API..."

# WireGuard private key is already configured above as base64 environment variable

# Start the FastAPI management API in the background
cd /app
poetry run uvicorn api.main:app --host 0.0.0.0 --port "${API_PORT:-8000}" &
API_PID=$!

# Wait a moment for API to start
sleep 2

# Verify API is running
# if ! curl -f -s http://localhost:${API_PORT:-8000}/health > /dev/null; then
#     echo "ERROR: API failed to start"
#     kill ${API_PID} 2>/dev/null || true
#     exit 1
# fi

echo "FastAPI management API started successfully (PID: ${API_PID})"
echo "API available on port ${API_PORT:-8000}"

# Start wgslirp WireGuard server as the main process
echo "Starting wgslirp WireGuard server..."
echo "WireGuard listening on UDP port ${WG_LISTEN_PORT:-51820}"

# wgslirp will run as the main container process
exec /usr/local/bin/wgslirp
