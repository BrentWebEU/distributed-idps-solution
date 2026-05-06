# TLS Certificate Setup

Place your TLS certificate and private key here:

```
config/tls/
├── cert.pem     — full-chain certificate (PEM format)
└── key.pem      — private key (PEM format, no passphrase)
```

## Generating a self-signed certificate (development only)

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout config/tls/key.pem \
  -out config/tls/cert.pem \
  -subj "/CN=idps-vps" \
  -addext "subjectAltName=IP:$(curl -s ifconfig.me),DNS:localhost"
```

## Production (Let's Encrypt)

```bash
certbot certonly --standalone -d your-vps-domain.com
cp /etc/letsencrypt/live/your-vps-domain.com/fullchain.pem config/tls/cert.pem
cp /etc/letsencrypt/live/your-vps-domain.com/privkey.pem   config/tls/key.pem
```

After placing the certs, use `docker-compose.idps.yml` which mounts this directory
into the nginx container and activates HTTPS on port 443.
