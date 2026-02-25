# 本地部署快速指南（无 Docker）

> 🚀 5 分钟快速部署 OpenClaw + Telegram Bot

---

## 📋 前置要求

- Python 3.11+
- ngrok
- Telegram 账号

---

## ⚡ 快速开始

### 方式 1: 一键部署（推荐）

```bash
# 运行快速部署脚本
./scripts/quick-deploy-local.sh
```

脚本会自动：
1. ✅ 检查环境
2. ✅ 部署 OpenClaw
3. ✅ 部署 openclaw-deploy
4. ✅ 配置 Telegram Bot
5. ✅ 创建启动脚本

### 方式 2: 手动部署

详见 [完整部署教程](docs/14-本地部署教程-无Docker.md)

---

## 🔧 配置

### 1. 创建 Telegram Bot

1. 在 Telegram 搜索 `@BotFather`
2. 发送 `/newbot` 创建 Bot
3. 保存返回的 Bot Token

### 2. 配置 API Key

编辑 `~/openclaw-workspace/openclaw/.env`:

```bash
GITHUB_TOKEN=your_github_token_here
```

编辑 `~/openclaw-workspace/openclaw-deploy/.env`:

```bash
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_WEBHOOK_SECRET=your_webhook_secret_here
```

---

## 🎬 启动服务

```bash
cd ~/openclaw-workspace
./start-all.sh
```

启动后会自动：
- ✅ 启动 OpenClaw (端口 18789)
- ✅ 启动 Gateway (端口 8000)
- ✅ 启动 ngrok
- ✅ 设置 Telegram Webhook

---

## ✅ 测试

### 1. 测试服务

```bash
# 测试 OpenClaw
curl http://localhost:18789/health

# 测试 Gateway
curl http://localhost:8000/health
```

### 2. 测试 Telegram Bot

1. 在 Telegram 搜索你的 Bot
2. 发送 `/start`
3. 发送 `/help`
4. 发送 `/agents`
5. 发送 `/development`
6. 发送普通消息测试对话

---

## 📊 查看日志

```bash
# OpenClaw 日志
tail -f ~/openclaw-workspace/openclaw/logs/openclaw.log

# Gateway 日志
tail -f ~/openclaw-workspace/openclaw-deploy/logs/gateway.log
```

---

## 🛑 停止服务

```bash
cd ~/openclaw-workspace
./stop-all.sh
```

---

## 🔧 故障排查

### Bot 无响应

```bash
# 1. 检查服务状态
curl http://localhost:18789/health
curl http://localhost:8000/health

# 2. 检查 Webhook
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"

# 3. 查看日志
tail -100 ~/openclaw-workspace/openclaw-deploy/logs/gateway.log

# 4. 重启服务
cd ~/openclaw-workspace
./stop-all.sh
./start-all.sh
```

### ngrok 断开

```bash
# 重启 ngrok 并更新 Webhook
pkill ngrok
ngrok http 8000 &
sleep 3

# 获取新 URL 并更新
cd ~/openclaw-workspace/openclaw-deploy
source .env
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1)
./scripts/set-telegram-webhook.sh "$NGROK_URL/telegram/webhook" "$TELEGRAM_WEBHOOK_SECRET"
```

---

## 📚 详细文档

- [完整部署教程](docs/14-本地部署教程-无Docker.md)
- [Telegram 配置指南](docs/11-Telegram配置.md)
- [Telegram 使用指南](docs/13-Telegram使用指南.md)

---

## 🆘 获取帮助

遇到问题？

1. 查看 [完整部署教程](docs/14-本地部署教程-无Docker.md)
2. 查看日志文件
3. 提交 Issue

---

## 📁 目录结构

```
~/openclaw-workspace/
├── openclaw/              # OpenClaw 服务
│   ├── venv/              # Python 虚拟环境
│   ├── data/              # 数据目录
│   ├── logs/              # 日志目录
│   └── .env               # 环境变量
├── openclaw-deploy/       # Gateway 服务
│   ├── venv/              # Python 虚拟环境
│   ├── data/              # 数据目录
│   ├── logs/              # 日志目录
│   └── .env               # 环境变量
├── start-all.sh           # 启动脚本
└── stop-all.sh            # 停止脚本
```

---

**祝你使用愉快！** 🎉
