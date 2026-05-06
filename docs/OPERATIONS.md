# IDPS — Operations

Deploy, run, and maintain the IDPS infrastructure.

---

## Prerequisites

| Tool | Version | Required on |
|---|---|---|
| Docker + Docker Compose | 24+ | VPS + Pi |
| Git | any | both |
| Rust + Cargo | 1.94+ | dev machine only |
| Node.js + npm | 22+ | dev machine (Angular dashboard) |
| Two ethernet interfaces | — | Raspberry Pi |

---

## Deploy — VPS

> The Traefik reverse proxy stack must already be running and the `proxy` Docker network must exist before starting the IDPS stack. IDPS services attach to that network for discovery.

```bash
# 1. Clone repo
cd /home/brent
git clone <repo-url> idps && cd idps

# 2. Configure environment
cp .env.example .env
nano .env   # set passwords and secrets (see env vars below)

# 3. Fix Elasticsearch vm.max_map_count (required, do once per host)
sudo sysctl -w vm.max_map_count=262144
grep -q vm.max_map_count /etc/sysctl.conf || echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# 4. Start all VPS services
docker compose -f docker-compose.vps.yml up -d

# 5. Verify
docker compose -f docker-compose.vps.yml ps
curl https://idps.brentweb.eu/api/vps/health
```

---

## Deploy — Raspberry Pi

> First-time setup: configure the network bridge, then set up the WireGuard keys before starting services. See [PI_BRIDGE_SETUP.md](PI_BRIDGE_SETUP.md).

The Pi sits behind a home router and is not directly reachable from the VPS. The WireGuard container runs on the Pi and initiates the outbound tunnel — NAT is not a problem. The VPS reaches the Pi at `10.10.0.2` over this tunnel.

### WireGuard key setup (one-time)

WireGuard runs as a Docker container on the Pi, driven entirely by environment variables. You only need to exchange public keys once.

**Generate a keypair for the Pi (run on Pi):**
```bash
# Install wireguard-tools temporarily just to generate keys, or run in a container
docker run --rm alpine sh -c "apk add --no-cache wireguard-tools -q && wg genkey | tee /tmp/pi-private.key | wg pubkey"
# Output: Pi public key (share this with VPS admin)
# Save the private key as WG_PRIVATE_KEY in .env
```

**Register the Pi as a peer on the VPS:**
```bash
# On the VPS — add Pi as a WireGuard peer (replace <PI_PUBKEY> with the key from above)
sudo wg set wg0 peer <PI_PUBKEY> allowed-ips 10.10.0.2/32 persistent-keepalive 25
sudo wg-quick save wg0   # persist across VPS reboots
```

**Get the VPS public key for .env:**
```bash
# On the VPS
sudo wg show wg0 public-key
# Copy this value as WG_VPS_PUBLIC_KEY in the Pi .env
```

**Verify tunnel (after Pi services are started):**
```bash
# From VPS
ping 10.10.0.2
wg show wg0   # should show Pi as peer with recent handshake

# From Pi (inside WireGuard container)
docker exec idps-wireguard ping -c 2 10.10.0.1
```

Also open UDP port 51820 on the VPS firewall if not already done:
```bash
sudo ufw allow 51820/udp
```

### Start Pi services

```bash
# 1. Clone repo (if not already done)
cd /home/brent
git clone <repo-url> idps && cd idps

# 2. Configure network bridge (first time only)
sudo ./scripts/setup/setup-bridge-unified.sh

# 3. Configure environment
cp .env.example .env
nano .env   # set passwords, WG_PRIVATE_KEY, WG_VPS_PUBLIC_KEY, VPS_API_URL, API_KEY

# 4. Start all Pi services
docker compose -f docker-compose.raspi.yml up -d

# 5. Verify
docker compose -f docker-compose.raspi.yml ps
docker logs idps-wireguard        # should say "WireGuard tunnel up"
curl http://localhost:8080/health  # raspi-collector (host network)
./scripts/diagnostics/check-eve-status.sh
```

---

## Environment Variables

### Pi — `docker-compose.raspi.yml`

