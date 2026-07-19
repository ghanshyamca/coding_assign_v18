"""Pytest suite covering the Flask endpoints using the built-in test client."""
import json

import pytest

from app import app as flask_app


@pytest.fixture()
def client():
    flask_app.config.update({"TESTING": True})
    with flask_app.test_client() as test_client:
        yield test_client


def test_index_returns_200_and_json(client):
    resp = client.get("/")
    assert resp.status_code == 200
    data = json.loads(resp.data)
    assert data["app"] == "flask-eks"
    assert data["message"] == "Hello from flask-eks!"
    assert "version" in data


def test_health_returns_200_and_healthy(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    data = json.loads(resp.data)
    assert data["status"] == "healthy"
    assert "version" in data


def test_unknown_route_returns_404(client):
    resp = client.get("/does-not-exist")
    assert resp.status_code == 404
