#!/bin/sh
set -e

echo "Starting OpenClaw dispatcher (port 18789)..."
cd /workspace
npx openclaw gateway --allow-unconfigured &
OPENCLAW_PID=$!

# Wait for openclaw to be ready
echo "Waiting for dispatcher to be ready..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:18789/health > /dev/null 2>&1; then
        echo "Dispatcher ready."
        break
    fi
    sleep 2
done

echo "Starting Flask gateway (port 8000)..."
cd /app
exec python wecom_gateway.py
