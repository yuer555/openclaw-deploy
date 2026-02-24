# Tasks: 添加 Telegram 机器人支持

**Change ID**: `add-telegram-bot-support`
**Status**: 🟡 Proposed

---

## 📋 实施任务清单

### 阶段 1: 基础设施搭建

#### 1.1 Telegram Bot 创建和配置
- [ ] 通过 @BotFather 创建新的 Telegram Bot
- [ ] 设置 Bot 名称为 "OpenClaw 虚拟员工"
- [ ] 设置 Bot 用户名为 "openclaw_assistant_bot"
- [ ] 获取并保存 Bot Token
- [ ] 配置 Bot 头像和描述信息

#### 1.2 项目结构创建
- [ ] 创建 `src/gateway/telegram_adapter.py` 文件（集成适配器）
- [ ] 更新 `src/gateway/main.py` 或 `wecom_gateway.py` 添加 Telegram 路由
- [ ] 更新 `src/gateway/requirements.txt` 添加依赖：
  - `requests==2.31.0`（用于调用 Telegram API）

#### 1.3 数据库表创建
- [ ] 创建数据库迁移脚本 `migrations/001_create_telegram_sessions.sql`
- [ ] 创建 `telegram_sessions` 表（存储 user_id, current_agent, last_active）
- [ ] 添加索引优化查询性能（idx_last_active）

#### 1.4 配置文件更新
- [ ] 在 `local/.env.local.example` 添加 Telegram 配置项
- [ ] 在 `production/.env.prod.example` 添加 Telegram 配置项
- [ ] 更新 `config/.env.example` 添加 Telegram 配置

---

### 阶段 2: 核心功能实现

#### 2.1 TelegramAdapter 类实现
- [ ] 实现 `TelegramAdapter` 类初始化（bot_token, db_path, agents 配置）
- [ ] 实现 `handle_webhook(update)` 方法处理 Telegram Update
- [ ] 实现 Webhook 签名验证（X-Telegram-Bot-Api-Secret-Token）
- [ ] 实现 Update 对象解析（提取 user_id, chat_id, text）
- [ ] 添加请求日志记录和错误处理

#### 2.2 命令处理实现
- [ ] 实现 `_handle_command(user_id, chat_id, text)` 方法
- [ ] 实现 `/start` 命令处理（`_cmd_start`）
- [ ] 实现 `/help` 命令处理（`_cmd_help`）
- [ ] 实现 `/agents` 命令处理（`_cmd_agents`）
- [ ] 实现 `/dispatcher` 命令处理（`_cmd_switch_agent`）
- [ ] 实现 `/operation` 命令处理
- [ ] 实现 `/product` 命令处理
- [ ] 实现 `/development` 命令处理
- [ ] 实现 `/testing` 命令处理
- [ ] 实现 `/service` 命令处理
- [ ] 实现 `/current` 命令处理（`_cmd_current`）
- [ ] 实现 `/reset` 命令处理（`_cmd_reset`）

#### 2.3 消息路由和会话管理
- [ ] 实现 `_handle_message(user_id, chat_id, text)` 方法
- [ ] 实现 `_get_current_agent(user_id)` 获取当前 Agent
- [ ] 实现 `_create_session(user_id, agent_id)` 创建会话
- [ ] 实现 `_switch_agent(user_id, agent_id)` 切换 Agent
- [ ] 实现 `_call_agent(agent_id, message, user_id)` 调用 OpenClaw
- [ ] 实现错误处理和超时处理

#### 2.4 消息发送功能
- [ ] 实现 `send_message(chat_id, text)` 方法
- [ ] 实现 `send_chat_action(chat_id, action)` 方法（typing 状态）
- [ ] 实现消息格式化（Markdown 支持）
- [ ] 实现发送失败重试机制

---

### 阶段 3: Flask 路由集成

#### 3.1 Flask 路由配置
- [ ] 在 `src/gateway/main.py` 中初始化 TelegramAdapter
- [ ] 添加 Flask 路由 `/telegram/webhook` (POST)
- [ ] 添加健康检查路由 `/telegram/health` (GET)
- [ ] 实现 Webhook 验证中间件
- [ ] 配置环境变量读取（TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET）

