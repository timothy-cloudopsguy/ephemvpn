# Ephemeral VPN - WireGuard VPN Server with Python API

A Docker-based WireGuard VPN server using wgslirp (userspace WireGuard) designed to run in AWS ECS Fargate without privileged networking permissions. Includes a FastAPI-based REST API for managing VPN users and configurations. Server keys and user data are stored in AWS SSM Parameter Store for persistence and security.

## Features

- **Fargate Compatible**: Uses wgslirp userspace WireGuard - no privileged networking required
- **WireGuard Protocol**: Modern, secure VPN with state-of-the-art cryptography
- **REST API**: FastAPI-based management interface for user operations
- **AWS Integration**: SSM Parameter Store for configuration persistence
- **Standard WireGuard**: Clients use standard WireGuard tools and configurations

## Architecture

### Infrastructure Modules

The Terraform configuration is organized into modular components for better maintainability:

1. **`ecs_cluster`**: Shared ECS cluster and execution role
   - Creates the ECS cluster used by all services
   - Manages the execution role for running containers
   - Can be reused across multiple services

2. **`ecs`**: Service-specific resources
   - Creates service-specific task roles with appropriate permissions
   - Manages security groups for network access
   - Handles CloudWatch logging configuration
   - Each service gets its own isolated resources

**Benefits:**
- **Separation of Concerns**: Cluster, service, and task infrastructure
- **Reusability**: Multiple services can share the same cluster
- **Security**: Each service has minimal required permissions
- **Maintainability**: Easier to update and manage components

### Container Services

The container runs two main services:
1. **WireGuard VPN Server** (main process) - wgslirp userspace WireGuard server
2. **Python API** (background) - REST API for user management and key generation

**Traffic Flow:**
```
Client → WireGuard → wgslirp Container → Internet
Client ← Encrypted ← wgslirp Container ← Internet
```

This works in Fargate because:
- wgslirp implements WireGuard in userspace
- No TUN/TAP devices, kernel modules, or privileged operations needed
- All networking handled via standard socket operations

## Quick Start

### Prerequisites

- Docker
- AWS CLI configured with appropriate permissions
- IAM role or credentials with SSM access (see IAM Policy below)

### Build the Image

```bash
docker build -t ephem-vpn .
```

### Run the Container

```bash
docker run -d \
  --name ephem-vpn \
  -p 51820:51820/udp \
  -p 8000:8000/tcp \
  -e AWS_REGION=us-east-1 \
  -e SSM_PREFIX=/ephem-vpn \
  ephem-vpn
```

**Note**: No special privileges needed - works in regular containers and ECS Fargate!

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SSM_PREFIX` | `/ephem-vpn` | Prefix for SSM parameter names |
| `AWS_REGION` | `us-east-1` | AWS region for SSM operations |
| `API_PORT` | `8000` | Port for the management API |
| `WG_LISTEN_PORT` | `51820` | UDP port for WireGuard connections |
| `WG_MTU` | `1380` | MTU setting for WireGuard interface |
| `DNS_NAME` | | Optional DNS name for the VPN server endpoint |

## API Endpoints

### Authentication
- **Master API Key**: Used for admin operations (create/delete users). Stored in SSM at `/ephem-vpn/master-api-key`
- **User API Keys**: Individual keys for VPN access. Generated via master key.

All requests require `Authorization: Bearer <api-key>` header.

### Health Check
```bash
curl http://localhost:8000/health
```

### Create User API Key (Master Key Required)
```bash
curl -X POST http://localhost:8000/users \
  -H "Authorization: Bearer YOUR_MASTER_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"client_id": "user1"}'
```

Response:
```json
{
  "api_key": "a1b2c3d4...",
  "client_id": "user1",
  "created_at": "2023-11-30T12:00:00",
  "status": "active"
}
```

### List Users
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:8000/users
```

Response:
```json
["user1", "user2", "user3"]
```

### Get User Info
```bash
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:8000/users/user1
```

### Delete User (Master Key Required)
```bash
curl -X DELETE \
  -H "Authorization: Bearer YOUR_MASTER_API_KEY" \
  http://localhost:8000/users/user1
```

## How It Works

### WireGuard VPN Architecture

The system runs a standard WireGuard VPN server using wgslirp (userspace WireGuard implementation) that can run in AWS ECS Fargate without privileged networking permissions.

**Key Components:**
1. **wgslirp WireGuard Server**: Userspace WireGuard implementation that handles VPN connections
2. **FastAPI Management API**: REST API for creating and managing VPN user configurations
3. **SSM Parameter Store**: Secure storage for server keys, user keys, and configuration data

**VPN Connection Flow:**
```
Client Device → WireGuard UDP/51820 → wgslirp Server → Internet
Client Device ← Encrypted Response ← wgslirp Server ← Internet
```

### User Management

- Users are created via the REST API with individual WireGuard keypairs
- Each user gets a unique IP address in the VPN subnet (10.77.0.0/24)
- Client configurations are generated automatically with proper peer settings
- All user data is encrypted and stored in AWS SSM Parameter Store

## SSM Parameter Store Structure

The system uses the following SSM parameters:

- `/{SSM_PREFIX}/master-api-key` - Master API key for admin operations (created by Terraform)
- `/{SSM_PREFIX}/users/{client_id}/api-key` - Individual user API keys
- `/{SSM_PREFIX}/users/{client_id}/created-at` - User creation timestamp
- `/{SSM_PREFIX}/users/{client_id}/status` - User status (active/inactive)

See `ssm-examples.json` for detailed parameter specifications.

## IAM Policy

