# Proposal: 添加 Telegram 机器人支持

**Change ID**: `add-telegram-bot-support`
**Status**: 🟡 Proposed
**Created**: 2026-02-24
**Author**: OpenClaw Team

---

## 📋 概述

### 目标

为 OpenClaw-Deploy 系统添加 Telegram 机器人支持，使用户能够通过 Telegram 与虚拟员工进行交互。提供专属命令用于切换虚拟员工，所有命令在 Telegram 中具有自动索引和提示功能。

### 动机

1. **扩展用户触达**：Telegram 是全球流行的即时通讯平台，用户基数大
2. **跨平台支持**：除企业微信外，提供另一个主流平台的接入方式
3. **国际化需求**：Telegram 在国际市场更受欢迎，有利于产品国际化
4. **用户体验优化**：Telegram Bot 命令系统提供更好的交互体验
5. **降低接入门槛**：相比企业微信，Telegram Bot 创建和配置更简单

### 范围

**包含**:
- Telegram Bot 网关实现
- 6 个虚拟员工的 Telegram 命令支持
- 命令菜单和自动索引
- 消息路由和会话管理
- 用户权限管理
- 部署脚本和配置

**不包含**:
- Telegram 支付功能
- 群组管理功能（首期仅支持私聊）
- 多语言支持（首期仅支持中文）
- 富媒体消息（图片、视频等，首期仅支持文本）

---

## 🎯 需求

### 功能需求

#### FR-1: Telegram Bot 基础功能

**优先级**: P0 (必须)

##### Requirement: Bot 注册和配置
Bot 必须能够通过 BotFather 创建并配置基本信息。

###### Scenario: 创建新的 Telegram Bot
```
Given 管理员访问 @BotFather
When 使用 /newbot 命令创建机器人
And 设置机器人名称为 "OpenClaw 虚拟员工"
And 设置用户名为 "openclaw_assistant_bot"
Then BotFather 返回 Bot Token
And Bot Token 可用于 API 调用
```

##### Requirement: Webhook 接收消息
Bot 必须能够通过 Webhook 接收用户消息。

###### Scenario: 接收用户文本消息
```
Given Telegram Bot 已配置 Webhook URL
When 用户发送文本消息 "帮我分析一下代码"
Then 系统接收到包含 message.text 的 Update 对象
And Update 对象包含 user_id, chat_id, message_id
And 系统在 5 秒内返回 200 OK
```

##### Requirement: 发送响应消息
Bot 必须能够向用户发送文本消息。

###### Scenario: 发送 AI 回复
```
Given 系统已处理用户消息
When AI 生成回复 "让我帮您分析代码性能..."
Then 系统调用 sendMessage API
And 消息成功发送到用户聊天
And 用户在 Telegram 中看到回复
```

---

#### FR-2: 虚拟员工命令系统

**优先级**: P0 (必须)

##### Requirement: 命令菜单定义
Bot 必须定义完整的命令菜单，在 Telegram 中可索引。

###### Scenario: 设置 Bot 命令菜单
```
Given 管理员配置 Bot 命令
When 调用 setMyCommands API
Then Telegram 注册以下命令：
  - /start - 开始使用，显示欢迎信息
  - /help - 显示帮助信息
  - /agents - 显示所有虚拟员工
  - /dispatcher - 切换到调度员
  - /operation - 切换到运营专员
  - /product - 切换到产品经理
  - /development - 切换到开发工程师
  - /testing - 切换到测试工程师
  - /service - 切换到客服专员
  - /current - 显示当前虚拟员工
  - /reset - 重置会话
And 用户输入 "/" 时显示命令列表
```

##### Requirement: 切换虚拟员工
用户必须能够通过命令切换当前对话的虚拟员工。

###### Scenario: 切换到开发工程师
```
Given 用户当前与调度员对话
When 用户发送命令 "/development"
Then 系统切换当前 Agent 为 development-agent
And 系统回复 "✅ 已切换到：开发工程师小王\n我可以帮您：代码审查、Bug诊断、技术支持"
And 后续消息路由到开发工程师
```

###### Scenario: 查看当前虚拟员工
```
Given 用户已切换到产品经理
When 用户发送命令 "/current"
Then 系统回复 "📍 当前虚拟员工：产品经理小李\n职责：需求管理、产品设计、竞品分析"
```

