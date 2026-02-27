#!/bin/bash
#==============================================================================
# 脚本名称: configure-openclaw.sh
# 功能描述: 从环境变量生成 openclaw 配置文件（宿主机版）
# 使用方法: source .env.prod && ./configure-openclaw.sh
# 版本: V2.0
#==============================================================================

set -e

OPENCLAW_DIR="${OPENCLAW_HOME:-$HOME/.openclaw}"
AGENT_DIR="$OPENCLAW_DIR/agents/main/agent"

mkdir -p "$AGENT_DIR"

INTERNAL_TOKEN="${OPENCLAW_INTERNAL_TOKEN:-openclaw-internal-secret}"
OPENAI_KEY="${OPENAI_API_KEY:-}"
API_BASE="${API_BASE_URL:-}"
API_SECRET="${API_KEY:-}"
MODEL="${MODEL_NAME:-claude-sonnet-4-20250514}"

if [ -n "$OPENAI_KEY" ]; then
  cat > "$OPENCLAW_DIR/openclaw.json" << CONF
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
  echo '{"providers":{}}' > "$AGENT_DIR/models.json"
  echo '{}' > "$AGENT_DIR/auth-profiles.json"
  echo "Using OpenAI API (OPENAI_API_KEY), model: openai/gpt-4o"

elif [ -n "$API_BASE" ] && [ -n "$API_SECRET" ]; then
  cat > "$OPENCLAW_DIR/openclaw.json" << CONF
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
  cat > "$AGENT_DIR/models.json" << CONF
{
  "providers": {
    "anthropic": {
      "baseUrl": "${API_BASE}",
      "models": []
    }
  }
}
CONF
  cat > "$AGENT_DIR/auth-profiles.json" << CONF
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
  cat > "$OPENCLAW_DIR/openclaw.json" << CONF
{
  "gateway": {
    "auth": {
      "mode": "token",
      "token": "${INTERNAL_TOKEN}"
    }
  }
}
CONF
  echo '{"providers":{}}' > "$AGENT_DIR/models.json"
  echo '{}' > "$AGENT_DIR/auth-profiles.json"
  echo "WARNING: No API key configured, openclaw may not work"
fi

echo "OpenClaw config written to $OPENCLAW_DIR"
