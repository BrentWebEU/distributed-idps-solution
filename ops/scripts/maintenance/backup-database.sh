#!/bin/bash

# Database Backup Script for Educational Environment
# Optimized for student data protection and compliance

set -e

# Configuration
MONGODB_URI=${MONGODB_URI:-"mongodb://brent:password@mongo:27017"}
BACKUP_DIR="/backups"
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-7}
STUDENT_DATA_RETENTION_DAYS=${STUDENT_DATA_RETENTION_DAYS:-365}
COMPRESS_BACKUPS=true
ENCRYPT_BACKUPS=true
GPG_RECIPIENT=${GPG_RECIPIENT:-"admin@school.local"}

# Databases to backup
DATABASES=("idps" "vulnerability_scanner")

# Collections with sensitive student data (require special handling)
STUDENT_DATA_COLLECTIONS=(
    "student_records"
    "personal_data"
    "grade_records"
    "attendance_records"
)

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup: $1"
}

# Create backup directory structure
create_backup_dirs() {
    local date_dir=$(date '+%Y/%m/%d')
    local backup_path="$BACKUP_DIR/$date_dir"
    
    mkdir -p "$backup_path/databases"
    mkdir -p "$backup_path/student_data"
    mkdir -p "$backup_path/configs"
    
    echo "$backup_path"
}

# Backup regular database
backup_database() {
    local db_name=$1
    local backup_path=$2
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="$backup_path/databases/${db_name}_${timestamp}.archive"
    
    log "Starting backup of database: $db_name"
    
    # Use mongodump for backup
    mongodump --uri="$MONGODB_URI/$db_name" \
        --out="$backup_file" \
        --gzip \
        --quiet || {
        log "ERROR: Failed to backup database $db_name"
        return 1
    }
    
    # Create archive
    cd "$backup_file"
    tar -czf "${backup_file}.tar.gz" .
    cd - > /dev/null
    rm -rf "$backup_file"
    
    log "Database backup completed: ${backup_file}.tar.gz"
    
    # Encrypt if enabled
    if [ "$ENCRYPT_BACKUPS" = true ]; then
        encrypt_backup "${backup_file}.tar.gz"
    fi
}

# Backup student data with special handling
backup_student_data() {
    local backup_path=$1
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local student_backup_file="$backup_path/student_data/student_data_${timestamp}.archive"
    
    log "Starting student data backup with enhanced protection"
    
    # Create temporary directory for student data
    local temp_dir=$(mktemp -d)
    
    # Backup each student data collection separately
    for collection in "${STUDENT_DATA_COLLECTIONS[@]}"; do
        local collection_dir="$temp_dir/$collection"
        mkdir -p "$collection_dir"
        
        log "Backing up collection: $collection"
        
        # Check if collection exists
        if mongo "$MONGODB_URI/idps" --quiet --eval "db.getCollectionNames().indexOf('$collection') >= 0" | grep -q "true"; then
            mongoexport --uri="$MONGODB_URI/idps" \
                --collection="$collection" \
                --out="$collection_dir/data.json" \
                --jsonArray \
                --quiet || {
                log "WARNING: Failed to export collection $collection"
                continue
            }
            
            # Create metadata
            cat > "$collection_dir/metadata.json" << EOF
{
    "collection": "$collection",
    "backup_date": "$(date -Iseconds)",
    "backup_type": "student_data",
    "retention_policy": "$STUDENT_DATA_RETENTION_DAYS days",
    "data_classification": "restricted"
}
EOF
            
            log "Collection $collection backed up successfully"
        else
            log "Collection $collection does not exist, skipping"
        fi
    done
    
    # Create archive
    tar -czf "$student_backup_file.tar.gz" -C "$temp_dir" .
    rm -rf "$temp_dir"
    
    log "Student data backup completed: ${student_backup_file}.tar.gz"
    
    # Encrypt student data (always)
    encrypt_backup "${student_backup_file}.tar.gz"
    
    # Create audit log entry
    create_audit_entry "student_data_backup" "$student_backup_file.tar.gz"
}

# Encrypt backup file
encrypt_backup() {
    local file=$1
    
    if command -v gpg >/dev/null 2>&1; then
        log "Encrypting backup: $file"
        
        gpg --symmetric --cipher-algo AES256 \
            --compress-algo 1 \
            --s2k-mode 3 \
            --s2k-digest-algo SHA512 \
            --s2k-count 65536 \
            --force-mdc \
            --batch --yes \
            --output "${file}.gpg" \
            "$file" || {
            log "ERROR: Failed to encrypt backup $file"
            return 1
        }
        
        # Remove unencrypted file
        rm -f "$file"
        log "Backup encrypted: ${file}.gpg"
    else
        log "WARNING: GPG not available, backup not encrypted"
    fi
}

# Create audit log entry
create_audit_entry() {
    local action=$1
    local file=$2
    local audit_file="/var/log/backup-audit.log"
    
    echo "$(date -Iseconds),$action,$file,$(whoami),$(hostname)" >> "$audit_file"
    log "Audit entry created for $action"
}

