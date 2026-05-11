# ─────────────────────────────────────────────────────────────────────────────
# DEPLOYMENT STRATEGY 09: Secrets Management – Vault / Env Vars
# FintechBank – Fintech Scalability Challenge
# ─────────────────────────────────────────────────────────────────────────────

ui            = true
log_level     = "warn"
log_format    = "json"

# ── API listener ──────────────────────────────────────────────────────────────
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_cert_file = "/vault/certs/vault.crt"
  tls_key_file  = "/vault/certs/vault.key"
  tls_min_version = "tls12"
  tls_cipher_suites = "TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
}

# ── Storage Backend (Raft for HA) ─────────────────────────────────────────────
storage "raft" {
  path    = "/vault/data"
  node_id = "fintech-vault-01"

  retry_join {
    leader_api_addr = "https://vault-01.fintech.dev:8200"
  }
}

# ── HA Config ─────────────────────────────────────────────────────────────────
cluster_addr = "https://vault-01.fintech.dev:8201"
api_addr     = "https://vault.fintech.dev:8200"

# ── Seal Configuration (auto-unseal via cloud KMS) ────────────────────────────
# Uncomment for AWS KMS:
# seal "awskms" {
#   region     = "ap-south-1"
#   kms_key_id = "mrk-xxxxxxxxxxxx"
# }

# ── Telemetry ─────────────────────────────────────────────────────────────────
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname          = true
}

# ── Misc ──────────────────────────────────────────────────────────────────────
disable_mlock           = false
default_lease_ttl       = "8h"
max_lease_ttl           = "720h"
raw_storage_endpoint    = false
introspection_endpoint  = false
