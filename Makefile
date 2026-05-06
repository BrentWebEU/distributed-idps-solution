.PHONY: help build build-edge build-cloud build-shared test test-edge test-cloud lint format clean dev-setup dev-watch dev-test-watch security-audit security-check docs docs-serve

help:
	@echo "Available targets:"
	@echo "  build          - Build all services"
	@echo "  build-edge     - Build edge services"
	@echo "  build-cloud    - Build cloud services"
	@echo "  build-shared   - Build shared libraries"
	@echo "  test           - Run all tests"
	@echo "  test-edge      - Run edge service tests"
	@echo "  test-cloud     - Run cloud service tests"
	@echo "  lint           - Run clippy + fmt check"
	@echo "  format         - Format all code"
	@echo "  clean          - Clean build artifacts"
	@echo "  dev-setup      - Install dev tools (cargo-watch, cargo-audit, cargo-deny)"
	@echo "  dev-watch      - Watch and rebuild edge-packet-processor"
	@echo "  dev-test-watch - Watch and run tests"
	@echo "  security-audit - Run cargo audit"
	@echo "  security-check - Run cargo deny + cargo audit"
	@echo "  docs           - Generate and open docs"
	@echo "  docs-serve     - Serve docs on :8000"

build:
	cargo build --release

build-edge:
	cargo build --release -p edge-packet-processor -p edge-network-filter -p edge-rule-engine -p edge-raspi-collector

build-cloud:
	cargo build --release -p cloud-packet-analyzer -p cloud-threat-intel -p cloud-rule-generator -p cloud-api-gateway

build-shared:
	cargo build --release -p shared-types -p shared-protocols -p shared-utils -p shared-config

test:
	cargo test --all-features

test-edge:
	cargo test -p edge-packet-processor -p edge-network-filter -p edge-rule-engine -p edge-telemetry

test-cloud:
	cargo test -p idps-packet-analyzer -p idps-threat-intel -p idps-rule-generator -p idps-api-gateway -p idps-log-processor

lint:
	cargo clippy --all-features -- -D warnings
	cargo fmt --check

format:
	cargo fmt

clean:
	cargo clean

dev-setup:
	cargo install cargo-watch cargo-audit cargo-deny

dev-watch:
	cargo watch -x 'run --bin edge-packet-processor'

dev-test-watch:
	cargo watch -x test

security-audit:
	cargo audit

security-check:
	cargo deny check
	cargo audit

docs:
	cargo doc --open

docs-serve:
	cargo doc --no-deps --document-private-items
	python3 -m http.server 8000 --directory target/doc
