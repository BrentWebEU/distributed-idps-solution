#!/bin/bash

# Deploy Raspberry Pi IDPS with VPS backend integration
# This script deploys the optimized Raspberry Pi configuration that connects to VPS services

set -e

echo "=== Deploying Raspberry Pi IDPS with VPS Backend ==="

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    echo "Warning: This script is designed for Raspberry Pi. Continuing anyway..."
fi

# Configuration
COMPOSE_FILE="docker-compose.raspi.yml"
VPS_IP="178.104.6.176"

# Environment variables
export MONGO_ROOT_PASSWORD=${MONGO_ROOT_PASSWORD:-SecurePassword123!}
export REDIS_PASSWORD=${REDIS_PASSWORD:-RedisSecure123!}
export PI_IP=${PI_IP:-$(hostname -I | awk '{print $1}')}

echo "Configuration:"
echo "- VPS IP: $VPS_IP"
echo "- Raspberry Pi IP: $PI_IP"
echo "- Compose File: $COMPOSE_FILE"

# Test VPS connectivity
echo "Testing VPS connectivity..."
if ! ping -c 3 $VPS_IP >/dev/null 2>&1; then
    echo "ERROR: Cannot reach VPS at $VPS_IP"
    echo "Please check your network connection and VPS status"
    exit 1
fi

# Test VPS MongoDB connection
echo "Testing VPS MongoDB connection..."
if ! nc -z $VPS_IP 27017 2>/dev/null; then
    echo "WARNING: Cannot connect to VPS MongoDB (port 27017)"
    echo "Please ensure MongoDB is running on the VPS"
fi

# Test VPS Redis connection
echo "Testing VPS Redis connection..."
if ! nc -z $VPS_IP 6379 2>/dev/null; then
    echo "WARNING: Cannot connect to VPS Redis (port 6379)"
    echo "Please ensure Redis is running on the VPS"
fi

# Create necessary directories
echo "Creating data directories..."
mkdir -p data/{suricata/{rules,logs},logs/{network-filter,ids-pi},config/{suricata,ids-pi},scans/ids-pi}
mkdir -p data/{mongodb,redis,elasticsearch,prometheus,grafana}
chmod 755 data/{suricata,logs,config,scans,mongodb,redis,elasticsearch,prometheus,grafana}

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

# Stop existing containers
echo "Stopping existing containers..."
$DOCKER_COMPOSE -f $COMPOSE_FILE down --remove-orphans || true

# Pull latest images
echo "Pulling latest images..."
$DOCKER_COMPOSE -f $COMPOSE_FILE pull

# Build custom services
echo "Building custom services..."
$DOCKER_COMPOSE -f $COMPOSE_FILE build

# Start services
echo "Starting IDPS services..."
$DOCKER_COMPOSE -f $COMPOSE_FILE up -d

# Wait for services to start
echo "Waiting for services to start..."
sleep 30

# Check service status
echo "Checking service status..."
$DOCKER_COMPOSE -f $COMPOSE_FILE ps

# Test local services
echo "Testing local services..."

# Test network-filter
if curl -f http://localhost:8092/health >/dev/null 2>&1; then
    echo "✓ Network Filter is healthy"
else
    echo "✗ Network Filter is not responding"
fi

# Test rule-engine
if curl -f http://localhost:8094/health >/dev/null 2>&1; then
    echo "✓ Rule Engine is healthy"
else
    echo "✗ Rule Engine is not responding"
fi

# Test raspi-collector
if curl -f http://localhost:8080/health >/dev/null 2>&1; then
    echo "✓ Raspi Collector is healthy"
else
    echo "✗ Raspi Collector is not responding"
fi

# Test dashboard
if curl -f http://localhost >/dev/null 2>&1; then
    echo "✓ Pi Dashboard is accessible"
else
    echo "✗ Pi Dashboard is not accessible"
fi

echo ""
echo "=== Deployment Summary ==="
echo "Raspberry Pi IDPS services are now running"
echo "All data is stored on VPS at $VPS_IP"
echo ""
echo "Local Services:"
echo "- Network Filter: http://localhost:8092"
echo "- Rule Engine: http://localhost:8094"
echo "- Raspi Collector: http://localhost:8080"
echo "- Pi Dashboard: http://localhost"
echo "- Node Exporter: http://localhost:9100"
echo ""
echo "VPS Services:"
echo "- MongoDB: $VPS_IP:27017"
echo "- Redis: $VPS_IP:6379"
echo ""
echo "To view logs: $DOCKER_COMPOSE -f $COMPOSE_FILE logs -f [service-name]"
echo "To stop services: $DOCKER_COMPOSE -f $COMPOSE_FILE down"
echo ""
echo "=== Deployment completed ==="