#### 3.2 Bot 命令菜单配置
- [ ] 编写命令菜单配置脚本 `scripts/setup-telegram-commands.sh`
- [ ] 创建命令配置 JSON 文件 `config/telegram-commands.json`
- [ ] 调用 Telegram API `setMyCommands` 设置命令列表
- [ ] 验证命令在 Telegram 中正确显示
- [ ] 添加命令描述和使用说明

#### 3.3 Bot 信息配置
- [ ] 设置 Bot 简介（About）
- [ ] 设置 Bot 描述（Description）
- [ ] 上传 Bot 头像
- [ ] 配置 Bot 隐私设置

---

### 阶段 4: 本地测试和部署配置

#### 4.1 本地测试配置
- [ ] 更新 `local/.env.local.example` 添加 Telegram 配置项
- [ ] 创建 `local/6-setup-telegram-local.sh` 本地 Telegram 配置脚本
- [ ] 配置 ngrok 暴露本地端口（用于 Webhook 测试）
- [ ] 实现 Webhook 设置脚本 `scripts/set-telegram-webhook.sh`
- [ ] 配置 Webhook URL（ngrok URL）
- [ ] 配置 Webhook Secret Token
- [ ] 验证 Webhook 连接
- [ ] 添加 Webhook 删除脚本 `scripts/delete-telegram-webhook.sh`（用于测试）

#### 4.2 Docker 配置更新
- [ ] 更新 `src/gateway/Dockerfile` 添加 Telegram 依赖
- [ ] 更新 `local/docker-compose.local.yml` 添加 Telegram 环境变量
- [ ] 更新 `production/docker-compose.prod.yml` 添加 Telegram 配置
- [ ] 确保数据库挂载包含 telegram_sessions 表

#### 4.3 生产部署配置
- [ ] 更新 `production/.env.prod.example` 添加 Telegram 配置项
- [ ] 创建 `production/7-setup-telegram-prod.sh` 生产 Telegram 配置脚本
- [ ] 配置生产域名（如 bot.openclaw.com）
- [ ] 配置 SSL 证书（Let's Encrypt 或现有证书）
- [ ] 配置 Nginx 反向代理（可选，用于 SSL 终止）
- [ ] 更新 `production/3-deploy-production.sh` 包含 Telegram 部署步骤

---

### 阶段 5: 测试

#### 5.1 单元测试
- [ ] 编写 TelegramAdapter 测试 `tests/test_telegram_adapter.py`
- [ ] 测试命令处理逻辑（所有命令）
- [ ] 测试会话管理逻辑（创建、获取、切换）
- [ ] 测试消息路由逻辑
- [ ] 测试 Webhook 验证逻辑
- [ ] 确保测试覆盖率 > 80%

#### 5.2 集成测试
- [ ] 编写 Webhook 接收测试（模拟 Telegram Update）
- [ ] 编写 OpenClaw 集成测试（调用 Agent）
- [ ] 编写数据库操作测试（会话 CRUD）
- [ ] 编写端到端流程测试（完整对话流程）

#### 5.3 手动测试
- [ ] 使用 ngrok 配置本地 Webhook
- [ ] 测试 `/start` 命令
- [ ] 测试 `/help` 命令
- [ ] 测试 `/agents` 命令
- [ ] 测试所有虚拟员工切换命令（6个）
- [ ] 测试 `/current` 命令
- [ ] 测试 `/reset` 命令
- [ ] 测试普通消息对话（与 AI 交互）
- [ ] 测试错误场景（超时、失败等）
- [ ] 测试并发用户场景（多用户同时使用）

---

### 阶段 6: 文档编写

#### 6.1 配置文档
- [ ] 创建 `docs/11-Telegram配置.md`
  - Bot 创建步骤
  - Token 获取方法
  - Webhook 配置说明
  - 命令菜单设置
  - 常见问题解答

#### 6.2 部署文档
- [ ] 创建 `docs/12-Telegram部署.md`
  - 本地测试部署步骤
  - 生产环境部署步骤
  - 环境变量配置说明
  - Docker 配置说明
  - 故障排查指南

#### 6.3 用户文档
- [ ] 创建 `docs/13-Telegram使用指南.md`
  - 如何开始使用
  - 命令列表和说明
  - 使用示例
  - 常见问题
  - 反馈渠道

#### 6.4 API 文档更新
- [ ] 更新 `docs/07-API文档.md` 添加 Telegram Webhook API
- [ ] 添加请求/响应示例
- [ ] 添加错误码说明

