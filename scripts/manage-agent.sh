#!/bin/bash
# manage-agent.sh — Agent 管理快捷脚本
# 自动检测运行环境（生产 venv / 开发直接 python3）

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGE_PY="$SCRIPT_DIR/scripts/manage-agent.py"

# 如果从 /opt/openclaw/gateway/ 运行（install.sh 会将此脚本复制到此处）
if [ ! -f "$MANAGE_PY" ]; then
    MANAGE_PY="$SCRIPT_DIR/manage-agent.py"
fi
# 也可能在 scripts/ 目录下
if [ ! -f "$MANAGE_PY" ]; then
    MANAGE_PY="$(dirname "$SCRIPT_DIR")/scripts/manage-agent.py"
fi

if [ ! -f "$MANAGE_PY" ]; then
    echo "❌ 找不到 manage-agent.py"
    exit 1
fi

# 生产环境：使用 venv python
VENV_PYTHON="/opt/openclaw/gateway/venv/bin/python"
if [ -x "$VENV_PYTHON" ]; then
    exec "$VENV_PYTHON" "$MANAGE_PY" "$@"
fi

# 开发环境：直接用 python3
exec python3 "$MANAGE_PY" "$@"
