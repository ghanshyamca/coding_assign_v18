# syntax=docker/dockerfile:1

##############################
# Stage 1 — install deps
##############################
FROM node:20.15.1-alpine3.20 AS build
WORKDIR /app
COPY package.json package-lock.json* ./
# Production-only install; direct deps are pinned exactly in package.json.
# (Commit a package-lock.json and switch to `npm ci` for fully locked
# transitive deps.)
RUN npm install --omit=dev --no-audit --no-fund

##############################
# Stage 2 — runtime
##############################
FROM node:20.15.1-alpine3.20 AS runtime
ENV NODE_ENV=production
WORKDIR /app

# Copy vetted node_modules from build stage and the app source.
COPY --from=build /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# Run as the built-in non-root "node" user.
USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "src/server.js"]
