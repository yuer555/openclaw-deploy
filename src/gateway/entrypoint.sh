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
PROVIDER="${MODEL_PROVIDER:-anthropic}"

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
    },
    "http": {
      "endpoints": {
        "responses": { "enabled": true }
      }
    }
  }
}
CONF
  echo '{"providers":{}}' > /root/.openclaw/agents/main/agent/models.json
  echo '{}' > /root/.openclaw/agents/main/agent/auth-profiles.json
  export ANTHROPIC_API_KEY=""
  echo "Using OpenAI API (OPENAI_API_KEY), model: openai/gpt-4o"

elif [ -n "$API_BASE" ] && [ -n "$API_SECRET" ]; then
  # 方式二：第三方流量池（自定义 provider，支持任意模型）
  # MODEL_PROVIDER 用自定义名称（如 gmn），避免与 openclaw 内置 provider 冲突
  # MODEL_API 指定 API 协议格式（默认 openai-responses）
  API_FORMAT="${MODEL_API:-openai-responses}"

  cat > /root/.openclaw/openclaw.json << CONF
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "${PROVIDER}/${MODEL}"
      },
      "models": {
        "${PROVIDER}/${MODEL}": {}
      }
    }
  },
  "gateway": {
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "${INTERNAL_TOKEN}"
    },
    "http": {
      "endpoints": {
        "responses": { "enabled": true }
      }
    },
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  }
}
CONF
  cat > /root/.openclaw/agents/main/agent/models.json << CONF
{
  "providers": {
    "${PROVIDER}": {
      "baseUrl": "${API_BASE}",
      "apiKey": "${API_SECRET}",
      "auth": "api-key",
      "api": "${API_FORMAT}",
      "authHeader": true,
      "models": [
        {
          "id": "${MODEL}",
          "name": "${MODEL}"
        }
      ]
    }
  }
}
CONF
  cat > /root/.openclaw/agents/main/agent/auth-profiles.json << CONF
{
  "version": 1,
  "profiles": {
    "${PROVIDER}:default": {
      "type": "api_key",
      "provider": "${PROVIDER}",
      "key": "${API_SECRET}"
    }
  }
}
CONF
  echo "Using third-party API: ${API_BASE} provider: ${PROVIDER} model: ${PROVIDER}/${MODEL} api: ${API_FORMAT}"

else
  cat > /root/.openclaw/openclaw.json << CONF
{
  "gateway": {
    "auth": {
      "mode": "token",
      "token": "${INTERNAL_TOKEN}"
    },
    "http": {
      "endpoints": {
        "responses": { "enabled": true }
      }
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
cd /root/.openclaw/workspace
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
