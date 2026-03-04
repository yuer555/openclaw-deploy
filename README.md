# OpenClaw 企业微信桥接网关

将企业微信机器人消息桥接到 [OpenClaw](https://openclaw.ai) AI Agent 的轻量级网关。

Gateway **不管理** OpenClaw 的部署、容器或镜像 — 它只负责消息转发。
你只需要告诉 Gateway：OpenClaw 的地址和认证 Token。

## 📚 文档导航

- **[用户指南](USER-GUIDE.md)** - 从零开始的傻瓜式教程，10 分钟部署完成
- **[并发分析](docs/CONCURRENCY-ANALYSIS.md)** - 多用户场景下的性能分析和优化建议
- **[开发指南](AGENTS.md)** - AI 编码助手的项目规范和常用命令
- **[架构设计](PHASE2-PLAN.md)** - 纯桥接模式的设计文档

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

### 方式零：安装配置 OpenClaw

如果服务器上还没有安装 OpenClaw，使用一键安装脚本：

```bash
git clone https://github.com/your-org/openclaw-deploy.git
cd openclaw-deploy

# 一键安装 OpenClaw + 配置模型 + 创建 Agent + 编辑人格设定
bash scripts/install-openclaw.sh
```

安装脚本会自动完成：
1. 安装 OpenClaw（需要 Node.js 22+）
2. 配置模型提供商（官方 API Key + 第三方流量池如 GMN）
3. 创建多个 Agent（各自 workspace、沙箱配置、人格设定）
4. 输出 Gateway 集成所需的 URL 和 Token

快捷模式：
```bash
bash scripts/install-openclaw.sh --skip-install   # 跳过安装，只做配置
bash scripts/install-openclaw.sh --add-agent       # 只添加新 Agent
bash scripts/install-openclaw.sh --add-provider    # 只添加模型提供商
```

### 方式一：生产环境自动化部署（推荐）

适用于 Ubuntu/Debian/CentOS/RHEL 等 Linux 服务器，一键部署并配置 systemd 服务，支持崩溃自动重启。

```bash
# 下载项目
git clone https://github.com/your-org/openclaw-deploy.git
cd openclaw-deploy

# 一键部署（需要 root 权限）
sudo bash deploy/install.sh
```

部署完成后：

```bash
# 添加 Agent
sudo bash deploy/gateway-ctl.sh add-agent dev

# 查看服务状态
sudo bash deploy/gateway-ctl.sh status

# 查看实时日志
sudo bash deploy/gateway-ctl.sh logs
```

**更多运维命令** 见下方 [生产环境运维](#生产环境运维) 章节。

### 方式二：开发环境手动启动

适用于本地开发和测试。

#### 环境要求

- Python 3.10+
- 已部署并运行的 OpenClaw 实例（可通过 `bash scripts/install-openclaw.sh` 安装）
- 企业微信应用（需要 Token 和 EncodingAESKey）

#### 1. 安装依赖

```bash
pip3 install -r src/gateway/requirements.txt
```

#### 2. 配置环境变量

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

#### 3. 启动 Gateway

```bash
python3 src/gateway/wecom_gateway.py
```

首次启动时无 Agent，Gateway 正常运行但不处理任何消息。

#### 4. 添加 Agent

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

#### 5. 验证

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

## 生产环境运维

### systemd 服务管理

部署后，Gateway 作为 systemd 服务运行，支持崩溃自动重启。

```bash
# 启动服务
sudo systemctl start openclaw-gateway

# 停止服务
sudo systemctl stop openclaw-gateway

# 重启服务
sudo systemctl restart openclaw-gateway

# 查看状态
sudo systemctl status openclaw-gateway

# 查看日志
sudo journalctl -u openclaw-gateway -f

# 开机自启（默认已启用）
sudo systemctl enable openclaw-gateway
```

### 快捷运维脚本

`deploy/gateway-ctl.sh` 提供了常用运维命令：

```bash
# 服务管理
sudo bash deploy/gateway-ctl.sh start          # 启动
sudo bash deploy/gateway-ctl.sh stop           # 停止
sudo bash deploy/gateway-ctl.sh restart        # 重启
sudo bash deploy/gateway-ctl.sh status         # 状态
sudo bash deploy/gateway-ctl.sh logs           # 日志

# 监控检查
sudo bash deploy/gateway-ctl.sh health         # 健康检查
sudo bash deploy/gateway-ctl.sh agents         # Agent 列表
sudo bash deploy/gateway-ctl.sh stats          # 统计信息

# Agent 管理
sudo bash deploy/gateway-ctl.sh add-agent dev       # 添加 Agent
sudo bash deploy/gateway-ctl.sh list-agents         # 列出所有 Agent
sudo bash deploy/gateway-ctl.sh update-agent dev    # 更新 Agent
sudo bash deploy/gateway-ctl.sh remove-agent dev    # 删除 Agent

# 数据库
sudo bash deploy/gateway-ctl.sh db             # 打开 SQLite 数据库
```

### 卸载

```bash
# 完全卸载（保留数据库）
sudo bash deploy/uninstall.sh
```

### 目录结构

生产环境安装后的目录结构：

```
/opt/openclaw/gateway/          # 安装目录
├── src/gateway/                # 源代码
├── scripts/                    # 管理脚本
└── .env                        # 环境配置

/opt/openclaw/data/             # 数据目录
└── gateway/
    └── gateway.db              # SQLite 数据库

/var/log/openclaw/              # 日志目录
├── gateway.log                 # 标准输出
└── gateway-error.log           # 错误日志
```

### 崩溃自动重启

systemd 服务配置了以下重启策略：

- `Restart=always` — 任何退出都自动重启
- `RestartSec=10` — 重启前等待 10 秒
- 日志自动追加到 `/var/log/openclaw/` 目录

测试自动重启：

```bash
# 强制结束进程
sudo pkill -9 -f wecom_gateway.py

# 查看日志，应看到 10 秒后自动重启
sudo journalctl -u openclaw-gateway -f
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

生产环境可使用快捷命令：

```bash
sudo bash deploy/gateway-ctl.sh add-agent <name>
sudo bash deploy/gateway-ctl.sh list-agents
sudo bash deploy/gateway-ctl.sh update-agent <name>
sudo bash deploy/gateway-ctl.sh remove-agent <name>
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
│   ├── manage-agent.py       # Agent 绑定管理工具
│   └── install-openclaw.sh   # OpenClaw 一键安装配置脚本
├── deploy/
│   ├── install.sh            # 自动化部署脚本
│   ├── uninstall.sh          # 卸载脚本
│   ├── gateway-ctl.sh        # 运维快捷命令
│   └── openclaw-gateway.service  # systemd 服务文件
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
