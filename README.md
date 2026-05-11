# 🏦 FintechBank – Fintech Scalability Challenge
### 10 Deployment Ways in 20 Days · 1 Application · 10 Industry Workflows
> **Desi Cloud. Global Standards. Asli DevOps.**

---

## 📁 Project Structure

```
fintech-deploy/
├── app/
│   ├── backend/                  ← Express.js Banking API
│   │   ├── server.js             ← Main API (auth, accounts, transactions)
│   │   ├── server.test.js        ← Jest test suite (18 tests)
│   │   ├── package.json
│   │   ├── Dockerfile            ← Multi-stage, non-root, hardened
│   │   └── .dockerignore
│   └── frontend/                 ← Single-page Banking UI
│       ├── index.html            ← Full dashboard (no framework, zero deps)
│       ├── Dockerfile
│       └── nginx-frontend.conf
│
├── deployments/
│   ├── 01-vps-ssh/               ← SSH Hardening + UFW + Fail2Ban
│   │   └── setup.sh
│   ├── 02-nginx-proxy/           ← Reverse Proxy + Security Headers + SSL
│   │   └── nginx.conf
│   ├── 03-docker-microservices/  ← Multi-service Docker Compose
│   │   └── docker-compose.yml
│   ├── 04-self-hosted-registry/  ← Private Docker Registry + UI
│   │   └── registry-compose.yml
│   ├── 05-cicd-github-actions/   ← Full CI/CD Pipeline (build→test→deploy)
│   │   └── deploy.yml
│   ├── 06-private-runners/       ← Self-hosted GitHub Actions Runner
│   │   └── runner-setup.sh
│   ├── 07-canary-releases/       ← Traffic Splitting (10% → 100%)
│   │   └── deploy-canary.sh
│   ├── 08-monitoring-grafana/    ← Prometheus + Grafana + Loki + Alertmanager
│   │   ├── docker-compose.monitoring.yml
│   │   └── prometheus.yml
│   ├── 09-secrets-management/    ← Vault + .env management
│   │   ├── vault-config.hcl
│   │   ├── secrets-init.sh
│   │   └── .env.example
│   └── 10-production-launch/     ← Full Production Docker Swarm Stack
│       ├── production-compose.yml
│       ├── health-check.sh
│       └── rollback.sh
│
├── docker-compose.dev.yml        ← Local development (all-in-one)
├── .gitignore
└── README.md
```

---

## 🚀 Quick Start – Run Locally

### Option A: Docker Compose (Recommended)
```bash
# Clone the project
git clone https://github.com/your-org/fintech-deploy.git
cd fintech-deploy

# Start all services
docker compose -f docker-compose.dev.yml up --build

# Access the app
open http://localhost:3000       # Frontend dashboard
open http://localhost:4000/health # API health check
```

### Option B: Manual (Node.js)
```bash
cd app/backend
npm install
node server.js

# In another terminal
cd app/frontend
npx serve .     # or open index.html directly in browser
```

### Demo Credentials
| Email | Password | Role |
|-------|----------|------|
| shubham@fintech.dev | Password@123 | admin |
| priya@fintech.dev | Password@123 | user |

---

## 🔐 10 Deployment Strategies – Overview

### 01 · Secure VPS Hosting (SSH Hardening)
**File:** `deployments/01-vps-ssh/setup.sh`

Full VPS hardening script:
- SSH on port 2222, key-auth only, root login disabled
- UFW firewall (allow only 80, 443, 2222, 4000)
- Fail2Ban with 3-strike bans (1-day lockout for SSH)
- Systemd service with security limits (`NoNewPrivileges`, `PrivateTmp`)
- Modern SSH crypto (curve25519, chacha20-poly1305 only)

```bash
chmod +x deployments/01-vps-ssh/setup.sh
sudo bash deployments/01-vps-ssh/setup.sh
```

---

### 02 · Nginx Reverse Proxy (Security Headers)
**File:** `deployments/02-nginx-proxy/nginx.conf`

