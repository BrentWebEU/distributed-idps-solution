#!/bin/bash
# IDPS Brain-VPS Log Setup - Educational Network Component
# Installeert logrotate voor brain scanning service

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGROTATE_CONFIG="/etc/logrotate.d/idps-brain"
LOG_DIR="/var/log/idps/brain"

# Logging functies
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
    logger -t idps-brain-setup "INFO: $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCES]\033[0m $1"
    logger -t idps-brain-setup "SUCCES: $1"
}

log_error() {
    echo -e "\033[0;31m[FOUT]\033[0m $1"
    logger -t idps-brain-setup "FOUT: $1"
}

# Controleer root privileges
if [[ $EUID -ne 0 ]]; then
    log_error "Dit script moet als root worden uitgevoerd"
    exit 1
fi

# Maak directories
mkdir -p "$LOG_DIR"
mkdir -p "/opt/idps/brain/scripts"
mkdir -p "/opt/idps/brain/scans"
chmod 755 "$LOG_DIR"

# Installeer logrotate configuratie
if [[ -f "$PROJECT_ROOT/config/logrotate.conf" ]]; then
    cp "$PROJECT_ROOT/config/logrotate.conf" "$LOGROTATE_CONFIG"
    chmod 644 "$LOGROTATE_CONFIG"
    
    # Test configuratie
    if logrotate -d "$LOGROTATE_CONFIG" >/dev/null 2>&1; then
        log_success "Brain logrotate configuratie geïnstalleerd"
    else
        log_error "Logrotate configuratie test mislukt"
        exit 1
    fi
else
    log_error "Logrotate configuratie niet gevonden: $PROJECT_ROOT/config/logrotate.conf"
    exit 1
fi

# Configureer cronjob
if ! crontab -l 2>/dev/null | grep -q "idps-brain"; then
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/sbin/logrotate /etc/logrotate.d/idps-brain >/dev/null 2>&1") | crontab -
    log_success "Brain log cronjob toegevoegd"
fi

# Stel rechten in
chown -R root:root "$LOG_DIR"
chmod 755 "$LOG_DIR"

log_success "IDPS Brain-VPS log setup voltooid"
