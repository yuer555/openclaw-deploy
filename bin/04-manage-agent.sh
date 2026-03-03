#!/bin/bash
# 04-manage-agent.sh — Agent 管理快捷脚本
# 自动检测运行环境（生产 venv / 开发直接 python3）
# 生产环境以 openclaw 用户运行，确保数据库写权限

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 从 bin/ 找兄弟 scripts/ 目录
MANAGE_PY="$(dirname "$SCRIPT_DIR")/scripts/manage-agent.py"

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

# 生产环境：使用 venv python，以 openclaw 用户运行（确保数据库写权限）
VENV_PYTHON="/opt/openclaw/gateway/venv/bin/python"
RUN_USER="openclaw"
if [ -x "$VENV_PYTHON" ]; then
    if [ "$(whoami)" = "$RUN_USER" ]; then
        exec "$VENV_PYTHON" "$MANAGE_PY" "$@"
    else
        # 通过 sudo -u 切换到 openclaw 用户
        # 传递 locale 环境变量确保中文输入和退格正常工作：
        #   LANG/LC_CTYPE: 多字节字符宽度（readline 退格需要）
        #   TERM: 终端类型
        #   INPUTRC: readline 配置（多字节字符支持）
        #   HOME: 让 _try_read_local_token() 能找到调用者的 ~/.openclaw/
        exec sudo -u "$RUN_USER" \
            HOME="$HOME" \
            LANG="${LANG:-en_US.UTF-8}" \
            LC_CTYPE="${LC_CTYPE:-en_US.UTF-8}" \
            TERM="${TERM:-xterm}" \
            INPUTRC="${INPUTRC:-/etc/inputrc}" \
            PYTHONIOENCODING=utf-8 \
            "$VENV_PYTHON" "$MANAGE_PY" "$@"
    fi
fi

# 开发环境：直接用 python3
exec python3 "$MANAGE_PY" "$@"
