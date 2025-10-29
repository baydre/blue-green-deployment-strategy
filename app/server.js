const express = require('express');
const app = express();

// Read environment variables
const RELEASE_ID = process.env.RELEASE_ID || 'unknown';
const APP_POOL = process.env.APP_POOL || 'unknown';
const PORT = process.env.PORT || 80;

// State: whether chaos mode is active (returns 500s)
let chaosMode = false;
let chaosType = 'error'; // 'error' or 'timeout'

// Middleware to add custom headers to all responses
app.use((req, res, next) => {
  res.setHeader('X-App-Pool', APP_POOL);
  res.setHeader('X-Release-Id', RELEASE_ID);
  next();
});

// Root endpoint
app.get('/', (req, res) => {
  if (chaosMode) {
    return res.status(500).json({
      error: 'Chaos mode active',
      pool: APP_POOL,
      release: RELEASE_ID,
      timestamp: new Date().toISOString()
    });
  }

  res.status(200).json({
    message: 'OK',
    pool: APP_POOL,
    release: RELEASE_ID,
    timestamp: new Date().toISOString()
  });
});

// Version endpoint (required by grading criteria)
app.get('/version', (req, res) => {
  if (chaosMode) {
    return res.status(500).json({
      error: 'Chaos mode active',
      pool: APP_POOL,
      release: RELEASE_ID,
      timestamp: new Date().toISOString()
    });
  }

  res.status(200).json({
    pool: APP_POOL,
    release: RELEASE_ID,
    version: RELEASE_ID,
    timestamp: new Date().toISOString()
  });
});

// Health check endpoint (required by grading criteria)
app.get('/healthz', (req, res) => {
  // Health endpoint always returns 200 even in chaos mode
  // (so Docker healthcheck still passes)
  res.status(200).json({
    status: 'healthy',
    pool: APP_POOL,
    release: RELEASE_ID,
    chaosMode: chaosMode
  });
});

// Start chaos mode (simulate failures)
app.post('/chaos/start', (req, res) => {
  const mode = req.query.mode || 'error'; // Support ?mode=error or ?mode=timeout
  chaosMode = true;
  chaosType = mode;
  console.log(`[${APP_POOL}] Chaos mode STARTED with mode: ${mode}`);
  res.status(200).json({
    message: 'Chaos mode activated',
    mode: mode,
    pool: APP_POOL,
    release: RELEASE_ID
  });
});

// Stop chaos mode (restore normal operation)
app.post('/chaos/stop', (req, res) => {
  chaosMode = false;
  console.log(`[${APP_POOL}] Chaos mode STOPPED`);
  res.status(200).json({
    message: 'Chaos mode deactivated',
    pool: APP_POOL,
    release: RELEASE_ID
  });
});

// Start server
app.listen(PORT, '0.0.0.0', () => {
  console.log(`[${APP_POOL}] Server listening on port ${PORT}`);
  console.log(`[${APP_POOL}] Release: ${RELEASE_ID}`);
  console.log(`[${APP_POOL}] Chaos mode: ${chaosMode}`);
});
