#!/bin/bash

#==============================================================================
# OpenClaw + Telegram 本地快速部署脚本（无 Docker）
# 用途: 一键部署 OpenClaw 和 openclaw-deploy，配置 Telegram Bot
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "OpenClaw + Telegram 本地快速部署"
echo "=========================================="
echo ""

# 工作目录
WORKSPACE=~/openclaw-workspace
OPENCLAW_DIR=$WORKSPACE/openclaw
DEPLOY_DIR=$WORKSPACE/openclaw-deploy

# 检查 Python 版本
echo "检查 Python 版本..."
if ! command -v python3.11 &> /dev/null; then
    echo -e "${RED}❌ 错误: Python 3.11 未安装${NC}"
    echo "请先安装 Python 3.11："
    echo "  macOS: brew install python@3.11"
    echo "  Linux: sudo apt install python3.11"
    exit 1
fi
echo -e "${GREEN}✅ Python 版本: $(python3.11 --version)${NC}"
echo ""

# 检查 ngrok
echo "检查 ngrok..."
if ! command -v ngrok &> /dev/null; then
    echo -e "${YELLOW}⚠️  ngrok 未安装${NC}"
    echo "请先安装 ngrok："
    echo "  macOS: brew install ngrok"
    echo "  Linux: 参考 https://ngrok.com/download"
    exit 1
fi
echo -e "${GREEN}✅ ngrok 已安装${NC}"
echo ""

# 创建工作目录
echo "创建工作目录..."
mkdir -p $WORKSPACE
cd $WORKSPACE
echo -e "${GREEN}✅ 工作目录: $WORKSPACE${NC}"
echo ""

# 步骤 1: 部署 OpenClaw
echo "=========================================="
echo "步骤 1: 部署 OpenClaw"
echo "=========================================="

if [ ! -d "$OPENCLAW_DIR" ]; then
    echo "请提供 OpenClaw 仓库 URL："
    read -p "OpenClaw Git URL: " OPENCLAW_REPO

    if [ -z "$OPENCLAW_REPO" ]; then
        echo -e "${YELLOW}⚠️  跳过 OpenClaw 克隆，假设已存在${NC}"
    else
        git clone $OPENCLAW_REPO openclaw
    fi
fi

if [ -d "$OPENCLAW_DIR" ]; then
    cd $OPENCLAW_DIR

    # 创建虚拟环境
    if [ ! -d "venv" ]; then
        echo "创建 Python 虚拟环境..."
        python3.11 -m venv venv
    fi

    # 激活虚拟环境
    source venv/bin/activate

    # 安装依赖
    echo "安装 OpenClaw 依赖..."
    pip install --upgrade pip -q
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt -q
    fi

    # 创建目录
    mkdir -p data logs

    # 配置环境变量
    if [ ! -f ".env" ]; then
        echo "配置 OpenClaw 环境变量..."
        cat > .env << 'EOF'
# AI 模型配置（必需）
GITHUB_TOKEN=your_github_token_here

# 数据库配置
DATABASE_URL=sqlite:///./data/openclaw.db

# 日志配置
LOG_LEVEL=INFO

# 服务端口
PORT=18789
EOF
        echo -e "${YELLOW}⚠️  请编辑 $OPENCLAW_DIR/.env 配置 GITHUB_TOKEN${NC}"
    fi

    echo -e "${GREEN}✅ OpenClaw 部署完成${NC}"
else
    echo -e "${RED}❌ OpenClaw 目录不存在，请手动克隆${NC}"
    exit 1
fi
echo ""

# 步骤 2: 部署 openclaw-deploy
echo "=========================================="
echo "步骤 2: 部署 openclaw-deploy"
echo "=========================================="

if [ ! -d "$DEPLOY_DIR" ]; then
    echo "克隆 openclaw-deploy..."
    cd $WORKSPACE

    # 假设当前就在 openclaw-deploy 目录
    if [ -f "../src/gateway/telegram_adapter.py" ]; then
        echo "检测到当前在 openclaw-deploy 目录"
        DEPLOY_DIR=$(pwd)
    else
        echo "请提供 openclaw-deploy 仓库 URL："
        read -p "openclaw-deploy Git URL: " DEPLOY_REPO

        if [ -z "$DEPLOY_REPO" ]; then
            echo -e "${RED}❌ 需要 openclaw-deploy 仓库${NC}"
            exit 1
        fi

        git clone $DEPLOY_REPO openclaw-deploy
    fi
