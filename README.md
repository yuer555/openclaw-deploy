# OpenClaw 企业微信桥接网关

将企业微信机器人消息桥接到 [OpenClaw](https://openclaw.ai) Agent 的轻量级 Gateway。

Gateway **不负责** OpenClaw 的镜像、容器和生命周期管理；它只负责：
- 接收企业微信回调
- 按 SQLite 绑定关系路由到指定 OpenClaw
- 将回复再发回企业微信
- 处理文件上传、共享目录和可选的 S3 发布

## 文档导航

- `USER-GUIDE.md` — 面向使用者的完整部署与操作手册
- `docs/CONCURRENCY-ANALYSIS.md` — 并发与性能说明
- `PHASE2-PLAN.md` — 架构设计说明
- `AGENTS.md` — 仓库开发规范

## 核心规则

- **纯桥接模式**：Gateway 只转发消息，不托管 OpenClaw。
- **强绑定规则**：`agent_id = Gateway 路由名 = SQLite agents.name = openclaw_agent_id`。
- **local 文件路径固定**：Gateway 下发给 Agent 的本地文件路径固定为 `/app/shared/<agent_id>/...`。
- **宿主机真实目录**：`/app/shared/<agent_id>` 应指向 `~/.openclaw/workspace-<agent_id>/shared`。
- **沙箱 bind 规则**：Docker 沙箱必须挂载 workspace 内 source，例如 `~/.openclaw/workspace-<agent_id>/shared:/app/shared/<agent_id>:rw`。
- **系统依赖安装策略**：沙箱里不要依赖运行时 `apt-get`；需要的系统工具应直接预装到 `bin/openclaw-sandbox-devtools.Dockerfile`。

升级提示：
- 如果旧版本沙箱配置里残留了 `setupCommand: "apt-get ..."`，请重新运行 `bash bin/03-install-openclaw.sh --skip-install`，然后执行 `openclaw sandbox recreate --agent <agent_id>`。

这样设计的原因是同时满足：
- Gateway 能稳定下发绝对路径
- OpenClaw 沙箱 allowed roots 要求 bind source 位于 workspace 内

一句话区分：
- **`FILE_STORAGE_MODE` 决定“企业微信发来的文件怎么交给 Agent”**。
- **`gateway-file-upload` skill 决定“Agent 能不能把自己的产物再上传出去”**。

## 权限规则

- `bin/02-install-gateway.sh`、`bin/05-cleanup.sh` 需要 `sudo`
- `bin/03-install-openclaw.sh`、`bin/04-manage-agent.sh` 必须用**普通用户**运行
- `scripts/manage-agent.py` 也必须用**普通用户**运行

不要用 `root` 或 `sudo` 运行 `03` / `04`，否则 OpenClaw home 会落到 `/root/.openclaw`，并触发沙箱路径限制。

## 快速开始

### 1) 安装和配置 OpenClaw

```bash
bash bin/03-install-openclaw.sh
```

快捷模式：

```bash
bash bin/03-install-openclaw.sh --skip-install
bash bin/03-install-openclaw.sh --add-agent
bash bin/03-install-openclaw.sh --add-provider
```

说明：
- 需要 Node.js 22+
- Docker **仅在创建沙箱 Agent 时需要**
- 如果启用沙箱但 Docker / 沙箱镜像未准备，脚本会提示安装 Docker、配置镜像加速和构建镜像

### 2) 部署 Gateway

```bash
sudo bash bin/02-install-gateway.sh
```

部署完成后，代码会被同步到 `/opt/openclaw/gateway`，并安装为 `systemd` 服务 `openclaw-gateway`。

### 3) 添加企业微信 Agent 绑定

生产环境：

```bash
/opt/openclaw/gateway/bin/04-manage-agent.sh add team-dev
```

开发环境：

```bash
python3 scripts/manage-agent.py add team-dev
```

交互顺序与当前脚本一致：
- **Gateway 地址** — 实际上是 OpenClaw 服务地址，例如 `http://localhost:18789`
- **Agent ID** — 路由名，同时也是 OpenClaw agent_id
- **共享文件目录** — 自动生成，固定为 `/app/shared/<agent_id>`
- **Gateway Token** — 实际上是 OpenClaw token
- **企业微信 Token**
- **企业微信 EncodingAESKey**
- **显示名**

### 4) 验证

```bash
curl http://localhost:8000/health
curl http://localhost:8000/admin/agents
```

## 开发环境启动

### 安装依赖

```bash
pip3 install -r src/gateway/requirements.txt
```

### 配置环境变量

```bash
cp .env.example .env
```

### 启动 Gateway

```bash
python3 src/gateway/wecom_gateway.py
```

首次启动时即使没有任何 Agent，Gateway 也会正常启动；只是不会处理实际企业微信消息。

## 环境变量

`.env.example` 只配置 Gateway 自身参数；Agent 绑定关系都在 SQLite 中维护。

### 常用配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DB_PATH` | `/opt/openclaw/data/gateway/gateway.db` | SQLite 数据库路径 |
| `GATEWAY_PORT` | `8000` | Gateway 监听端口 |
| `OPENCLAW_PROTOCOL` | `ws` | `ws` / `sse` / `http` |
| `OPENCLAW_TIMEOUT` | `180` | 兼容旧配置的总超时 |
| `OPENCLAW_CONNECT_TIMEOUT` | `10` | 连接 OpenClaw 超时 |
| `OPENCLAW_WS_IDLE_TIMEOUT` | `30` | WS 空闲超时 |
| `OPENCLAW_WS_TOTAL_TIMEOUT` | `180` | WS 总超时 |
| `OPENCLAW_SSE_IDLE_TIMEOUT` | `30` | SSE 空闲超时 |
| `OPENCLAW_SSE_TOTAL_TIMEOUT` | `180` | SSE 总超时 |
| `OPENCLAW_HTTP_TIMEOUT` | `180` | HTTP 总超时 |
| `MAX_GATEWAY_WORKERS` | `8` | Gateway 全局 worker 数 |
| `MAX_PER_USER_PENDING` | `1` | 单用户最多等待消息数 |
| `MAX_QUEUE_WAIT_SECONDS` | `60` | 等待队列最大时长 |
| `GATEWAY_URL` | `http://localhost:8000` | 管理脚本回调 `/admin/reload` 使用 |
| `FILE_STORAGE_MODE` | `local` | `local` / `s3` |
| `FILE_STORAGE_PRESIGN_EXPIRES` | `86400` | S3 预签名有效期 |
| `FILE_UPLOAD_INTERNAL_TOKEN` | 空 | Gateway 内部上传接口鉴权；`03` 会据此生成 `OPENCLAW_FILE_UPLOAD_TOKEN` |
| `MAX_INTERNAL_UPLOAD_FILE_SIZE` | `52428800` | 内部上传大小限制 |
| `FILE_STORAGE_KEY_PREFIX` | `openclaw-gateway` | 对象存储 key 前缀 |

上传 Skill 运行时变量说明：
- `03-install-openclaw.sh` 会自动生成：
  - `OPENCLAW_FILE_UPLOAD_GATEWAY_URL` ← `GATEWAY_URL`
  - `OPENCLAW_FILE_UPLOAD_TOKEN` ← `FILE_UPLOAD_INTERNAL_TOKEN`
  - `OPENCLAW_FILE_UPLOAD_EXPIRES` ← `FILE_STORAGE_PRESIGN_EXPIRES`
- 非沙箱 Agent：写入 `~/.openclaw/.env`；如果 OpenClaw 已在运行，必须重启 OpenClaw 后生效。
- 沙箱 Agent：写入对应 agent 的 `sandbox.docker.env`；如果原始地址是 `localhost/127.0.0.1`，脚本会自动改成 `host.docker.internal`，并补 `extraHosts: ["host.docker.internal:host-gateway"]`。
- 沙箱配置变更后，如果容器已存在，执行 `openclaw sandbox recreate --agent <agent_id>`。
- 这里自动转换的是 **上传 Skill 使用的 `OPENCLAW_FILE_UPLOAD_GATEWAY_URL`**；`GATEWAY_URL` 本身仍保留原值，继续给管理脚本回调 `/admin/reload` 使用。

不要混淆这两件事：
- **入站文件处理**：`FILE_STORAGE_MODE=local` 时下发 `/app/shared/<agent_id>/...` 绝对路径；`FILE_STORAGE_MODE=s3` 时下发对象存储下载链接。
- **主动上传能力**：与 `local/s3` 无直接绑定；只要安装了 `gateway-file-upload` 且 `OPENCLAW_FILE_UPLOAD_*` 生效，Agent 就可以主动上传文件或文本。

快速对照：

| 组合 | 企微来件怎么交给 Agent | Agent 能否主动上传 |
|------|------------------------|--------------------|
| `local` + 无 skill | 本地绝对路径 | 否 |
| `local` + 有 skill | 本地绝对路径 | 是 |
| `s3` + 无 skill | S3 下载链接 | 否 |
| `s3` + 有 skill | S3 下载链接 | 是 |

### S3 模式

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `S3_BUCKET` | 空 | 目标桶 |
| `S3_ENDPOINT_URL` | 空 | 自建 S3/兼容服务地址 |
| `S3_ACCESS_KEY_ID` | 空 | 访问密钥 |
| `S3_SECRET_ACCESS_KEY` | 空 | 密钥 |
| `S3_REGION` | `us-east-1` | 区域 |
| `S3_SIGNATURE_VERSION` | `s3` | 签名版本 |
| `S3_ADDRESSING_STYLE` | `path` | 地址风格 |
| `S3_KEY_PREFIX` | `openclaw-gateway` | 兼容旧配置 |
| `S3_SSE_MODE` | 空 | 服务端加密模式 |
| `S3_SSE_KMS_KEY_ID` | 空 | KMS Key |

## Agent 管理

基础命令：

```bash
python3 scripts/manage-agent.py add [agent_id]
python3 scripts/manage-agent.py list
python3 scripts/manage-agent.py update <agent_id>
python3 scripts/manage-agent.py remove <agent_id>
python3 scripts/manage-agent.py sync-token [--url <openclaw_url>]
```

说明：
- `add` / `update` / `remove` 后会自动通知 Gateway 重载
- `sync-token` 用于批量同步 DB 中保存的 OpenClaw token
- 生产环境推荐使用 `/opt/openclaw/gateway/bin/04-manage-agent.sh`

## 手工部署 OpenClaw 时必须满足的约束

如果你不是通过 `bin/03-install-openclaw.sh` 部署 OpenClaw，而是手动安装、手动编辑 `~/.openclaw/openclaw.json`，请确保：

- `agent_id = Gateway 路由名 = SQLite agents.name`
- Gateway 对外下发的 local 文件路径固定为 `/app/shared/<agent_id>/...`
- 宿主机上的 `/app/shared/<agent_id>` 指向 `~/.openclaw/workspace-<agent_id>/shared`
- 若使用仓库自带上传 Skill，请将 `openclaw-skills/gateway-file-upload` 同步到 `~/.openclaw/workspace-<agent_id>/skills/gateway-file-upload`
- 非沙箱 Agent 若要使用上传 Skill，请把 `OPENCLAW_FILE_UPLOAD_*` 写入 `~/.openclaw/.env`，并在修改后重启 OpenClaw
- 沙箱 Agent 若要使用上传 Skill，请把同名变量写入该 agent 的 `sandbox.docker.env`，并在修改后重建沙箱容器
- 若启用沙箱，bind source 必须位于 workspace 内，例如：

```json
[
  "/home/ubuntu/.openclaw/workspace-dev/shared:/app/shared/dev:rw"
]
```

- `/app/shared` 需提前创建并放权，`02` 脚本默认会创建并设置为 `775`

## 生产环境运维

### systemd

```bash
sudo systemctl start openclaw-gateway
sudo systemctl stop openclaw-gateway
sudo systemctl restart openclaw-gateway
sudo systemctl status openclaw-gateway
sudo journalctl -u openclaw-gateway -f
```

### 运维脚本

部署后可使用：

```bash
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh start
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh stop
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh restart
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh status
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh logs
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh health
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh agents
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh stats
```

管理 Agent 时同样建议用普通用户执行：

```bash
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh add-agent team-dev
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh list-agents
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh update-agent team-dev
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh remove-agent team-dev
```

### 升级 Gateway

```bash
cd ~/openclaw-deploy
git pull
sudo bash bin/02-install-gateway.sh
```

`02` 会重新同步仓库代码到 `/opt/openclaw/gateway` 并重启服务；仅执行 `systemctl restart` 不会同步新代码。

### 清理

```bash
sudo bash bin/05-cleanup.sh
```

## API

| 方法 | 路径 | 说明 |
|------|------|------|
| `GET/POST` | `/{agent_name}/wecom/callback` | 企业微信回调 |
| `GET/POST` | `/wecom/callback` | 兼容旧路径 |
| `GET` | `/health` | 健康检查 |
| `GET` | `/stats` | 统计信息 |
| `GET` | `/admin/agents` | 当前 Agent 绑定 |
| `POST` | `/admin/reload` | 重载 Agent 配置 |
| `POST` | `/internal/files/upload` | 内部上传接口（上传 Skill 用） |

## 消息处理流程

```text
企业微信
  -> /{agent_name}/wecom/callback
  -> SQLite 查询 agent 配置
  -> 按 agent 的 Token / AESKey 解密验签
  -> 组装 session_key = wecom:{agent_name}:{user_id}
  -> 调用目标 OpenClaw（ws / sse / http）
  -> 收到回复
  -> 回发企业微信
```

## 项目结构

```text
openclaw-deploy/
├── bin/
│   ├── 01-upload.sh
│   ├── 02-install-gateway.sh
│   ├── 03-install-openclaw.sh
│   ├── 04-manage-agent.sh
│   ├── 05-cleanup.sh
│   └── openclaw-sandbox-devtools.Dockerfile
├── scripts/
│   ├── gateway-ctl.sh
│   ├── manage-agent.py
│   └── openclaw-gateway.service
├── src/gateway/
│   ├── requirements.txt
│   └── wecom_gateway.py
├── .env.example
├── README.md
└── USER-GUIDE.md
```

## 数据库

### `agents`

| 字段 | 说明 |
|------|------|
| `name` | 路由名 / agent_id 主键 |
| `display_name` | 显示名 |
| `wecom_token` | 企业微信 Token |
| `wecom_aes_key` | 企业微信 EncodingAESKey |
| `openclaw_url` | OpenClaw 地址 |
| `openclaw_token` | OpenClaw token |
| `openclaw_agent_id` | 与 `name` 保持一致 |
| `shared_dir` | 固定为 `/app/shared/<agent_id>` |
| `created_at` | 创建时间 |
| `updated_at` | 更新时间 |

### `task_logs`

| 字段 | 说明 |
|------|------|
| `task_id` | 任务 ID |
| `user_id` | 企业微信用户 |
| `agent_id` | Agent ID |
| `task_content` | 消息内容 |
| `status` | 状态 |
| `result` | 结果 |
| `created_at` | 创建时间 |
| `updated_at` | 更新时间 |

## 注意事项

- 不要提交 `.env`、`*.db`、运行时日志
- Gateway 启动成功但没有 Agent 时，不会处理消息
- `/app/shared` 由 `02` 脚本创建并赋予 `775`
- 新装系统如果遗留错误的 `REQUESTS_CA_BUNDLE` / `SSL_CERT_FILE`，Gateway 启动时会自动忽略无效证书路径
