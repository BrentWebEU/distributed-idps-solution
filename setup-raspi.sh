#!/bin/bash
#
# IDPS Raspberry Pi Setup Script
# Based on architecture docs: ARCHITECTURE.md, SETUP.md, raspberry-pi-bridge-setup.md
#
# This script sets up the complete IDPS edge infrastructure on a Raspberry Pi
# including network bridge configuration, Docker services, and Suricata IDS/IPS.
#
# Prerequisites:
#   - Raspberry Pi 4B (4GB+ RAM recommended)
#   - Two ethernet interfaces (eth0 + eth1 or USB adapter)
#   - Raspberry Pi OS (64-bit) or Ubuntu Server ARM64
#   - Internet connection
#
# Usage: sudo ./setup-raspberry-pi.sh [VPS_IP]
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IDPS_DIR="/opt/idps"
DATA_DIR="${IDPS_DIR}/data"
LOGS_DIR="${IDPS_DIR}/logs"
CONFIG_DIR="${IDPS_DIR}/config"
VPS_IP="${1:-}"  # Can be passed as argument or set in .env
BRIDGE_IP="192.168.100.1"
BRIDGE_NETMASK="255.255.255.0"

# Service ports (for verification)
declare -A SERVICE_PORTS=(
    ["mongodb"]=27017
    ["redis"]=6379
    ["network-filter"]=8092
    ["raspi-collector"]=8091
    ["ids-pi"]=8081
    ["telemetry"]=8096
    ["node-exporter"]=9100
    ["pi-dashboard"]=80
)

# Logging
LOG_FILE="/var/log/idps-setup.log"
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }
warn() { log "WARN" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }

# =============================================================================
# PREREQUISITE CHECKS
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_architecture() {
    info "Checking system architecture..."
    ARCH=$(uname -m)
    if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" && "$ARCH" != "armv7l" ]]; then
        warn "Architecture is $ARCH. This script is optimized for ARM64 (aarch64)"
        warn "Continuing anyway, but you may encounter issues."
    else
        success "Architecture check passed: $ARCH"
    fi
}

check_network_interfaces() {
    info "Checking network interfaces..."
    
    # Check for eth0
    if ! ip link show eth0 &>/dev/null; then
        warn "eth0 not found. Available interfaces:"
        ip link show | grep "^[0-9]" | awk '{print $2}' | tr -d ':'
        error "eth0 is required for WAN connection"
        exit 1
    fi
    
    # Check for eth1 or alternative
    if ip link show eth1 &>/dev/null; then
        success "Found eth1 for LAN connection"
        LAN_IFACE="eth1"
    else
        # Look for USB ethernet or second interface
        LAN_IFACE=$(ip link show | grep "^[0-9]" | awk '{print $2}' | tr -d ':' | grep -v "lo\|eth0\|docker\|br0" | head -1)
        if [[ -n "$LAN_IFACE" ]]; then
            warn "eth1 not found, using $LAN_IFACE as LAN interface"
        else
            warn "No second ethernet interface found. You need:"
            warn "  - eth0: Connected to modem/router (WAN)"
            warn "  - eth1 or USB ethernet: Connected to switch/AP (LAN)"
            warn "Continuing setup, but bridge configuration may fail."
        fi
    fi
    
    success "Network interface check completed"
}

check_internet() {
    info "Checking internet connectivity..."
    if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        success "Internet connectivity verified"
    else
        warn "No internet connectivity detected"
        warn "Some services may not install properly"
    fi
}

# =============================================================================
# SYSTEM PREPARATION
# =============================================================================

install_docker() {
    info "Installing Docker..."
    
    if command -v docker &>/dev/null; then
        success "Docker is already installed: $(docker --version)"
    else
        info "Installing Docker using official script..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm -f get-docker.sh
        
        # Add current user to docker group
        usermod -aG docker "$SUDO_USER" 2>/dev/null || usermod -aG docker pi 2>/dev/null || true
        
        success "Docker installed successfully"
    fi
    
    # Start Docker service
    systemctl enable docker
    systemctl start docker
    
    # Install Docker Compose plugin
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        info "Installing Docker Compose..."
        apt-get update
        apt-get install -y docker-compose-plugin
        # Create compatibility symlink
        ln -sf /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose 2>/dev/null || true
    fi
    
    success "Docker Compose ready"
}