| Variable | Default | Description |
|---|---|---|
| `VPS_API_URL` | *(required)* | Public VPS API URL, e.g. `https://idps.brentweb.eu/api/vps` |
| `VPS_ENDPOINT` | `http://10.10.0.1:8080` | Direct VPS API Gateway address over WireGuard — used by `raspi-collector` health checks and traffic forwarding |
| `VPS_WS_URL` | `wss://idps.brentweb.eu/ws/raspi` | WebSocket for receiving block/rule commands from VPS |
| `PACKET_STREAM_WS_URL` | `wss://idps.brentweb.eu/ws/packets` | WebSocket for streaming raw packets to VPS (used by packet-processor when deployed) |
| `API_KEY` | *(required)* | API key sent as `X-API-Key` header on all requests to VPS |
| `WG_PRIVATE_KEY` | *(required)* | Pi WireGuard private key (base64) |
| `WG_VPS_PUBLIC_KEY` | *(required)* | VPS WireGuard public key (base64) |
| `VPS_PUBLIC_IP` | `178.104.6.176` | VPS public IP for WireGuard endpoint |
| `WG_ADDRESS` | `10.10.0.2/24` | Pi WireGuard interface address |
| `WG_PORT` | `51820` | VPS WireGuard listen port |
| `WG_ALLOWED_IPS` | `10.10.0.1/32` | Route only VPS traffic through tunnel |
| `WG_KEEPALIVE` | `25` | PersistentKeepalive — keeps tunnel alive through NAT |
| `SURICATA_IFACE` | `eth0` | Interface Suricata monitors |
| `MONGODB_URI` | `mongodb://admin:…@localhost:27017` | Local MongoDB (host network services use localhost) |
| `REDIS_URL` | `redis://:…@localhost:6379` | Local Redis |
| `MONGO_ROOT_PASSWORD` | `SecurePassword123!` | **Change in production** |
| `REDIS_PASSWORD` | `RedisSecure123!` | **Change in production** |
| `RUST_LOG` | `info` | Log level (`debug` for verbose) |

### VPS — `docker-compose.vps.yml`

| Variable | Default | Description |
|---|---|---|
| `MONGODB_URI` | `mongodb://admin:…@mongodb:27017` | MongoDB connection string |
| `REDIS_URL` | `redis://redis:6379` | Redis connection string |
| `ELASTICSEARCH_URL` | `http://elasticsearch:9200` | Elasticsearch endpoint |
| `AUTO_BLOCK_ENABLED` | `false` | Set `true` to auto-apply iptables rules on Pi |
| `RASPI_ENDPOINT` | `http://10.10.0.2:8080` | Pi raspi-collector URL (WireGuard tunnel IP) |
| `API_KEY` | *(required)* | API key for all authenticated endpoints |
| `MONGO_ROOT_PASSWORD` | `SecurePassword123!` | **Change in production** |
| `REDIS_PASSWORD` | `RedisSecure123!` | **Change in production** |
| `GRAFANA_PASSWORD` | `Admin123!` | **Change in production** |
| `RUST_LOG` | `info` | Log level |

---

## Access

All public access is through HTTPS via the Traefik reverse proxy. No services expose ports directly except SSH and services that require host networking.

| Resource | URL |
|---|---|
| Dashboard | https://idps.brentweb.eu |
| API (REST) | https://idps.brentweb.eu/api/vps |
| WebSocket | wss://idps.brentweb.eu/ws |
| Grafana | https://grafana.idps.brentweb.eu |
| VPS SSH | `root@178.104.6.176` |
| Pi SSH (LAN) | `brent@192.168.1.47` |
| Pi (from VPS via WireGuard) | `ssh brent@10.10.0.2` |

---

## API Endpoints

All endpoints require `X-API-Key: <API_KEY>` header except `/health` and `/api/health`.

