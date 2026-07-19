'use strict';

const { test } = require('node:test');
const assert = require('node:assert');
const request = require('supertest');
const app = require('./server');

test('GET /health returns ok', async () => {
  const res = await request(app).get('/health');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.status, 'ok');
});

test('GET / returns running message', async () => {
  const res = await request(app).get('/');
  assert.strictEqual(res.status, 200);
  assert.match(res.body.message, /running/);
});

test('GET /load burns CPU and reports burnedMs', async () => {
  const res = await request(app).get('/load?ms=50');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.burnedMs, 50);
  assert.ok(res.body.iterations > 0);
});

test('GET /load caps burn time at 2000ms', async () => {
  const res = await request(app).get('/load?ms=999999');
  assert.strictEqual(res.status, 200);
  assert.strictEqual(res.body.burnedMs, 2000);
});