The container requires an IAM role with the following permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:PutParameter",
        "ssm:DescribeParameters",
        "ssm:DeleteParameter"
      ],
      "Resource": [
        "arn:aws:ssm:*:*:parameter/ephem-vpn/*"
      ]
    }
  ]
}
```

## Container Behavior

### Startup
1. Starts VPN proxy server on port 3128
2. Starts API server on port 8000
3. Master API key is pre-created by Terraform
4. User API keys are managed via API endpoints

### User Management
- Use master API key to create/delete user accounts
- Each user gets their own API key for VPN access
- API keys are encrypted and stored in SSM

## Client Setup

### 1. Install WireGuard
```bash
# Ubuntu/Debian
sudo apt install wireguard wireguard-tools

# CentOS/RHEL
sudo yum install wireguard-tools

# macOS
brew install wireguard-tools

# Windows: Download from https://www.wireguard.com/install/
```

### 2. Get Master API Key
After Terraform deployment, retrieve the master API key:
```bash
aws ssm get-parameter --name "/ephem-vpn/master-api-key" \
  --with-decryption --query Parameter.Value --output text
```

### 3. Setup VPN Client
```bash
# Setup the client with your VPN server
python3 vpn-client.py setup https://your-vpn-server:8000 YOUR_MASTER_KEY
```

### 4. Create Your VPN User
```bash
# Create your user and get WireGuard configuration
python3 vpn-client.py create your-username
```

### 5. Connect to VPN
```bash
# Connect using WireGuard
python3 vpn-client.py connect your-username

# Verify connection - check if your IP has changed
curl https://httpbin.org/ip
```

### 6. Disconnect
```bash
python3 vpn-client.py disconnect your-username
```

## Security Notes

- Master API key is auto-generated on first container startup
- All sensitive data (keys, API keys) is stored encrypted in SSM Parameter Store
- WireGuard provides end-to-end encryption for VPN traffic
- No privileged operations required in Fargate container
- Server uses wgslirp userspace WireGuard - no kernel modules needed
- Client connections require standard WireGuard tools and root privileges for interface management
- ICMP (ping) support is enabled via wgslirp modifications

## Troubleshooting

### Container won't start
- Check IAM permissions for SSM access
- Verify AWS credentials are configured
- Check container logs: `docker logs ephem-vpn`
- Ensure UDP port 51820 is not blocked by firewall

### API returns 401 Unauthorized
- Check that the master API key exists in SSM: `aws ssm get-parameter --name "/ephem-vpn/master-api-key"`
- Ensure `Authorization: Bearer <api-key>` header is included in requests
- Verify the API key is correct and not expired

### WireGuard connection fails
- Ensure WireGuard tools are installed: `wg --version`
- Check that UDP port 51820 is accessible on the VPN server
- Verify the WireGuard configuration file is correct
- Run `wg show` to check interface status

### Cannot connect to VPN server
- Verify the server endpoint (IP/DNS) is correct in the config
- Check that the server's public key matches what's in the client config
- Ensure your firewall allows outbound UDP connections
- Try connecting from a different network to rule out local firewall issues

### DNS resolution issues
- Check that DNS servers are configured correctly in the WireGuard config
- Verify that DNS queries are working: `nslookup google.com`
- Try using different DNS servers (8.8.8.8, 1.1.1.1)

## Limitations

### Current Implementation Notes
- **TCP/UDP Focus**: Optimized for TCP and UDP traffic, with ICMP support via wgslirp modifications
- **IPv4 Only**: Currently designed for IPv4 traffic. IPv6 support would require additional development
- **Userspace WireGuard**: Uses wgslirp for Fargate compatibility - performance characteristics may differ from kernel WireGuard
- **Single Container**: Both VPN server and API run in the same container process
- **DNS**: DNS queries are routed through the VPN tunnel for privacy

### Future Improvements
- IPv6 support
- ICMP tunneling
- Connection multiplexing for better performance
- UDP hole punching for gaming/P2P applications
- Split tunneling (selective routing)

## Development

### Local Testing
```bash
# Install dependencies
poetry install

# Run API server locally (WireGuard server requires container environment)
uvicorn api.main:app --host 0.0.0.0 --port 8000
```

### Testing with Docker
```bash
# Build and run locally
docker build -t ephem-vpn .
docker run -it --rm \
  -p 3128:3128/tcp -p 8000:8000/tcp \
  -e AWS_REGION=us-east-1 \
  ephem-vpn
```

### Testing Full Traffic Routing
```bash
# Test connectivity to your VPN server
sudo ./setup-routing.sh test your-vpn-server.com 3128

# Start full traffic VPN (routes ALL laptop traffic through VPN)
sudo ./setup-routing.sh start your-vpn-server.com 3128

# In another terminal, verify traffic is routed through VPN
curl https://httpbin.org/ip  # Should show VPN server IP, not your real IP

# Stop VPN (Ctrl+C) and verify routing is restored
```

## File Structure

```
.
├── Dockerfile              # Multi-stage container build (wgslirp + API)
├── entrypoint.sh          # Container startup script
├── keygen.sh              # WireGuard key generation utility
├── vpn-client.py          # WireGuard VPN client management tool
├── pyproject.toml         # Python dependencies
├── poetry.lock           # Locked dependency versions
├── api/
│   └── main.py           # FastAPI application with WireGuard user management
├── terraform/            # Infrastructure as Code
│   ├── main.tf           # Main configuration with module composition
│   ├── locals.tf         # Property file loading
│   ├── modules/
│   │   ├── ecs_cluster/     # Shared ECS cluster and execution role
│   │   └── ecs/             # ECS service configuration
│   └── properties.dev.json # Environment configuration
├── ssm-examples.json     # SSM parameter examples
└── README.md             # This file
```
