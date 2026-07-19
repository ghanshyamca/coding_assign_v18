const express = require("express");

// Downstream orders service. In Kubernetes this resolves to the orders
// Service DNS name inside the same namespace.
const ORDERS_URL = process.env.ORDERS_URL || "http://orders:3000";
const SERVICE_NAME = "api-gateway";

function createApp() {
  const app = express();

  app.get("/health", (_req, res) => {
    res.status(200).json({ status: "ok", service: SERVICE_NAME });
  });

  app.get("/", async (_req, res) => {
    let orders = { reachable: false };
    try {
      // Best-effort call to the orders service so the gateway demonstrates
      // real service-to-service communication without hard-failing when the
      // dependency is absent (e.g. in unit tests).
      const resp = await fetch(`${ORDERS_URL}/`, { signal: AbortSignal.timeout(1000) });
      orders = { reachable: resp.ok, data: await resp.json() };
    } catch (_err) {
      orders = { reachable: false };
    }

    res.status(200).json({
      service: SERVICE_NAME,
      message: "microsvc api-gateway up",
      environment: process.env.APP_ENV || "unknown",
      orders,
    });
  });

  return app;
}

module.exports = { createApp };