##### Requirement: 显示虚拟员工列表
用户必须能够查看所有可用的虚拟员工。

###### Scenario: 查看员工列表
```
Given 用户发送命令 "/agents"
Then 系统回复包含所有虚拟员工信息：
  """
  🤖 可用的虚拟员工：

  1️⃣ 调度员 - 智能任务分发和路由
     命令：/dispatcher

  2️⃣ 运营专员 - 数据分析、报表生成
     命令：/operation

  3️⃣ 产品经理 - 需求管理、功能设计
     命令：/product

  4️⃣ 开发工程师 - 技术支持、代码审查
     命令：/development

  5️⃣ 测试工程师 - 质量保障、测试用例
     命令：/testing

  6️⃣ 客服专员 - 客户服务、问题解答
     命令：/service

  💡 使用命令切换虚拟员工，或直接发送消息给当前员工
  """
```

---

#### FR-3: 消息路由和处理

**优先级**: P0 (必须)

##### Requirement: 会话管理
系统必须为每个用户维护独立的会话状态。

###### Scenario: 用户会话隔离
```
Given 用户 A (user_id: 123) 切换到开发工程师
And 用户 B (user_id: 456) 切换到产品经理
When 用户 A 发送消息 "代码有bug"
And 用户 B 发送消息 "需求变更"
Then 用户 A 的消息路由到 development-agent
And 用户 B 的消息路由到 product-agent
And 两个会话互不干扰
```

##### Requirement: 消息路由到 OpenClaw
系统必须将用户消息路由到 OpenClaw Gateway。

###### Scenario: 调用 OpenClaw API
```
Given 用户当前 Agent 为 development-agent
When 用户发送消息 "帮我优化这段代码"
Then 系统调用 OpenClaw Gateway API：
  POST /api/v1/sessions/send
  {
    "message": "帮我优化这段代码",
    "agentId": "development-agent",
    "label": "telegram-123456",
    "timeoutSeconds": 30
  }
And 等待 AI 响应
And 将响应发送回用户
```

##### Requirement: 错误处理
系统必须优雅处理各种错误情况。

###### Scenario: OpenClaw 超时
```
Given 用户发送消息
When OpenClaw Gateway 响应超时（>30秒）
Then 系统回复 "⏱️ 处理超时，请稍后重试"
And 记录错误日志
```

###### Scenario: API 调用失败
```
Given 用户发送消息
When OpenClaw Gateway 返回 500 错误
Then 系统回复 "❌ 系统暂时无法处理您的请求，请稍后再试"
And 记录错误详情
```

---

#### FR-4: 用户体验优化

**优先级**: P1 (重要)

##### Requirement: 欢迎消息
新用户首次使用时必须看到欢迎信息。

###### Scenario: 首次启动 Bot
```
Given 用户首次访问 Bot
When 用户发送 "/start" 命令
Then 系统回复欢迎消息：
  """
  👋 欢迎使用 OpenClaw 虚拟员工！

  我们有 6 位专业的 AI 虚拟员工为您服务：
  • 调度员 - 智能任务分发
  • 运营专员 - 数据分析
  • 产品经理 - 需求管理
  • 开发工程师 - 技术支持
  • 测试工程师 - 质量保障
  • 客服专员 - 客户服务

  💡 使用 /agents 查看所有员工
  💡 使用 /help 查看帮助信息
  💡 直接发送消息开始对话

  当前默认员工：调度员
  """
And 系统创建用户会话
And 默认 Agent 设置为 dispatcher
```

##### Requirement: 帮助信息
用户必须能够随时查看帮助信息。

###### Scenario: 查看帮助
```
Given 用户发送 "/help" 命令
Then 系统回复帮助信息：
  """
  📖 OpenClaw 使用指南

  🤖 切换虚拟员工：
  /dispatcher - 调度员
  /operation - 运营专员
  /product - 产品经理
  /development - 开发工程师
  /testing - 测试工程师
  /service - 客服专员

  📋 其他命令：
  /agents - 查看所有虚拟员工
  /current - 查看当前员工
  /reset - 重置会话
  /help - 显示此帮助

  💬 使用方法：
  1. 选择一个虚拟员工（使用命令切换）
  2. 直接发送消息进行对话
  3. 随时切换到其他员工

  ❓ 问题反馈：https://github.com/your-org/openclaw-deploy/issues
  """
```

