# Ephemeral VPN - WireGuard VPN Server with Python API

A Docker-based WireGuard VPN server using wgslirp (userspace WireGuard) that routes ALL traffic through secure VPN tunnels. Designed to work in AWS ECS Fargate without privileged networking permissions. Server configurations and client data are stored in AWS SSM Parameter Store for persistence and security.

## Features

- **Fargate Compatible**: Uses wgslirp userspace WireGuard - no privileged networking required
- **Full Traffic Routing**: Routes ALL internet traffic through WireGuard VPN tunnels
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

3. **`ecs_one_shot`**: One-time task execution
   - Creates ECS service with `desired_count = 0`
   - Triggers tasks based on configuration changes (SHA256 hash)
   - Perfect for key generation, migrations, setup tasks

**Benefits:**
- **Separation of Concerns**: Cluster, service, and task infrastructure
- **Reusability**: Multiple services can share the same cluster
- **Security**: Each service has minimal required permissions
- **Maintainability**: Easier to update and manage components
- **Automation**: One-shot tasks run automatically on config changes

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
  -p 3128:3128/tcp \
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
| `PROXY_PORT` | `3128` | Port for the VPN proxy server |
| `VPN_PROXY_HOST` | `localhost` | Hostname for proxy server (for client configs) |
| `VPN_PROXY_PORT` | `3128` | Port for proxy server (for client configs) |

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

### VPN Architecture

The solution uses a **hybrid architecture** to achieve full traffic routing while maintaining Fargate compatibility:

1. **Fargate Proxy Server**: HTTP CONNECT proxy server in ECS Fargate (unprivileged)
2. **Local VPN Client**: Creates TUN device and captures ALL system traffic (requires root on local machine)
3. **Traffic Flow**: Local client tunnels all captured packets through HTTP CONNECT to Fargate proxy

### Full Traffic Routing

The local VPN client captures **ALL traffic** on your laptop:

1. **TUN Device Creation**: Creates virtual network interface (requires root)
2. **System Routing**: Sets default route through TUN device - **ALL traffic is captured**
3. **Packet Tunneling**: Each TCP/UDP packet is tunneled through HTTP CONNECT
4. **Destination Routing**: Fargate proxy forwards traffic to final destinations

**What gets routed:**
- ✅ Web browsing (HTTP/HTTPS)
- ✅ Email, messaging apps
- ✅ DNS queries
- ✅ Gaming traffic
- ✅ Video streaming
- ✅ ALL internet traffic

### Client Setup

**For FULL traffic routing (recommended):**

```bash
# 1. Backup your current routing
sudo ./setup-routing.sh backup

# 2. Start VPN with automatic routing setup
sudo ./setup-routing.sh start your-vpn-server.com 3128

# ALL traffic on your laptop now goes through the VPN!
# Press Ctrl+C to stop and automatically restore routing
```

**Alternative: Manual routing setup**
```bash
# Set up routing manually
sudo ./setup-routing.sh setup

# Start VPN client
sudo python3 vpn-client.py your-vpn-server.com 3128
```

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
# Connect - this routes ALL traffic through WireGuard VPN
python3 vpn-client.py connect your-username

# Verify connection
curl https://httpbin.org/ip  # Should show VPN server IP
```

### 6. Disconnect
```bash
python3 vpn-client.py disconnect your-username
```

## Key Generation

WireGuard keys are automatically generated using a one-shot ECS task:

### Automatic Key Generation
- **Trigger**: SHA256 hash of `terraform/keygen-config.json`
- **Process**: One-shot ECS task runs keygen container
- **Storage**: Keys saved to SSM Parameter Store (base64 encoded)
- **Timing**: Runs before main service deployment

### Manual Key Regeneration
To regenerate keys, modify `terraform/keygen-config.json`:
```json
{
  "ssm_prefix": "/ephem-vpn",
  "key_algorithm": "curve25519",
  "key_purpose": "wireguard-server",
  "regenerate_keys": true
}
```

Then run:
```bash
terraform apply  # Will trigger keygen due to config change
```

### Key Storage in SSM
- `/ephem-vpn/wg/server-private-key-b64` - Base64 encoded private key
- `/ephem-vpn/wg/server-public-key-b64` - Base64 encoded public key
- `/ephem-vpn/wg/server-private-key` - Plain private key
- `/ephem-vpn/wg/server-public-key` - Plain public key
- `/ephem-vpn/wg/server-key-metadata` - Generation metadata

## Security Notes

- API key is auto-generated on first run
- All sensitive data is stored encrypted in SSM
- HTTP CONNECT tunneling provides transport-level security
- No privileged operations required in Fargate container
- Traffic is encrypted in transit via HTTPS when connecting to destinations
- Local VPN client requires root privileges (normal for VPN software)
- All traffic routing happens at network level - comprehensive but requires trust in VPN server

## Troubleshooting

### Container won't start
- Check IAM permissions
- Verify SSM parameters exist
- Check container logs: `docker logs ephem-vpn`

### Proxy connection fails
- Verify proxy server is accessible on port 3128
- Check that HTTP CONNECT requests are not blocked by firewalls
- Ensure client is sending proper CONNECT requests

### Traffic not routing through VPN
- Verify system proxy settings are configured correctly
- Check that applications respect proxy settings
- Consider using proxychains/tsocks for applications that don't support proxies

### API returns 401
- Check API key in SSM parameter `/{SSM_PREFIX}/api-key`
- Ensure `Authorization: Bearer <key>` header is correct

### VPN client fails to start
- Make sure you're running as root: `sudo python vpn-client.py ...`
- Check that TUN device can be created: `ls -la /dev/net/tun`
- Verify proxy server is accessible and responding

### Traffic not routing through VPN
- Check routing table: `ip route show` (should show default via tun0)
- Verify TUN interface is up: `ip addr show tun0`
- Test proxy connectivity: `./setup-routing.sh test host port`
- Check that applications aren't using cached DNS

### Cannot restore original routing
- Manual restore: `sudo ip route del default dev tun0; sudo ip route add default via <original-gateway> dev <interface>`
- Check backup file: `cat /tmp/vpn-routing-backup.txt`
- Restart networking: `sudo systemctl restart networking` (Linux) or reboot

## Limitations

### Current Implementation Notes
- **TCP/UDP Only**: Currently handles TCP and UDP traffic. ICMP (ping) and other protocols may not work perfectly
- **IPv4 Only**: Designed for IPv4 traffic. IPv6 support would require additional implementation
- **Connection Tracking**: Each TCP/UDP flow creates a separate HTTP CONNECT tunnel
- **Performance**: HTTP CONNECT tunneling adds latency compared to direct VPN protocols
- **DNS**: DNS queries are routed through the VPN (no local DNS leaks)

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

# Run API and proxy server locally
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
├── keygen.sh              # WireGuard key generation script
├── vpn-client.py          # WireGuard VPN client manager
├── setup-routing.sh       # Legacy routing setup script
├── pyproject.toml         # Python dependencies
├── poetry.lock           # Locked dependency versions
├── api/
│   └── main.py           # FastAPI application with WireGuard key management
├── terraform/            # Infrastructure as Code
│   ├── main.tf           # Main configuration with module composition
│   ├── locals.tf         # Property file loading
│   ├── modules/
│   │   ├── ecs_cluster/     # Shared cluster and execution role
│   │   ├── ecs/             # Service-specific resources
│   │   └── ecs_one_shot/    # One-shot task execution
│   └── properties.dev.json # Environment configuration
├── ssm-examples.json     # SSM parameter examples
└── README.md             # This file
```
