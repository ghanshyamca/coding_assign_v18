const { test } = require("node:test");
const assert = require("node:assert");
const { createApp } = require("../src/app");

async function start() {
  const server = createApp().listen(0);
  const port = server.address().port;
  return { server, base: `http://127.0.0.1:${port}` };
}

test("GET /health returns ok", async () => {
  const { server, base } = await start();
  try {
    const res = await fetch(`${base}/health`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.status, "ok");
    assert.strictEqual(body.service, "orders");
  } finally {
    server.close();
  }
});

test("GET / returns orders list", async () => {
  const { server, base } = await start();
  try {
    const res = await fetch(`${base}/`);
    assert.strictEqual(res.status, 200);
    const body = await res.json();
    assert.strictEqual(body.service, "orders");
    assert.ok(Array.isArray(body.orders));
    assert.strictEqual(body.count, body.orders.length);
  } finally {
    server.close();
  }
});