install_dependencies() {
    info "Installing system dependencies..."
    
    apt-get update
    apt-get install -y \
        bridge-utils \
        net-tools \
        iptables \
        iproute2 \
        curl \
        wget \
        git \
        vim \
        htop \
        tcpdump \
        jq \
        bc \
        netcat-openbsd
    
    success "System dependencies installed"
}

# =============================================================================
# NETWORK BRIDGE CONFIGURATION
# =============================================================================

setup_sysctl() {
    info "Configuring kernel parameters for bridge..."
    
    cat > /etc/sysctl.d/99-idps.conf << 'EOF'
# IDPS Bridge Configuration
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.conf.all.forwarding = 1

# Performance tuning
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF
    
    # Apply sysctl settings
    sysctl -p /etc/sysctl.d/99-idps.conf
    
    success "Kernel parameters configured"
}

setup_bridge() {
    info "Setting up network bridge (br0) with internet preservation..."
    
    # Determine LAN interface
    if ip link show eth1 &>/dev/null; then
        LAN_IFACE="eth1"
    else
        LAN_IFACE=$(ip link show | grep "^[0-9]" | awk '{print $2}' | tr -d ':' | grep -v "lo\|eth0\|docker\|br0" | head -1)
    fi
    
    if [[ -z "$LAN_IFACE" ]]; then
        error "No suitable LAN interface found for bridge"
        return 1
    fi
    
    # Store eth0 IP configuration before adding to bridge
    ETH0_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | head -1)
    ETH0_GW=$(ip route | grep default | awk '{print $3}' | head -1)
    
    info "Preserving eth0 IP: ${ETH0_IP:-DHCP}, Gateway: ${ETH0_GW:-DHCP}"
    
    # Create bridge if it doesn't exist
    if ! ip link show br0 &>/dev/null; then
        info "Creating bridge interface br0..."
        ip link add name br0 type bridge
    fi
    
    # Add interfaces to bridge
    ip link set eth0 master br0 2>/dev/null || warn "Could not add eth0 to bridge (may already be attached)"
    ip link set "$LAN_IFACE" master br0 2>/dev/null || warn "Could not add $LAN_IFACE to bridge"
    
    # Configure bridge
    ip link set br0 up
    
    # Restore IP configuration to bridge (preserves internet)
    if [[ -n "$ETH0_IP" ]]; then
        info "Restoring IP configuration to bridge..."
        ip addr add "$ETH0_IP" dev br0
    else
        # Use DHCP if no static IP was configured
        info "Using DHCP for bridge..."
        dhclient br0 || warn "dhclient failed, bridge may not have internet"
    fi
    
    # Add bridge management IP (different from restored IP)
    if [[ -n "$ETH0_IP" ]]; then
        # Add management IP as secondary
        ip addr add "${BRIDGE_IP}/${BRIDGE_NETMASK}" dev br0 2>/dev/null || true
    fi
    
    # Restore default route
    if [[ -n "$ETH0_GW" ]]; then
        ip route add default via "$ETH0_GW" dev br0 2>/dev/null || true
    fi
    
    success "Bridge br0 configured with internet preservation"
    info "Bridge interfaces: eth0 (WAN), $LAN_IFACE (LAN)"
    info "Bridge IP: ${ETH0_IP:-DHCP}, Management IP: $BRIDGE_IP"
}

setup_bridge_systemd() {
    info "Configuring bridge with systemd-networkd..."
    
    # Determine LAN interface
    if ip link show eth1 &>/dev/null; then
        LAN_IFACE="eth1"
    else
        LAN_IFACE=$(ip link show | grep "^[0-9]" | awk '{print $2}' | tr -d ':' | grep -v "lo\|eth0\|docker\|br0" | head -1)
    fi
    
    [[ -z "$LAN_IFACE" ]] && return 1
    
    mkdir -p /etc/systemd/network/
    
    # Bridge netdev
    cat > /etc/systemd/network/10-br0.netdev << EOF
[NetDev]
Name=br0
Kind=bridge
EOF
    
    # Bridge network
    cat > /etc/systemd/network/20-br0.network << EOF
[Match]
Name=br0

[Network]
Address=${BRIDGE_IP}/24
DHCP=no
EOF
    
    # eth0 network (WAN)
    cat > /etc/systemd/network/30-eth0.network << EOF
[Match]
Name=eth0

[Network]
Bridge=br0
EOF
    
    # LAN interface network
    cat > /etc/systemd/network/40-${LAN_IFACE}.network << EOF
[Match]
Name=${LAN_IFACE}

[Network]
Bridge=br0
EOF
    
    # Enable and restart systemd-networkd
    systemctl enable systemd-networkd
    systemctl restart systemd-networkd
    
    success "systemd-networkd bridge configuration applied"
}

