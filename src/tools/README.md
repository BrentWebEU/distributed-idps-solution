# Development Tools

Command-line tools, dashboards, and utilities for IDPS development and operations.

## Tools

- **cli**: Command-line interface for system management
- **dashboard**: Web dashboard for monitoring and control
- **benchmarks**: Performance testing and load generation

## CLI Usage

```bash
# Install CLI tool
cargo install --path tools/cli

# Use CLI
idps-cli status
idps-cli deploy --environment raspi
idps-cli logs --service packet-processor
```

## Dashboard

Access the web dashboard at `http://localhost:3000` after starting the development stack.

## Benchmarks

Run performance tests:

```bash
cd tools/benchmarks
cargo run -- --target packet-processor --duration 300s
```
