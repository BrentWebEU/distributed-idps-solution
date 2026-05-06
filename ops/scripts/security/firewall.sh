#!/usr/bin/env bash
# firewall.sh — Restrict access to trusted IPs only.
# Docker bypasses the INPUT chain, so rules go into DOCKER-USER (for container
# ports) and INPUT (for host-level ports like SSH).
#
# Trusted IPs:
#   109.133.17.150  — Raspberry Pi / operator machine
#
# Run as root:  sudo bash ops/scripts/security/firewall.sh

set -euo pipefail

RASPI_IP="109.133.17.150"

echo "[*] Applying IDPS firewall rules..."

# ── INPUT chain (host-level, non-Docker ports) ──────────────────────────────
# Allow established/related connections
iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow loopback
iptables -I INPUT 2 -i lo -j ACCEPT

# Allow SSH from anywhere (keep this to avoid locking yourself out)
iptables -I INPUT 3 -p tcp --dport 22 -j ACCEPT

# Allow all from the Raspi
iptables -I INPUT 4 -s "$RASPI_IP" -j ACCEPT

# Drop everything else on INPUT
iptables -A INPUT -j DROP

# ── DOCKER-USER chain (container ports exposed by Docker) ───────────────────
# Flush existing DOCKER-USER rules first
iptables -F DOCKER-USER 2>/dev/null || true

# Allow the Raspi to reach all Docker-exposed ports
iptables -I DOCKER-USER -s "$RASPI_IP" -j RETURN

# Allow loopback / internal Docker network (172.20.0.0/24)
iptables -I DOCKER-USER -s 127.0.0.1 -j RETURN
iptables -I DOCKER-USER -s 172.20.0.0/24 -j RETURN

# Drop all other external traffic to Docker containers
iptables -A DOCKER-USER -j DROP

echo "[✓] Firewall rules applied."
echo ""
echo "    Allowed source: $RASPI_IP"
echo "    SSH (port 22):  open to all (prevent lockout)"
echo "    All other traffic: DROPPED"
echo ""
echo "  To persist across reboots:"
echo "    Debian/Ubuntu: apt install iptables-persistent && netfilter-persistent save"
