# IDPS Scripts Directory

This directory contains all scripts for managing the IDPS system.

## Main Management Script

### `idps-manager.sh` ⭐
**Unified management script for all IDPS operations**

Usage:
```bash
sudo ./scripts/idps-manager.sh [command]
```

Commands:
- `setup` - Complete IDPS setup from scratch
- `bridge-setup` - Setup network bridge
- `fix-eve` - Fix eve.json issues
- `fix-dns` - Fix DNS resolution
- `fix-iptables` - Fix iptables issues
- `status` - Show system status
- `clean` - Clean up system

## Script Categories

### 🚀 Setup Scripts (`setup/`)
- `setup-bridge-unified.sh` - Network bridge setup with multiple options
- `setup-suricata-scratch.sh` - Complete Suricata setup from scratch

### 🔧 Diagnostic Scripts (`diagnostics/`)
- `check-eve-status.sh` - Check eve.json file status
- `debug-restart-loop.sh` - Debug container restart issues
- `diagnose-suricata.sh` - Comprehensive Suricata diagnostics
- `fix-dns-resolution.sh` - Fix DNS resolution issues
- `fix-iptables.sh` - Fix iptables DNAT rule errors

### 📦 Deployment Scripts (`deployment/`)
- `deploy-vps.sh` - Deploy VPS services
- `deploy-raspi-vps.sh` - Deploy Raspberry Pi services

### 🔨 Utility Scripts (root level)
- `build-docker.sh` - Build Docker images
- `fix-eve-json.sh` - Comprehensive eve.json fix script
- `fix-eve-json-raspi.sh` - Raspberry Pi specific eve.json fix

### 📁 Archived Scripts (`archive/`)
Contains duplicate and obsolete scripts that have been consolidated into `idps-manager.sh`.

## Quick Start

1. **Complete Setup**:
   ```bash
   sudo ./scripts/idps-manager.sh setup
   ```

2. **Check Status**:
   ```bash
   ./scripts/idps-manager.sh status
   ```

3. **Fix Issues**:
   ```bash
   sudo ./scripts/idps-manager.sh fix-eve
   sudo ./scripts/idps-manager.sh fix-dns
   ```

## Migration Notes

The following scripts have been consolidated into `idps-manager.sh`:
- `setup-network-bridge.sh` → `idps-manager.sh bridge-setup`
- `fix-docker-commands.sh` → `idps-manager.sh fix-docker`
- `fix-dns-resolution.sh` → `idps-manager.sh fix-dns`
- `fix-iptables.sh` → `idps-manager.sh fix-iptables`

Use `idps-manager.sh` for all common operations.
