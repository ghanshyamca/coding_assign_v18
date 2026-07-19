# syntax=docker/dockerfile:1

############################
# Stage 1: install deps
############################
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
# Install only production dependencies for the runtime image.
RUN npm ci --omit=dev

############################
# Stage 2: runtime
############################
FROM node:20-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

# node:20-alpine ships a non-root "node" user (uid 1000).
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node package.json ./
COPY --chown=node:node server.js ./

USER node

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://127.0.0.1:3001/api/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "server.js"]