verify_internet_after_bridge() {
    info "Verifying internet connectivity after bridge setup..."
    
    # Wait a moment for interfaces to settle
    sleep 3
    
    # Test connectivity
    if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
        success "Internet connectivity preserved through bridge"
        return 0
    else
        warn "Internet connectivity lost after bridge setup"
        warn "Attempting to restore connectivity..."
        
        # Try to restore with DHCP
        dhclient br0 &>/dev/null || true
        sleep 2
        
        if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
            success "Internet connectivity restored with DHCP"
            return 0
        else
            error "Could not restore internet connectivity"
            error "You may need to manually configure network or run:"
            error "  sudo dhclient br0"
            error "  Or check your router's DHCP settings"
            return 1
        fi
    fi
}

setup_iptables() {
    info "Setting up iptables rules for bridge..."
    
    # Create iptables setup script
    cat > /usr/local/bin/setup-bridge-iptables.sh << 'EOF'
#!/bin/bash
# IDPS Bridge iptables rules

# Enable forwarding
iptables -A FORWARD -i br0 -o br0 -j ACCEPT
iptables -A FORWARD -i eth0 -o br0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i br0 -o eth0 -j ACCEPT

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
iptables -A INPUT -i lo -j ACCEPT

# Allow SSH (port 22)
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow IDPS services
iptables -A INPUT -p tcp --dport 80 -j ACCEPT      # Dashboard
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT    # API
iptables -A INPUT -p tcp --dport 8091 -j ACCEPT  # Collector
iptables -A INPUT -p tcp --dport 8092 -j ACCEPT  # Network Filter
iptables -A INPUT -p tcp --dport 27017 -j ACCEPT # MongoDB (local only recommended)

# Default drop (optional - uncomment for strict mode)
# iptables -A INPUT -j DROP
EOF
    chmod +x /usr/local/bin/setup-bridge-iptables.sh
    
    # Create cleanup script
    cat > /usr/local/bin/cleanup-bridge-iptables.sh << 'EOF'
#!/bin/bash
# Cleanup IDPS bridge iptables rules
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
EOF
    chmod +x /usr/local/bin/cleanup-bridge-iptables.sh
    
    # Apply rules
    /usr/local/bin/setup-bridge-iptables.sh
    
    # Make persistent
    if command -v netfilter-persistent &>/dev/null; then
        netfilter-persistent save
    else
        apt-get install -y iptables-persistent
    fi
    
    success "iptables rules configured"
}

# =============================================================================
# IDPS DIRECTORY STRUCTURE
# =============================================================================

setup_directories() {
    info "Creating IDPS directory structure..."
    
    # Create base directories
    mkdir -p "${IDPS_DIR}"
    mkdir -p "${DATA_DIR}"/{mongodb,redis,suricata/rules,suricata/logs}
    mkdir -p "${LOGS_DIR}"/{network-filter,raspi-collector,ids-pi,suricata}
    mkdir -p "${CONFIG_DIR}"/{suricata,ids-pi}
    
    # Create Suricata rules directory with empty dynamic rules file
    touch "${DATA_DIR}/suricata/rules/idps-dynamic.rules"
    
    # Set permissions
    chown -R "${SUDO_USER:-root}:${SUDO_USER:-root}" "${IDPS_DIR}" 2>/dev/null || true
    chmod -R 755 "${IDPS_DIR}"
    
    success "Directory structure created at ${IDPS_DIR}"
}

# =============================================================================
# CONFIGURATION FILES
# =============================================================================

