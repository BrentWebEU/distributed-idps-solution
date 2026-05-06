# Edge Services

Edge services designed for Raspberry Pi deployment with resource constraints and offline operation capabilities.

## Services

- **packet-processor**: Main packet capture and processing service
- **network-filter**: Network filtering and caching logic  
- **rule-engine**: Local rule application and enforcement
- **telemetry**: Metrics collection and logging

## Deployment

```bash
# Deploy edge services
./deploy.sh raspi
```

## Resource Requirements

- Memory: 512MB per service
- Storage: 1GB minimum
- Network: 100Mbps recommended
