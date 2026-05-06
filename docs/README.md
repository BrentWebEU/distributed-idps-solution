# IDPS — Intrusion Detection & Prevention System

Distributed security system for educational networks. A Raspberry Pi sits between the router and the rest of the network, streams all traffic to a VPS for deep analysis, and enforces block rules locally — without holding up traffic.

If you just want to get the system running, start with:
- [SETUP.md](SETUP.md) — short deploy runbook (VPS + Pi) and the 5 commands you actually need.
- [PROJECT_STRUCTURE.md](PROJECT_STRUCTURE.md) — what lives where after cleanup.

---

## Project Goals

This project is a graduation thesis for Provil-ION, a Flemish secondary school. The research question:

> *Which common cyberattacks (DDoS, brute-force, internal network infiltration) pose the greatest threat to the Provil-ION school network, and how can software-based detection contribute to better security?*

### Design Criteria (from literature study)

A school environment differs fundamentally from a corporate network: limited ICT staff, constrained budgets, high wireless device density, and unpredictable user behaviour. An IDPS is only practically usable in this context when it meets all of the following criteria:

| Criterion | Requirement |
|---|---|
| **Affordability** | Runs on existing hardware; no heavy licences or dedicated appliances |
| **Easy management** | Clear configuration, understandable alerts, minimal daily tuning |
| **Exportable logging** | Logs must be readable, exportable, and usable for incident follow-up (GRIP basis 5 T11) |
| **Low false-positive rate** | Normal school traffic (simultaneous class logins, heavy wifi) must not trigger alarms |
| **Wireless-aware** | Handles many simultaneous connections with dynamic IPs (GRIP basis 2 T3) |
| **Automatic prevention** | Blocks clear threats (e.g. brute-force) without requiring an admin to be online 24/7 |

### Complementary Approach: Vulnerability Assessment

A full penetration test carries too much risk for an active school network. The chosen approach combines:

- **IDPS** (Suricata + custom services) — continuous real-time monitoring and automatic blocking
- **Vulnerability assessment** (Nuclei / OpenVAS) — periodic automated scans for misconfigurations, outdated software, and open services

Results from scans feed back into IDPS detection rules, so the system improves over time.

### Security Layers

The complete security strategy addresses three layers, as defined by ENISA, NIS2, and DataGuard:

1. **Technical** — strong passwords, 2FA, WPA3 encryption, regular patching
2. **Organisational** — clear responsibilities (DPO), incident response procedure, annual risk analysis (NIS2)
3. **Awareness** — training staff and students to recognise phishing, social engineering, and unsafe behaviour

### Alignment with Flemish GRIP Framework

The system design aligns with the *Groeipad Informatieveiligheid en Privacy* (GRIP) from Kenniscentrum Digisprong:
- Logging and incident follow-up (basis 5 T11)
- Secured wireless network access (basis 2 T3)
- Formal roles for data protection and information security (basis 1 O2)

---

## How It Works

```
[Router] → [Raspberry Pi eth0]
               │ Suricata monitors traffic → eve.json
               │ raspi-collector tails eve.json
               │ forwards events via HTTPS
               ▼
           [VPS — api-gateway]
               │ threat analysis + rule generation
               │ pushes block_command + Suricata rule back
               ▼
           [Raspberry Pi]
               │ network-filter applies iptables DROP
               └ rule-engine writes Suricata rule + reloads
```

Traffic is **never held waiting** for VPS analysis. If the VPS is unreachable the Pi keeps forwarding traffic normally (fail-open). Only IPs that have already been flagged are dropped immediately from the in-memory cache.

---

## Quick Start

### VPS
```bash
cd /home/brent/idps
cp .env.example .env    # fill in passwords and API_KEY

# Required once per host (Elasticsearch)
sudo sysctl -w vm.max_map_count=262144

docker compose -f docker-compose.vps.yml up -d
curl https://idps.brentweb.eu/api/vps/health
```

> The Traefik reverse proxy stack must be running before deploying. IDPS services attach to the external `proxy` Docker network for discovery.

### Raspberry Pi
```bash
cd /home/brent/idps
sudo ./scripts/setup/setup-bridge-unified.sh   # first-time bridge setup only
cp .env.example .env

# Generate WireGuard keypair for the Pi
wg genkey | tee pi-private.key | wg pubkey
# → Set WG_PRIVATE_KEY and WG_VPS_PUBLIC_KEY in .env
# → Register Pi public key as a peer on the VPS (see PI_BRIDGE_SETUP.md)

docker compose -f docker-compose.raspi.yml up -d
docker compose -f docker-compose.raspi.yml ps
docker logs idps-wireguard   # verify tunnel is up
```

> The Pi sits behind a home router (NAT) and is not directly reachable from the VPS. The WireGuard container initiates the outbound tunnel — the VPS can then push commands back to the Pi via `10.10.0.2`. See [PI_BRIDGE_SETUP.md](PI_BRIDGE_SETUP.md) for the full key exchange procedure.

### Dashboard
- https://idps.brentweb.eu
- https://grafana.idps.brentweb.eu

---

## Requirements

| Component | Minimum | Used |
|---|---|---|
| VPS | 4 vCPU, 8 GB RAM, Ubuntu 22.04 | Hetzner CPX42 (8 vCPU, 16 GB, x86_64) |
| Raspberry Pi | Pi 4 (4 GB RAM), 2 ethernet ports | Pi 4 (ARM64) |
| Docker | 24+ | 24+ |
| Rust (dev only) | 1.94+ | 1.94 |

---

## Docs

| File | Contents |
|---|---|
| [ARCHITECTURE.md](ARCHITECTURE.md) | System design, all services, event flow, detection logic |
| [OPERATIONS.md](OPERATIONS.md) | Deploy, env vars, access, API endpoints, troubleshooting |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Build, test, debug, add services |
| [PI_BRIDGE_SETUP.md](PI_BRIDGE_SETUP.md) | One-time Pi network bridge + WireGuard setup |
| [BACKLOG.md](BACKLOG.md) | Implementation status, remaining work, known limitations |
| [TODO.md](TODO.md) | Prioritised task list (current) |
