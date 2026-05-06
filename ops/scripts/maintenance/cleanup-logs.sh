#!/bin/bash

# Log Cleanup Script for Educational Environment
# Optimized for school data retention policies

set -e

# Configuration
LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-30}
MAX_LOG_SIZE_MB=${MAX_LOG_SIZE_MB:-100}
LOG_DIRS="/var/log/suricata /var/log/vulnerability-scanner /var/log/idps"
ARCHIVE_DIR="/var/log/archives"
COMPRESS_OLD_LOGS=true
STUDENT_DATA_PROTECTION=true

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Log Cleanup: $1"
}

# Create archive directory if it doesn't exist
create_archive_dir() {
    if [ ! -d "$ARCHIVE_DIR" ]; then
        mkdir -p "$ARCHIVE_DIR"
        log "Created archive directory: $ARCHIVE_DIR"
    fi
}

# Check if log contains student data (simplified check)
contains_student_data() {
    local file=$1
    if [ "$STUDENT_DATA_PROTECTION" = true ]; then
        # Check for patterns that might indicate student data
        grep -qi -E "(student|pupil|leerling|élève|schüler)" "$file" 2>/dev/null || return 1
        return 0
    fi
    return 1
}

# Securely delete files with student data
secure_delete_student_data() {
    local file=$1
    log "Securely deleting file with student data: $file"
    
    # For files with student data, we might want to keep them longer
    # or handle them according to GDPR requirements
    local student_data_retention_days=365  # 1 year for audit purposes
    
    if [ $(find "$file" -mtime +$student_data_retention_days -print 2>/dev/null) ]; then
        # Use shred if available for secure deletion
        if command -v shred >/dev/null 2>&1; then
            shred -vfz -n 3 "$file"
        else
            rm -f "$file"
        fi
        log "Securely deleted student data file: $file"
    else
        log "Keeping student data file (within retention period): $file"
    fi
}

# Compress old logs
compress_logs() {
    local log_dir=$1
    
    if [ ! -d "$log_dir" ]; then
        return
    fi
    
    log "Processing log directory: $log_dir"
    
    # Find and compress logs older than 7 days
    find "$log_dir" -name "*.log" -type f -mtime +7 -print0 | while IFS= read -r -d '' file; do
        if [ ! -f "${file}.gz" ]; then
            if contains_student_data "$file"; then
                log "Skipping compression of student data file: $file"
                continue
            fi
            
            log "Compressing log file: $file"
            gzip "$file"
        fi
    done
}

# Remove old archived logs
cleanup_archives() {
    log "Cleaning up old archives"
    
    # Remove compressed logs older than retention period
    find "$ARCHIVE_DIR" -name "*.gz" -type f -mtime +$LOG_RETENTION_DAYS -delete
    find "$ARCHIVE_DIR" -name "*.tar.gz" -type f -mtime +$LOG_RETENTION_DAYS -delete
    
    log "Removed archives older than $LOG_RETENTION_DAYS days"
}

# Check and rotate large log files
rotate_large_logs() {
    local log_dir=$1
    
    if [ ! -d "$log_dir" ]; then
        return
    fi
    
    # Find log files larger than MAX_LOG_SIZE_MB
    find "$log_dir" -name "*.log" -type f -size +${MAX_LOG_SIZE_MB}M -print | while read -r file; do
        if contains_student_data "$file"; then
            log "Large student data file detected: $file (size exceeds limit)"
            # Handle student data files differently
            continue
        fi
        
        log "Rotating large log file: $file ($(du -h "$file" | cut -f1))"
        
        # Create timestamp for rotation
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local rotated_file="${file}.${timestamp}"
        
        # Move current log to rotated file
        mv "$file" "$rotated_file"
        
        # Compress rotated file
        gzip "$rotated_file"
        
        # Move to archive
        mv "${rotated_file}.gz" "$ARCHIVE_DIR/"
        
        log "Rotated and archived: $file"
    done
}

# Monitor disk usage
check_disk_usage() {
    local log_dir=$1
    local max_usage_percent=85
    
    if [ ! -d "$log_dir" ]; then
        return
    fi
    
    # Check disk usage of log directory
    local usage=$(df "$log_dir" | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$usage" -gt "$max_usage_percent" ]; then
        log "WARNING: Log directory $log_dir is ${usage}% full (threshold: ${max_usage_percent}%)"
        
        # Emergency cleanup - remove oldest non-student logs
        find "$log_dir" -name "*.log.gz" -type f -mtime +7 -delete
        find "$ARCHIVE_DIR" -name "*.gz" -type f -mtime +7 -delete
        
        log "Emergency cleanup completed for $log_dir"
    fi
}

# Generate cleanup report
generate_cleanup_report() {
    local report_file="/var/log/cleanup-report-$(date '+%Y%m%d').log"
    
    {
        echo "=== Log Cleanup Report ==="
        echo "Date: $(date)"
        echo "Retention Policy: $LOG_RETENTION_DAYS days"
        echo "Max Log Size: ${MAX_LOG_SIZE_MB}MB"
        echo ""
        
        echo "=== Disk Usage ==="
        for dir in $LOG_DIRS; do
            if [ -d "$dir" ]; then
                echo "$dir: $(du -sh "$dir" 2>/dev/null | cut -f1)"
            fi
        done
        
        echo ""
        echo "=== Archive Directory ==="
        if [ -d "$ARCHIVE_DIR" ]; then
            echo "Archive size: $(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)"
            echo "Archive files: $(find "$ARCHIVE_DIR" -type f | wc -l)"
        fi
        
        echo ""
        echo "=== Cleanup Completed ==="
    } > "$report_file"
    
    log "Cleanup report generated: $report_file"
}

# Main cleanup function
main() {
    log "Starting log cleanup process"
    log "Retention policy: $LOG_RETENTION_DAYS days"
    log "Max log size: ${MAX_LOG_SIZE_MB}MB"
    
    create_archive_dir
    
    # Process each log directory
    for log_dir in $LOG_DIRS; do
        if [ -d "$log_dir" ]; then
            log "Processing directory: $log_dir"
            
            # Check disk usage first
            check_disk_usage "$log_dir"
            
            # Rotate large logs
            rotate_large_logs "$log_dir"
            
            # Compress old logs
            if [ "$COMPRESS_OLD_LOGS" = true ]; then
                compress_logs "$log_dir"
            fi
        fi
    done
    
    # Clean up old archives
    cleanup_archives
    
    # Generate report
    generate_cleanup_report
    
    log "Log cleanup process completed"
}

# Execute main function
main "$@"
