# Shared Libraries

Common libraries, utilities, and protocols shared across all IDPS services.

## Modules

- **types**: Common data types and structures
- **protocols**: Communication protocols and message formats
- **utils**: Common utilities and helper functions
- **config**: Configuration management and validation

## Usage

Add to service `Cargo.toml`:

```toml
[dependencies]
idps-types = { path = "../../shared/types" }
idps-protocols = { path = "../../shared/protocols" }
idps-utils = { path = "../../shared/utils" }
```

## Architecture

All shared modules follow semantic versioning and maintain backward compatibility within major versions.
