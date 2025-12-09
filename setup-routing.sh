#!/bin/bash
# Ephemeral VPN Routing Setup Script
# This script helps configure system routing for full traffic VPN

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TUN_INTERFACE="tun0"
TUN_IP="10.0.0.2"
TUN_GATEWAY="10.0.0.1"
BACKUP_FILE="/tmp/vpn-routing-backup.txt"

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (sudo)"
        exit 1
    fi
}

backup_routing() {
    log "Backing up current routing configuration..."
    {
        echo "# VPN Routing Backup - $(date)"
        echo "# Original default route:"
        ip route show default
        echo "# Original iptables rules:"
        iptables-save
        echo "# DNS configuration:"
        cat /etc/resolv.conf
    } > "$BACKUP_FILE"

    log "Backup saved to: $BACKUP_FILE"
}

restore_routing() {
    if [[ ! -f "$BACKUP_FILE" ]]; then
        warning "No backup file found at $BACKUP_FILE"
        return 1
    fi

    log "Restoring original routing configuration..."

    # Extract and restore default route
    DEFAULT_ROUTE=$(grep "^default" "$BACKUP_FILE" | head -1)
    if [[ -n "$DEFAULT_ROUTE" ]]; then
        # Remove current default routes first
        ip route del default 2>/dev/null || true
        # Add back original default route
        eval "ip route add $DEFAULT_ROUTE"
    fi

    # Remove TUN interface routes
    ip route del 10.0.0.0/24 dev "$TUN_INTERFACE" 2>/dev/null || true

    # Bring down TUN interface
    ip link set "$TUN_INTERFACE" down 2>/dev/null || true

    log "Original routing restored"
}

setup_vpn_routing() {
    log "Setting up VPN routing..."

    # Check if TUN interface exists
    if ! ip link show "$TUN_INTERFACE" >/dev/null 2>&1; then
        log "TUN interface $TUN_INTERFACE does not exist. It will be created by the VPN client."
        return 0
    fi

    # Remove any existing default routes through TUN
    ip route del default dev "$TUN_INTERFACE" 2>/dev/null || true

    # Add VPN subnet route
    ip route add 10.0.0.0/24 dev "$TUN_INTERFACE" 2>/dev/null || true

    log "VPN routing configured"
}

show_current_routing() {
    info "Current routing table:"
    ip route show
    echo
    info "Current iptables rules:"
    iptables -t nat -L -n | head -10
    echo
    info "Network interfaces:"
    ip addr show
}

test_connectivity() {
    local proxy_host=$1
    local proxy_port=$2

    info "Testing connectivity to VPN proxy server..."

    if timeout 5 bash -c "echo >/dev/tcp/$proxy_host/$proxy_port" 2>/dev/null; then
        log "✓ Can connect to $proxy_host:$proxy_port"
        return 0
    else
        error "✗ Cannot connect to $proxy_host:$proxy_port"
        warning "Make sure the VPN proxy server is running and accessible"
        return 1
    fi
}

show_usage() {
    cat << EOF
Ephemeral VPN Routing Setup Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    backup          Backup current routing configuration
    restore         Restore routing from backup
    setup           Set up routing for VPN (run before starting VPN client)
    show            Show current routing and network configuration
    test HOST PORT  Test connectivity to VPN proxy server
    start HOST PORT Start VPN client with routing setup
    help            Show this help message

Examples:
    sudo $0 backup
    sudo $0 setup
    sudo $0 test vpn.example.com 3128
    sudo $0 start vpn.example.com 3128

The VPN client will:
1. Create a TUN device ($TUN_INTERFACE)
2. Set up routing to capture ALL traffic
3. Tunnel traffic through HTTP CONNECT to proxy server

WARNING: This routes ALL internet traffic through the VPN!
EOF
}

main() {
    case "${1:-help}" in
        backup)
            check_root
            backup_routing
            ;;
        restore)
            check_root
            restore_routing
            ;;
        setup)
            check_root
            setup_vpn_routing
            ;;
        show)
            show_current_routing
            ;;
        test)
            if [[ $# -lt 3 ]]; then
                error "Usage: $0 test HOST PORT"
                exit 1
            fi
            test_connectivity "$2" "$3"
            ;;
        start)
            if [[ $# -lt 3 ]]; then
                error "Usage: $0 start HOST PORT [API_KEY]"
                exit 1
            fi
            check_root
            backup_routing
            setup_vpn_routing

            if [[ $# -ge 4 ]]; then
                export VPN_API_KEY="$4"
            fi

            log "Starting VPN client..."
            log "Press Ctrl+C to stop VPN and restore routing"

            # Start VPN client
            python3 vpn-client.py "$2" "$3"

            # This runs after VPN client exits (Ctrl+C)
            log "VPN client stopped, restoring routing..."
            restore_routing
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            error "Unknown command: $1"
            echo
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
