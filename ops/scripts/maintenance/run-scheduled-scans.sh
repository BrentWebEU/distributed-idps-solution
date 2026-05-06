#!/bin/bash

# Educational Environment Scan Scheduler
# Optimized scanning schedules for school environments

set -e

# Configuration
API_URL="http://api-vps:8081"
VULN_API_URL="http://vulnerability-scanner:8082"
LOG_FILE="/var/log/scan-scheduler.log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Wait for services to be ready
wait_for_services() {
    log "Waiting for services to be ready..."
    
    while ! curl -f "$API_URL/config" > /dev/null 2>&1; do
        log "Waiting for IDPS API..."
        sleep 10
    done
    
    while ! curl -f "$VULN_API_URL/health" > /dev/null 2>&1; do
        log "Waiting for Vulnerability Scanner..."
        sleep 10
    done
    
    log "All services are ready!"
}

# Network scan for educational environment
scan_network() {
    local scan_type=$1
    local network_range=${2:-"192.168.0.0/16"}
    
    log "Starting $scan_type network scan for $network_range"
    
    case $scan_type in
        "minimal")
            # Quick scan during school hours - minimal impact
            curl -X GET "$VULN_API_URL/vulnerability/scan?scan_type=Network&targets=$network_range&scan_intensity=Low&timeout_minutes=30" \
                -H "Content-Type: application/json" \
                2>/dev/null || log "Failed to start minimal network scan"
            ;;
        "comprehensive")
            # Full scan outside school hours
            curl -X GET "$VULN_API_URL/vulnerability/scan?scan_type=Network&targets=$network_range&scan_intensity=Medium&compliance_framework=GRIP&timeout_minutes=120" \
                -H "Content-Type: application/json" \
                2>/dev/null || log "Failed to start comprehensive network scan"
            ;;
        "deep")
            # Weekend deep scan
            curl -X GET "$VULN_API_URL/vulnerability/scan?scan_type=Network&targets=$network_range&scan_intensity=High&compliance_framework=GRIP&timeout_minutes=240" \
                -H "Content-Type: application/json" \
                2>/dev/null || log "Failed to start deep network scan"
            ;;
    esac
}

# Student systems scan (non-intrusive)
scan_student_systems() {
    log "Starting student systems compliance scan"
    
    # Define student system targets
    local student_targets=(
        "student-management.school.local"
        "grades.school.local"
        "library.school.local"
        "lms.school.local"
        "email.school.local"
    )
    
    local targets_json=$(printf '%s,' "${student_targets[@]}" | sed 's/,$//')
    
    curl -X POST "$VULN_API_URL/vulnerability/scan/student-systems" \
        -H "Content-Type: application/json" \
        -d "{\"targets\": [$(echo "$student_targets" | sed 's/[^[:space:]]\+/"&"/g' | sed 's/ /,/g')], \"scan_type\": \"Compliance\"}" \
        2>/dev/null || log "Failed to start student systems scan"
}

# GRIP compliance scan
scan_grip_compliance() {
    log "Starting GRIP compliance scan"
    
    curl -X GET "$VULN_API_URL/vulnerability/compliance/GRIP" \
        -H "Content-Type: application/json" \
        2>/dev/null || log "Failed to start GRIP compliance scan"
}

# Web application security scan
scan_web_applications() {
    log "Starting web application security scan"
    
    local web_targets=(
        "https://school.local"
        "https://portal.school.local"
        "https://admin.school.local"
    )
    
    for target in "${web_targets[@]}"; do
        curl -X GET "$VULN_API_URL/vulnerability/scan?scan_type=Web&targets=$target&scan_intensity=Low&timeout_minutes=60" \
            -H "Content-Type: application/json" \
            2>/dev/null || log "Failed to start web scan for $target"
    done
}

# Asset discovery
discover_assets() {
    log "Starting asset discovery"
    
    local network_ranges=(
        "192.168.1.0/24"  # Admin network
        "192.168.2.0/24"  # Teacher network
        "192.168.3.0/24"  # Student network
        "192.168.10.0/24" # Server network
    )
    
    for range in "${network_ranges[@]}"; do
        curl -X GET "$VULN_API_URL/vulnerability/scan?scan_type=AssetDiscovery&targets=$range&scan_intensity=Low&timeout_minutes=45" \
            -H "Content-Type: application/json" \
            2>/dev/null || log "Failed to start asset discovery for $range"
    done
}

# Generate compliance report
generate_compliance_report() {
    log "Generating GRIP compliance report"
    
    curl -X POST "$VULN_API_URL/vulnerability/compliance/report" \
        -H "Content-Type: application/json" \
        -d '{"framework": "GRIP", "include_recommendations": true}' \
        2>/dev/null || log "Failed to generate compliance report"
}

# Cleanup old scans
cleanup_old_scans() {
    log "Cleaning up old scan data"
    
    # This would integrate with the vulnerability scanner API to clean up old scans
    # For now, just log the action
    log "Old scan cleanup completed"
}

# Main execution based on scan type
main() {
    local scan_type=$1
    
    log "=== Educational Scan Scheduler ==="
    log "Starting $scan_type scan schedule"
    
    wait_for_services
    
    case $scan_type in
        "minimal")
            log "Executing minimal scan schedule (educational hours)"
            scan_network "minimal" "192.168.0.0/24"
            sleep 300  # 5 minutes between scans
            scan_student_systems
            ;;
        "comprehensive")
            log "Executing comprehensive scan schedule (outside educational hours)"
            scan_network "comprehensive"
            sleep 600  # 10 minutes between scans
            scan_web_applications
            sleep 300
            scan_grip_compliance
            ;;
        "deep")
            log "Executing deep scan schedule (weekend/maintenance)"
            scan_network "deep"
            sleep 900  # 15 minutes between intensive scans
            discover_assets
            sleep 600
            scan_web_applications
            sleep 300
            scan_student_systems
            sleep 300
            generate_compliance_report
            ;;
        "compliance")
            log "Executing compliance-focused scan"
            scan_grip_compliance
            sleep 300
            scan_student_systems
            sleep 300
            generate_compliance_report
            ;;
        "maintenance")
            log "Executing maintenance tasks"
            cleanup_old_scans
            generate_compliance_report
            ;;
        *)
            log "Unknown scan type: $scan_type"
            log "Available types: minimal, comprehensive, deep, compliance, maintenance"
            exit 1
            ;;
    esac
    
    log "Scan schedule completed"
}

# Execute main function with all arguments
main "$@"