generate_env_file() {
    info "Generating environment configuration..."
    
    # Get VPS IP if not provided
    if [[ -z "$VPS_IP" ]]; then
        read -rp "Enter VPS IP address (e.g., 178.104.6.176): " VPS_IP
    fi
    
    if [[ -z "$VPS_IP" ]]; then
        warn "No VPS IP provided. Using placeholder - you must update .env manually"
        VPS_IP="YOUR_VPS_IP"
    fi
    
    # Generate .env file
    cat > "${IDPS_DIR}/.env" << EOF
# IDPS Raspberry Pi Environment Configuration
# Generated on $(date)

# =============================================================================
# DATABASE
# =============================================================================
MONGO_ROOT_PASSWORD=SecurePassword123!
MONGODB_URI=mongodb://admin:SecurePassword123!@localhost:27017/idps_database?authSource=admin

REDIS_PASSWORD=RedisSecure123!
REDIS_URL=redis://:RedisSecure123!@localhost:6379

# =============================================================================
# AUTHENTICATION
# =============================================================================
API_KEY=your-api-key-here
VPS_API_KEY=your-api-key-here

# =============================================================================
# CONNECTIVITY — VPS ↔ Raspberry Pi
# =============================================================================
VPS_IP=${VPS_IP}
VPS_API_URL=http://${VPS_IP}:8080
VPS_URL=http://${VPS_IP}:8080
VPS_ENDPOINT=http://${VPS_IP}:8080
VPS_PROCESSOR_URL=http://${VPS_IP}:8080
VPS_WS_URL=ws://${VPS_IP}:8080/ws/raspi
VPS_PACKETS_WS_URL=ws://${VPS_IP}:8080/ws/packets
PACKET_STREAM_WS_URL=ws://${VPS_IP}:8080/ws/packets

# =============================================================================
# NETWORK / PACKET CAPTURE
# =============================================================================
CAPTURE_INTERFACE=eth0
PCAP_INTERFACE=eth0
RASPI_INTERFACE=eth0
NETWORK_INTERFACE=eth0
HOST_NETNS_PATH=/host_proc/1/ns/net

# =============================================================================
# SURICATA
# =============================================================================
EVE_JSON_PATH=/var/log/suricata/eve.json
SURICATA_EVE_PATH=/var/log/suricata/eve.json
SURICATA_CUSTOM_RULES=/etc/suricata/rules/idps-custom.rules

# =============================================================================
# DETECTION & BLOCKING
# =============================================================================
AUTO_BLOCK_ENABLED=false
DEFAULT_BLOCK_DURATION_HOURS=24
TTL_CLEANUP_INTERVAL_SECS=300
MAX_PACKETS_PER_SECOND=10000
RATE_LIMITING_ENABLED=true

# =============================================================================
# TELEMETRY SERVICE
# =============================================================================
DEVICE_ID=raspi-edge-$(hostname)
COLLECTION_INTERVAL_SECS=10
TELEMETRY_PORT=8096

# =============================================================================
# LOGGING
# =============================================================================
RUST_LOG=info
LOG_LEVEL=info
EOF
    
    success "Environment file created at ${IDPS_DIR}/.env"
    info "IMPORTANT: Review and update passwords in ${IDPS_DIR}/.env before production use"
}

copy_config_files() {
    info "Copying configuration files..."
    
    # Check if we're running from the repo
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Skip copying if we're already in the target directory
    if [[ "$SCRIPT_DIR" == "$IDPS_DIR" ]]; then
        info "Already in target directory, skipping config file copy"
        return 0
    fi
    
    if [[ -f "${SCRIPT_DIR}/config/suricata/suricata.yaml" ]]; then
        # Running from repo
        REPO_DIR="$SCRIPT_DIR"
    elif [[ -f "${SCRIPT_DIR}/suricata.yaml" ]]; then
        # Running from repo root
        REPO_DIR="$SCRIPT_DIR"
    else
        warn "Could not find repository config files"
        warn "You may need to manually copy configuration files"
        return 0
    fi
    
    # Copy Suricata config
    if [[ -f "${REPO_DIR}/config/suricata/suricata.yaml" ]]; then
        cp "${REPO_DIR}/config/suricata/suricata.yaml" "${CONFIG_DIR}/suricata/"
        success "Suricata configuration copied"
    fi
    
    # Copy nginx config
    if [[ -f "${REPO_DIR}/config/nginx/pi-nginx.conf" ]]; then
        cp "${REPO_DIR}/config/nginx/pi-nginx.conf" "${CONFIG_DIR}/nginx.conf"
        success "Nginx configuration copied"
    fi
    
    # Copy mongo-init.js if exists
    if [[ -f "${REPO_DIR}/ops/scripts/mongo-init.js" ]]; then
        cp "${REPO_DIR}/ops/scripts/mongo-init.js" "${IDPS_DIR}/"
        success "MongoDB initialization script copied"
    fi
}

