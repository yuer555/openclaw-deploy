#!/bin/bash
#==============================================================================
# 脚本名称: start-gateway.sh
# 功能描述: 启动宿主机 Gateway（dispatcher + Flask）
# 使用方法: ./start-gateway.sh
# 版本: V2.0
#==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PID_DIR="${PID_DIR:-/tmp/openclaw}"
OPENCLAW_DIR="${OPENCLAW_HOME:-$HOME/.openclaw}"
WORKSPACE_DIR="$OPENCLAW_DIR/workspace"
GATEWAY_SRC="$PROJECT_DIR/src/gateway"
SHARED_FILES_BASE="${SHARED_FILES_BASE:-/opt/openclaw/shared-files}"
DB_PATH="${DB_PATH:-/opt/openclaw/data/gateway/gateway.db}"
VENV_DIR="${VENV_DIR:-/opt/openclaw/venv}"

# 加载环境变量（优先 production，其次 local）
if [ -f "$PROJECT_DIR/production/.env.prod" ]; then
    set -a; source "$PROJECT_DIR/production/.env.prod"; set +a
elif [ -f "$PROJECT_DIR/local/.env.local" ]; then
    set -a; source "$PROJECT_DIR/local/.env.local"; set +a
fi

# 选择 python：优先用 venv，fallback 到系统 python3
if [ -f "$VENV_DIR/bin/python" ]; then
    PYTHON="$VENV_DIR/bin/python"
else
    PYTHON="python3"
fi

mkdir -p "$PID_DIR"
mkdir -p "$SHARED_FILES_BASE"
mkdir -p "$(dirname "$DB_PATH")"

echo "=== OpenClaw Gateway 启动 ==="

# 启动 Flask gateway
echo "启动 Flask gateway (port 8000)..."
cd "$GATEWAY_SRC"
export DB_PATH
export SHARED_FILES_BASE
export CONTAINER_FILES_BASE="${CONTAINER_FILES_BASE:-/shared-files}"
$PYTHON wecom_gateway.py > /tmp/openclaw/flask.log 2>&1 &
echo $! > "$PID_DIR/flask.pid"

echo "等待 Flask 就绪..."
for i in $(seq 1 15); do
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        echo "Flask gateway 就绪"
        break
    fi
    if [ "$i" -eq 15 ]; then
        echo "ERROR: Flask gateway 启动超时"
        exit 1
    fi
    sleep 2
done

echo "=== Gateway 启动完成 ==="
echo "  Flask PID: $(cat $PID_DIR/flask.pid)"
echo "  日志: /tmp/openclaw/flask.log"