Production-grade Nginx config:
- HTTP → HTTPS redirect, TLS 1.2/1.3 only
- HSTS, CSP, X-Frame-Options, OCSP Stapling
- Rate limiting: 30 req/min (API), 5 req/min (auth)
- Upstream load balancing with health checks
- Separate location blocks for API vs static files

```bash
sudo cp deployments/02-nginx-proxy/nginx.conf /etc/nginx/conf.d/fintech.conf
sudo nginx -t && sudo systemctl reload nginx
```

---

### 03 · Docker Microservices (Optimized Builds)
**File:** `deployments/03-docker-microservices/docker-compose.yml`

Production Docker Compose:
- Multi-stage builds (builder → production, non-root users)
- Resource limits (CPU + memory) on every container
- Internal network isolation (`fintech-internal`)
- Health checks on all services
- Read-only filesystem for API container

```bash
cd deployments/03-docker-microservices
docker compose up -d
```

---

### 04 · Self-Hosted Registry (Private Images)
**File:** `deployments/04-self-hosted-registry/registry-compose.yml`

Private Docker registry:
- Registry v2 with htpasswd authentication
- TLS-encrypted registry endpoint
- Registry UI at port 8080
- Image deletion enabled
- Runs alongside main stack

```bash
# Create credentials
docker run --rm --entrypoint htpasswd httpd:2 -Bbn fintech-ci your-password > auth/htpasswd

# Start registry
cd deployments/04-self-hosted-registry
docker compose -f registry-compose.yml up -d

# Push images
docker tag fintech-api registry.fintech.dev:5000/fintech-api:latest
docker push registry.fintech.dev:5000/fintech-api:latest
```

---

### 05 · CI/CD Automation (GitHub Actions)
**File:** `deployments/05-cicd-github-actions/deploy.yml`

Full pipeline:
1. 🔐 Security Audit (npm audit + Semgrep SAST)
2. 🧪 Test (Jest with coverage)
3. 🐳 Docker Build & Push (multi-platform, cache optimized)
4. 🚀 Deploy Staging (SSH + Docker Compose)
5. 🌍 Deploy Production (Canary → Full rollout)

**Required GitHub Secrets:**
```
REGISTRY_HOST, REGISTRY_USER, REGISTRY_PASSWORD
STAGING_HOST, STAGING_SSH_KEY
PROD_HOST, PROD_SSH_KEY
SLACK_WEBHOOK_URL, CODECOV_TOKEN
```

---

### 06 · Private Runners (Self-Hosted Speed)
**File:** `deployments/06-private-runners/runner-setup.sh`

Self-hosted GitHub Actions runner:
- Faster builds (no network latency to registry)
- Direct Docker daemon access
- Automatic daily cleanup cron
- Systemd service with resource limits
- Docker-in-Docker support

```bash
chmod +x deployments/06-private-runners/runner-setup.sh
sudo bash deployments/06-private-runners/runner-setup.sh
# Then register with: sudo -u runner ./config.sh --url ... --token ...
```

---

### 07 · Canary Releases (Traffic Splitting)
**File:** `deployments/07-canary-releases/deploy-canary.sh`

Progressive traffic splitting:
- Deploy to 10% → monitor → promote to 100%
- Nginx `split_clients` directive for traffic splitting
- Automatic health check after canary deploy
- One-command rollback to stable

```bash
# Canary: 10% new version
bash deployments/07-canary-releases/deploy-canary.sh 10

# Full rollout
bash deployments/07-canary-releases/deploy-canary.sh 100

# Rollback
bash deployments/07-canary-releases/deploy-canary.sh 0
```

---

### 08 · Full-Stack Monitoring (Grafana/Prometheus)
**File:** `deployments/08-monitoring-grafana/docker-compose.monitoring.yml`

Complete observability stack:
- **Prometheus** – metrics collection (15s scrape)
- **Grafana** – dashboards at port 3001
- **Alertmanager** – Slack/email alerts
- **Loki + Promtail** – centralized log aggregation
- **Node Exporter** – host metrics (CPU, memory, disk)
- **cAdvisor** – container metrics

```bash
cd deployments/08-monitoring-grafana
docker compose -f docker-compose.monitoring.yml up -d
open http://localhost:3001   # Grafana dashboard
```

