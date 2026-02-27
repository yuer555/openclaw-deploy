#!/bin/bash
#==============================================================================
# 脚本名称: stop-gateway.sh
# 功能描述: 停止宿主机 Gateway（dispatcher + Flask）
# 使用方法: ./stop-gateway.sh
# 版本: V2.0
#==============================================================================

PID_DIR="${PID_DIR:-/tmp/openclaw}"

echo "=== 停止 OpenClaw Gateway ==="

stop_process() {
    local name="$1"
    local pid_file="$PID_DIR/$2"
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            echo "$name (PID $pid) 已停止"
        else
            echo "$name (PID $pid) 已不存在"
        fi
        rm -f "$pid_file"
    else
        echo "$name PID 文件不存在，跳过"
    fi
}

stop_process "Flask gateway" "flask.pid"

echo "=== Gateway 已停止 ==="