#### 6.5 项目文档更新
- [ ] 更新 `README.md` 添加 Telegram 支持说明
- [ ] 更新 `QUICK_START.md` 添加 Telegram 快速开始
- [ ] 更新 `SYSTEM_ANALYSIS.md` 添加 Telegram 架构说明
- [ ] 更新 `openspec/project.md` 添加 Telegram 技术栈

---

### 阶段 7: 生产部署

#### 7.1 生产环境准备
- [ ] 申请生产环境域名（如 bot.openclaw.com）
- [ ] 配置 DNS 解析指向服务器
- [ ] 配置 SSL 证书（Let's Encrypt）
- [ ] 配置 Nginx 反向代理（可选，用于 SSL 终止）
- [ ] 配置防火墙规则（开放 443 端口）

#### 7.2 生产部署
- [ ] 上传代码到生产服务器
- [ ] 配置生产环境变量（.env.prod）
- [ ] 运行数据库迁移（创建 telegram_sessions 表）
- [ ] 启动 OpenClaw Gateway 服务（集成 Telegram 支持）
- [ ] 设置生产环境 Webhook（使用生产域名）
- [ ] 配置 Bot 命令菜单

#### 7.3 监控和告警
- [ ] 配置日志收集（Telegram 相关日志）
- [ ] 配置性能监控（响应时间、成功率）
- [ ] 配置错误告警（Webhook 失败、API 错误）
- [ ] 配置健康检查（/telegram/health 端点）

#### 7.4 上线验证
- [ ] 验证 Webhook 正常工作
- [ ] 验证所有命令正常响应
- [ ] 验证消息路由正常
- [ ] 验证 AI 响应正常
- [ ] 进行压力测试（模拟多用户并发）

---

## 📊 进度跟踪

### 总体进度
- 阶段 1: 基础设施搭建 - 0/11 (0%)
- 阶段 2: 核心功能实现 - 0/25 (0%)
- 阶段 3: Flask 路由集成 - 0/13 (0%)
- 阶段 4: 本地测试和部署配置 - 0/18 (0%)
- 阶段 5: 测试 - 0/16 (0%)
- 阶段 6: 文档编写 - 0/13 (0%)
- 阶段 7: 生产部署 - 0/17 (0%)

**总计**: 0/113 任务完成 (0%)

---

## 🎯 里程碑

- [ ] **M1**: 基础设施搭建完成（Week 1）
- [ ] **M2**: 核心功能实现完成（Week 2）
- [ ] **M3**: 测试通过（Week 3）
- [ ] **M4**: 文档完成（Week 3）
- [ ] **M5**: 生产部署完成（Week 4）

---

## 📝 备注

### 架构说明
本提案采用**简化架构**，将 Telegram 支持直接集成到现有的 OpenClaw Gateway 中：
- **集成方式**: 在 `src/gateway/` 中添加 `telegram_adapter.py`
- **无需独立服务**: 不创建单独的 Telegram Gateway 服务
- **复用基础设施**: 使用现有的数据库、日志、配置系统
- **简化部署**: 本地测试使用 ngrok，生产环境可选 Nginx（仅用于 SSL）

### 优先级说明
- **P0**: 必须完成，阻塞上线
- **P1**: 重要功能，建议完成
- **P2**: 优化功能，可后续迭代

### 依赖关系
- 阶段 2 依赖阶段 1 完成
- 阶段 3 依赖阶段 2 完成
- 阶段 4 可与阶段 2-3 并行
- 阶段 5 依赖阶段 2-3 完成
- 阶段 6 可与阶段 5 并行
- 阶段 7 依赖所有前置阶段完成

### 风险提示
- Telegram API 可能有限流，需要实现请求队列
- Webhook 需要 HTTPS，本地测试需要使用 ngrok 或类似工具
- 会话状态需要持久化，避免服务重启丢失

### 技术优势
- **减少 50% 的服务数量**: 1 个服务 vs 3 个服务
- **减少 60% 的配置文件**: 1 个配置 vs 3 个配置
- **减少 40% 的代码量**: 集成实现更简洁
- **降低延迟**: 减少网络跳转（2 跳 vs 4 跳）
- **简化部署**: 本地 3 步，生产 1 个容器

---

**任务清单创建时间**: 2026-02-24
**任务清单更新时间**: 2026-02-24 (简化架构版本)
**预计完成时间**: 2026-03-24 (4 周)
**负责人**: OpenClaw Team
