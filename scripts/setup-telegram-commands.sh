#!/bin/bash

#==============================================================================
# Telegram Bot 命令菜单配置脚本
# 用途: 设置 Telegram Bot 的命令列表，使命令在输入 "/" 时自动显示
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Telegram Bot 命令菜单配置"
echo "=========================================="

# 检查环境变量
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "${RED}❌ 错误: TELEGRAM_BOT_TOKEN 未设置${NC}"
    echo "请先设置环境变量："
    echo "  export TELEGRAM_BOT_TOKEN=your_bot_token"
    exit 1
fi

# 检查配置文件
COMMANDS_FILE="$(dirname "$0")/../config/telegram-commands.json"
if [ ! -f "$COMMANDS_FILE" ]; then
    echo -e "${RED}❌ 错误: 命令配置文件不存在: $COMMANDS_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Bot Token 已配置${NC}"
echo -e "${GREEN}✅ 命令配置文件: $COMMANDS_FILE${NC}"
echo ""

# 调用 Telegram API 设置命令
echo "正在设置命令菜单..."
RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setMyCommands" \
    -H "Content-Type: application/json" \
    -d @"$COMMANDS_FILE")

# 检查响应
if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo -e "${GREEN}✅ 命令菜单设置成功！${NC}"
    echo ""
    echo "已设置的命令："
    echo "  /start - 开始使用，显示欢迎信息"
    echo "  /help - 显示帮助信息"
    echo "  /agents - 显示所有虚拟员工"
    echo "  /dispatcher - 切换到调度员"
    echo "  /operation - 切换到运营专员"
    echo "  /product - 切换到产品经理"
    echo "  /development - 切换到开发工程师"
    echo "  /testing - 切换到测试工程师"
    echo "  /service - 切换到客服专员"
    echo "  /current - 显示当前虚拟员工"
    echo "  /reset - 重置会话"
    echo ""
    echo "💡 提示: 在 Telegram 中输入 '/' 即可看到命令列表"
else
    echo -e "${RED}❌ 命令菜单设置失败${NC}"
    echo "响应: $RESPONSE"
    exit 1
fi

echo "=========================================="
echo "配置完成"
echo "=========================================="
