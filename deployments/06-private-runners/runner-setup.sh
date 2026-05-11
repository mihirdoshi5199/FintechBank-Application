#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT STRATEGY 06: Private GitHub Actions Runners – Self-Hosted Speed
# FintechBank – Fintech Scalability Challenge
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RUNNER_VERSION="2.311.0"
RUNNER_DIR="/opt/github-runner"
RUNNER_USER="runner"
ORG_URL="https://github.com/your-org/fintech-app"  # Change this
RUNNER_LABELS="fintech-runner,linux,self-hosted"

echo "═══════════════════════════════════════════════"
echo "  FintechBank - Self-Hosted Runner Setup"
echo "═══════════════════════════════════════════════"

# ── Create runner user ────────────────────────────────────────────────────────
if ! id "$RUNNER_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$RUNNER_USER"
  usermod -aG docker "$RUNNER_USER"
fi

# ── Install Docker ────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
fi

# ── Install dependencies ──────────────────────────────────────────────────────
apt-get install -y jq curl wget libicu-dev

# ── Download runner ───────────────────────────────────────────────────────────
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

echo "Downloading GitHub Actions runner v${RUNNER_VERSION}..."
curl -fsSL -O "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
tar xzf "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
rm "actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"

# ── Configure runner (requires GITHUB_TOKEN from env) ─────────────────────────
echo ""
echo "To register the runner, run:"
echo ""
echo "  cd $RUNNER_DIR"
echo "  sudo -u $RUNNER_USER ./config.sh \\"
echo "    --url $ORG_URL \\"
echo "    --token \$GITHUB_RUNNER_TOKEN \\"
echo "    --name fintech-runner-\$(hostname) \\"
echo "    --labels \"$RUNNER_LABELS\" \\"
echo "    --work _work \\"
echo "    --unattended"
echo ""

# ── Runner environment ────────────────────────────────────────────────────────
cat > "$RUNNER_DIR/.env" << 'ENVEOF'
# FintechBank Runner Environment
NODE_ENV=production
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1
BUILDX_NO_DEFAULT_ATTESTATIONS=1

# Registry
REGISTRY_HOST=registry.fintech.dev:5000
REGISTRY_USER=fintech-ci
# REGISTRY_PASSWORD= (set via GitHub secret)

# Deployment hosts  
# PROD_HOST=  (set via GitHub secret)
# STAGING_HOST= (set via GitHub secret)
ENVEOF

# ── Systemd service for runner ────────────────────────────────────────────────
cat > /etc/systemd/system/github-runner.service << SVCEOF
[Unit]
Description=GitHub Actions Self-Hosted Runner
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
User=$RUNNER_USER
WorkingDirectory=$RUNNER_DIR
ExecStart=$RUNNER_DIR/run.sh
Restart=always
RestartSec=10
EnvironmentFile=$RUNNER_DIR/.env

# Resource limits
LimitNOFILE=65536
MemoryMax=4G
CPUQuota=200%

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload

# ── Runner cleanup cron ───────────────────────────────────────────────────────
cat > /etc/cron.daily/runner-cleanup << 'CRONEOF'
#!/bin/bash
docker system prune -f --filter "until=24h"
docker volume prune -f
find /tmp -name "runner-*" -mtime +1 -delete
CRONEOF
chmod +x /etc/cron.daily/runner-cleanup

echo ""
echo "═══════════════════════════════════════════════"
echo "  Runner setup complete!"
echo "  1. Register: sudo -u $RUNNER_USER ./config.sh ..."
echo "  2. Enable:   systemctl enable --now github-runner"
echo "═══════════════════════════════════════════════"
