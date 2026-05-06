# IDPS — Development Guide

---

## Workspace structure

```
idps/
├── src/
│   ├── services/
│   │   ├── edge/           Raspberry Pi services (Rust, workspace members)
│   │   └── cloud/          VPS services (Rust, workspace members)
│   └── shared/             Shared libraries (types, protocols, utils, config)
├── src/tools/dashboard/    Angular dashboard application
├── raspi/wireguard/        WireGuard container (Alpine, env-var-driven)
├── tests/                  Integration tests
├── docker-compose.vps.yml  VPS deployment
├── docker-compose.raspi.yml  Pi deployment
└── Cargo.toml              Workspace root
```

> All crates use `{ workspace = true }` for shared dependencies — do not pin versions in individual `Cargo.toml` files.
> Angular dashboard is a separate Angular CLI project at `src/tools/dashboard/`.

---

## Building

### Rust Services
```bash
# Check entire workspace (fast, no binaries)
cargo check --workspace

# Build all workspace services
cargo build --workspace

# Build a specific service
cargo build -p idps-packet-processor
cargo build -p idps-api-gateway
cargo build -p idps-rule-engine
cargo build -p idps-raspi-collector

# Release build (optimised for deployment)
cargo build --workspace --release
```

### Angular Dashboard
```bash
cd src/tools/dashboard

# Install dependencies (first time only)
npm install

# Development server (with hot reload)
npm run start
# Dashboard available at http://localhost:4200

# Production build (uses environment.prod.ts via fileReplacements in angular.json)
npm run build
# Equivalent: ng build --configuration production
# Output in dist/ng-tailadmin/browser/

# Run tests
npm run test

# Lint
ng lint
```

---

## Testing

```bash
# Run all workspace tests
cargo test --workspace

# Run tests for a single service
cargo test -p idps-api-gateway

# Integration tests
cargo test --test integration

# With output visible
cargo test -- --nocapture
```

---

## Running services locally

### Prerequisites
```bash
export RUST_LOG=debug

# Start MongoDB and Redis (required for most services)
docker run -d -p 27017:27017 --name mongodb mongo:7.0
docker run -d -p 6379:6379 --name redis redis:7.4-alpine
```

### Development Workflow
```bash
# Terminal 1: Start API Gateway
cargo run -p idps-api-gateway

# Terminal 2: Angular Dashboard (proxies /api/vps → localhost:8080 in dev)
cd src/tools/dashboard
npm run start
# Access at http://localhost:4200

# Terminal 3: Edge services (if testing locally)
cargo run -p idps-network-filter
cargo run -p idps-rule-engine
cargo run -p idps-raspi-collector
```

### Docker Development Environment
```bash
# Start VPS stack
docker compose -f docker-compose.vps.yml up -d

docker compose -f docker-compose.vps.yml ps
docker compose -f docker-compose.vps.yml logs -f api-gateway
```

---

## Code quality

```bash
# Format all code
cargo fmt --all

# Lint (warnings become errors)
cargo clippy --workspace -- -D warnings

# Security audit of dependencies
cargo audit
```

---

## Adding a new service

1. Create the directory: `src/services/edge/my-service/` or `src/services/cloud/my-service/`
2. Add a `Cargo.toml` using workspace dependencies:
   ```toml
   [package]
   name = "idps-my-service"
   version = "0.1.0"
   edition = "2021"

   [dependencies]
   tokio = { workspace = true }
   axum = { workspace = true }
   serde = { workspace = true }
   ```
3. Add the path to the `[workspace] members` list in the root `Cargo.toml`
4. Add a `Dockerfile` — copy from a similar service and update the binary name
5. Add the service to the relevant `docker-compose` file with `networks: - idps-net`
6. If it needs to be publicly reachable, also add `- proxy` to its networks and add Traefik labels

---

## Debugging

### Rust Services
```bash
# Verbose logs
RUST_LOG=trace cargo run -p idps-packet-processor

# Docker logs (running containers)
docker compose -f docker-compose.vps.yml logs -f api-gateway
docker compose -f docker-compose.raspi.yml logs -f raspi-collector
```

### Angular Dashboard
```bash
# Build with verbose output
ng build --verbose

# Run tests with coverage
npm run test -- --code-coverage
```

