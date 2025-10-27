# Blue/Green Test App

Simple Express.js application for testing blue/green deployment with Nginx.

## Features

- **`/`** - Main endpoint. Returns 200 with JSON and headers (`X-App-Pool`, `X-Release-Id`). Returns 500 if chaos mode is active.
- **`/health`** - Health check endpoint. Always returns 200 (even in chaos mode).
- **`POST /chaos/start`** - Activate chaos mode (all requests to `/` return 500).
- **`POST /chaos/stop`** - Deactivate chaos mode (restore normal operation).

## Build Instructions

Build the blue and green images locally:

```bash
# Build blue image
docker build -t blue-app:local ./app

# Build green image
docker build -t green-app:local ./app
```

## Test Locally

Run a single instance to test:

```bash
docker run -p 3000:80 \
  -e RELEASE_ID=v1.0.0-test \
  -e APP_POOL=test \
  blue-app:local
```

Test endpoints:

```bash
# Normal response
curl -i http://localhost:3000/

# Health check
curl http://localhost:3000/health

# Activate chaos mode
curl -X POST http://localhost:3000/chaos/start

# Verify chaos mode (should return 500)
curl -i http://localhost:3000/

# Deactivate chaos mode
curl -X POST http://localhost:3000/chaos/stop
```

## Environment Variables

- `RELEASE_ID` - Release identifier exposed in `X-Release-Id` header (default: "unknown")
- `APP_POOL` - Pool name exposed in `X-App-Pool` header (default: "unknown")
- `PORT` - Server port (default: 80)
