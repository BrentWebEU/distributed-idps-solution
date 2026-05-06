#!/bin/bash
# IDPS Raspberry Pi Rust Log Setup - Rust Service Component
# Installeert logrotate voor Rust-based IDS service

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOGROTATE_CONFIG="/etc/logrotate.d/raspi-rust"
LOG_DIR="/var/log/idps/raspi-rust"

# Logging functies
log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $1"
    logger -t raspi-rust-setup "INFO: $1"
}

log_success() {
    echo -e "\033[0;32m[SUCCES]\033[0m $1"
    logger -t raspi-rust-setup "SUCCES: $1"
}

log_error() {
    echo -e "\033[0;31m[FOUT]\033[0m $1"
    logger -t raspi-rust-setup "FOUT: $1"
}

# Controleer root privileges
if [[ $EUID -ne 0 ]]; then
    log_error "Dit script moet als root worden uitgevoerd"
    exit 1
fi

# Maak rust gebruiker aan indien nodig
if ! id rust &>/dev/null; then
    log_info "Aanmaken rust gebruiker"
    useradd -r -s /bin/false -d /var/log/idps/raspi-rust rust
    log_success "Rust gebruiker aangemaakt"
fi

# Maak directories
mkdir -p "$LOG_DIR"
mkdir -p "/opt/idps/raspi-rust/scripts"
chmod 755 "$LOG_DIR"

# Installeer logrotate configuratie
if [[ -f "$PROJECT_ROOT/config/logrotate.conf" ]]; then
    cp "$PROJECT_ROOT/config/logrotate.conf" "$LOGROTATE_CONFIG"
    chmod 644 "$LOGROTATE_CONFIG"
    
    # Test configuratie
    if logrotate -d "$LOGROTATE_CONFIG" >/dev/null 2>&1; then
        log_success "Rust logrotate configuratie geïnstalleerd"
    else
        log_error "Logrotate configuratie test mislukt"
        exit 1
    fi
else
    log_error "Logrotate configuratie niet gevonden: $PROJECT_ROOT/config/logrotate.conf"
    exit 1
fi

# Configureer cronjob (frequentier voor service monitoring)
if ! crontab -l 2>/dev/null | grep -q "raspi-rust"; then
    (crontab -l 2>/dev/null; echo "0 */4 * * * /usr/sbin/logrotate /etc/logrotate.d/raspi-rust >/dev/null 2>&1") | crontab -
    log_success "Rust log cronjob toegevoegd (elke 4 uur)"
fi

# Stel rechten in
chown -R rust:rust "$LOG_DIR"
chmod 755 "$LOG_DIR"

log_success "IDPS Raspberry Pi Rust log setup voltooid"