### API testing
```bash
# Health check (no auth required)
curl https://idps.brentweb.eu/api/vps/health

# Authenticated endpoints
curl -H "X-API-Key: <API_KEY>" https://idps.brentweb.eu/api/vps/status
curl -H "X-API-Key: <API_KEY>" https://idps.brentweb.eu/api/vps/events

# Local development
curl http://localhost:8080/api/health
curl -H "X-API-Key: <API_KEY>" http://localhost:8080/api/status
```

---

## Performance Testing

```bash
# Run benchmarks
cargo run -p idps-benchmarks

# Load testing
hey -n 1000 -c 10 https://idps.brentweb.eu/api/vps/status

# Bundle analysis (Angular)
ng build --stats-json
npx webpack-bundle-analyzer dist/ng-tailadmin/stats.json
```

---

## Shared libraries

| Crate | Status | Contents |
|---|---|---|
| `shared/types` | Complete | `PacketEvent`, `AlertEvent`, `SystemMetrics`, `ThreatData` |
| `shared/protocols` | Complete | Protocol parsers and message formats |
| `shared/utils` | Complete | `is_in_cidr()`, `retry_with_backoff()`, `init_logging()` |
| `shared/config` | Complete | `EdgeConfig`, `CloudConfig` typed structs from env |

---

## Angular Dashboard

### Architecture
- **Framework**: Angular 21 with TypeScript
- **Styling**: TailwindCSS
- **Charts**: ApexCharts
- **Real-time**: WebSocket integration for live updates

### Key Components
- `idps.component.ts` — main dashboard with real-time data
- `api.service.ts` — HTTP API integration
- `websocket.service.ts` — real-time WebSocket client
- `idps.service.ts` — IDPS-specific service methods

### Environment Configuration

The production build **must** use `--configuration production` (or `npm run build`) to activate the `fileReplacements` in `angular.json` that swaps `environment.ts` for `environment.prod.ts`. Without this, the dev build ships `localhost` URLs to production.

```typescript
// src/environments/environment.ts (development)
export const environment = {
  production: false,
  apiUrl: 'http://localhost:8082/api',
  wsUrl: 'ws://localhost:8082/ws',
  apiKey: '',
};

// src/environments/environment.prod.ts (production)
// Uses relative URLs — Traefik routes them on idps.brentweb.eu
export const environment = {
  production: true,
  apiUrl: '/api/vps',
  wsUrl: '/ws',
  apiKey: '',
  apiGatewayUrl: '/api/vps',
  networkFilterUrl: '/api/prevention',
};
```

Production URLs are relative and resolved by Traefik:
- `/api/vps` → `api-gateway:8080` (Traefik strips the `/api/vps` prefix via `replacepathregex` middleware)
- `/ws` → `api-gateway:8080`
- `/api/prevention` → `api-gateway:8080`
- Everything else → `vps-dashboard:80` (Angular SPA)

> **Traefik v3 note:** Middlewares defined in Docker labels must be referenced with the `@docker` provider suffix:
> `traefik.http.routers.idps-api.middlewares=idps-strip-vps@docker`

### Tailwind CSS v4 and `@apply` in component styles

Tailwind v4 no longer scans component CSS files automatically. Any component `.css` file that uses `@apply` must add a `@reference` directive pointing to the global styles file:

```css
/* Required as the first line in any component .css that uses @apply */
@reference "../../../../styles.css";

.my-class {
  @apply bg-green-500 text-white;
}
```

Without this, the build fails with `Cannot apply unknown utility class '...'`.

---

## Workspace dependency versions

Key versions defined in root `Cargo.toml`:

| Dependency | Version |
|---|---|
| `tokio` | 1 |
| `axum` | 0.8 |
| `tower` | 0.5 |
| `tower-http` | 0.6 |
| `serde` / `serde_json` | 1.0 |
| `mongodb` | 3.1 |
| `redis` | 0.27 |
| `hickory-resolver` | 0.24 |
| `etherparse` | 0.15 |
| `pcap` | 2.0 |
| `dashmap` | 6.1 |
| `tokio-tungstenite` | 0.26 |

---

## Axum 0.8 notes

- Route parameters use `{param}` syntax, not `:param`
- `Message::Text` requires `Utf8Bytes` — use `.into()` on `String` values
- Middleware state is separate from app state — register with `from_fn_with_state`
