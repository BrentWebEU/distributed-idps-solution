#!/bin/bash

# Deploy VPS IDPS services with database backend
# This script deploys the VPS configuration that provides database and API services for Raspberry Pi

set -e

echo "=== Deploying VPS IDPS Services ==="

# Configuration
COMPOSE_FILE="docker-compose.yml"
VPS_IP=${VPS_IP:-$(curl -s ifconfig.me)}
RASPI_IP=${RASPI_IP:-""}

echo "Configuration:"
echo "- VPS IP: $VPS_IP"
echo "- Compose File: $COMPOSE_FILE"
if [ -n "$RASPI_IP" ]; then
    echo "- Expected Raspberry Pi IP: $RASPI_IP"
fi

# Environment variables
export MONGO_INITDB_ROOT_USERNAME=${MONGO_INITDB_ROOT_USERNAME:-admin}
export MONGO_INITDB_ROOT_PASSWORD=${MONGO_INITDB_ROOT_PASSWORD:-SecurePassword123!}
export REDIS_PASSWORD=${REDIS_PASSWORD:-RedisSecure123!}

# Check system requirements
echo "Checking system requirements..."

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed"
    exit 1
fi

# Check Docker Compose
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE="docker-compose"
elif docker compose version &> /dev/null; then
    DOCKER_COMPOSE="docker compose"
else
    echo "ERROR: Docker Compose is not installed"
    echo "Please install either docker-compose or docker compose plugin"
    exit 1
fi

echo "Using: $DOCKER_COMPOSE"

# Check available memory
AVAILABLE_MEM=$(free -m | awk 'NR==2{printf "%.0f", $7}')
if [ "$AVAILABLE_MEM" -lt 2048 ]; then
    echo "WARNING: Less than 2GB available memory ($AVAILABLE_MEM MB)"
    echo "Consider upgrading VPS for better performance"
fi

# Check available disk space
AVAILABLE_DISK=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE_DISK" -lt 10 ]; then
    echo "WARNING: Less than 10GB available disk space ($AVAILABLE_DISK GB)"
    echo "Consider upgrading storage for log retention"
fi

# Create necessary directories
echo "Creating data directories..."
mkdir -p logs/{suricata,network-filter,api,log-processor}
mkdir -p data/{mongodb,redis,suricata/{rules,logs},scans}
mkdir -p config/{suricata,api,nginx}
chmod 755 data logs config

# Set proper permissions for Suricata
echo "Setting permissions for Suricata..."
sudo mkdir -p /var/log/suricata 2>/dev/null || true
sudo chown -R $USER:$USER logs 2>/dev/null || true

# Stop existing containers
echo "Stopping existing containers..."
$DOCKER_COMPOSE -f $COMPOSE_FILE down --remove-orphans || true

# Clean up old networks
echo "Cleaning up old networks..."
docker network rm idps-network 2>/dev/null || true

# Pull latest images
echo "Pulling latest images..."
$DOCKER_COMPOSE -f $COMPOSE_FILE pull

# Build custom services
echo "Building custom services..."
$DOCKER_COMPOSE -f $COMPOSE_FILE build

# Start core services first (databases)
echo "Starting database services..."
$DOCKER_COMPOSE -f $COMPOSE_FILE up -d mongo redis

# Wait for databases to be ready
echo "Waiting for databases to be ready..."
sleep 30

# Check database health
echo "Checking database health..."

# MongoDB
if docker exec idps-mongo mongosh --eval "db.adminCommand('ping')" >/dev/null 2>&1; then
    echo "✓ MongoDB is healthy"
else
    echo "✗ MongoDB is not responding"
fi

# Redis
if docker exec idps-redis redis-cli ping >/dev/null 2>&1; then
    echo "✓ Redis is healthy"
else
    echo "✗ Redis is not responding"
fi

# Start remaining services
echo "Starting remaining services..."
$DOCKER_COMPOSE -f $COMPOSE_FILE up -d

# Wait for all services to start
echo "Waiting for services to start..."
sleep 30

# Check service status
echo "Checking service status..."
$DOCKER_COMPOSE -f $COMPOSE_FILE ps

# Test service endpoints
echo "Testing service endpoints..."

# Test MongoDB
if nc -z localhost 27017 >/dev/null 2>&1; then
    echo "✓ MongoDB is accessible on port 27017"
