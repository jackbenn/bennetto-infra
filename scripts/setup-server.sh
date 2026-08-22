#!/usr/bin/env bash
# One-time setup for a fresh EC2 instance (Ubuntu).
# Run this after cloning bennetto-infra and before the first deploy.
#
# Usage:
#   git clone --recurse-submodules https://github.com/jackbenn/bennetto-infra.git
#   cd bennetto-infra
#   bash scripts/setup-server.sh
#
# After this script completes:
#   1. Edit bookclub.env with real secrets (see bookclub/infra/bookclub.env.example)
#   2. Run ./scripts/deploy.sh to build and start all services
#   3. Run scripts/issue-cert.sh to get the TLS certificate (needs the site running first)

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Installing Docker ==="
sudo apt-get update -q
sudo apt-get install -y -q ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -q
sudo apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker "$USER"

echo "=== Installing Certbot ==="
sudo apt-get install -y -q certbot

echo "=== Adding swap (1 GB) ==="
if ! grep -q '/swapfile' /etc/fstab; then
    sudo fallocate -l 1G /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    echo "Swap created."
else
    echo "Swap already configured, skipping."
fi

echo "=== Creating certbot webroot directory ==="
sudo mkdir -p /var/www/certbot

echo "=== Setting up cert renewal cron job ==="
sudo tee /etc/cron.d/certbot-renew << 'EOF'
0 3 * * * root certbot renew --quiet --webroot -w /var/www/certbot --deploy-hook "docker compose -f /home/ubuntu/bennetto-infra/docker-compose.yml exec nginx nginx -s reload"
EOF

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Log out and back in (so docker group takes effect)"
echo "  2. Copy bookclub.env.example to bookclub.env and fill in secrets:"
echo "       cp bookclub/infra/bookclub.env.example bookclub.env"
echo "  3. Run: ./scripts/deploy.sh"
echo "  4. Once the site is up, run: ./scripts/issue-cert.sh"
