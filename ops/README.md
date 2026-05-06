# Operations Directory

This directory contains all operational files for the IDPS system.

## Structure

```
ops/
├── config/              # Configuration files
│   ├── docker/         # Docker configurations
│   ├── nginx/          # Nginx configurations
│   ├── suricata/       # Suricata rules and configs
│   ├── grafana/        # Grafana dashboards
│   └── prometheus/     # Prometheus configs
├── deployment/         # Deployment configurations
│   ├── docker/         # Docker Compose files
│   ├── kubernetes/     # K8s manifests
│   └── ansible/        # Ansible playbooks
├── scripts/            # Setup and maintenance scripts
│   ├── setup/          # Installation scripts
│   ├── maintenance/    # Maintenance tasks
│   └── monitoring/     # Monitoring scripts
└── monitoring/         # Monitoring and alerting
    ├── dashboards/     # Grafana dashboards
    ├── alerts/         # Alert rules
    └── logs/           # Log configurations
```

## Usage

### Deployment
```bash
# Deploy to VPS
./ops/scripts/deploy.sh vps

# Deploy to Raspberry Pi
./ops/scripts/deploy.sh raspi

# Deploy distributed setup
./ops/scripts/deploy-distributed.sh
```

### Configuration
- Service configs in `config/`
- Environment-specific configs in `deployment/`
- Monitoring configs in `monitoring/`

### Scripts
- All operational scripts are in `scripts/`
- Setup scripts for initial installation
- Maintenance scripts for ongoing operations