else
    echo "✗ MongoDB is not accessible"
fi

# Test Redis
if nc -z localhost 6379 >/dev/null 2>&1; then
    echo "✓ Redis is accessible on port 6379"
else
    echo "✗ Redis is not accessible"
fi

# Test Mock API
if curl -f http://localhost:8081/api/status >/dev/null 2>&1; then
    echo "✓ Mock API is accessible"
else
    echo "✗ Mock API is not accessible"
fi

# Test Log Processor
if curl -f http://localhost:8095/health >/dev/null 2>&1; then
    echo "✓ Log Processor is accessible"
else
    echo "✗ Log Processor is not accessible"
fi

# Test Angular Dashboard
if curl -f http://localhost >/dev/null 2>&1; then
    echo "✓ Angular Dashboard is accessible"
else
    echo "✗ Angular Dashboard is not accessible"
fi

# Test Suricata
if docker exec suricata-vps suricata --version >/dev/null 2>&1; then
    echo "✓ Suricata is running"
else
    echo "✗ Suricata is not responding"
fi

# Test Raspberry Pi connectivity if IP provided
if [ -n "$RASPI_IP" ]; then
    echo "Testing Raspberry Pi connectivity..."
    if ping -c 3 $RASPI_IP >/dev/null 2>&1; then
        echo "✓ Raspberry Pi at $RASPI_IP is reachable"
        
        # Test if Raspberry Pi services are accessible
        if curl -f http://$RASPI_IP:8080/health >/dev/null 2>&1; then
            echo "✓ Raspberry Pi Collector is accessible"
        else
            echo "✗ Raspberry Pi Collector is not accessible"
        fi
    else
        echo "✗ Raspberry Pi at $RASPI_IP is not reachable"
    fi
fi

# Configure firewall if needed
echo "Configuring firewall..."
if command -v ufw &> /dev/null; then
    sudo ufw allow 27017/tcp >/dev/null 2>&1 || true  # MongoDB
    sudo ufw allow 6379/tcp >/dev/null 2>&1 || true   # Redis
    sudo ufw allow 80/tcp >/dev/null 2>&1 || true     # HTTP
    sudo ufw allow 8081/tcp >/dev/null 2>&1 || true   # Mock API
    sudo ufw allow 8095/tcp >/dev/null 2>&1 || true   # Log Processor
    echo "✓ Firewall rules configured (ufw)"
elif command -v firewall-cmd &> /dev/null; then
    sudo firewall-cmd --permanent --add-port=27017/tcp >/dev/null 2>&1 || true
    sudo firewall-cmd --permanent --add-port=6379/tcp >/dev/null 2>&1 || true
    sudo firewall-cmd --permanent --add-port=80/tcp >/dev/null 2>&1 || true
    sudo firewall-cmd --permanent --add-port=8081/tcp >/dev/null 2>&1 || true
    sudo firewall-cmd --permanent --add-port=8095/tcp >/dev/null 2>&1 || true
    sudo firewall-cmd --reload >/dev/null 2>&1 || true
    echo "✓ Firewall rules configured (firewalld)"
fi

echo ""
echo "=== VPS Deployment Summary ==="
echo "VPS IDPS services are now running"
echo "VPS IP: $VPS_IP"
echo ""
echo "Database Services:"
echo "- MongoDB: localhost:27017 (or $VPS_IP:27017)"
echo "- Redis: localhost:6379 (or $VPS_IP:6379)"
echo ""
echo "API Services:"
echo "- Mock API: http://localhost:8081 (or http://$VPS_IP:8081)"
echo "- Log Processor: http://localhost:8095 (or http://$VPS_IP:8095)"
echo ""
echo "Web Interface:"
echo "- Angular Dashboard: http://localhost (or http://$VPS_IP)"
echo ""
echo "Security Services:"
echo "- Suricata IDS/IPS: Running on host network"
echo ""
echo "To view logs: $DOCKER_COMPOSE -f $COMPOSE_FILE logs -f [service-name]"
echo "To stop services: $DOCKER_COMPOSE -f $COMPOSE_FILE down"
echo "To restart services: $DOCKER_COMPOSE -f $COMPOSE_FILE restart"
echo ""
echo "=== VPS Deployment completed ==="

# Show resource usage
echo ""
echo "Resource Usage:"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
