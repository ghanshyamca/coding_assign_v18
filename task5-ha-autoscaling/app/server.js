'use strict';

const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;

// Liveness / readiness probe target.
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', pod: process.env.HOSTNAME || 'local' });
});

// Root endpoint.
app.get('/', (req, res) => {
  res.status(200).json({
    message: 'ha-app is running',
    pod: process.env.HOSTNAME || 'local',
    hint: 'Hit /load?ms=200 repeatedly to burn CPU and trigger the HPA.'
  });
});

// CPU-burn endpoint. Busy-loops for `ms` milliseconds (default 100, capped at
// 2000) to generate CPU load on demand so HPA scaling is demonstrable.
app.get('/load', (req, res) => {
  const requested = parseInt(req.query.ms, 10);
  const ms = Math.min(Number.isNaN(requested) ? 100 : requested, 2000);

  const start = Date.now();
  let iterations = 0;
  // Intentional busy loop to consume CPU.
  while (Date.now() - start < ms) {
    Math.sqrt(Math.random() * Math.random());
    iterations++;
  }

  res.status(200).json({
    message: 'load generated',
    burnedMs: ms,
    iterations,
    pod: process.env.HOSTNAME || 'local'
  });
});

// Only start listening when run directly (so tests can import the app).
if (require.main === module) {
  app.listen(PORT, () => {
    // eslint-disable-next-line no-console
    console.log(`ha-app listening on port ${PORT}`);
  });
}

module.exports = app;
