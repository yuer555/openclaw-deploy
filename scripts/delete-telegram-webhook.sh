#!/bin/bash

#==============================================================================
# Telegram Webhook 删除脚本
# 用途: 删除 Telegram Bot 的 Webhook 配置（用于测试或切换到轮询模式）
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Telegram Webhook 删除"
echo "=========================================="

# 检查环境变量
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "${RED}❌ 错误: TELEGRAM_BOT_TOKEN 未设置${NC}"
    echo "请先设置环境变量："
    echo "  export TELEGRAM_BOT_TOKEN=your_bot_token"
    exit 1
fi

echo -e "${GREEN}✅ Bot Token 已配置${NC}"
echo ""

# 调用 Telegram API 删除 Webhook
echo "正在删除 Webhook..."
RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteWebhook")

# 检查响应
if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo -e "${GREEN}✅ Webhook 删除成功！${NC}"
    echo ""
    echo "💡 提示: Bot 现在不会接收 Webhook 消息"
    echo "💡 如需重新启用，请运行: scripts/set-telegram-webhook.sh"
else
    echo -e "${RED}❌ Webhook 删除失败${NC}"
    echo "响应: $RESPONSE"
    exit 1
fi

echo "=========================================="
echo "删除完成"
echo "=========================================="
