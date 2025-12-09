#!/usr/bin/env python3
"""
Ephemeral VPN API - FastAPI application for managing WireGuard VPN users
"""

import os
import socket
import subprocess
import requests
import json
from typing import List, Optional, Tuple
from datetime import datetime
import boto3
from fastapi import FastAPI, HTTPException, Depends
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel


# Configuration
SSM_PREFIX = os.getenv("SSM_PREFIX", "/ephem-vpn")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
DNS_NAME = os.getenv("DNS_NAME")  # VPN DNS name from environment

# Initialize AWS SSM client
ssm = boto3.client('ssm', region_name=AWS_REGION)


def get_public_ip() -> str:
    """Get the public IP address of this server using multiple methods"""
    # Method 1: Try ECS task metadata endpoint (for ECS/Fargate)
    try:
        ecs_metadata_url = os.getenv("ECS_CONTAINER_METADATA_URI_V4")
        if ecs_metadata_url:
            response = requests.get(f"{ecs_metadata_url}/task", timeout=5)
            if response.status_code == 200:
                task_data = response.json()
                # Get the public IP from network interfaces
                networks = task_data.get("Networks", [])
                for network in networks:
                    if network.get("NetworkMode") == "awsvpc":
                        # This would require additional AWS API calls to get the public IP
                        # For now, we'll fall back to external services
                        break
    except Exception:
        pass

    # Method 2: Try external IP detection services
    ip_services = [
        "https://api.ipify.org?format=json",
        "https://httpbin.org/ip",
        "https://ipapi.co/json/",
        "https://api.myip.com"
    ]

    for service_url in ip_services:
        try:
            response = requests.get(service_url, timeout=5)
            if response.status_code == 200:
                data = response.json()
                if "ip" in data:
                    return data["ip"]
                elif "origin" in data:  # httpbin.org format
                    return data["origin"].split(",")[0].strip()  # Handle multiple IPs
        except Exception:
            continue

    # Method 3: Try EC2 instance metadata (if running on EC2)
    try:
        response = requests.get("http://169.254.169.254/latest/meta-data/public-ipv4", timeout=2)
        if response.status_code == 200:
            return response.text.strip()
    except Exception:
        pass

    # Method 4: Environment variable override
    env_ip = os.getenv("VPN_PUBLIC_IP")
    if env_ip:
        return env_ip

    # Fallback - return empty string to indicate IP detection failed
    return ""


# FastAPI app
app = FastAPI(title="Ephemeral VPN API", version="0.1.0")
security = HTTPBearer()


class WireGuardConfig(BaseModel):
    private_key: str
    public_key: str
    client_id: str
    created_at: datetime
    status: str = "active"
    client_config: str  # Full WireGuard client configuration


class CreateWireGuardUserRequest(BaseModel):
    client_id: str


