# ─── Stage 1: Builder ────────────────────────────────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files first (layer caching)
COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

# ─── Stage 2: Production ──────────────────────────────────────────────────────
FROM node:20-alpine AS production

# Security: create non-root user
RUN addgroup -g 1001 -S nodejs && adduser -S fintech -u 1001

WORKDIR /app

# Copy from builder
COPY --from=builder --chown=fintech:nodejs /app/node_modules ./node_modules
COPY --chown=fintech:nodejs . .

# Remove dev files
RUN rm -f .env.* *.test.js

USER fintech

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:4000/health || exit 1

ENV NODE_ENV=production

CMD ["node", "server.js"]
