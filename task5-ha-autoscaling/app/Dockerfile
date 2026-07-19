# syntax=docker/dockerfile:1

###############################################################################
# Stage 1 - install production dependencies
###############################################################################
FROM node:20.15.1-alpine3.20 AS deps

WORKDIR /app

# Install only production deps, fully locked by the committed package-lock.json.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund

###############################################################################
# Stage 2 - minimal runtime image
###############################################################################
FROM node:20.15.1-alpine3.20 AS runtime

ENV NODE_ENV=production \
    PORT=3000

WORKDIR /app

# wget is needed for the container HEALTHCHECK (already present in alpine base).
COPY --from=deps /app/node_modules ./node_modules
COPY package.json server.js ./

# Run as the built-in unprivileged "node" user (non-root).
USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:3000/health || exit 1

CMD ["node", "server.js"]
