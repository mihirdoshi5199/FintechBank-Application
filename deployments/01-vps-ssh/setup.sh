#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT STRATEGY 01: Secure VPS Hosting with SSH Hardening
# FintechBank – Fintech Scalability Challenge
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo "═══════════════════════════════════════════════"
echo "  FintechBank - VPS Security Hardening Setup"
echo "═══════════════════════════════════════════════"

APP_USER="fintech"
APP_PORT=4000

# ── 1. Update system ──────────────────────────────────────────────────────────
echo "[1/8] Updating system packages..."
apt-get update -y && apt-get upgrade -y
apt-get install -y ufw fail2ban curl wget htop unzip git

# ── 2. Create non-root user ───────────────────────────────────────────────────
echo "[2/8] Creating application user..."
if ! id "$APP_USER" &>/dev/null; then
  adduser --disabled-password --gecos "" $APP_USER
  usermod -aG sudo $APP_USER
fi

# ── 3. SSH Key setup ──────────────────────────────────────────────────────────
echo "[3/8] Configuring SSH keys..."
mkdir -p /home/$APP_USER/.ssh
chmod 700 /home/$APP_USER/.ssh
# NOTE: In production, replace with your actual public key
echo "# Add your SSH public key here" > /home/$APP_USER/.ssh/authorized_keys
chmod 600 /home/$APP_USER/.ssh/authorized_keys
chown -R $APP_USER:$APP_USER /home/$APP_USER/.ssh

# ── 4. SSH Hardening ──────────────────────────────────────────────────────────
echo "[4/8] Applying SSH hardening..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)

cat > /etc/ssh/sshd_config << 'SSHEOF'
# FintechBank SSH Hardening Configuration
Port 2222
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# Authentication
LoginGraceTime 30
PermitRootLogin no
StrictModes yes
MaxAuthTries 3
MaxSessions 5
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
AuthenticationMethods publickey

# Session Security
X11Forwarding no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers fintech

# Logging
LogLevel VERBOSE
SyslogFacility AUTH

# Crypto (modern only)
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group16-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
SSHEOF

systemctl restart sshd
echo "✓ SSH hardened on port 2222"

# ── 5. UFW Firewall ───────────────────────────────────────────────────────────
echo "[5/8] Configuring UFW firewall..."
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 2222/tcp comment 'SSH custom port'
ufw allow 80/tcp   comment 'HTTP'
ufw allow 443/tcp  comment 'HTTPS'
ufw allow $APP_PORT/tcp comment 'FintechBank API'
ufw --force enable
echo "✓ Firewall configured"

# ── 6. Fail2Ban ───────────────────────────────────────────────────────────────
echo "[6/8] Setting up Fail2Ban..."
cat > /etc/fail2ban/jail.local << 'F2BEOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 3
backend  = systemd
destemail = admin@fintech.dev
sendername = Fail2Ban

[sshd]
enabled  = true
port     = 2222
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400

[nginx-http-auth]
enabled = true
port    = http,https

[nginx-limit-req]
enabled = true
port    = http,https
logpath = /var/log/nginx/error.log
F2BEOF

systemctl enable fail2ban
systemctl restart fail2ban
echo "✓ Fail2Ban configured"

# ── 7. Install Node.js & App ──────────────────────────────────────────────────
echo "[7/8] Installing Node.js 20..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
node --version && npm --version
echo "✓ Node.js installed"

# ── 8. systemd service ───────────────────────────────────────────────────────
echo "[8/8] Creating systemd service..."
cat > /etc/systemd/system/fintech-api.service << SVCEOF
[Unit]
Description=FintechBank API Service
After=network.target
Wants=network-online.target

[Service]
Type=simple
User=$APP_USER
WorkingDirectory=/opt/fintech/backend
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=fintech-api
Environment=NODE_ENV=production
Environment=PORT=$APP_PORT
EnvironmentFile=/opt/fintech/.env

# Security limits
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/opt/fintech/logs

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable fintech-api
echo "✓ systemd service created"

echo ""
echo "═══════════════════════════════════════════════"
echo "  ✅ VPS Hardening Complete!"
echo "  SSH Port: 2222 (key-auth only)"
echo "  API Port: $APP_PORT"
echo "  Fail2Ban: Active"
echo "  UFW: Active"
echo "═══════════════════════════════════════════════"
