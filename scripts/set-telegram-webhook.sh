#!/bin/bash

#==============================================================================
# Telegram Webhook 设置脚本
# 用途: 配置 Telegram Bot 的 Webhook URL
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Telegram Webhook 配置"
echo "=========================================="

# 检查参数
if [ $# -lt 1 ]; then
    echo "用法: $0 <webhook_url> [secret_token]"
    echo ""
    echo "示例:"
    echo "  本地测试 (ngrok):"
    echo "    $0 https://your-ngrok-url.ngrok.io/telegram/webhook your_secret"
    echo ""
    echo "  生产环境:"
    echo "    $0 https://your-domain.com/telegram/webhook your_secret"
    exit 1
fi

WEBHOOK_URL=$1
SECRET_TOKEN=${2:-""}

# 检查环境变量
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "${RED}❌ 错误: TELEGRAM_BOT_TOKEN 未设置${NC}"
    echo "请先设置环境变量："
    echo "  export TELEGRAM_BOT_TOKEN=your_bot_token"
    exit 1
fi

echo -e "${GREEN}✅ Bot Token 已配置${NC}"
echo -e "${GREEN}✅ Webhook URL: $WEBHOOK_URL${NC}"

if [ -n "$SECRET_TOKEN" ]; then
    echo -e "${GREEN}✅ Secret Token 已配置${NC}"
fi

echo ""

# 构建请求数据
if [ -n "$SECRET_TOKEN" ]; then
    REQUEST_DATA="{\"url\":\"$WEBHOOK_URL\",\"secret_token\":\"$SECRET_TOKEN\",\"allowed_updates\":[\"message\"]}"
else
    REQUEST_DATA="{\"url\":\"$WEBHOOK_URL\",\"allowed_updates\":[\"message\"]}"
fi

# 调用 Telegram API 设置 Webhook
echo "正在设置 Webhook..."
RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
    -H "Content-Type: application/json" \
    -d "$REQUEST_DATA")

# 检查响应
if echo "$RESPONSE" | grep -q '"ok":true'; then
    echo -e "${GREEN}✅ Webhook 设置成功！${NC}"
    echo ""

    # 获取 Webhook 信息
    echo "正在验证 Webhook 配置..."
    INFO_RESPONSE=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo")

    echo ""
    echo "Webhook 信息:"
    echo "$INFO_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$INFO_RESPONSE"
    echo ""
    echo "💡 提示: 现在可以在 Telegram 中向 Bot 发送消息进行测试"
else
    echo -e "${RED}❌ Webhook 设置失败${NC}"
    echo "响应: $RESPONSE"
    exit 1
fi

echo "=========================================="
echo "配置完成"
echo "=========================================="
