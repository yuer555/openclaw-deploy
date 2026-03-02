#!/bin/bash
set -e

# OpenClaw Gateway 卸载脚本
# 用途: 完全卸载 Gateway 服务
# 用法: sudo bash deploy/uninstall.sh

echo "=========================================="
echo "OpenClaw Gateway 卸载"
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
USER="openclaw"

# 确认卸载
echo "⚠️  警告: 此操作将删除以下内容:"
echo "   - Gateway 服务和配置"
echo "   - 安装目录: $INSTALL_DIR"
echo "   - 日志目录: $LOG_DIR"
echo ""
echo "   数据库将保留在: $DATA_DIR"
echo ""
read -p "确认卸载? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^yes$ ]]; then
    echo "❌ 已取消"
    exit 0
fi

# 步骤 1: 停止并禁用服务
echo "⏹️  步骤 1/4: 停止服务..."
if systemctl is-active --quiet openclaw-gateway.service; then
    systemctl stop openclaw-gateway.service
    echo "   ✅ 服务已停止"
else
    echo "   服务未运行，跳过"
fi

if systemctl is-enabled --quiet openclaw-gateway.service; then
    systemctl disable openclaw-gateway.service
    echo "   ✅ 服务已禁用"
fi

# 步骤 2: 删除 systemd 服务文件
echo ""
echo "🗑️  步骤 2/4: 删除 systemd 服务..."
if [ -f /etc/systemd/system/openclaw-gateway.service ]; then
    rm /etc/systemd/system/openclaw-gateway.service
    systemctl daemon-reload
    echo "   ✅ systemd 服务已删除"
else
    echo "   服务文件不存在，跳过"
fi

# 步骤 3: 删除安装目录
echo ""
echo "🗑️  步骤 3/4: 删除安装目录..."
if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    echo "   ✅ 安装目录已删除"
else
    echo "   安装目录不存在，跳过"
fi

# 步骤 4: 删除日志目录
echo ""
echo "🗑️  步骤 4/4: 删除日志目录..."
if [ -d "$LOG_DIR" ]; then
    rm -rf "$LOG_DIR"
    echo "   ✅ 日志目录已删除"
else
    echo "   日志目录不存在，跳过"
fi

echo ""
echo "=========================================="
echo "✅ 卸载完成！"
echo "=========================================="
echo ""
echo "保留的内容:"
echo "  - 数据目录: $DATA_DIR（包含数据库）"
echo "  - 用户: $USER（如需删除请手动执行: userdel $USER）"
echo ""
echo "如需完全清理，请执行:"
echo "  sudo rm -rf $DATA_DIR"
echo "  sudo userdel $USER"
echo ""
