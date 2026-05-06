# Source Directory

This directory contains all source code for the IDPS system.

## Structure

```
src/
├── services/            # Core services
│   ├── edge/           # Edge services (Raspberry Pi)
│   │   ├── packet-processor/
│   │   ├── network-filter/
│   │   ├── rule-engine/
│   │   └── telemetry/
│   └── cloud/          # Cloud services (VPS)
│       ├── api-gateway/
│       ├── packet-analyzer/
│       ├── threat-intel/
│       ├── vulnerability-scanner/
│       └── rule-generator/
├── shared/             # Shared libraries
│   ├── types/          # Common data types
│   ├── protocols/      # Communication protocols
│   ├── utils/          # Common utilities
│   └── config/         # Configuration management
└── tools/              # Development tools
    ├── cli/            # Command-line interface
    ├── dashboard/      # Web dashboard
    └── benchmarks/     # Performance testing
```

## Building

```bash
# Build all services
cargo build --workspace

# Build specific service
cargo build -p idps-packet-processor

# Build with optimizations
cargo build --workspace --release
```

## Running Services

```bash
# Edge services
cargo run -p idps-packet-processor
cargo run -p idps-network-filter

# Cloud services
cargo run -p idps-api-gateway
cargo run -p idps-packet-analyzer

# Tools
cargo run -p idps-cli
cargo run -p idps-benchmarks
```

## Development

All services use shared libraries from `src/shared/` to ensure consistency and reduce code duplication.

- `idps-types`: Common data structures
- `idps-protocols`: Communication protocols
- `idps-utils`: Shared utilities
- `idps-config`: Configuration management
