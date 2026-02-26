#!/bin/sh
set -e

# Configure openclaw with token auth and API provider
mkdir -p /root/.openclaw/agents/main/agent
INTERNAL_TOKEN="${OPENCLAW_INTERNAL_TOKEN:-openclaw-internal-secret}"

# API 配置优先级: OPENAI_API_KEY > API_BASE_URL + API_KEY
OPENAI_KEY="${OPENAI_API_KEY:-}"
API_BASE="${API_BASE_URL:-}"
API_SECRET="${API_KEY:-}"
MODEL="${MODEL_NAME:-claude-sonnet-4-20250514}"

if [ -n "$OPENAI_KEY" ]; then
  # 方式一：直接使用 OpenAI API
  cat > /root/.openclaw/openclaw.json << CONF
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "openai/gpt-4o"
      },
      "models": {
        "openai/gpt-4o": {}
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
  echo '{"providers":{}}' > /root/.openclaw/agents/main/agent/models.json
  echo '{}' > /root/.openclaw/agents/main/agent/auth-profiles.json
  export ANTHROPIC_API_KEY=""
  echo "Using OpenAI API (OPENAI_API_KEY), model: openai/gpt-4o"

elif [ -n "$API_BASE" ] && [ -n "$API_SECRET" ]; then
  # 方式二：第三方 API（通过 anthropic provider 代理）
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
  export ANTHROPIC_API_KEY="${API_SECRET}"
  echo "Using third-party API: ${API_BASE} model: anthropic/${MODEL}"

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
  echo '{"providers":{}}' > /root/.openclaw/agents/main/agent/models.json
  echo '{}' > /root/.openclaw/agents/main/agent/auth-profiles.json
  echo "WARNING: No API key configured, openclaw may not work"
fi

export OPENCLAW_INTERNAL_TOKEN="$INTERNAL_TOKEN"

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
