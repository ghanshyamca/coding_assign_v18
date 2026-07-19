const express = require("express");

const SERVICE_NAME = "orders";

// A tiny in-memory order list so the endpoint returns something real.
const ORDERS = [
  { id: 1, item: "keyboard", qty: 2 },
  { id: 2, item: "mouse", qty: 1 },
];

function createApp() {
  const app = express();

  app.get("/health", (_req, res) => {
    res.status(200).json({ status: "ok", service: SERVICE_NAME });
  });

  app.get("/", (_req, res) => {
    res.status(200).json({
      service: SERVICE_NAME,
      environment: process.env.APP_ENV || "unknown",
      count: ORDERS.length,
      orders: ORDERS,
    });
  });

  return app;
}

module.exports = { createApp };
