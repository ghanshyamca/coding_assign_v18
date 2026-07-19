# syntax=docker/dockerfile:1

###############################################################################
# Stage 1 — install production dependencies
###############################################################################
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
# Deterministic install of production deps only.
RUN npm ci --omit=dev

###############################################################################
# Stage 2 — runtime
###############################################################################
FROM node:20-alpine AS runtime
ENV NODE_ENV=production \
    PORT=3000

WORKDIR /app

# Copy pre-installed node_modules and app source.
COPY --from=deps /app/node_modules ./node_modules
COPY server.js package.json ./

# node:20-alpine ships a non-root "node" user (uid 1000). Run as it.
USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:'+(process.env.PORT||3000)+'/health',r=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "server.js"]