##### Requirement: 输入状态提示
系统处理消息时必须显示"正在输入"状态。

###### Scenario: 显示输入状态
```
Given 用户发送消息
When 系统开始处理消息
Then 调用 sendChatAction API
And action 设置为 "typing"
And 用户在 Telegram 中看到 "正在输入..." 提示
```

---

### 非功能需求

#### NFR-1: 性能要求

##### Requirement: 响应时间
系统必须在合理时间内响应用户消息。

###### Scenario: 正常响应时间
```
Given 用户发送消息
When OpenClaw 正常处理
Then 系统在 5 秒内返回 Webhook 响应
And AI 回复在 30 秒内发送给用户
```

#### NFR-2: 安全要求

##### Requirement: Webhook 验证
系统必须验证 Telegram Webhook 请求的合法性。

###### Scenario: 验证 Webhook 签名
```
Given Telegram 发送 Webhook 请求
When 系统接收请求
Then 验证 X-Telegram-Bot-Api-Secret-Token 头
And 只处理验证通过的请求
And 拒绝未授权请求（返回 403）
```

##### Requirement: 敏感信息保护
Bot Token 和配置必须安全存储。

###### Scenario: 环境变量配置
```
Given 系统启动
Then Bot Token 从环境变量 TELEGRAM_BOT_TOKEN 读取
And Token 不出现在日志中
And Token 不提交到代码仓库
```

#### NFR-3: 可维护性

##### Requirement: 日志记录
系统必须记录关键操作日志。

###### Scenario: 记录消息处理日志
```
Given 用户发送消息
Then 系统记录日志：
  - 时间戳
  - 用户 ID
  - 消息内容（脱敏）
  - 当前 Agent
  - 处理结果
  - 响应时间
```

---

## 🏗️ 技术设计

### 架构概览

```
Telegram 用户
    ↓ 发送消息/命令
Telegram 服务器
    ↓ HTTPS Webhook
    ↓ POST /telegram/webhook
OpenClaw Gateway (现有，扩展 Telegram 支持)
    ├─ 企业微信适配器 (/wecom/callback) - 已有
    ├─ Telegram 适配器 (/telegram/webhook) - 新增
    │   ├─ Webhook 接收和验证
    │   ├─ 命令处理 (/start, /help, /agents, /dispatcher 等)
    │   ├─ 会话管理 (user_id -> agent_id)
    │   └─ 消息路由到 OpenClaw
    └─ OpenClaw Core
        ├─ Agent 调度
        └─ AI 模型调用 (GitHub Copilot / OpenAI)
```

**关键点**：
- Telegram 支持直接集成到现有的 `src/gateway/` 中
- 复用现有的数据库和配置
- 与企业微信适配器并行工作
- 本地测试可直接使用 ngrok 暴露 Webhook

### 核心组件

#### 1. Telegram 适配器 (`src/gateway/telegram_adapter.py`)

**职责**：
- 接收 Telegram Webhook 请求
- 处理命令和普通消息
- 管理用户会话（user_id -> agent_id 映射）
- 调用 OpenClaw Core 的 Agent

**集成方式**：
- 在现有的 `wecom_gateway.py` 同级添加 `telegram_adapter.py`
- 在主 Flask app 中注册 `/telegram/webhook` 路由
- 复用现有的数据库连接和配置

#### 2. 会话管理

**存储方式**：
- 使用现有的 SQLite/PostgreSQL 数据库
- 新增 `telegram_sessions` 表
- 存储：user_id, current_agent, last_active

#### 3. 命令系统

**实现方式**：
- 在 Telegram 中通过 `setMyCommands` API 注册命令
- 用户输入 "/" 时自动显示命令列表
- 命令直接更新用户的 current_agent

**命令列表**：
```
/start - 开始使用
/help - 显示帮助
/agents - 显示所有虚拟员工
/dispatcher - 切换到调度员
/operation - 切换到运营专员
/product - 切换到产品经理
/development - 切换到开发工程师
/testing - 切换到测试工程师
/service - 切换到客服专员
/current - 显示当前虚拟员工
/reset - 重置会话
```