# =============================================================================
# DOCKER SERVICES
# =============================================================================

setup_docker_compose() {
    info "Setting up Docker Compose configuration..."
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # Check for docker-compose.raspi.yml in repo
    if [[ -f "${SCRIPT_DIR}/docker-compose.raspi.yml" ]]; then
        cp "${SCRIPT_DIR}/docker-compose.raspi.yml" "${IDPS_DIR}/docker-compose.yml"
        success "Docker Compose file copied"
    else
        warn "docker-compose.raspi.yml not found in repository"
        warn "You need to manually copy it to ${IDPS_DIR}/docker-compose.yml"
    fi
}

pull_images() {
    info "Pulling required Docker images..."
    
    cd "${IDPS_DIR}"
    
    # Pull base images that don't need building
    docker pull mongodb/mongodb-community-server:4.4.3-ubuntu2004
    docker pull redis:7.2-alpine
    docker pull jasonish/suricata:latest
    docker pull prom/node-exporter:latest
    docker pull arm64v8/nginx:alpine
    
    success "Base images pulled"
}

build_services() {
    info "Building IDPS services..."
    
    cd "${IDPS_DIR}"
    
    if [[ -f "docker-compose.yml" ]]; then
        # Build the services (this may take a while on Pi)
        export DOCKER_BUILDKIT=1
        docker compose build --parallel 2>/dev/null || docker compose build
        success "Services built successfully"
    else
        warn "No docker-compose.yml found. Skipping build."
    fi
}

start_services() {
    info "Starting IDPS services..."
    
    cd "${IDPS_DIR}"
    
    if [[ ! -f "docker-compose.yml" ]]; then
        error "docker-compose.yml not found"
        return 1
    fi
    
    # Start MongoDB first (for initialization)
    info "Starting MongoDB..."
    docker compose up -d mongodb
    
    # Wait for MongoDB
    info "Waiting for MongoDB to be ready..."
    sleep 15
    
    # Start Redis
    info "Starting Redis..."
    docker compose up -d redis
    
    # Start remaining services
    info "Starting all services..."
    docker compose up -d
    
    success "All services started"
}

# =============================================================================
# VERIFICATION
# =============================================================================

verify_services() {
    info "Verifying service status..."
    
    cd "${IDPS_DIR}"
    
    # Check container status
    info "Container status:"
    docker compose ps
    
    # Test each service
    local failed=0
    
    # MongoDB
    if docker exec idps-mongodb-pi mongosh --eval "db.adminCommand('ping')" &>/dev/null; then
        success "MongoDB is responding"
    else
        warn "MongoDB check failed"
        ((failed++))
    fi
    
    # Redis
    if docker exec idps-redis-pi redis-cli ping | grep -q "PONG"; then
        success "Redis is responding"
    else
        warn "Redis check failed"
        ((failed++))
    fi
    
    # Suricata logs
    if docker logs idps-suricata-pi --tail 5 2>/dev/null | grep -q "Suricata"; then
        success "Suricata is running"
    else
        warn "Suricata check failed (may need more time to start)"
    fi
    
    # Network Filter
    if curl -s http://localhost:8092/health &>/dev/null; then
        success "Network Filter API is responding"
    else
        warn "Network Filter not yet responding"
    fi
    
    # Check eve.json generation
    sleep 5
    if [[ -f "${DATA_DIR}/logs/suricata/eve.json" ]]; then
        local eve_count=$(wc -l < "${DATA_DIR}/logs/suricata/eve.json" 2>/dev/null || echo "0")
        success "Suricata eve.json exists with ${eve_count} lines"
    else
        warn "eve.json not yet generated (Suricata may still be initializing)"
    fi
    
    return $failed
}

# =============================================================================
# MONITORING & MAINTENANCE
# =============================================================================