def verify_master_api_key(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Verify master API key for admin operations"""
    try:
        master_key_param = ssm.get_parameter(
            Name=f"{SSM_PREFIX}/master-api-key",
            WithDecryption=True
        )
        master_key = master_key_param['Parameter']['Value']

        if credentials.credentials != master_key:
            raise HTTPException(status_code=401, detail="Invalid master API key")

        return credentials.credentials
    except ssm.exceptions.ParameterNotFound:
        raise HTTPException(status_code=500, detail="Master API key not configured")


def verify_api_key(credentials: HTTPAuthorizationCredentials = Depends(security)):
    """Verify any valid API key (master or user)"""
    # First check master key
    try:
        master_key_param = ssm.get_parameter(
            Name=f"{SSM_PREFIX}/master-api-key",
            WithDecryption=True
        )
        if credentials.credentials == master_key_param['Parameter']['Value']:
            return credentials.credentials
    except ssm.exceptions.ParameterNotFound:
        pass

    # Check user API keys
    try:
        # List all user API keys
        response = ssm.describe_parameters(
            ParameterFilters=[
                {
                    'Key': 'Name',
                    'Option': 'BeginsWith',
                    'Values': [f"{SSM_PREFIX}/users/"]
                }
            ]
        )

        for param in response['Parameters']:
            if param['Name'].endswith('/api-key'):
                try:
                    user_key_param = ssm.get_parameter(
                        Name=param['Name'],
                        WithDecryption=True
                    )
                    if credentials.credentials == user_key_param['Parameter']['Value']:
                        return credentials.credentials
                except:
                    continue

    except Exception:
        pass

    raise HTTPException(status_code=401, detail="Invalid API key")


def generate_wireguard_keys():
    """Generate WireGuard private and public key pair"""
    # Use subprocess to run wg commands for proper key generation
    import subprocess

    try:
        # Generate private key
        private_key = subprocess.run(['wg', 'genkey'],
                                   capture_output=True, text=True, check=True)
        private_key = private_key.stdout.strip()

        # Generate public key from private key
        public_key = subprocess.run(['wg', 'pubkey'],
                                  input=private_key, capture_output=True, text=True, check=True)
        public_key = public_key.stdout.strip()

        return private_key, public_key
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fallback: generate random base64 strings (not cryptographically secure for production)
        # import base64
        # import secrets
        private_key = "failed_to_generate_private_key"
        # For demo purposes, we'll create a fake public key
        # In production, you should ensure wg is available
        public_key = "failed_to_generate_public_key"
        return private_key, public_key








def save_user_wireguard_keys(client_id: str, private_key: str, public_key: str):
    """Save user WireGuard keys to SSM Parameter Store"""
    ssm.put_parameter(
        Name=f"{SSM_PREFIX}/users/{client_id}/wg-private-key",
        Value=private_key,
        Type='SecureString',
        Overwrite=True,
        Description=f"WireGuard private key for user {client_id}"
    )

    ssm.put_parameter(
        Name=f"{SSM_PREFIX}/users/{client_id}/wg-public-key",
        Value=public_key,
        Type='String',
        Overwrite=True,
        Description=f"WireGuard public key for user {client_id}"
    )

    # Also store metadata
    ssm.put_parameter(
        Name=f"{SSM_PREFIX}/users/{client_id}/created-at",
        Value=datetime.utcnow().isoformat(),
        Type='String',
        Overwrite=True
    )

    ssm.put_parameter(
        Name=f"{SSM_PREFIX}/users/{client_id}/status",
        Value="active",
        Type='String',
        Overwrite=True
    )


def load_user_wireguard_keys(client_id: str) -> Optional[tuple]:
    """Load user WireGuard keys from SSM Parameter Store"""
    try:
        private_response = ssm.get_parameter(
            Name=f"{SSM_PREFIX}/users/{client_id}/wg-private-key",
            WithDecryption=True
        )
        public_response = ssm.get_parameter(
            Name=f"{SSM_PREFIX}/users/{client_id}/wg-public-key"
        )

        return (private_response['Parameter']['Value'], public_response['Parameter']['Value'])
    except ssm.exceptions.ParameterNotFound:
        return None


def list_users() -> List[str]:
    """List all user IDs from SSM"""
    try:
        response = ssm.describe_parameters(
            ParameterFilters=[
                {
                    'Key': 'Name',
                    'Option': 'BeginsWith',
                    'Values': [f"{SSM_PREFIX}/users/"]
                }
            ]
        )
        user_ids = set()
        for param in response['Parameters']:
            # Extract user_id from parameter name
            name_parts = param['Name'].split('/')
            if len(name_parts) >= 3 and name_parts[2] != "":
                user_ids.add(name_parts[2])
        return list(user_ids)
    except Exception:
        return []


def delete_user_wireguard_keys(client_id: str):
    """Delete user WireGuard keys from SSM"""
    try:
        # Delete all user parameters
        ssm.delete_parameter(Name=f"{SSM_PREFIX}/users/{client_id}/wg-private-key")
        ssm.delete_parameter(Name=f"{SSM_PREFIX}/users/{client_id}/wg-public-key")
        ssm.delete_parameter(Name=f"{SSM_PREFIX}/users/{client_id}/created-at")
        ssm.delete_parameter(Name=f"{SSM_PREFIX}/users/{client_id}/status")
    except ssm.exceptions.ParameterNotFound:
        pass  # Already deleted


def get_user_info(client_id: str) -> Optional[dict]:
    """Get user information including WireGuard keys and metadata"""
    keys = load_user_wireguard_keys(client_id)
    if not keys:
        return None

    private_key, public_key = keys

    try:
        created_at_response = ssm.get_parameter(
            Name=f"{SSM_PREFIX}/users/{client_id}/created-at"
        )
        status_response = ssm.get_parameter(
            Name=f"{SSM_PREFIX}/users/{client_id}/status"
        )

        return {
            "client_id": client_id,
            "private_key": private_key,
            "public_key": public_key,
            "created_at": created_at_response['Parameter']['Value'],
            "status": status_response['Parameter']['Value']
        }
    except:
        # Return basic info if metadata not available
        return {
            "client_id": client_id,
            "private_key": private_key,
            "public_key": public_key,
            "created_at": datetime.utcnow().isoformat(),
            "status": "active"
        }


def generate_wireguard_client_config(client_id: str, private_key: str, public_key: str) -> str:
    """Generate WireGuard client configuration"""
    # Get server public key
    try:
        server_public_key_response = ssm.get_parameter(
            Name=f"{SSM_PREFIX}/wg/server-public-key",
            WithDecryption=True
        )
        server_public_key = server_public_key_response['Parameter']['Value'].strip()
        print(f"Server public key: {server_public_key}")
    except:
        server_public_key = "SERVER_PUBLIC_KEY_PLACEHOLDER"

    # Get server endpoint - use DNS name if available, otherwise public IP
    wg_listen_port = os.getenv("WG_LISTEN_PORT", "51820")

    # Use DNS name if available, otherwise fall back to public IP
    if DNS_NAME:
        server_endpoint = f"{DNS_NAME}:{wg_listen_port}"
        print(f"Using DNS name for server endpoint: {server_endpoint}")
    else:
        public_ip = get_public_ip()
        server_endpoint = f"{public_ip}:{wg_listen_port}"
        print(f"Using public IP for server endpoint: {server_endpoint}")

    # Generate consistent IP address using MD5 hash (same as entrypoint.sh)
    import hashlib
    client_id_hash = hashlib.md5(client_id.encode()).hexdigest()
    hash_decimal = int(client_id_hash[:16], 16)  # Use first 16 hex chars
    ip_suffix = hash_decimal % 254 + 2

    config = f"""# WireGuard VPN Client Configuration for {client_id}
# Save this as {client_id}.conf and use with: wg-quick up {client_id}.conf

[Interface]
PrivateKey = {private_key}
Address = 10.0.0.{ip_suffix}/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = {server_public_key}
Endpoint = {server_endpoint}
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

# To connect:
# 1. Install WireGuard: https://www.wireguard.com/install/
# 2. Save this config as {client_id}.conf
# 3. Run: wg-quick up {client_id}.conf
# 4. To disconnect: wg-quick down {client_id}.conf
"""

    return config




@app.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.utcnow(), "services": ["api"]}


@app.post("/users", response_model=WireGuardConfig)
async def create_user_wireguard_config(request: CreateWireGuardUserRequest, master_key: str = Depends(verify_master_api_key)):
    """Create a new WireGuard user configuration (requires master API key)"""
    client_id = request.client_id

    # Check if user already exists
    if load_user_wireguard_keys(client_id):
        raise HTTPException(status_code=409, detail=f"User {client_id} already exists")

    # Generate WireGuard keypair
    private_key, public_key = generate_wireguard_keys()

    # Save to SSM
    save_user_wireguard_keys(client_id, private_key, public_key)

    # Generate client configuration
    client_config = generate_wireguard_client_config(client_id, private_key, public_key)

    user_response = WireGuardConfig(
        private_key=private_key,
        public_key=public_key,
        client_id=client_id,
        created_at=datetime.utcnow(),
        client_config=client_config
    )

    return user_response


@app.get("/users", response_model=List[str])
async def list_users_endpoint(api_key: str = Depends(verify_api_key)):
    """List all user IDs"""
    return list_users()


@app.get("/users/{client_id}", response_model=WireGuardConfig)
async def get_user(client_id: str, api_key: str = Depends(verify_api_key)):
    """Get user WireGuard configuration"""
    user_info = get_user_info(client_id)
    if not user_info:
        raise HTTPException(status_code=404, detail=f"User {client_id} not found")

    # Generate client configuration
    client_config = generate_wireguard_client_config(
        client_id,
        user_info["private_key"],
        user_info["public_key"]
    )

    return WireGuardConfig(
        private_key=user_info["private_key"],
        public_key=user_info["public_key"],
        client_id=client_id,
        created_at=datetime.fromisoformat(user_info["created_at"]),
        status=user_info["status"],
        client_config=client_config
    )


@app.delete("/users/{client_id}")
async def delete_user(client_id: str, master_key: str = Depends(verify_master_api_key)):
    """Delete a user WireGuard configuration (requires master API key)"""
    # Check if user exists
    if not load_user_wireguard_keys(client_id):
        raise HTTPException(status_code=404, detail=f"User {client_id} not found")

    # Remove from SSM
    delete_user_wireguard_keys(client_id)

    return {"message": f"User {client_id} deleted successfully"}