---

### 09 · Secrets Management (Vault/Env Vars)
**Files:** `deployments/09-secrets-management/`

HashiCorp Vault setup:
- Raft storage backend (HA-ready)
- TLS 1.2+ with modern ciphers
- KV v2 secrets engine at `fintech/production`
- AppRole authentication for CI/CD
- Audit logging enabled
- Auto-unseal via cloud KMS (AWS/GCP)

```bash
# Initialize Vault and run secrets setup
export VAULT_ADDR=https://vault.fintech.dev:8200
vault operator init
vault operator unseal
bash deployments/09-secrets-management/secrets-init.sh
```

---

### 10 · Production-Grade Launch (Final Stage)
**Files:** `deployments/10-production-launch/`

Full production Docker Swarm deployment:
- 4 API replicas, 2 frontend replicas, 2 nginx replicas
- Rolling updates (1 at a time) with auto-rollback on failure
- Docker secrets for sensitive values
- Resource reservations + limits on every service
- Placement constraints (workers for API, managers for nginx)
- Overlay networks with subnet isolation

```bash
# Initialize swarm
docker swarm init

# Create secrets
echo "your-jwt-secret" | docker secret create jwt_secret -
echo "your-redis-pass" | docker secret create redis_password -

# Deploy stack
docker stack deploy -c deployments/10-production-launch/production-compose.yml fintech

# Health check
bash deployments/10-production-launch/health-check.sh

# Rollback if needed
bash deployments/10-production-launch/rollback.sh sha-abc1234
```

---

## 🧪 Running Tests

```bash
cd app/backend
npm install
npm test

# With coverage report
npm test -- --coverage
```

Tests cover: Auth (login/register/JWT), Accounts, Transactions, Dashboard stats, Health endpoints, Security (headers, 401/403), Rate limiting.

---

## 📊 API Reference

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/auth/login` | ❌ | Login, returns JWT |
| POST | `/api/auth/register` | ❌ | Register new user |
| GET | `/api/auth/me` | ✅ | Current user info |
| GET | `/api/accounts` | ✅ | List accounts + total balance |
| GET | `/api/accounts/:id` | ✅ | Single account details |
| GET | `/api/transactions` | ✅ | Transaction history |
| POST | `/api/transactions/transfer` | ✅ | Transfer funds |
| GET | `/api/dashboard/stats` | ✅ | Dashboard summary |
| GET | `/api/deployments/status` | ✅ | All 10 deployment statuses |
| GET | `/api/admin/users` | ✅ Admin | All users (admin only) |
| GET | `/health` | ❌ | Health check |
| GET | `/metrics` | ❌ | System metrics |

---

## 🔒 Security Features

- **JWT authentication** (8h expiry, HS256)
- **Password hashing** (bcrypt, 10 rounds)
- **Helmet.js** security headers on all responses
- **Rate limiting** (100 req/15min global, 10 req/15min on auth)
- **CORS** locked to allowed origins
- **Request size limit** (10kb body)
- **Role-based access control** (admin vs user)
- **SSH hardening** (key-auth only, modern ciphers, port 2222)
- **Non-root Docker containers**
- **Read-only container filesystem**
- **Docker secrets** for sensitive values in production
- **Vault** for centralized secrets management

---

## 🎯 Tech Stack

| Layer | Technology |
|-------|-----------|
| **Runtime** | Node.js 20 LTS |
| **Framework** | Express.js 4.18 |
| **Auth** | JWT + bcrypt |
| **Frontend** | Vanilla HTML/CSS/JS (zero deps) |
| **Container** | Docker + Docker Compose / Swarm |
| **Proxy** | Nginx 1.25 |
| **Cache** | Redis 7 |
| **CI/CD** | GitHub Actions |
| **Registry** | Docker Registry v2 |
| **Monitoring** | Prometheus + Grafana + Loki |
| **Secrets** | HashiCorp Vault |
| **Testing** | Jest + Supertest |

---

*Built for Tech Tadka with Shubham · Powered by Utho Cloud*
*Desi Cloud. Global Standards. Asli DevOps. 🚀*
