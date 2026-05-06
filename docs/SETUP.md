# Setup Guide (VPS + Raspberry Pi)

A short, human-first runbook to get the distributed IDPS running.

## What you’ll deploy
- **VPS**: API gateway + processing services (Docker Compose).
- **Raspberry Pi**: Inline bridge that forwards traffic, runs Suricata, and receives block rules.
- **Dashboard**: Angular UI on the VPS (or locally) at `http://localhost` in dev.

## Prerequisites
- Docker 24+ and Docker Compose plugin on both hosts.
- A VPS (Ubuntu 22.04+ recommended) with public IP.
- Raspberry Pi 4 with two Ethernet interfaces (eth0 WAN, eth1/USB LAN).
- WireGuard keys for the Pi↔VPS tunnel (see PI_BRIDGE_SETUP.md).

## 5-minute checklist
1) Copy `.env.example` to `.env` and fill secrets + IPs.
2) Set `VPS_IP` in the Pi `.env` and WireGuard peer keys.
3) Ensure `SURICATA_IFACE` in `.env` matches the Pi’s monitored interface.
4) Open required ports on the VPS firewall (HTTP/HTTPS or Traefik network).
5) Run the compose file for your target (commands below).

## Deploy the VPS stack
```bash
cp .env.example .env             # fill passwords + API_KEY + WireGuard peer
sudo sysctl -w vm.max_map_count=262144
Docker_BUILDKIT=1 docker compose -f docker-compose.vps.yml up -d
```
Verify:
```bash
docker compose -f docker-compose.vps.yml ps
curl http://localhost:8081/health
```

## Deploy the Raspberry Pi stack
```bash
cp .env.example .env
# Set: VPS_IP, WG_PRIVATE_KEY, WG_VPS_PUBLIC_KEY, SURICATA_IFACE

# One-time bridge setup (creates br0 between eth0↔eth1)
sudo ./scripts/setup/setup-bridge-unified.sh setup

# Bring up the Pi services
sudo VPS_IP=<vps-ip> docker compose -f docker-compose.raspi.yml up -d
```
Verify:
```bash
docker compose -f docker-compose.raspi.yml ps
sudo tail -f data/logs/suricata/eve.json
```

## Common commands (single entrypoint)
Use the consolidated manager:
```bash
sudo ./scripts/idps-manager.sh status        # health snapshot
sudo ./scripts/idps-manager.sh deploy-vps    # start VPS services
sudo ./scripts/idps-manager.sh deploy-raspi  # start Pi services
sudo ./scripts/idps-manager.sh bridge-status # check br0
sudo ./scripts/idps-manager.sh fix-eve       # ensure eve.json exists
```

## Troubleshooting quick hits
- **No logs in `eve.json`**: run `idps-manager.sh fix-eve`, ensure `SURICATA_IFACE` is correct, and generate traffic (`ping 8.8.8.8`).
- **WireGuard down**: re-check keys and allowed-ips in `PI_BRIDGE_SETUP.md`.
- **Containers restarting**: `docker compose -f <file> logs --tail=50 <service>`.
- **Slow pulls on Pi**: export `DOCKER_BUILDKIT=1` and build services in batches.

## Where to go next
- **Architecture**: [ARCHITECTURE.md](ARCHITECTURE.md)
- **Operations & credentials**: [OPERATIONS.md](OPERATIONS.md)
- **Bridge/WireGuard pairing**: [PI_BRIDGE_SETUP.md](PI_BRIDGE_SETUP.md)
- **Contributor workflow**: [DEVELOPMENT.md](DEVELOPMENT.md)
