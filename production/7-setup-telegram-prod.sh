#!/bin/bash

#==============================================================================
# OpenClaw 生产环境 Telegram Bot 配置脚本
# 用途: 配置生产环境的 Telegram Bot
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "OpenClaw 生产环境 Telegram Bot 配置"
echo "=========================================="
echo ""

# 检查是否在生产服务器上运行
if [ ! -f "/opt/openclaw/.env" ]; then
    echo -e "${RED}❌ 错误: 未找到生产环境配置文件${NC}"
    echo "请确保在生产服务器上运行此脚本"
    exit 1
fi

# 加载环境变量
source /opt/openclaw/.env

# 检查 Telegram 配置
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "${RED}❌ 错误: TELEGRAM_BOT_TOKEN 未配置${NC}"
    echo ""
    echo "请在 /opt/openclaw/.env 中配置："
    echo "  TELEGRAM_BOT_TOKEN=your_bot_token"
    echo "  TELEGRAM_WEBHOOK_SECRET=your_webhook_secret"
    exit 1
fi

if [ -z "$TELEGRAM_WEBHOOK_SECRET" ]; then
    echo -e "${YELLOW}⚠️  警告: TELEGRAM_WEBHOOK_SECRET 未配置${NC}"
    echo "建议生成一个随机密钥："
    echo "  openssl rand -hex 32"
    echo ""
fi

if [ -z "$DOMAIN" ]; then
    echo -e "${RED}❌ 错误: DOMAIN 未配置${NC}"
    echo "请在 /opt/openclaw/.env 中配置域名"
    exit 1
fi

echo -e "${GREEN}✅ Telegram Bot Token 已配置${NC}"
echo -e "${GREEN}✅ 域名: $DOMAIN${NC}"
echo ""

# 步骤 1: 检查服务状态
echo "步骤 1: 检查服务状态"
echo "----------------------------------------"
if docker ps | grep -q openclaw-production; then
    echo -e "${GREEN}✅ OpenClaw 服务正在运行${NC}"
else
    echo -e "${RED}❌ OpenClaw 服务未运行${NC}"
    echo "请先启动服务："
    echo "  cd /opt/openclaw/production"
    echo "  ./5-start-production.sh"
    exit 1
fi
echo ""

# 步骤 2: 检查 SSL 证书
echo "步骤 2: 检查 SSL 证书"
echo "----------------------------------------"
if [ -f "/opt/openclaw/config/ssl/fullchain.pem" ]; then
    echo -e "${GREEN}✅ SSL 证书已配置${NC}"
else
    echo -e "${YELLOW}⚠️  SSL 证书未找到${NC}"
    echo "Telegram Webhook 需要 HTTPS"
    echo "请先配置 SSL 证书："
    echo "  ./4-setup-ssl.sh $DOMAIN"
    echo ""
    read -p "是否继续？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi
echo ""

# 步骤 3: 测试健康检查
echo "步骤 3: 测试健康检查"
echo "----------------------------------------"
echo "测试 Telegram 健康检查端点..."
HEALTH_RESPONSE=$(curl -s "https://${DOMAIN}/telegram/health" || echo "failed")

if echo "$HEALTH_RESPONSE" | grep -q "healthy\|disabled"; then
    echo -e "${GREEN}✅ 健康检查通过${NC}"
    echo "响应: $HEALTH_RESPONSE"
else
    echo -e "${RED}❌ 健康检查失败${NC}"
    echo "响应: $HEALTH_RESPONSE"
    echo ""
    echo "请检查："
    echo "1. Nginx 配置是否正确"
    echo "2. 服务是否正常运行"
    echo "3. 防火墙是否开放 443 端口"
    exit 1
fi
echo ""

# 步骤 4: 设置 Webhook
echo "步骤 4: 设置 Telegram Webhook"
echo "----------------------------------------"
WEBHOOK_URL="https://${DOMAIN}/telegram/webhook"
echo "Webhook URL: $WEBHOOK_URL"
echo ""

# 调用 Webhook 设置脚本
export TELEGRAM_BOT_TOKEN
cd /opt/openclaw
if [ -n "$TELEGRAM_WEBHOOK_SECRET" ]; then
    ./scripts/set-telegram-webhook.sh "$WEBHOOK_URL" "$TELEGRAM_WEBHOOK_SECRET"
else
    ./scripts/set-telegram-webhook.sh "$WEBHOOK_URL"
fi
echo ""

# 步骤 5: 设置命令菜单
echo "步骤 5: 设置命令菜单"
echo "----------------------------------------"
./scripts/setup-telegram-commands.sh
echo ""

# 步骤 6: 验证配置
echo "步骤 6: 验证配置"
echo "----------------------------------------"
echo "获取 Webhook 信息..."
WEBHOOK_INFO=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo")
echo "$WEBHOOK_INFO" | python3 -m json.tool 2>/dev/null || echo "$WEBHOOK_INFO"
echo ""

# 完成
echo "=========================================="
echo -e "${GREEN}✅ 配置完成！${NC}"
echo "=========================================="
echo ""
echo "测试步骤："
echo "1. 在 Telegram 中搜索你的 Bot"
echo "2. 发送 /start 命令"
echo "3. 尝试发送消息与虚拟员工对话"
echo ""
echo "查看日志："
echo "  docker logs openclaw-production -f"
echo ""
echo "监控 Webhook："
echo "  curl https://api.telegram.org/bot\$TELEGRAM_BOT_TOKEN/getWebhookInfo"
echo ""