### 本地测试方案

**使用 ngrok 暴露本地服务**：
```bash
# 1. 启动本地服务
cd local/
./2-start-local.sh

# 2. 使用 ngrok 暴露端口
ngrok http 3000

# 3. 设置 Telegram Webhook
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=https://your-ngrok-url.ngrok.io/telegram/webhook"

# 4. 测试 Bot
# 在 Telegram 中搜索你的 Bot 并发送消息
```

### 生产部署方案

**直接配置域名和 SSL**：
```bash
# 1. 配置域名指向服务器
# 2. 使用 Let's Encrypt 配置 SSL
./production/4-setup-ssl.sh

# 3. 设置 Telegram Webhook
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=https://your-domain.com/telegram/webhook"
```

**注意**：
- 生产环境可以使用 Nginx 作为反向代理（可选）
- 也可以直接让 Flask 处理 HTTPS（使用 SSL 证书）
- Telegram 要求 Webhook 必须使用 HTTPS

### 数据库设计

#### 用户会话表 (`telegram_sessions`)

```sql
CREATE TABLE telegram_sessions (
    user_id BIGINT PRIMARY KEY,
    chat_id BIGINT NOT NULL,
    current_agent VARCHAR(50) DEFAULT 'dispatcher',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    message_count INTEGER DEFAULT 0
);
```

#### 消息日志表 (`telegram_messages`)

```sql
CREATE TABLE telegram_messages (
    id SERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    message_id BIGINT NOT NULL,
    message_text TEXT,
    agent_id VARCHAR(50),
    response_text TEXT,
    status VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### API 集成

#### Telegram Bot API

**Webhook 设置**:
```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://your-domain.com/telegram/webhook",
    "secret_token": "your-secret-token",
    "allowed_updates": ["message"]
  }'
```

**命令菜单设置**:
```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/setMyCommands" \
  -H "Content-Type: application/json" \
  -d '{
    "commands": [
      {"command": "start", "description": "开始使用"},
      {"command": "help", "description": "显示帮助"},
      {"command": "agents", "description": "显示所有虚拟员工"},
      {"command": "dispatcher", "description": "切换到调度员"},
      {"command": "operation", "description": "切换到运营专员"},
      {"command": "product", "description": "切换到产品经理"},
      {"command": "development", "description": "切换到开发工程师"},
      {"command": "testing", "description": "切换到测试工程师"},
      {"command": "service", "description": "切换到客服专员"},
      {"command": "current", "description": "显示当前虚拟员工"},
      {"command": "reset", "description": "重置会话"}
    ]
  }'
```

#### OpenClaw Core 集成

**直接调用 Agent**:
```python
# 在 telegram_adapter.py 中
# 不需要调用外部 API，直接使用 OpenClaw Core 的 Agent 系统

from openclaw.agents import AgentManager

agent_manager = AgentManager()

# 处理用户消息
response = agent_manager.process_message(
    agent_id="development-agent",
    message="帮我优化代码",
    user_id="telegram-123456"
)
```

**注意**：
- 如果 OpenClaw 是独立服务，则通过 HTTP API 调用
- 如果 OpenClaw 是库/模块，则直接导入使用
- 需要根据实际的 OpenClaw 架构调整集成方式

### 配置管理

#### 环境变量

```bash
# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_WEBHOOK_SECRET=your_webhook_secret

# OpenClaw 配置（已有）
OPENCLAW_GATEWAY_URL=http://localhost:18789  # 如果是独立服务
# 或者直接使用 OpenClaw Core（如果是集成模式）

# 数据库配置（已有）
DATABASE_URL=sqlite:///data/openclaw.db  # 本地
# DATABASE_URL=postgresql://user:password@localhost:5432/openclaw  # 生产

