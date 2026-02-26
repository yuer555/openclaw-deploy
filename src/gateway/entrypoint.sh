#!/bin/sh
set -e

# Configure openclaw with token auth and third-party API provider
mkdir -p /root/.openclaw/agents/main/agent
INTERNAL_TOKEN="${OPENCLAW_INTERNAL_TOKEN:-openclaw-internal-secret}"

# Gateway auth + model config
API_BASE="${API_BASE_URL:-}"
API_SECRET="${API_KEY:-}"
MODEL="${MODEL_NAME:-claude-sonnet-4}"

if [ -n "$API_BASE" ] && [ -n "$API_SECRET" ]; then
  cat > /root/.openclaw/openclaw.json << CONF
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/${MODEL}"
      },
      "models": {
        "anthropic/${MODEL}": {}
      }
    }
  },
  "gateway": {
    "auth": {
      "mode": "token",
      "token": "${INTERNAL_TOKEN}"
    }
  }
}
CONF
else
  cat > /root/.openclaw/openclaw.json << CONF
{
  "gateway": {
    "auth": {
      "mode": "token",
      "token": "${INTERNAL_TOKEN}"
    }
  }
}
CONF
fi

# Model provider config (anthropic with third-party baseUrl)
if [ -n "$API_BASE" ] && [ -n "$API_SECRET" ]; then
  cat > /root/.openclaw/agents/main/agent/models.json << CONF
{
  "providers": {
    "anthropic": {
      "baseUrl": "${API_BASE}",
      "models": []
    }
  }
}
CONF
  cat > /root/.openclaw/agents/main/agent/auth-profiles.json << CONF
{
  "profiles": {
    "anthropic:manual": {
      "provider": "anthropic",
      "kind": "apiKey",
      "apiKey": "${API_SECRET}",
      "label": "third-party"
    }
  }
}
CONF
  echo "Configured third-party API: ${API_BASE} model: anthropic/${MODEL}"
else
  echo "WARNING: API_BASE_URL or API_KEY not set, openclaw may not work"
  echo '{"providers":{}}' > /root/.openclaw/agents/main/agent/models.json
  echo '{}' > /root/.openclaw/agents/main/agent/auth-profiles.json
fi

export OPENCLAW_INTERNAL_TOKEN="$INTERNAL_TOKEN"
export ANTHROPIC_API_KEY="${API_SECRET}"

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
