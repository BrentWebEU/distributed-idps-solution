# IDPS — Intrusion Detection & Prevention System

Distributed security monitoring for educational networks. A Raspberry Pi captures all network traffic inline, streams it to a VPS for analysis, and enforces block rules locally — without ever holding up traffic.

## Documentation

Everything lives in [`docs/`](docs/). Start with the setup guide, then dive deeper as needed:

| File | Purpose |
|---|---|
| [docs/README.md](docs/README.md) | Orientation and research context |
| [docs/SETUP.md](docs/SETUP.md) | Deploy on VPS or Raspberry Pi, required env vars, top 5 commands |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System design, services, and data/packet flows |
| [docs/OPERATIONS.md](docs/OPERATIONS.md) | Day-2 operations, credentials, endpoints, troubleshooting |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Build/test/debug workflow for contributors |
| [docs/PI_BRIDGE_SETUP.md](docs/PI_BRIDGE_SETUP.md) | One-time bridge + WireGuard pairing for the Pi |
| [docs/BACKLOG.md](docs/BACKLOG.md) | Implementation status and remaining work |
| [docs/TODO.md](docs/TODO.md) | Current short-term tasks |

See [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) for a tour of the trimmed repository layout.

## AI assistance

Parts of this codebase were developed with the help of AI (Claude by Anthropic). AI assisted with writing Rust service boilerplate, Angular components, configuration files, and documentation. All code was reviewed, tested, and integrated by the author.

## Quick start

```bash
# VPS (Cloud deployment)
docker compose -f docker-compose.vps.yml up -d

# Raspberry Pi (Edge deployment)
VPS_IP=<your-vps-ip> docker compose -f docker-compose.raspi.yml up -d
```