# 日志配置（已有）
LOG_LEVEL=info
```

**配置文件位置**：
- 本地测试：`local/.env.local`
- 生产环境：`production/.env.prod`

**注意**：
- 不需要配置 Nginx（除非生产环境需要）
- 本地测试使用 ngrok 暴露端口
- 生产环境直接配置域名和 SSL

---

## 📦 实施计划

### 阶段 1: 基础设施 (Week 1)

- [ ] 创建 Telegram Bot（通过 BotFather）
- [ ] 实现 `telegram_gateway.py` 基础框架
- [ ] 实现 Webhook 接收和验证
- [ ] 配置数据库表结构
- [ ] 实现基本的消息发送功能

### 阶段 2: 命令系统 (Week 2)

- [ ] 实现命令解析器
- [ ] 实现 `/start` 和 `/help` 命令
- [ ] 实现 `/agents` 命令
- [ ] 实现虚拟员工切换命令（6个）
- [ ] 实现 `/current` 和 `/reset` 命令
- [ ] 设置 Bot 命令菜单

### 阶段 3: 消息路由 (Week 3)

- [ ] 实现会话管理器
- [ ] 实现消息路由到 OpenClaw
- [ ] 实现 AI 响应处理
- [ ] 实现错误处理和重试机制
- [ ] 实现输入状态提示

### 阶段 4: 部署和测试 (Week 4)

- [ ] 编写部署脚本
- [ ] 配置 Docker 容器
- [ ] 编写测试用例
- [ ] 进行端到端测试
- [ ] 编写用户文档
- [ ] 生产环境部署

---

## 🧪 测试策略

### 单元测试

- 命令解析器测试
- 会话管理器测试
- 消息路由逻辑测试
- API 调用测试

### 集成测试

- Webhook 接收测试
- OpenClaw API 集成测试
- 数据库操作测试

### 端到端测试

- 用户完整对话流程测试
- 虚拟员工切换测试
- 错误场景测试

---

## 📚 文档

### 需要创建的文档

1. **Telegram Bot 配置指南** (`docs/11-Telegram配置.md`)
   - Bot 创建步骤
   - Webhook 配置
   - 命令菜单设置

2. **Telegram 部署指南** (`docs/12-Telegram部署.md`)
   - 本地测试部署
   - 生产环境部署
   - 故障排查

3. **用户使用指南** (`docs/13-Telegram使用指南.md`)
   - 如何开始使用
   - 命令列表
   - 常见问题

---

## 🔄 依赖和风险

### 依赖

- **外部依赖**:
  - Telegram Bot API
  - OpenClaw Gateway
  - PostgreSQL / SQLite

- **技术依赖**:
  - Python 3.11+
  - Flask 3.0+
  - python-telegram-bot 库（或 requests）

### 风险

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| Telegram API 限流 | 高 | 实现请求队列和重试机制 |
| Webhook 不稳定 | 中 | 实现健康检查和自动恢复 |
| 会话状态丢失 | 中 | 使用数据库持久化会话 |
| OpenClaw 超时 | 低 | 设置合理超时和错误提示 |

---

## ✅ 验收标准

### 功能验收

- [ ] 用户可以通过 Telegram 与 6 个虚拟员工对话
- [ ] 所有命令在 Telegram 中可索引和使用
- [ ] 用户可以随时切换虚拟员工
- [ ] 系统正确路由消息到 OpenClaw
- [ ] AI 响应正确返回给用户

### 性能验收

- [ ] Webhook 响应时间 < 5 秒
- [ ] AI 回复时间 < 30 秒
- [ ] 支持并发 100+ 用户

### 安全验收

- [ ] Webhook 请求验证通过
- [ ] Bot Token 安全存储
- [ ] 用户数据加密存储

### 文档验收

- [ ] 配置指南完整
- [ ] 部署指南完整
- [ ] 用户指南完整
- [ ] API 文档完整

---

## 📝 备注

### 未来扩展

- 支持群组对话
- 支持多语言（英文、日文等）
- 支持富媒体消息（图片、文件）
- 支持内联键盘（Inline Keyboard）
- 支持回调查询（Callback Query）
- 集成 Telegram 支付

### 参考资料

- [Telegram Bot API 文档](https://core.telegram.org/bots/api)
- [python-telegram-bot 库](https://github.com/python-telegram-bot/python-telegram-bot)
- [OpenClaw Gateway API 文档](docs/07-API文档.md)

---

**提案状态**: 🟡 等待审批
**下一步**: 等待团队审核和批准后开始实施