# Backup configuration files
backup_configs() {
    local backup_path=$1
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local config_backup_file="$backup_path/configs/configs_${timestamp}.tar.gz"
    
    log "Backing up configuration files"
    
    # Create temporary directory
    local temp_dir=$(mktemp -d)
    
    # Backup important configuration files
    local config_files=(
        "/etc/suricata"
        "/docker-compose.yml"
        ".env"
        "suricata-config"
        "scripts"
    )
    
    for config in "${config_files[@]}"; do
        if [ -e "$config" ]; then
            cp -r "$config" "$temp_dir/" 2>/dev/null || true
        fi
    done
    
    # Create archive
    tar -czf "$config_backup_file" -C "$temp_dir" .
    rm -rf "$temp_dir"
    
    log "Configuration backup completed: $config_backup_file"
    
    # Encrypt if enabled
    if [ "$ENCRYPT_BACKUPS" = true ]; then
        encrypt_backup "$config_backup_file"
    fi
}

# Cleanup old backups
cleanup_old_backups() {
    log "Cleaning up old backups"
    
    # Regular backups
    find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime +$BACKUP_RETENTION_DAYS -delete
    find "$BACKUP_DIR" -name "*.tar.gz.gpg" -type f -mtime +$BACKUP_RETENTION_DAYS -delete
    
    # Student data backups (different retention)
    find "$BACKUP_DIR" -path "*/student_data/*" -name "*.tar.gz" -type f -mtime +$STUDENT_DATA_RETENTION_DAYS -delete
    find "$BACKUP_DIR" -path "*/student_data/*" -name "*.tar.gz.gpg" -type f -mtime +$STUDENT_DATA_RETENTION_DAYS -delete
    
    # Remove empty directories
    find "$BACKUP_DIR" -type d -empty -delete
    
    log "Old backups cleaned up"
}

# Verify backup integrity
verify_backup() {
    local file=$1
    
    if [[ $file == *.gpg ]]; then
        # For encrypted files, just check if they can be decrypted (without actually doing it)
        if gpg --list-packets "$file" >/dev/null 2>&1; then
            log "Backup integrity verified: $file"
            return 0
        else
            log "ERROR: Backup integrity check failed: $file"
            return 1
        fi
    else
        # For unencrypted files, check if they're valid gzip files
        if gzip -t "$file" 2>/dev/null; then
            log "Backup integrity verified: $file"
            return 0
        else
            log "ERROR: Backup integrity check failed: $file"
            return 1
        fi
    fi
}

# Generate backup report
generate_backup_report() {
    local backup_path=$1
    local report_file="$backup_path/backup_report_$(date '+%Y%m%d_%H%M%S').json"
    
    # Count backup files
    local total_backups=$(find "$backup_path" -name "*.tar.gz*" -type f | wc -l)
    local student_backups=$(find "$backup_path/student_data" -name "*.tar.gz*" -type f 2>/dev/null | wc -l)
    local config_backups=$(find "$backup_path/configs" -name "*.tar.gz*" -type f 2>/dev/null | wc -l)
    
    # Calculate total size
    local total_size=$(du -sh "$backup_path" 2>/dev/null | cut -f1)
    
    cat > "$report_file" << EOF
{
    "backup_date": "$(date -Iseconds)",
    "backup_path": "$backup_path",
    "summary": {
        "total_backups": $total_backups,
        "student_data_backups": $student_backups,
        "configuration_backups": $config_backups,
        "total_size": "$total_size"
    },
    "configuration": {
        "retention_days": $BACKUP_RETENTION_DAYS,
        "student_data_retention_days": $STUDENT_DATA_RETENTION_DAYS,
        "compression_enabled": $COMPRESS_BACKUPS,
        "encryption_enabled": $ENCRYPT_BACKUPS
    },
    "databases": [
EOF
    
    # Add database information
    local first=true
    for db in "${DATABASES[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        echo "        \"$db\"" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
    ],
    "student_data_collections": [
EOF
    
    # Add student data collections
    first=true
    for collection in "${STUDENT_DATA_COLLECTIONS[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$report_file"
        fi
        echo "        \"$collection\"" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF
    ]
}
EOF
    
    log "Backup report generated: $report_file"
}

# Main backup function
main() {
    log "Starting database backup process"
    
    # Wait for MongoDB to be ready
    log "Waiting for MongoDB connection..."
    while ! mongo "$MONGODB_URI" --quiet --eval "db.adminCommand('ismaster')" >/dev/null 2>&1; do
        sleep 5
    done
    log "MongoDB connection established"
    
    # Create backup directory
    local backup_path=$(create_backup_dirs)
    log "Backup directory: $backup_path"
    
    # Backup regular databases
    for db in "${DATABASES[@]}"; do
        backup_database "$db" "$backup_path"
    done
    
    # Backup student data with special handling
    backup_student_data "$backup_path"
    
    # Backup configurations
    backup_configs "$backup_path"
    
    # Cleanup old backups
    cleanup_old_backups
    
    # Generate report
    generate_backup_report "$backup_path"
    
    # Create audit entry
    create_audit_entry "database_backup" "$backup_path"
    
    log "Database backup process completed successfully"
}

# Execute main function
main "$@"
