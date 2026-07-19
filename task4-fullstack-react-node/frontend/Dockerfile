# syntax=docker/dockerfile:1

############################
# Stage 1: build static assets
############################
FROM node:20-alpine AS build
WORKDIR /app

# Optional API base baked in at build time (defaults to relative /api).
ARG VITE_API_BASE=""
ENV VITE_API_BASE=$VITE_API_BASE

COPY package.json package-lock.json* ./
RUN npm ci

COPY . .
RUN npm run build

############################
# Stage 2: serve with nginx (non-root)
############################
FROM nginx:1.27-alpine AS runtime

# Custom SPA + reverse-proxy config listening on 8080.
COPY nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/dist /usr/share/nginx/html

# Make the paths nginx needs writable by the unprivileged "nginx" user.
RUN touch /tmp/nginx.pid \
  && chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx /tmp

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q --spider http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
