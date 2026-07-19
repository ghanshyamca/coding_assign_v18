'use strict';

const express = require('express');

const app = express();
const PORT = process.env.PORT || 3001;
const MESSAGE = process.env.API_MESSAGE || 'Hello from the Node.js backend!';

app.use(express.json());

// Liveness / readiness endpoint used by Kubernetes probes and Docker HEALTHCHECK.
app.get('/api/health', (req, res) => {
  res.status(200).json({ status: 'ok', service: 'fullstack-backend' });
});

// Primary API consumed by the React frontend.
app.get('/api/message', (req, res) => {
  res.status(200).json({ message: MESSAGE });
});

// Export the app so tests can import it without binding a port.
module.exports = app;

// Only start listening when run directly (not when imported by jest).
if (require.main === module) {
  app.listen(PORT, () => {
    // eslint-disable-next-line no-console
    console.log(`fullstack-backend listening on port ${PORT}`);
  });
}
