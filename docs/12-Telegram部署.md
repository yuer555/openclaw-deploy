# Telegram Bot 部署指南

本文档介绍如何在本地和生产环境部署 OpenClaw Telegram Bot。

---

## 📋 目录

- [本地测试部署](#本地测试部署)
- [生产环境部署](#生产环境部署)
- [故障排查](#故障排查)

---

## 🏠 本地测试部署

### 前置要求

- Docker 和 Docker Compose
- ngrok（用于暴露本地端口）
- Telegram Bot Token（参见 [Telegram 配置指南](11-Telegram配置.md)）

### 步骤 1: 安装 ngrok

**macOS:**
```bash
brew install ngrok
```

**Linux:**
```bash
# 下载并安装
wget https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz
tar xvzf ngrok-v3-stable-linux-amd64.tgz
sudo mv ngrok /usr/local/bin/
```

**验证安装:**
```bash
ngrok version
```

### 步骤 2: 配置环境变量

复制配置文件：
```bash
cd local/
cp .env.local.example .env.local
```

编辑 `.env.local`，添加 Telegram 配置：
```bash
# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_WEBHOOK_SECRET=your_webhook_secret_here

# AI 模型配置（必需）
GITHUB_TOKEN=your_github_token_here
```

### 步骤 3: 初始化环境

```bash
./1-init-local.sh
```

这会：
- 创建必要的目录
- 初始化数据库
- 检查配置

### 步骤 4: 启动服务

```bash
./2-start-local.sh
```

等待服务启动完成（约 30 秒）。

### 步骤 5: 配置 Telegram Bot

运行自动配置脚本：
```bash
./6-setup-telegram-local.sh
```

这会自动：
1. 启动 ngrok
2. 设置 Webhook
3. 配置命令菜单

**或者手动配置：**

```bash
# 1. 启动 ngrok
ngrok http 3000

# 2. 获取 ngrok URL（在另一个终端）
curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1

# 3. 设置 Webhook
export TELEGRAM_BOT_TOKEN=your_bot_token
./scripts/set-telegram-webhook.sh https://your-ngrok-url.ngrok.io/telegram/webhook your_secret

# 4. 设置命令菜单
./scripts/setup-telegram-commands.sh
```

### 步骤 6: 测试

1. 在 Telegram 中搜索你的 Bot
2. 发送 `/start` 命令
3. 尝试与虚拟员工对话

### 查看日志

```bash
# 实时日志
docker logs openclaw-local -f

# 最近 100 行
docker logs openclaw-local --tail=100
```

### 停止服务

```bash
./4-stop-local.sh
```

### 清理环境

```bash
# 删除所有数据和容器
./5-clean-local.sh
```

---

## 🚀 生产环境部署

### 前置要求

- 云服务器（推荐 2 核 4GB 以上）
- 域名（如 `bot.openclaw.com`）
- SSL 证书（Let's Encrypt 或其他）
- Docker 和 Docker Compose

### 架构说明

```
Internet
    ↓ HTTPS
Nginx (443)
    ↓
OpenClaw Gateway (3000)
    ├─ /telegram/webhook
    └─ /wecom/callback
```

### 步骤 1: 准备服务器

在服务器上运行：
```bash
cd production/
./1-prepare-server.sh
```

这会安装：
- Docker
- Docker Compose
- 其他必要工具

### 步骤 2: 配置域名

**DNS 配置：**
```
A 记录: bot.openclaw.com -> 服务器 IP
```

**验证：**
```bash
ping bot.openclaw.com
```

### 步骤 3: 上传文件

在本地运行：
```bash
cd production/
./2-upload-to-server.sh
```

这会上传：
- 配置文件
- Docker Compose 文件
- 脚本文件

### 步骤 4: 配置环境变量

在服务器上编辑配置：
```bash
vim /opt/openclaw/.env
```

添加 Telegram 配置：
```bash
# 域名
DOMAIN=bot.openclaw.com

# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_WEBHOOK_SECRET=your_webhook_secret_here

# AI 模型配置
GITHUB_TOKEN=your_github_token_here

# 其他必需配置...
```

### 步骤 5: 配置 SSL 证书

```bash
./4-setup-ssl.sh bot.openclaw.com
```

这会：
- 安装 Certbot
- 申请 Let's Encrypt 证书
- 配置自动续期

### 步骤 6: 部署服务

```bash
./3-deploy-production.sh
```

这会：
- 构建 Docker 镜像
- 启动服务容器
- 配置 Nginx

### 步骤 7: 配置 Telegram Bot

```bash
./7-setup-telegram-prod.sh
```

这会自动：
1. 检查服务状态
2. 设置 Webhook
3. 配置命令菜单
4. 验证配置

### 步骤 8: 验证部署

```bash
./6-health-check.sh
```

检查项：
- ✅ 服务运行状态
- ✅ 健康检查端点
- ✅ Webhook 连接
- ✅ SSL 证书有效性

### 查看日志

```bash
# OpenClaw 服务日志
docker logs openclaw-production -f

# Nginx 日志
docker logs openclaw-nginx -f

# 系统日志
tail -f /opt/openclaw/logs/gateway/app.log
```

### 更新服务

```bash
# 拉取最新代码
cd /opt/openclaw
git pull

# 重新部署
cd production/
./3-deploy-production.sh
```

### 备份数据

```bash
./scripts/backup.sh telegram-backup-$(date +%Y%m%d)
```

### 回滚版本

```bash
./scripts/rollback.sh
```

---

## 🔧 故障排查

### 问题 1: Webhook 设置失败

**症状：**
```
❌ Webhook 设置失败
```

**原因：**
- SSL 证书无效
- 域名解析错误
- 防火墙阻止

**解决方法：**
```bash
# 检查 SSL 证书
openssl s_client -connect bot.openclaw.com:443

# 检查域名解析
nslookup bot.openclaw.com

# 检查防火墙
sudo ufw status

# 测试健康检查
curl https://bot.openclaw.com/telegram/health
```

### 问题 2: Bot 无响应

**症状：**
发送消息后 Bot 没有回复

**检查步骤：**

1. **检查服务状态：**
```bash
docker ps | grep openclaw
```

2. **查看日志：**
```bash
docker logs openclaw-production --tail=100
```

3. **检查 Webhook 状态：**
```bash
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

4. **测试健康检查：**
```bash
curl https://bot.openclaw.com/telegram/health
```

**常见原因：**
- 环境变量未配置
- OpenClaw Gateway 未启动
- Webhook Secret 不匹配

### 问题 3: 数据库错误

**症状：**
```
❌ 数据库操作失败
```

**解决方法：**
```bash
# 检查数据库文件
ls -lh /opt/openclaw/data/openclaw.db

# 运行数据库迁移
sqlite3 /opt/openclaw/data/openclaw.db < migrations/001_create_telegram_sessions.sql

# 检查表结构
sqlite3 /opt/openclaw/data/openclaw.db "SELECT name FROM sqlite_master WHERE type='table';"
```

### 问题 4: ngrok 连接断开（本地测试）

**症状：**
本地测试时 Bot 突然无响应

**原因：**
ngrok 免费版会话超时（2 小时）

**解决方法：**
```bash
# 重启 ngrok
pkill ngrok
ngrok http 3000 &

# 获取新 URL
NEW_URL=$(curl -s http://localhost:4040/api/tunnels | grep -o 'https://[^"]*\.ngrok[^"]*' | head -1)

# 更新 Webhook
./scripts/set-telegram-webhook.sh $NEW_URL/telegram/webhook your_secret
```

### 问题 5: SSL 证书过期

**症状：**
```
SSL certificate problem
```

**解决方法：**
```bash
# 手动续期
sudo certbot renew

# 重启 Nginx
docker restart openclaw-nginx

# 验证证书
openssl s_client -connect bot.openclaw.com:443 | grep "Verify return code"
```

---

## 📊 监控和维护

### 性能监控

```bash
# 查看资源使用
docker stats openclaw-production

# 查看系统负载
./scripts/monitor.sh
```

### 定期维护

**每日：**
- 检查服务状态
- 查看错误日志

**每周：**
- 备份数据库
- 清理旧日志

**每月：**
- 更新系统依赖
- 检查 SSL 证书有效期
- 审查安全日志

### 自动化脚本

```bash
# 添加到 crontab
crontab -e

# 每天凌晨 2 点备份
0 2 * * * /opt/openclaw/scripts/backup.sh

# 每周日清理日志
0 3 * * 0 /opt/openclaw/scripts/cleanup.sh

# 每小时健康检查
0 * * * * /opt/openclaw/production/6-health-check.sh
```

---

## 📚 相关文档

- [Telegram 配置指南](11-Telegram配置.md)
- [Telegram 使用指南](13-Telegram使用指南.md)
- [运维手册](05-运维手册.md)
- [故障排查](06-故障排查.md)

---

## 🆘 获取帮助

如遇问题，请：

1. 查看日志文件
2. 运行健康检查
3. 查阅故障排查文档
4. 提交 Issue

---

**部署完成后，你的 Telegram Bot 就可以为用户提供服务了！** 🎉
