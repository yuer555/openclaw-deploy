# OpenClaw 企业微信桥接网关

将企业微信机器人消息桥接到 [OpenClaw](https://openclaw.ai) AI Agent 的轻量级网关。

Gateway **不管理** OpenClaw 的部署、容器或镜像 — 它只负责消息转发。
你只需要告诉 Gateway：OpenClaw 的地址和认证 Token。

## 特性

- **纯桥接模式** — Gateway 仅做企业微信与 OpenClaw 之间的消息转发
- **多 Agent 支持** — 每个 Agent 对接一个企业微信机器人，一对一绑定
- **灵活部署** — 单实例多 Agent / 多实例 / 混合模式，自动兼容
- **SQLite 存储** — Agent 绑定关系持久化，通过管理脚本操作
- **多协议** — 支持 WebSocket（默认）、SSE、HTTP 三种通信协议
- **会话隔离** — 按 Agent + 企业微信用户自动隔离会话

## 部署模式

```
模式 A：单 OpenClaw 实例 + 多 Agent
  企业微信A ──► /dev/wecom/callback  ──┐
  企业微信B ──► /ops/wecom/callback  ──┼──► 同一个 OpenClaw（不同 agent_id）
  企业微信C ──► /svc/wecom/callback  ──┘

模式 B：多 OpenClaw 实例
  企业微信A ──► /dev/wecom/callback  ──► OpenClaw 实例 1
  企业微信B ──► /ops/wecom/callback  ──► OpenClaw 实例 2

模式 C：混合
  企业微信A ──► /dev/wecom/callback  ──┐
  企业微信B ──► /ops/wecom/callback  ──┼──► OpenClaw 实例 1（不同 agent_id）
  企业微信C ──► /svc/wecom/callback  ──────► OpenClaw 实例 2
```

无需额外配置，Gateway 根据 SQLite 中的绑定关系自动路由。

## 快速开始

### 环境要求

- Python 3.10+
- 已部署并运行的 OpenClaw 实例（需要其 URL 和 Token）
- 企业微信应用（需要 Token 和 EncodingAESKey）

### 1. 安装依赖

```bash
pip3 install -r src/gateway/requirements.txt
```

### 2. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env，按需修改
```

环境变量说明：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DB_PATH` | `/opt/openclaw/data/gateway/gateway.db` | SQLite 数据库路径 |
| `GATEWAY_PORT` | `8000` | Gateway 监听端口 |
| `OPENCLAW_PROTOCOL` | `ws` | 通信协议：`ws` / `sse` / `http` |
| `OPENCLAW_TIMEOUT` | `2700` | OpenClaw 调用超时（秒） |
| `GATEWAY_URL` | `http://localhost:8000` | Gateway 地址（管理脚本用于通知重载） |

### 3. 启动 Gateway

```bash
python3 src/gateway/wecom_gateway.py
```

首次启动时无 Agent，Gateway 正常运行但不处理任何消息。

### 4. 添加 Agent

```bash
python3 scripts/manage-agent.py add dev
```

按提示依次输入：
- **显示名** — 如"开发工程师小明"
- **企业微信 Token** — 企业微信应用的 Token
- **企业微信 AES Key** — 企业微信应用的 EncodingAESKey
- **OpenClaw 地址** — 如 `http://10.0.1.5:18789`
- **OpenClaw Token** — OpenClaw 的认证 Token
- **OpenClaw Agent ID** — 回车跳过则使用默认 `main`

添加成功后，将企业微信回调地址设为：

```
https://your-domain/dev/wecom/callback
```

### 5. 验证

```bash
# 健康检查
curl http://localhost:8000/health

# 查看已绑定的 Agent
curl http://localhost:8000/admin/agents
```

## Agent 管理

所有 Agent 绑定通过 `scripts/manage-agent.py` 管理：

```bash
# 添加 Agent（交互式）
python3 scripts/manage-agent.py add <name>

# 列出所有 Agent
python3 scripts/manage-agent.py list

# 更新 Agent（交互式，回车保持原值不变）
python3 scripts/manage-agent.py update <name>

# 删除 Agent（需确认）
python3 scripts/manage-agent.py remove <name>
```

管理脚本在添加/更新/删除后会自动通知 Gateway 重载配置，无需重启。

## API 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET/POST | `/{agent_name}/wecom/callback` | 企业微信回调（按 Agent 路由） |
| GET/POST | `/wecom/callback` | 旧版兼容路径 |
| GET | `/health` | 健康检查 |
| GET | `/stats` | 统计信息 |
| GET | `/admin/agents` | 列出所有 Agent 绑定 |
| POST | `/admin/reload` | 重载 Agent 配置 |

## 消息处理流程

```
企业微信用户发消息
       │
       ▼
GET/POST /{agent_name}/wecom/callback
       │
       ├─ 从 SQLite 查找 agent 配置（未找到 → 404）
       │
       ├─ 用该 agent 的 wecom_token/aes_key 解密验签
       │
       ├─ 提取 user_id, content
       │
       ├─ 构造 session_key = "wecom:{agent_name}:{user_id}"
       │
       ├─ 调用 OpenClaw（WS/SSE/HTTP）
       │   ├─ URL:      agent 的 openclaw_url
       │   ├─ Token:    agent 的 openclaw_token
       │   ├─ Agent ID: agent 的 openclaw_agent_id（默认 main）
       │   └─ Session:  session_key
       │
       └─ 收到回复 → 通过企业微信回复用户
```

## 项目结构

```
openclaw-deploy/
├── src/gateway/
│   ├── wecom_gateway.py      # Gateway 主程序
│   └── requirements.txt      # Python 依赖
├── scripts/
│   └── manage-agent.py       # Agent 绑定管理工具
├── .env.example              # 环境变量模板
├── AGENTS.md                 # AI 编码助手指南
└── PHASE2-PLAN.md            # 架构方案文档
```

## 数据库

Gateway 使用 SQLite 存储 Agent 绑定关系，数据库路径由 `DB_PATH` 环境变量指定。

### agents 表

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | TEXT (PK) | 路由标识，用于 URL 路径 |
| `display_name` | TEXT | 显示名称 |
| `wecom_token` | TEXT | 企业微信 Token |
| `wecom_aes_key` | TEXT | 企业微信 EncodingAESKey |
| `openclaw_url` | TEXT | OpenClaw 地址 |
| `openclaw_token` | TEXT | OpenClaw 认证 Token |
| `openclaw_agent_id` | TEXT | OpenClaw Agent ID（空 = 默认 main） |
| `created_at` | TEXT | 创建时间 |
| `updated_at` | TEXT | 更新时间 |

### task_logs 表

| 字段 | 类型 | 说明 |
|------|------|------|
| `task_id` | TEXT (PK) | 任务 ID |
| `user_id` | TEXT | 用户 ID |
| `agent_id` | TEXT | Agent 标识 |
| `task_content` | TEXT | 任务内容 |
| `status` | TEXT | 状态 |
| `result` | TEXT | 结果 |
| `created_at` | TIMESTAMP | 创建时间 |
| `updated_at` | TIMESTAMP | 更新时间 |

### 常用查询

```bash
# 查看数据库结构
sqlite3 $DB_PATH ".schema"

# 查看所有 Agent 绑定
sqlite3 $DB_PATH "SELECT name, display_name, openclaw_url FROM agents;"

# 查看任务统计
sqlite3 $DB_PATH "SELECT COUNT(*), status FROM task_logs GROUP BY status;"
```

## 注意事项

- **安全**：不要将 `.env` 和 `*.db` 文件提交到 Git
- **首次启动**：Gateway 正常启动但无 Agent，需通过 `manage-agent.py` 添加
- **热重载**：添加/删除 Agent 后管理脚本自动通知 Gateway，无需重启
- **数据目录**：`data/` 目录在运行时自动创建，已在 `.gitignore` 中排除