| Method | Endpoint | Description |
|---|---|---|
| GET | `/api/vps/health` | Service health (no auth required) |
| GET | `/api/vps/status` | Suricata / event pipeline status |
| GET | `/api/vps/events` | Security events (paginated) |
| GET | `/api/vps/alerts/statistics` | Alert statistics |
| GET | `/api/vps/threat-intel` | Threat intelligence data |
| GET | `/api/vps/network/topology` | Network topology |
| GET | `/api/vps/metrics` | System metrics |
| GET | `/api/vps/services/status` | All service health |
| GET | `/api/vps/connection/raspi-vps` | Raspi↔VPS connection status (cached) |
| POST | `/api/vps/traffic` | Ingest single traffic event from raspi-collector |
| POST | `/api/vps/traffic/batch` | Ingest batch of traffic events from raspi-collector |
| POST | `/api/prevention/block` | Manually block an IP |
| POST | `/api/prevention/unblock` | Manually unblock an IP |
| GET | `/api/prevention/blocked` | List all blocked IPs |
| DELETE | `/api/prevention/blocked/{ip}` | Unblock specific IP |
| GET | `/api/vps/settings/detection` | Get detection settings |
| PUT | `/api/vps/settings/detection` | Update detection settings |
| WS | `wss://idps.brentweb.eu/ws` | Real-time dashboard updates |
| WS | `wss://idps.brentweb.eu/ws/raspi` | Raspi command channel (block/rule push) |

---

## Day-to-day Commands

### View live logs
```bash
# VPS
docker compose -f docker-compose.vps.yml logs -f api-gateway

# Pi
docker compose -f docker-compose.raspi.yml logs -f raspi-collector
docker compose -f docker-compose.raspi.yml logs -f wireguard
tail -f /home/brent/idps/data/logs/suricata/eve.json
```

### Restart a single service
```bash
docker compose -f docker-compose.raspi.yml restart network-filter
docker compose -f docker-compose.vps.yml restart api-gateway
```

### Check active iptables blocks
```bash
sudo iptables -L INPUT -n --line-numbers | grep DROP
```

### Manually unblock an IP
```bash
curl -X POST http://localhost:8092/api/v1/unblock \
  -H "Content-Type: application/json" \
  -d '{"ip": "1.2.3.4"}'
```

### Check Suricata dynamic rules
```bash
docker compose -f docker-compose.raspi.yml exec idps-suricata-pi \
  cat /etc/suricata/rules/idps-dynamic.rules
```

### Enable auto-blocking (off by default)
```bash
# In .env on VPS
AUTO_BLOCK_ENABLED=true
docker compose -f docker-compose.vps.yml up -d api-gateway
```

### Check WireGuard tunnel status
```bash
# On VPS
sudo wg show wg0

# On Pi
docker exec idps-wireguard wg show wg0
docker logs idps-wireguard --tail 20
```

### Rotate WireGuard keys (Pi compromised or key leaked)

Run these steps in order. The tunnel will be down for ~30 seconds.

**1. Generate a new keypair on the Pi:**
```bash
docker run --rm alpine sh -c "apk add --no-cache wireguard-tools -q && wg genkey | tee /tmp/pi-new.key | wg pubkey"
# Save the private key output as WG_PRIVATE_KEY_NEW, the public key as WG_PUBKEY_NEW
```

**2. Remove the old Pi peer from the VPS:**
```bash
# On VPS — get the old public key first
sudo wg show wg0 peers
# Then remove it
sudo wg set wg0 peer <OLD_PI_PUBKEY> remove
sudo wg-quick save wg0
```

**3. Add the new Pi peer on the VPS:**
```bash
sudo wg set wg0 peer <WG_PUBKEY_NEW> allowed-ips 10.10.0.2/32 persistent-keepalive 25
sudo wg-quick save wg0
```

**4. Update `.env` on the Pi and restart WireGuard:**
```bash
# Edit .env: replace WG_PRIVATE_KEY with WG_PRIVATE_KEY_NEW
nano /home/brent/idps/.env

docker compose -f docker-compose.raspi.yml restart wireguard
docker logs idps-wireguard --tail 10  # should show "WireGuard tunnel up"
```

**5. Verify:**
```bash
# From VPS
ping -c 2 10.10.0.2
sudo wg show wg0   # should show new peer with recent handshake
```

---

## Health Monitoring

```bash
# VPS — service status
docker compose -f docker-compose.vps.yml ps

# VPS — api-gateway logs
docker compose -f docker-compose.vps.yml logs -f api-gateway

# Pi — service status
docker compose -f docker-compose.raspi.yml ps

# Pi — Suricata events
tail -f /home/brent/idps/data/logs/suricata/eve.json

# Resource usage
docker stats
```

---

## Troubleshooting

**Elasticsearch fails to start**
```bash
docker logs idps-elasticsearch-vps 2>&1 | tail -20
sudo sysctl -w vm.max_map_count=262144
# If data dir permissions are wrong (ES runs as UID 1000):
sudo chown -R 1000:1000 /home/brent/idps/data/elasticsearch
```

