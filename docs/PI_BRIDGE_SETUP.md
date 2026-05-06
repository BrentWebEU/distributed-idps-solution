# Raspberry Pi Bridge Setup

One-time hardware setup to put the Pi inline between the modem and the rest of the network.

```
Modem → Pi eth0 → Pi eth1 → Router / Switch → Clients
                ↓
          IDPS Services (Suricata, packet capture)
```

Once the bridge is up, deploy the Pi services with `docker compose -f docker-compose.raspi.yml up -d` (see [OPERATIONS.md](OPERATIONS.md)).

---

## Hardware Requirements

- Raspberry Pi 4 or 5 (Gigabit ethernet required for line-rate performance)
- USB-to-Ethernet adapter (for second network port)
- SD card 32 GB+
- Power supply 3 A+
- 2× ethernet cables

## Network Interfaces

| Interface | Connection |
|---|---|
| `eth0` | Modem / WAN |
| `eth1` | Router or switch WAN port |
| `br0` | Virtual bridge combining eth0 + eth1 |

---

## 1. Prepare OS

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y bridge-utils net-tools
```

---

## 2. Configure Network Bridge

Run the automated script:
```bash
sudo ./scripts/setup/setup-bridge-unified.sh
```

Or configure manually:

```bash
# Enable IP forwarding
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Create bridge
sudo ip link add name br0 type bridge
sudo ip link set br0 up
sudo ip link set eth0 master br0
sudo ip link set eth1 master br0
sudo ip addr add 192.168.100.1/24 dev br0
```

---

## 3. Persist Bridge Configuration

**Option A — ifupdown** (`/etc/network/interfaces`):
```bash
sudo cp config/network/interfaces-bridge /etc/network/interfaces
sudo systemctl restart networking
```

**Option B — systemd-networkd**:
```bash
sudo cp config/network/systemd-bridge/* /etc/systemd/network/
sudo systemctl enable systemd-networkd
sudo systemctl restart systemd-networkd
```

Enable IP forwarding and bridge netfilter (add to `/etc/sysctl.d/99-idps.conf`):
```
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
```
```bash
sudo sysctl -p /etc/sysctl.d/99-idps.conf
```

---

## 4. Setup iptables Rules

```bash
sudo ./scripts/diagnostics/fix-iptables.sh
```

Open ports so the VPS can reach the Pi's services over WireGuard:
```bash
iptables -A INPUT -p tcp --dport 8080 -j ACCEPT   # raspi-collector API
iptables -A INPUT -p udp --dport 51820 -j ACCEPT  # WireGuard (outbound only — Pi initiates)
```

---

## 5. WireGuard Tunnel (required — Pi is behind NAT)

The Pi's LAN IP (`192.168.1.47`) is not reachable from the internet. WireGuard runs as a Docker container on the Pi (`idps-wireguard`) and initiates the tunnel outbound, keeping NAT transparent. The VPS can then reach the Pi at `10.10.0.2`.

### Key exchange (one-time)

**Generate a keypair for the Pi:**
```bash
# Run on the Pi (or any machine with wireguard-tools)
wg genkey | tee pi-private.key | wg pubkey
# Output: Pi public key — give this to the VPS admin
# Save the private key as WG_PRIVATE_KEY in .env (never commit it)
```

**Register the Pi on the VPS (run on VPS):**
```bash
# Replace <PI_PUBKEY> with the public key from the step above
sudo wg set wg0 peer <PI_PUBKEY> allowed-ips 10.10.0.2/32 persistent-keepalive 25
sudo wg-quick save wg0   # persist across VPS reboots
```

**Get the VPS public key for .env (run on VPS):**
```bash
sudo wg show wg0 public-key
# Copy this as WG_VPS_PUBLIC_KEY in Pi .env
```

**Set keys in Pi `.env`:**
```bash
WG_PRIVATE_KEY=<pi-private-key-base64>
WG_VPS_PUBLIC_KEY=<vps-public-key-base64>
VPS_PUBLIC_IP=178.104.6.176
WG_ADDRESS=10.10.0.2/24
WG_PORT=51820
WG_ALLOWED_IPS=10.10.0.1/32
WG_KEEPALIVE=25
```

### WireGuard container

WireGuard runs via the `wireguard` service in `docker-compose.raspi.yml`. It starts before all other Pi services and self-monitors the tunnel with a 30 s watchdog loop.

```bash
# Start (happens automatically with compose up)
docker compose -f docker-compose.raspi.yml up -d wireguard

# Check tunnel status
docker exec idps-wireguard wg show wg0
docker logs idps-wireguard --tail 20

# Restart if tunnel drops
docker compose -f docker-compose.raspi.yml restart wireguard
```

Tunnel IPs after setup:
- VPS: `10.10.0.1` (server, listens on UDP 51820)
- Pi: `10.10.0.2` (client, `PersistentKeepalive = 25` maintains connection through NAT)

---

## 6. Suricata Performance Tuning

Edit `config/suricata/suricata.yaml`:
```yaml
threading:
  set-cpu-affinity: yes
  cpu-affinity:
    - management-cpu-set:
        cpu: [ 0 ]
    - worker-cpu-set:
        cpu: [ 1, 2, 3 ]

detect:
  profile: high
  custom-values:
    toclient-chunk-size: 2560
    toserver-chunk-size: 2560
```

Optional Pi performance tweaks:
```bash
# Disable GUI if desktop OS
sudo systemctl disable lightdm bluetooth

# Set CPU governor to performance
echo 'performance' | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

---

## Troubleshooting

**Bridge not working**
```bash
ip link show              # check interface status
bridge link show          # check bridge members
cat /proc/sys/net/ipv4/ip_forward   # should be 1
sudo iptables -L -n -v    # check iptables rules
```

**Suricata not processing traffic**
```bash
docker logs idps-suricata-pi
docker exec idps-suricata-pi ip link show br0   # verify interface binding
tail -f data/logs/suricata/eve.json             # check event output
```

**No internet after bridge setup**
```bash
sudo ./scripts/setup/setup-bridge-unified.sh
```

**Bridge management**
```bash
sudo ip link set br0 down && sudo ip link set br0 up   # restart bridge
sudo tcpdump -i br0 -n                                  # verify traffic flow
```

**WireGuard tunnel not coming up**
```bash
# Check container logs
docker logs idps-wireguard

# Verify keys are correct in .env
grep WG_ /home/brent/idps/.env

# Confirm VPS has Pi registered as peer
# (run on VPS)
sudo wg show wg0

# Test connectivity after tunnel is up
docker exec idps-wireguard ping -c 3 10.10.0.1
```
