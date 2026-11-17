# syntax=docker/dockerfile:1
# LUMASHA Smart — image de production (Next.js standalone + base SQLite persistante).
#
# La base vit dans un volume monté sur /app/data (voir docker-compose.yml ou
# `-v lumasha-data:/app/data`). Sans volume, les données seraient perdues à
# chaque redéploiement du conteneur.

# ---------- Dépendances ----------
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# ---------- Build ----------
FROM node:24-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Variables publiques inlinées au build (surchargeables via --build-arg).
ARG NEXT_PUBLIC_SITE_URL
ARG NEXT_PUBLIC_WA_NUMBER=+22890000000
ARG NEXT_PUBLIC_STAND=AR114
ENV NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL \
    NEXT_PUBLIC_WA_NUMBER=$NEXT_PUBLIC_WA_NUMBER \
    NEXT_PUBLIC_STAND=$NEXT_PUBLIC_STAND \
    NEXT_TELEMETRY_DISABLED=1

RUN npm run build

# ---------- Exécution ----------
FROM node:24-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0 \
    LUMASHA_DB_PATH=/app/data/lumasha.db

RUN addgroup -g 1001 -S nodejs && adduser -S nextjs -u 1001

# Sortie standalone : serveur + dépendances minimales.
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Dossier de la base (monté en volume).
RUN mkdir -p /app/data && chown -R nextjs:nodejs /app/data
VOLUME ["/app/data"]

USER nextjs
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/api/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]
