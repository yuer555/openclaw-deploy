#!/bin/bash
set -e

# OpenClaw 清理脚本
# 用途: 卸载 Gateway 服务 / 清空 OpenClaw / 全部重置
# 用法: sudo bash bin/05-cleanup.sh

echo "=========================================="
echo "OpenClaw 清理工具"
echo "=========================================="
echo ""

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用 sudo 运行此脚本"
    exit 1
fi

# 配置变量
INSTALL_DIR="/opt/openclaw/gateway"
DATA_DIR="/opt/openclaw/data"
LOG_DIR="/var/log/openclaw"
OPENCLAW_HOME="${SUDO_USER:+$(eval echo ~$SUDO_USER)}/.openclaw"
USER="openclaw"

# --- 功能函数 ---

uninstall_gateway() {
    echo ""
    echo "🗑️  卸载 Gateway 服务..."

    # 停止并禁用 systemd 服务
    if systemctl is-active --quiet openclaw-gateway.service 2>/dev/null; then
        systemctl stop openclaw-gateway.service
        echo "   ✅ 服务已停止"
    else
        echo "   服务未运行，跳过"
    fi

    if systemctl is-enabled --quiet openclaw-gateway.service 2>/dev/null; then
        systemctl disable openclaw-gateway.service
        echo "   ✅ 服务已禁用"
    fi

    # 删除 systemd 服务文件
    if [ -f /etc/systemd/system/openclaw-gateway.service ]; then
        rm /etc/systemd/system/openclaw-gateway.service
        systemctl daemon-reload
        echo "   ✅ systemd 服务已删除"
    fi

    # 删除安装目录
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
        echo "   ✅ 安装目录已删除: $INSTALL_DIR"
    fi

    # 删除日志目录
    if [ -d "$LOG_DIR" ]; then
        rm -rf "$LOG_DIR"
        echo "   ✅ 日志目录已删除: $LOG_DIR"
    fi

    echo ""
    echo "   保留的内容:"
    echo "     - 数据目录: $DATA_DIR（包含数据库）"
    echo "     - 用户: $USER（如需删除请手动执行: userdel $USER）"
    echo ""
    echo "✅ Gateway 卸载完成"
}

cleanup_openclaw() {
    echo ""
    echo "🗑️  清空 OpenClaw..."

    # 停止 openclaw gateway
    if command -v openclaw &>/dev/null; then
        openclaw gateway stop 2>/dev/null || true
        echo "   ✅ OpenClaw Gateway 已停止"
    fi

    if [ -d "$OPENCLAW_HOME" ]; then
        rm -rf "$OPENCLAW_HOME"
        echo "   ✅ OpenClaw 目录已删除: $OPENCLAW_HOME"
    else
        echo "   OpenClaw 目录不存在: $OPENCLAW_HOME"
    fi

    echo ""
    echo "✅ OpenClaw 清理完成"
}

# --- 菜单 ---

echo "请选择清理操作："
echo ""
echo "  1) 卸载 Gateway 服务（停服务 + 删安装目录 + 删 systemd）"
echo "  2) 清空 OpenClaw（停 gateway + 删 ~/.openclaw）"
echo "  3) 全部清理（1+2 + 删数据目录）"
echo ""
read -p "请选择 [1-3]: " choice

case "$choice" in
    1)
        echo ""
        echo "⚠️  将卸载 Gateway 服务并删除 $INSTALL_DIR"
        read -p "确认? (yes/no): " -r
        if [[ ! $REPLY =~ ^yes$ ]]; then
            echo "❌ 已取消"
            exit 0
        fi
        uninstall_gateway
        ;;
    2)
        echo ""
        echo "⚠️  将停止 OpenClaw 并删除 $OPENCLAW_HOME"
        echo "   这会清除所有 Agent、模型配置、workspace"
        read -p "确认? (yes/no): " -r
        if [[ ! $REPLY =~ ^yes$ ]]; then
            echo "❌ 已取消"
            exit 0
        fi
        cleanup_openclaw
        ;;
    3)
        echo ""
        echo "⚠️  将执行全部清理:"
        echo "   - 卸载 Gateway 服务"
        echo "   - 删除 OpenClaw 配置 ($OPENCLAW_HOME)"
        echo "   - 删除数据目录 ($DATA_DIR)"
        read -p "确认? (yes/no): " -r
        if [[ ! $REPLY =~ ^yes$ ]]; then
            echo "❌ 已取消"
            exit 0
        fi
        uninstall_gateway
        cleanup_openclaw

        # 删除数据目录
        if [ -d "$DATA_DIR" ]; then
            rm -rf "$DATA_DIR"
            echo "   ✅ 数据目录已删除: $DATA_DIR"
        fi

        # 删除用户
        if id "$USER" &>/dev/null; then
            userdel "$USER" 2>/dev/null || true
            echo "   ✅ 用户已删除: $USER"
        fi

        echo ""
        echo "✅ 全部清理完成"
        ;;
    *)
        echo "❌ 无效选项"
        exit 1
        ;;
esac

echo ""
echo "=========================================="
echo "清理操作已完成"
echo "=========================================="
