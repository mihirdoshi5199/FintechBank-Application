#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Vault Secrets Initialization for FintechBank
# Run once after Vault is initialized and unsealed
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VAULT_ADDR="${VAULT_ADDR:-https://vault.fintech.dev:8200}"
export VAULT_ADDR

echo "Configuring Vault for FintechBank..."

# Enable KV secrets engine v2
vault secrets enable -path=fintech kv-v2

# Enable AppRole auth
vault auth enable approle

# ── Store Application Secrets ─────────────────────────────────────────────────
echo "Writing application secrets..."
vault kv put fintech/production \
  jwt_secret="$(openssl rand -base64 64)" \
  redis_password="$(openssl rand -base64 32)" \
  db_password="$(openssl rand -base64 32)" \
  smtp_password="${SMTP_PASSWORD:-changeme}" \
  registry_password="${REGISTRY_PASSWORD:-changeme}" \
  slack_webhook="${SLACK_WEBHOOK:-}"

# ── Policy for FintechBank App ────────────────────────────────────────────────
vault policy write fintech-app - << 'POLICY'
# Allow reading production secrets
path "fintech/data/production" {
  capabilities = ["read"]
}
# Allow reading specific keys
path "fintech/data/production/*" {
  capabilities = ["read"]
}
# Allow renewing own token
path "auth/token/renew-self" {
  capabilities = ["update"]
}
# Deny all other access
path "*" {
  capabilities = ["deny"]
}
POLICY

# ── Create AppRole for the App ────────────────────────────────────────────────
vault write auth/approle/role/fintech-app \
  token_policies="fintech-app" \
  token_ttl=8h \
  token_max_ttl=24h \
  token_num_uses=0 \
  secret_id_ttl=720h \
  secret_id_num_uses=0

ROLE_ID=$(vault read -field=role_id auth/approle/role/fintech-app/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/fintech-app/secret-id)

echo ""
echo "═══════════════════════════════════════════════"
echo "  ✅ Vault configured!"
echo "  VAULT_ROLE_ID=$ROLE_ID"
echo "  VAULT_SECRET_ID=$SECRET_ID"
echo ""
echo "  Store these in GitHub Secrets / CI environment."
echo "═══════════════════════════════════════════════"

# ── Enable audit log ──────────────────────────────────────────────────────────
vault audit enable file file_path=/vault/logs/audit.log
echo "✓ Audit logging enabled"
