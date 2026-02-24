#!/bin/bash

#==============================================================================
# OpenClaw 本地 Telegram Bot 配置脚本
# 用途: 配置本地测试环境的 Telegram Bot
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "OpenClaw 本地 Telegram Bot 配置"
echo "=========================================="
echo ""

# 检查 .env.local 文件
if [ ! -f ".env.local" ]; then
    echo -e "${RED}❌ 错误: .env.local 文件不存在${NC}"
    echo "请先复制配置文件："
    echo "  cp .env.local.example .env.local"
    exit 1
fi

# 加载环境变量
source .env.local

# 检查 Telegram 配置
if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
    echo -e "${RED}❌ 错误: TELEGRAM_BOT_TOKEN 未配置${NC}"
    echo ""
    echo "请按以下步骤配置："
    echo "1. 在 Telegram 中搜索 @BotFather"
    echo "2. 发送 /newbot 创建新 Bot"
    echo "3. 按提示设置 Bot 名称和用户名"
    echo "4. 复制获得的 Bot Token"
    echo "5. 在 .env.local 中设置 TELEGRAM_BOT_TOKEN"
    exit 1
fi

if [ -z "$TELEGRAM_WEBHOOK_SECRET" ]; then
    echo -e "${YELLOW}⚠️  警告: TELEGRAM_WEBHOOK_SECRET 未配置${NC}"
    echo "建议生成一个随机密钥："
    echo "  openssl rand -hex 32"
    echo ""
fi

echo -e "${GREEN}✅ Telegram Bot Token 已配置${NC}"
echo ""

# 步骤 1: 检查 ngrok 是否安装
echo "步骤 1: 检查 ngrok"
echo "----------------------------------------"
if command -v ngrok &> /dev/null; then
    echo -e "${GREEN}✅ ngrok 已安装${NC}"
else
    echo -e "${YELLOW}⚠️  ngrok 未安装${NC}"
    echo ""
    echo "请安装 ngrok："
    echo "  macOS: brew install ngrok"
    echo "  Linux: 访问 https://ngrok.com/download"
    echo ""
    echo "或者手动启动 ngrok："
    echo "  ngrok http 3000"
    exit 1
fi
echo ""

# 步骤 2: 启动本地服务
echo "步骤 2: 启动本地服务"
echo "----------------------------------------"
echo "请确保本地服务已启动："
echo "  ./2-start-local.sh"
echo ""
read -p "本地服务是否已启动？(y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "请先启动本地服务，然后重新运行此脚本"
    exit 1
fi
echo ""

# 步骤 3: 启动 ngrok
echo "步骤 3: 启动 ngrok"
echo "----------------------------------------"
echo "正在启动 ngrok（后台运行）..."
pkill -f "ngrok http 3000" 2>/dev/null || true
ngrok http 3000 > /dev/null &
NGROK_PID=$!
echo -e "${GREEN}✅ ngrok 已启动 (PID: $NGROK_PID)${NC}"
echo ""

# 等待 ngrok 启动
echo "等待 ngrok 启动..."
sleep 3

# 获取 ngrok URL
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1)

if [ -z "$NGROK_URL" ]; then
    echo -e "${RED}❌ 错误: 无法获取 ngrok URL${NC}"
    echo "请手动启动 ngrok 并查看 URL："
    echo "  ngrok http 3000"
    exit 1
fi

echo -e "${GREEN}✅ ngrok URL: $NGROK_URL${NC}"
echo ""

# 步骤 4: 设置 Webhook
echo "步骤 4: 设置 Telegram Webhook"
echo "----------------------------------------"
WEBHOOK_URL="${NGROK_URL}/telegram/webhook"
echo "Webhook URL: $WEBHOOK_URL"
echo ""

# 调用 Webhook 设置脚本
export TELEGRAM_BOT_TOKEN
cd ..
if [ -n "$TELEGRAM_WEBHOOK_SECRET" ]; then
    ./scripts/set-telegram-webhook.sh "$WEBHOOK_URL" "$TELEGRAM_WEBHOOK_SECRET"
else
    ./scripts/set-telegram-webhook.sh "$WEBHOOK_URL"
fi
cd local
echo ""

# 步骤 5: 设置命令菜单
echo "步骤 5: 设置命令菜单"
echo "----------------------------------------"
cd ..
./scripts/setup-telegram-commands.sh
cd local
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
echo "  docker logs openclaw-local -f"
echo ""
echo "停止 ngrok："
echo "  kill $NGROK_PID"
echo ""
echo "删除 Webhook（测试完成后）："
echo "  ../scripts/delete-telegram-webhook.sh"
echo ""
