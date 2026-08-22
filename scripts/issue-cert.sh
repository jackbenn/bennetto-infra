#!/usr/bin/env bash
# Get the initial TLS certificate from Let's Encrypt.
# Run this once after the site is first deployed and responding on HTTP.
# Subsequent renewals are handled automatically by /etc/cron.d/certbot-renew.
#
# Usage (run on the EC2 instance, from anywhere):
#   bash ~/bennetto-infra/scripts/issue-cert.sh

set -euo pipefail

EMAIL="jack@bennetto.com"
DOMAINS="-d bennetto.com -d www.bennetto.com -d bookclub.bennetto.com"
WEBROOT="/var/www/certbot"
COMPOSE_FILE="/home/ubuntu/bennetto-infra/docker-compose.yml"

echo "=== Requesting certificate via webroot ==="
echo "(nginx must be running and bennetto.com must resolve to this server)"
echo ""

sudo certbot certonly --webroot -w "$WEBROOT" \
    $DOMAINS \
    --email "$EMAIL" \
    --agree-tos \
    --non-interactive

echo ""
echo "=== Reloading nginx to pick up the new certificate ==="
docker compose -f "$COMPOSE_FILE" exec nginx nginx -s reload

echo ""
echo "Certificate issued. Renewal is handled by /etc/cron.d/certbot-renew."
