#!/bin/bash
# 04-manage-agent.sh — Agent 管理快捷脚本
# 自动检测运行环境（生产 venv / 开发直接 python3）

set -e

# 禁止以 root/sudo 运行（避免共享目录路径解析为 /root/.openclaw）
if [ "$(id -u)" -eq 0 ]; then
    echo "错误: 请不要使用 sudo 运行此脚本"
    echo "用法: ./04-manage-agent.sh <command> [args]"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 从 bin/ 找兄弟 scripts/ 目录
MANAGE_PY="$(dirname "$SCRIPT_DIR")/scripts/manage-agent.py"

# 读取 Gateway 配置（优先 /opt/openclaw/gateway/.env，回退 /opt/openclaw/.env）
ENV_FILE="/opt/openclaw/gateway/.env"
if [ ! -f "$ENV_FILE" ]; then
    ENV_FILE="/opt/openclaw/.env"
fi
if [ -f "$ENV_FILE" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
fi

# 如果从 /opt/openclaw/gateway/ 运行（manage-agent.sh 快捷入口）
if [ ! -f "$MANAGE_PY" ]; then
    MANAGE_PY="$SCRIPT_DIR/scripts/manage-agent.py"
fi
# 也可能同目录下
if [ ! -f "$MANAGE_PY" ]; then
    MANAGE_PY="$SCRIPT_DIR/manage-agent.py"
fi

if [ ! -f "$MANAGE_PY" ]; then
    echo "错误: 找不到 manage-agent.py"
    exit 1
fi

# 生产环境：使用 venv python
VENV_PYTHON="/opt/openclaw/gateway/venv/bin/python"
if [ -x "$VENV_PYTHON" ]; then
    exec "$VENV_PYTHON" "$MANAGE_PY" "$@"
fi

# 开发环境：直接用 python3
exec python3 "$MANAGE_PY" "$@"
