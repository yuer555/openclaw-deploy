# Telegram Bot 配置指南

本文档介绍如何配置 OpenClaw 的 Telegram Bot 支持。

---

## 📋 前置要求

- Telegram 账号
- 访问 @BotFather 的权限
- 基本的命令行操作能力

---

## 🤖 创建 Telegram Bot

### 步骤 1: 访问 BotFather

1. 在 Telegram 中搜索 `@BotFather`
2. 点击 "Start" 开始对话

### 步骤 2: 创建新 Bot

发送命令：
```
/newbot
```

### 步骤 3: 设置 Bot 名称

BotFather 会要求你输入 Bot 的显示名称：
```
OpenClaw 虚拟员工
```

### 步骤 4: 设置 Bot 用户名

输入 Bot 的用户名（必须以 `bot` 结尾）：
```
openclaw_assistant_bot
```

### 步骤 5: 获取 Bot Token

创建成功后，BotFather 会返回一个 Token，格式类似：
```
123456789:ABCdefGHIjklMNOpqrsTUVwxyz
```

**⚠️ 重要：请妥善保管此 Token，不要泄露给他人！**

---

## ⚙️ 配置 Bot 信息

### 设置 Bot 描述

发送命令：
```
/setdescription
```

选择你的 Bot，然后输入描述：
```
OpenClaw 虚拟员工 - 智能 AI 助手，提供调度、运营、产品、开发、测试、客服等专业服务。
```

### 设置 Bot 简介

发送命令：
```
/setabouttext
```

选择你的 Bot，然后输入简介：
```
OpenClaw 虚拟员工系统，6 位专业 AI 助手为您服务。
```

### 上传 Bot 头像

1. 发送命令：`/setuserpic`
2. 选择你的 Bot
3. 上传一张图片作为头像（建议 512x512 像素）

### 配置隐私设置

发送命令：
```
/setprivacy
```

选择你的 Bot，然后选择：
- `Disable` - 允许 Bot 在群组中接收所有消息
- `Enable` - Bot 只接收命令和 @ 提及

**建议：选择 `Disable` 以获得更好的体验**

---

## 🔐 生成 Webhook Secret

Webhook Secret 用于验证来自 Telegram 的请求。

### 生成随机密钥

```bash
openssl rand -hex 32
```

这会生成一个 64 字符的十六进制字符串，例如：
```
a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2
```

---

## 📝 配置环境变量

### 本地测试环境

编辑 `local/.env.local`：

```bash
# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_WEBHOOK_SECRET=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2
```

### 生产环境

编辑 `/opt/openclaw/.env`：

```bash
# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrsTUVwxyz
TELEGRAM_WEBHOOK_SECRET=a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2
```

---

## 🎯 设置命令菜单

命令菜单让用户在输入 `/` 时看到可用命令列表。

### 自动设置（推荐）

运行配置脚本：

```bash
# 设置环境变量
export TELEGRAM_BOT_TOKEN=your_bot_token

# 运行脚本
./scripts/setup-telegram-commands.sh
```

### 手动设置

1. 发送命令：`/setcommands`
2. 选择你的 Bot
3. 粘贴以下命令列表：

```
start - 开始使用，显示欢迎信息
help - 显示帮助信息
agents - 显示所有虚拟员工
dispatcher - 切换到调度员
operation - 切换到运营专员
product - 切换到产品经理
development - 切换到开发工程师
testing - 切换到测试工程师
service - 切换到客服专员
current - 显示当前虚拟员工
reset - 重置会话
```

---

## 🔗 配置 Webhook

### 本地测试

使用 ngrok 暴露本地端口：

```bash
# 启动 ngrok
ngrok http 3000

# 设置 Webhook
export TELEGRAM_BOT_TOKEN=your_bot_token
./scripts/set-telegram-webhook.sh https://your-ngrok-url.ngrok.io/telegram/webhook your_webhook_secret
```

### 生产环境

```bash
# 设置 Webhook
export TELEGRAM_BOT_TOKEN=your_bot_token
./scripts/set-telegram-webhook.sh https://your-domain.com/telegram/webhook your_webhook_secret
```

### 验证 Webhook

检查 Webhook 状态：

```bash
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

---

## ✅ 验证配置

### 测试 Bot

1. 在 Telegram 中搜索你的 Bot 用户名
2. 点击 "Start" 或发送 `/start`
3. 应该收到欢迎消息
4. 尝试发送 `/help` 查看帮助
5. 尝试发送 `/agents` 查看虚拟员工列表

### 测试命令

依次测试以下命令：

- `/start` - 欢迎消息
- `/help` - 帮助信息
- `/agents` - 虚拟员工列表
- `/dispatcher` - 切换到调度员
- `/current` - 查看当前员工
- `/reset` - 重置会话

### 测试对话

1. 切换到某个虚拟员工（如 `/development`）
2. 发送普通消息（如 "帮我分析代码"）
3. 应该收到 AI 回复

---

## 🔧 故障排查

### Bot 无响应

**检查项：**
1. Bot Token 是否正确
2. Webhook 是否设置成功
3. 服务是否正常运行
4. 防火墙是否开放端口

**解决方法：**
```bash
# 检查 Webhook 状态
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"

# 查看服务日志
docker logs openclaw-local -f

# 测试健康检查
curl http://localhost:3000/telegram/health
```

### Webhook 验证失败

**原因：** Secret Token 不匹配

**解决方法：**
1. 检查环境变量 `TELEGRAM_WEBHOOK_SECRET`
2. 重新设置 Webhook
3. 重启服务

### 命令菜单不显示

**解决方法：**
1. 重新运行 `setup-telegram-commands.sh`
2. 在 Telegram 中重启对话（删除对话后重新开始）

---

## 📚 相关文档

- [Telegram 部署指南](12-Telegram部署.md)
- [Telegram 使用指南](13-Telegram使用指南.md)
- [Telegram Bot API 官方文档](https://core.telegram.org/bots/api)

---

## 🆘 获取帮助

如遇问题，请：

1. 查看 [故障排查指南](06-故障排查.md)
2. 查看服务日志
3. 提交 Issue：https://github.com/your-org/openclaw-deploy/issues

---

**配置完成后，你的 Telegram Bot 就可以正常工作了！** 🎉