fi

cd $DEPLOY_DIR

# 创建虚拟环境
if [ ! -d "venv" ]; then
    echo "创建 Python 虚拟环境..."
    python3.11 -m venv venv
fi

# 激活虚拟环境
source venv/bin/activate

# 安装依赖
echo "安装 Gateway 依赖..."
pip install --upgrade pip -q
pip install -r src/gateway/requirements.txt -q

# 创建目录
mkdir -p data logs

# 初始化数据库
echo "初始化数据库..."
if [ -f "migrations/001_create_telegram_sessions.sql" ]; then
    sqlite3 data/gateway.db < migrations/001_create_telegram_sessions.sql
fi

# 配置环境变量
if [ ! -f ".env" ]; then
    echo "配置 Gateway 环境变量..."
    cat > .env << 'EOF'
# OpenClaw Gateway 配置
OPENCLAW_GATEWAY_URL=http://localhost:18789

# 数据库配置
DB_PATH=./data/gateway.db

# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_WEBHOOK_SECRET=your_webhook_secret_here

# 日志配置
LOG_LEVEL=INFO

# 服务端口
GATEWAY_PORT=8000
EOF
    echo -e "${YELLOW}⚠️  请编辑 $DEPLOY_DIR/.env 配置 Telegram Bot Token${NC}"
fi

echo -e "${GREEN}✅ openclaw-deploy 部署完成${NC}"
echo ""

# 步骤 3: 配置 Telegram Bot
echo "=========================================="
echo "步骤 3: 配置 Telegram Bot"
echo "=========================================="

echo "请按以下步骤配置 Telegram Bot："
echo ""
echo "1. 在 Telegram 中搜索 @BotFather"
echo "2. 发送 /newbot 创建新 Bot"
echo "3. 设置 Bot 名称和用户名"
echo "4. 保存返回的 Bot Token"
echo "5. 生成 Webhook Secret: openssl rand -hex 32"
echo ""
read -p "是否已完成 Bot 创建？(y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "请先创建 Bot，然后重新运行此脚本"
    exit 1
fi

read -p "请输入 Bot Token: " BOT_TOKEN
read -p "请输入 Webhook Secret (留空自动生成): " WEBHOOK_SECRET

if [ -z "$WEBHOOK_SECRET" ]; then
    WEBHOOK_SECRET=$(openssl rand -hex 32)
    echo "生成的 Webhook Secret: $WEBHOOK_SECRET"
fi

# 更新环境变量
cd $DEPLOY_DIR
sed -i.bak "s/TELEGRAM_BOT_TOKEN=.*/TELEGRAM_BOT_TOKEN=$BOT_TOKEN/" .env
sed -i.bak "s/TELEGRAM_WEBHOOK_SECRET=.*/TELEGRAM_WEBHOOK_SECRET=$WEBHOOK_SECRET/" .env
rm .env.bak

echo -e "${GREEN}✅ Telegram Bot 配置完成${NC}"
echo ""

# 步骤 4: 创建启动脚本
echo "=========================================="
echo "步骤 4: 创建启动脚本"
echo "=========================================="

cat > $WORKSPACE/start-all.sh << 'EOFSTART'
#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

WORKSPACE=~/openclaw-workspace
OPENCLAW_DIR=$WORKSPACE/openclaw
DEPLOY_DIR=$WORKSPACE/openclaw-deploy

echo "=========================================="
echo "启动 OpenClaw 本地服务"
echo "=========================================="

# 启动 OpenClaw
echo -e "${GREEN}1. 启动 OpenClaw...${NC}"
cd $OPENCLAW_DIR
source venv/bin/activate
nohup python main.py > logs/openclaw.log 2>&1 &
OPENCLAW_PID=$!
echo "OpenClaw PID: $OPENCLAW_PID"
sleep 5

