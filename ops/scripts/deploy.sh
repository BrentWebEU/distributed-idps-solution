#!/bin/bash
# IDPS Unified Deployment Script
# Choose between VPS and Raspberry Pi deployment

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_vps() { echo -e "${CYAN}[VPS]${NC} $1"; }
log_raspi() { echo -e "${PURPLE}[RASPI]${NC} $1"; }

# Show deployment options
show_options() {
    echo "🚀 IDPS Deployment Options"
    echo "========================="
    echo
    echo "Choose your deployment environment:"
    echo
    echo "1) 🖥️  VPS Deployment"
    echo "   - Full-featured IDPS system"
    echo "   - Complete documentation center"
    echo "   - All services and monitoring"
    echo "   - Recommended for thesis presentation"
    echo
    echo "2) 🍓 Raspberry Pi Deployment"
    echo "   - Edge security monitoring"
    echo "   - Resource-optimized (512MB RAM)"
    echo "   - Lightweight services"
    echo "   - ARM64 optimized containers"
    echo
    echo "3) 🌐 Distributed Architecture"
    echo "   - Raspberry Pi + VPS integration"
    echo "   - Low-latency edge collection"
    echo "   - High-performance VPS processing"
    echo "   - Real-time rule distribution"
    echo
    echo "4) 📊 Current Status"
    echo "   - Check running services"
    echo "   - Show system information"
    echo
    echo "5) 🛑 Stop All Services"
    echo "   - Stop all deployment types"
    echo
    echo "6) ❓ Help"
    echo "   - Show detailed help information"
    echo
}

# Quick deployment for command line
quick_deploy() {
    local environment="${1:-vps}"
    
    case "$environment" in
        "vps"|"VPS")
            log_vps "Quick VPS deployment..."
            if [[ -f "./ops/scripts/deploy-vps.sh" ]]; then
                ./ops/scripts/deploy-vps.sh
            else
                log_error "VPS deployment script not found"
                exit 1
            fi
            ;;
        "raspi"|"raspberry"|"pi")
            log_raspi "Quick Raspberry Pi deployment..."
            if [[ -f "./ops/scripts/deploy-raspi.sh" ]]; then
                ./ops/scripts/deploy-raspi.sh
            else
                log_error "Raspberry Pi deployment script not found"
                exit 1
            fi
            ;;
        "distributed"|"dist"|"edge")
            log_info "Quick distributed deployment..."
            if [[ -f "./ops/scripts/deploy-distributed.sh" ]]; then
                ./ops/scripts/deploy-distributed.sh
            else
                log_error "Distributed deployment script not found"
                exit 1
            fi
            ;;
        *)
            log_error "Unknown environment: $environment"
            echo "Use: $0 deploy [vps|raspi|distributed]"
            exit 1
            ;;
    esac
}

# Main function
main() {
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        echo "Please install Docker and try again."
        exit 1
    fi
    
    # Check if we're in the right directory
    if [[ ! -f "docker-compose.yml" ]]; then
        log_error "Please run this script from the IDPS root directory"
        echo "Expected file: docker-compose.yml"
        exit 1
    fi
    
    # Handle command line arguments
    case "${1:-}" in
        "vps"|"VPS")
            quick_deploy "vps"
            ;;
        "raspi"|"raspberry"|"pi")
            quick_deploy "raspi"
            ;;
        "distributed"|"dist"|"edge")
            quick_deploy "distributed"
            ;;
        "deploy")
            quick_deploy "${2:-vps}"
            ;;
        "status"|"check")
            echo "📊 Current Status:"
            docker compose ps 2>/dev/null || echo "No VPS services running"
            if [[ -f "docker-compose.raspi.yml" ]]; then
                echo "🍓 Raspberry Pi:"
                docker compose -f docker-compose.raspi.yml ps 2>/dev/null || echo "No Raspberry Pi services running"
            fi
            if [[ -f "docker-compose.distributed.yml" ]]; then
                echo "🌐 Distributed:"
                docker compose -f docker-compose.distributed.yml ps 2>/dev/null || echo "No distributed services running"
            fi
            ;;
        "stop"|"down")
            echo "🛑 Stopping services..."
            docker compose down 2>/dev/null || true
            if [[ -f "docker-compose.raspi.yml" ]]; then
                docker compose -f docker-compose.raspi.yml down 2>/dev/null || true
            fi
            if [[ -f "docker-compose.distributed.yml" ]]; then
                docker compose -f docker-compose.distributed.yml down 2>/dev/null || true
            fi
            log_success "All services stopped"
            ;;
        "--help"|"-h"|"help")
            echo "IDPS Deployment Script"
            echo "====================="
            echo "Usage: $0 [vps|raspi|distributed|status|stop|help]"
            echo
            echo "Commands:"
            echo "  vps         - Deploy VPS environment (full-featured)"
            echo "  raspi       - Deploy Raspberry Pi environment (edge)"
            echo "  distributed - Deploy distributed architecture (Pi + VPS)"
            echo "  status      - Check current deployment status"
            echo "  stop        - Stop all services"
            echo "  help        - Show this help"
            echo
            echo "Examples:"
            echo "  $0 vps           # Deploy VPS environment"
            echo "  $0 raspi         # Deploy Raspberry Pi environment"
            echo "  $0 distributed   # Deploy distributed architecture"
            echo "  $0 status        # Check status"
            echo "  $0 stop          # Stop all services"
            ;;
        "")
            # Interactive mode
            show_options
            echo
            echo "Quick commands:"
            echo "  $0 vps         # Deploy VPS environment"
            echo "  $0 raspi       # Deploy Raspberry Pi environment"
            echo "  $0 distributed # Deploy distributed architecture"
            echo "  $0 status      # Check current status"
            echo "  $0 stop        # Stop all services"
            echo "  $0 help        # Show detailed help"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
