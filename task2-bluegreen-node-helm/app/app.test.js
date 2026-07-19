'use strict';

const request = require('supertest');
const app = require('./server');

describe('bluegreen-node app', () => {
  it('GET / returns color and version', async () => {
    const res = await request(app).get('/');
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('color');
    expect(res.body).toHaveProperty('version');
  });

  it('GET / reflects the COLOR env var', async () => {
    // server.js reads COLOR at require time; default is "blue".
    const res = await request(app).get('/');
    expect(res.body.color).toBe(process.env.COLOR || 'blue');
  });

  it('GET /health returns 200 JSON ok', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toBe(200);
    expect(res.body.status).toBe('ok');
  });
});
