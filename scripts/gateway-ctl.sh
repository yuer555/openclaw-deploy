#!/bin/bash

# OpenClaw Gateway 运维脚本
# 快速执行常见运维操作

INSTALL_DIR="/opt/openclaw/gateway"

case "$1" in
    start)
        echo "🚀 启动 Gateway..."
        sudo systemctl start openclaw-gateway
        sudo systemctl status openclaw-gateway --no-pager
        ;;
    stop)
        echo "⏹️  停止 Gateway..."
        sudo systemctl stop openclaw-gateway
        ;;
    restart)
        echo "🔄 重启 Gateway（仅重启，不同步代码）..."
        sudo systemctl restart openclaw-gateway
        sudo systemctl status openclaw-gateway --no-pager
        ;;
    status)
        echo "📊 服务状态:"
        sudo systemctl status openclaw-gateway --no-pager
        ;;
    logs)
        echo "📋 查看日志 (Ctrl+C 退出):"
        sudo journalctl -u openclaw-gateway -f
        ;;
    health)
        echo "🏥 健康检查:"
        curl -s http://localhost:8000/health | python3 -m json.tool
        ;;
    agents)
        echo "👥 Agent 列表:"
        curl -s http://localhost:8000/admin/agents | python3 -m json.tool
        ;;
    stats)
        echo "📈 统计信息:"
        curl -s http://localhost:8000/stats | python3 -m json.tool
        ;;
    add-agent)
        if [ -z "$2" ]; then
            echo "❌ 用法: $0 add-agent <agent_name>"
            exit 1
        fi
        "$INSTALL_DIR/bin/04-manage-agent.sh" add "$2"
        ;;
    list-agents)
        "$INSTALL_DIR/bin/04-manage-agent.sh" list
        ;;
    update-agent)
        if [ -z "$2" ]; then
            echo "❌ 用法: $0 update-agent <agent_name>"
            exit 1
        fi
        "$INSTALL_DIR/bin/04-manage-agent.sh" update "$2"
        ;;
    remove-agent)
        if [ -z "$2" ]; then
            echo "❌ 用法: $0 remove-agent <agent_name>"
            exit 1
        fi
        "$INSTALL_DIR/bin/04-manage-agent.sh" remove "$2"
        ;;
    db)
        echo "🗄️  打开数据库 (输入 .quit 退出):"
        DB_PATH=$(grep DB_PATH "$INSTALL_DIR/.env" | cut -d= -f2)
        sudo -u "$USER" sqlite3 "$DB_PATH"
        ;;
    *)
        echo "OpenClaw Gateway 运维脚本"
        echo ""
        echo "用法: $0 <命令> [参数]"
        echo ""
        echo "服务管理:"
        echo "  start              启动服务"
        echo "  stop               停止服务"
        echo "  restart            重启服务"
        echo "                     (仅重启，不会同步新代码)"
        echo "                     更新代码后请执行: sudo bash /opt/openclaw/bin/02-install-gateway.sh"
        echo "  status             查看服务状态"
        echo "  logs               实时查看日志"
        echo ""
        echo "监控检查:"
        echo "  health             健康检查"
        echo "  agents             查看所有 Agent"
        echo "  stats              查看统计信息"
        echo ""
        echo "Agent 管理:"
        echo "  add-agent <name>       添加 Agent"
        echo "  list-agents            列出所有 Agent"
        echo "  update-agent <name>    更新 Agent"
        echo "  remove-agent <name>    删除 Agent"
        echo ""
        echo "数据库:"
        echo "  db                 打开 SQLite 数据库"
        echo ""
        exit 1
        ;;
esac
