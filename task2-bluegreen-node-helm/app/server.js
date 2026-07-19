'use strict';

const express = require('express');

const app = express();

// COLOR distinguishes blue vs green deployments visually / in responses.
const COLOR = process.env.COLOR || 'blue';
// VERSION is typically set to the git SHA at build/deploy time.
const VERSION = process.env.VERSION || 'dev';
const PORT = parseInt(process.env.PORT, 10) || 3000;

app.get('/', (req, res) => {
  res.status(200).json({ color: COLOR, version: VERSION });
});

app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok', color: COLOR });
});

// Only start listening when run directly, so tests can import the app.
if (require.main === module) {
  app.listen(PORT, () => {
    // eslint-disable-next-line no-console
    console.log(`bluegreen-node [${COLOR}] version=${VERSION} listening on :${PORT}`);
  });
}

module.exports = app;