setup_monitoring() {
    info "Setting up monitoring..."
    
    # Create monitoring script
    cat > /usr/local/bin/idps-status << 'EOF'
#!/bin/bash
# IDPS Status Check Script

IDPS_DIR="/opt/idps"
cd "$IDPS_DIR" 2>/dev/null || { echo "IDPS directory not found"; exit 1; }

echo "=== IDPS Raspberry Pi Status ==="
echo "Date: $(date)"
echo ""

echo "=== Docker Containers ==="
docker compose ps

echo ""
echo "=== Bridge Interface ==="
ip addr show br0 2>/dev/null || echo "br0 not configured"

echo ""
echo "=== Suricata Logs (last 5 lines) ==="
tail -n 5 "${IDPS_DIR}/data/logs/suricata/eve.json" 2>/dev/null || echo "eve.json not found"

echo ""
echo "=== Service Endpoints ==="
curl -s http://localhost:8092/health 2>/dev/null && echo "Network Filter: OK" || echo "Network Filter: Not responding"
echo ""
echo "=== System Resources ==="
free -h | grep Mem
df -h | grep -E '^/dev'
EOF
    chmod +x /usr/local/bin/idps-status
    
    # Create log rotation config
    cat > /etc/logrotate.d/idps << EOF
${IDPS_DIR}/logs/**/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}

${DATA_DIR}/logs/suricata/*.json {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    size 100M
}
EOF
    
    success "Monitoring tools configured"
}

create_systemd_service() {
    info "Creating systemd service for IDPS..."
    
    cat > /etc/systemd/system/idps.service << EOF
[Unit]
Description=IDPS Raspberry Pi Services
Requires=docker.service
After=docker.service network.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${IDPS_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable idps.service
    
    success "IDPS systemd service created and enabled"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

show_banner() {
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                     IDPS Raspberry Pi Setup Script                        ║
║                                                                           ║
║  This script will configure your Raspberry Pi as an IDPS edge node:       ║
║                                                                           ║
║  1. Install Docker and dependencies                                       ║
║  2. Configure network bridge (eth0 + eth1 → br0)                         ║
║  3. Setup Suricata IDS/IPS                                                ║
║  4. Deploy edge services (MongoDB, Redis, Network Filter, etc.)          ║
║  5. Configure iptables rules                                              ║
║                                                                           ║
║  Network Topology:                                                        ║
║    [Internet] → [eth0] → [br0 Bridge] → [eth1] → [Router/Switch]         ║
║                              ↓                                            ║
║                        [Suricata Monitoring]                              ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
}

show_completion() {
    cat << EOF

╔═══════════════════════════════════════════════════════════════════════════╗
║                      Setup Complete!                                       ║
╚═══════════════════════════════════════════════════════════════════════════╝

IDPS has been installed at: ${IDPS_DIR}

Next Steps:
-----------
1. Review configuration:   nano ${IDPS_DIR}/.env
2. Check service status:   idps-status
3. View logs:              docker compose -f ${IDPS_DIR}/docker-compose.yml logs -f
4. Access dashboard:       http://${BRIDGE_IP}

Service Ports:
--------------
EOF
    
    for service in "${!SERVICE_PORTS[@]}"; do
        echo "  ${service}: Port ${SERVICE_PORTS[$service]}"
    done
    
    cat << EOF

Useful Commands:
----------------
  sudo idps-status              # Check IDPS status
  docker compose ps             # List containers
  docker logs -f idps-suricata-pi    # View Suricata logs
  tail -f ${DATA_DIR}/logs/suricata/eve.json  # View events
  sudo systemctl restart idps   # Restart all services

Files:
------
  Config:  ${CONFIG_DIR}
  Data:    ${DATA_DIR}
  Logs:    ${LOGS_DIR}

For support, refer to the documentation in the docs/ directory.

EOF
}

main() {
    show_banner
    
    # Phase 1: Prerequisites
    check_root
    check_architecture
    check_network_interfaces
    check_internet
    
    # Phase 2: System preparation
    install_dependencies
    install_docker
    
    # Phase 3: Network setup
    setup_sysctl
    setup_bridge || setup_bridge_systemd || warn "Bridge setup may require manual configuration"
    verify_internet_after_bridge || warn "Internet connectivity issues detected - check network configuration"
    setup_iptables
    
    # Phase 4: IDPS setup
    setup_directories
    generate_env_file
    copy_config_files
    setup_docker_compose
    
    # Phase 5: Deployment
    pull_images
    build_services
    start_services
    
    # Phase 6: Verification and monitoring
    verify_services
    setup_monitoring
    create_systemd_service
    
    show_completion
    
    success "Raspberry Pi IDPS setup complete!"
}

# Run main function
main "$@"