**Service not reachable via domain**
```bash
# Check the service is on the proxy network
docker inspect idps-api-gateway-vps | grep -A5 Networks
# Check Traefik picked up the labels
docker logs traefik 2>&1 | grep idps
# Verify DNS resolves to the VPS IP
dig idps.brentweb.eu
```

**WebSocket connection failed (Pi → VPS)**
```bash
# Check api-gateway is running on VPS
curl https://idps.brentweb.eu/api/vps/health
# Check Pi can reach VPS via WireGuard
docker exec idps-wireguard ping -c 2 10.10.0.1
# Check api-gateway logs for connection events
docker compose -f docker-compose.vps.yml logs api-gateway | grep "raspi\|WebSocket"
```

**Pi shows as "disconnected" in the dashboard**
```bash
# The VPS reaches the Pi via WireGuard at 10.10.0.2:8080
# Check the tunnel is up on the VPS
sudo wg show wg0   # look for Pi peer with recent handshake

# If no handshake, restart WireGuard container on the Pi
docker compose -f docker-compose.raspi.yml restart wireguard
docker logs idps-wireguard --tail 20

# Verify RASPI_ENDPOINT is set correctly in VPS .env
grep RASPI_ENDPOINT /home/brent/idps/.env
# Should be: RASPI_ENDPOINT=http://10.10.0.2:8080

# Confirm api-gateway has the env var
docker exec idps-api-gateway-vps env | grep RASPI
```

**Suricata shows as "stopped" in the API**
```bash
# api-gateway derives Suricata status from recent MongoDB event counts
# Check events are arriving from the Pi
curl -H "X-API-Key: <API_KEY>" https://idps.brentweb.eu/api/vps/services/vps

# Check Suricata is running on the Pi and writing eve.json
docker ps | grep suricata
docker logs idps-suricata-pi --tail 20
tail -5 /home/brent/idps/data/logs/suricata/eve.json

# Check raspi-collector is forwarding events
docker logs idps-raspi-collector-pi --tail 30 | grep -i traffic
```

**raspi-collector health checks failing (repeated "failed checks")**
```bash
# raspi-collector polls VPS_ENDPOINT/health every 10 s
# Traefik maps: /api/vps/health → /api/health on api-gateway
# Check the path resolves:
curl https://idps.brentweb.eu/api/vps/health

# Check API_KEY is set in Pi .env (health endpoint skips auth, but good to verify)
grep API_KEY /home/brent/idps/.env
```

**Traefik returns 404 on /api/vps/***
```bash
# Middleware must use @docker provider suffix in Traefik v3
docker inspect idps-api-gateway-vps | grep -i middleware
docker logs traefik 2>&1 | grep -i "idps\|404"
# Verify in docker-compose.vps.yml:
# traefik.http.routers.idps-api.middlewares=idps-strip-vps@docker
```

**MongoDB connection refused**
```bash
# Pi
docker exec idps-mongodb-pi mongo --eval "db.adminCommand('ping')"
docker compose -f docker-compose.raspi.yml logs mongodb

# VPS
docker exec idps-mongodb-vps mongosh --eval "db.adminCommand('ping')"
```

**Packet capture not working**
```bash
ip addr show   # verify interface names
docker compose -f docker-compose.raspi.yml logs raspi-collector
# Ensure NET_RAW and NET_ADMIN capabilities are present in compose
```

**Bridge not working / internet lost**
```bash
sudo ./scripts/setup/setup-bridge-unified.sh
```

---

## Updates

```bash
# VPS
cd /home/brent/idps
git pull
docker compose -f docker-compose.vps.yml up -d --build

# Pi
cd /home/brent/idps
git pull
docker compose -f docker-compose.raspi.yml up -d --build
```

---

## Open Ports

All IDPS services on the VPS are internal — only SSH and Traefik (managed separately) are exposed on the host.

| Port | Protocol | Service | Host |
|---|---|---|---|
| 22 | TCP | SSH | both |
| 80/443 | TCP | Traefik (external stack) | VPS |
| 51820 | UDP | WireGuard | VPS |
| 8080 | TCP | raspi-collector API (WireGuard only) | Pi |
| 9100 | TCP | Node Exporter | Pi |
| 8096 | TCP | Telemetry service | Pi |
