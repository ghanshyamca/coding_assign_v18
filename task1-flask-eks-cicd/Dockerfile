# syntax=docker/dockerfile:1

###############################################################################
# Stage 1 - builder: install python dependencies into an isolated prefix
###############################################################################
FROM python:3.12-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /build

# Install dependencies first to leverage Docker layer caching.
COPY app/requirements.txt .
RUN pip install --prefix=/install --no-cache-dir -r requirements.txt

###############################################################################
# Stage 2 - runtime: minimal image, non-root user, gunicorn entrypoint
###############################################################################
FROM python:3.12-slim AS runtime

# Build-time version, promoted to a runtime env var consumed by app.py.
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/usr/local/bin:${PATH}"

# curl is used by the container HEALTHCHECK below.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    # Create a non-root user/group with a fixed uid/gid of 1000.
    && groupadd --gid 1000 appuser \
    && useradd --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin appuser

# Copy the installed python packages from the builder stage.
COPY --from=builder /install /usr/local

WORKDIR /app
COPY app/ /app/

# Drop privileges.
USER 1000

EXPOSE 5000

# Container-level health check hitting the Flask /health endpoint.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -fsS http://127.0.0.1:5000/health || exit 1

# Serve with gunicorn: 2 workers, bind on all interfaces port 5000.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "60", "app:app"]
