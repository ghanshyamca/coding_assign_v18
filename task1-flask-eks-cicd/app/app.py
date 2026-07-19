"""Minimal but production-shaped Flask application for the flask-eks demo.

Exposes:
  GET /        -> greeting + metadata as JSON
  GET /health  -> liveness/readiness probe target as JSON

The app is served by gunicorn in the container (see Dockerfile) but can also
be run directly with `python app.py` for local development.
"""
import os
import platform

from flask import Flask, jsonify

# Application version is injected at build/deploy time via the APP_VERSION env
# var (Docker build ARG -> ENV, or Kubernetes env). Falls back to "dev".
APP_VERSION = os.environ.get("APP_VERSION", "dev")

app = Flask(__name__)


@app.route("/", methods=["GET"])
def index():
    """Root endpoint returning a small JSON payload with app metadata."""
    return jsonify(
        {
            "message": "Hello from flask-eks!",
            "app": "flask-eks",
            "version": APP_VERSION,
            "hostname": platform.node(),
        }
    )


@app.route("/health", methods=["GET"])
def health():
    """Health endpoint used by container HEALTHCHECK and k8s probes."""
    return jsonify({"status": "healthy", "version": APP_VERSION}), 200


if __name__ == "__main__":
    # Local development server only. Production uses gunicorn.
    port = int(os.environ.get("PORT", "5000"))
    app.run(host="0.0.0.0", port=port)