if curl -s http://localhost:18789/health > /dev/null; then
    echo -e "${GREEN}✅ OpenClaw 启动成功${NC}"
else
    echo -e "${YELLOW}⚠️  OpenClaw 可能未正常启动${NC}"
fi

# 启动 Gateway
echo -e "${GREEN}2. 启动 Gateway...${NC}"
cd $DEPLOY_DIR
source venv/bin/activate
nohup python src/gateway/wecom_gateway.py > logs/gateway.log 2>&1 &
GATEWAY_PID=$!
echo "Gateway PID: $GATEWAY_PID"
sleep 3

if curl -s http://localhost:8000/health > /dev/null; then
    echo -e "${GREEN}✅ Gateway 启动成功${NC}"
else
    echo -e "${YELLOW}⚠️  Gateway 可能未正常启动${NC}"
fi

# 启动 ngrok
echo -e "${GREEN}3. 启动 ngrok...${NC}"
nohup ngrok http 8000 > logs/ngrok.log 2>&1 &
NGROK_PID=$!
sleep 3

NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1)

if [ -n "$NGROK_URL" ]; then
    echo -e "${GREEN}✅ ngrok 启动成功${NC}"
    echo "ngrok URL: $NGROK_URL"

    # 设置 Webhook
    echo -e "${GREEN}4. 设置 Telegram Webhook...${NC}"
    cd $DEPLOY_DIR
    source .env
    export TELEGRAM_BOT_TOKEN
    ./scripts/set-telegram-webhook.sh "$NGROK_URL/telegram/webhook" "$TELEGRAM_WEBHOOK_SECRET"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ 所有服务启动完成！${NC}"
echo "=========================================="
echo ""
echo "服务信息："
echo "  OpenClaw:  http://localhost:18789"
echo "  Gateway:   http://localhost:8000"
echo "  ngrok:     $NGROK_URL"
echo ""
echo "进程 ID："
echo "  OpenClaw: $OPENCLAW_PID"
echo "  Gateway:  $GATEWAY_PID"
echo "  ngrok:    $NGROK_PID"
echo ""
echo "查看日志："
echo "  tail -f $OPENCLAW_DIR/logs/openclaw.log"
echo "  tail -f $DEPLOY_DIR/logs/gateway.log"
echo ""
echo "停止服务："
echo "  $WORKSPACE/stop-all.sh"
echo ""
EOFSTART

chmod +x $WORKSPACE/start-all.sh

# 创建停止脚本
cat > $WORKSPACE/stop-all.sh << 'EOFSTOP'
#!/bin/bash

echo "停止所有服务..."

pkill -f "python main.py"
pkill -f "openclaw.server"
pkill -f "wecom_gateway.py"
pkill -f "ngrok http"

echo "✅ 所有服务已停止"
EOFSTOP

chmod +x $WORKSPACE/stop-all.sh

echo -e "${GREEN}✅ 启动脚本创建完成${NC}"
echo ""

# 完成
echo "=========================================="
echo -e "${GREEN}✅ 部署完成！${NC}"
echo "=========================================="
echo ""
echo "下一步："
echo ""
echo "1. 配置 API Key："
echo "   编辑 $OPENCLAW_DIR/.env"
echo "   设置 GITHUB_TOKEN 或 OPENAI_API_KEY"
echo ""
echo "2. 启动所有服务："
echo "   $WORKSPACE/start-all.sh"
echo ""
echo "3. 测试 Telegram Bot："
echo "   在 Telegram 中搜索你的 Bot"
echo "   发送 /start 命令"
echo ""
echo "4. 查看日志："
echo "   tail -f $OPENCLAW_DIR/logs/openclaw.log"
echo "   tail -f $DEPLOY_DIR/logs/gateway.log"
echo ""
echo "5. 停止服务："
echo "   $WORKSPACE/stop-all.sh"
echo ""
echo "详细文档："
echo "   $DEPLOY_DIR/docs/14-本地部署教程-无Docker.md"
echo ""
