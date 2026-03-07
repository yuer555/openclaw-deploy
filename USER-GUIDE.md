# OpenClaw 企业微信桥接网关 - 用户指南

> 从零开始，10 分钟部署完成 🚀

---

## 快速部署流程

| 步骤 | 脚本 | 执行位置 | 说明 |
|------|------|---------|------|
| 1. 上传代码 | `bin/01-upload.sh` | 本地 | 打包项目文件并上传到服务器 |
| 2. 安装 Gateway | `sudo bash bin/02-install-gateway.sh` | 服务器 | 安装 Python 依赖、配置 systemd 服务 |
| 3. 安装 OpenClaw | `bash bin/03-install-openclaw.sh` | 服务器 | 安装 OpenClaw、配置模型和 Agent |
| 4. 添加 Agent 绑定 | `bin/04-manage-agent.sh add [agent_id]` | 服务器 | 绑定企业微信机器人到 OpenClaw Agent，`agent_id` 同时作为路由名 |
| 5. 清理环境 | `sudo bash bin/05-cleanup.sh` | 服务器 | 卸载服务 / 清空 OpenClaw / 全部重置 |

> 权限规则：`02`、`05` 需要 `sudo`；`03`、`04` 必须使用**普通用户**运行，不能用 `sudo`、不能用 `root`。

---

## 📋 目录

1. [快速开始](#1-快速开始)
2. [环境准备](#2-环境准备)
3. [安装部署](#3-安装部署)
4. [配置企业微信](#4-配置企业微信)
5. [添加 Agent](#5-添加-agent)
6. [测试验证](#6-测试验证)
7. [日常使用](#7-日常使用)
8. [常见问题](#8-常见问题)
9. [进阶配置](#9-进阶配置)

---

## 1. 快速开始

### 1.1 这是什么？

**OpenClaw 企业微信桥接网关** 是一个让你的企业微信机器人能够使用 OpenClaw AI 助手的桥梁。

```
你在企业微信发消息 → 企业微信机器人 → 网关 → OpenClaw AI → 回复你
```

### 1.2 你需要什么？

- ✅ 一台 Linux 服务器（CentOS/Ubuntu）或 macOS
- ✅ OpenClaw 已安装并运行（未安装？用 `bash bin/03-install-openclaw.sh` 一键搞定，需要 Node.js 22+）
- ✅ 企业微信管理员权限（能创建机器人应用）
- ✅ 基本的命令行操作能力（会复制粘贴命令即可）

### 1.3 需要多长时间？

- ⏱️ **首次部署**: 10-15 分钟
- ⏱️ **添加新机器人**: 2-3 分钟
- ⏱️ **日常维护**: 几乎为零

---

## 2. 环境准备

### 2.1 安装配置 OpenClaw（如尚未安装）

如果服务器上还没有安装 OpenClaw，可以使用项目提供的一键安装脚本：

```bash
cd ~/openclaw-deploy

# 一键安装 OpenClaw + 配置模型 + 创建 Agent + 编辑人格设定
bash bin/03-install-openclaw.sh
```

**快捷模式**（已安装 OpenClaw 的情况下）：

```bash
# 跳过安装，只做配置（OpenClaw 已安装）
bash bin/03-install-openclaw.sh --skip-install

# 只添加新 Agent
bash bin/03-install-openclaw.sh --add-agent

# 只添加模型提供商
bash bin/03-install-openclaw.sh --add-provider
```

---

### 2.1.1 第一步：检查环境 & 安装 OpenClaw

脚本会自动检测 Node.js (22+)、npm；Docker 仅在你创建沙箱 Agent 时才需要。
如果本机残留过历史 OpenClaw 沙箱容器，脚本在首次初始化和“清理重装”前都会先执行一次沙箱清理。

#### 场景 A：OpenClaw 未安装

```
选择安装方式:
  1) npm install -g openclaw@latest (推荐)
  2) curl -fsSL https://openclaw.ai/install.sh | bash

请输入选项 [1-2, 默认 2]: _
```

| 选项 | 说明 |
|------|------|
| **1** | 通过 npm 全局安装，需要 Node.js 22+。如果无全局写权限会自动提示 sudo |
| **2** | 官方安装脚本，自动处理依赖和 PATH 配置（**推荐新手使用**） |

安装完成后会自动运行 OpenClaw 初始化向导：若当前环境支持托管服务，则使用 `openclaw onboard --install-daemon`；若检测到 `systemctl --user` 不可用等情况，则自动改为跳过 daemon 安装的兼容模式（见 [2.1.6](#216-openclaw-onboard-初始化向导)）。

#### 场景 B：OpenClaw 已安装

```
✓ OpenClaw 已安装 (v2026.3.1)

是否清理当前安装并重新配置? [y/N]: _
```

| 选项 | 说明 |
|------|------|
| **N（默认）** | 保留现有配置，直接进入下一步 |
| **y** | 删除 `~/.openclaw` 目录并重新运行初始化向导。**会清除所有 Agent、模型配置、workspace** |

---

### 2.1.2 第二步：配置模型提供商

```
→ 当前已配置的模型:
  gmn/gpt-5.3-codex  (默认)
  ...

是否需要添加或修改模型提供商? (直接回车默认 No) [y/N]: _
```

输入 `y` 后进入配置循环：

```
请选择提供商类型:
  1) 官方 API 提供商 (Anthropic, OpenAI, DeepSeek 等)
  2) 第三方流量池 (如 GMN)
  3) 完成，继续下一步

请输入选项 [1-3]: _
```

#### 选项 1：官方 API 提供商

显示内置提供商列表：

```
官方提供商列表:
  1) Anthropic (Claude) (anthropic)
  2) OpenAI (GPT) (openai)
  3) DeepSeek (deepseek)
  4) Groq (groq)
  5) Together AI (together)
  6) Fireworks AI (fireworks)
  7) OpenRouter (openrouter)
  8) xAI (Grok) (xai)
  9) MiniMax (minimax)
  10) Moonshot AI (moonshot)

请输入选项 [1-10]: _
```

选择后输入该提供商的 API Key：

```
请输入 Anthropic (Claude) API Key (输入时会显示): sk-ant-xxxxx
```

通过 `openclaw models auth set` 命令自动配置认证。

#### 选项 2：第三方流量池（自定义提供商）

依次填写以下信息：

```
提供商 ID (英文, 如 gmn): gmn
API Base URL (如 https://gmn.chuangzuoli.com/v1): https://gmn.chuangzuoli.com/v1
API Key (输入时会显示): sk-xxxxx

API 协议格式:
  1) OpenAI 兼容 (openai-responses) — GPT、DeepSeek、国产大模型等
  2) Anthropic 兼容 (anthropic-messages) — Claude 系列
  3) 其他 (跳过自动配置，需手动编辑 openclaw.json)

请选择 [1-3, 默认 1]: _
```

| 选项 | 说明 | 自动配置 |
|------|------|---------|
| **1（默认）** | OpenAI 兼容协议，适用于 GPT、DeepSeek、通义千问、GLM 等 | `auth: api-key`, `authHeader: true`, 标准 headers |
| **2** | Anthropic 原生协议，适用于 Claude 系列模型 | `auth: api-key`，openclaw 自动处理 `x-api-key` 头 |
| **3** | 非标准协议，脚本只写入 baseUrl 和 apiKey | 需手动编辑 `~/.openclaw/openclaw.json` 补充 |

选择协议后，循环添加模型：

```
模型 ID (留空结束添加): gpt-5.3-codex
模型显示名称 (直接回车使用模型ID: gpt-5.3-codex): GPT-5.3 Codex
上下文窗口大小 (直接回车默认 200000 tokens): 400000
最大输出 Token (直接回车默认 128000 tokens): 128000
是否支持推理 (reasoning)? (直接回车默认 Yes) [Y/n]: Y

✓ 已添加模型: gmn/gpt-5.3-codex

模型 ID (留空结束添加): _    ← 直接回车结束
```

- 如果只添加了 1 个模型，自动设为默认模型
- 如果添加了多个模型，会询问是否修改默认模型

---

### 2.1.3 第三步：创建和配置 Agent

```
→ 当前已配置的 Agent:
  - main
  ...

是否编辑主 Agent (main) 的人格设定? (直接回车默认 Yes) [Y/n]: _
```

#### 编辑人格设定

选择 `Y` 后会用 `$EDITOR`（默认 nano）依次打开 5 个文件：

| 文件 | 说明 | 编辑建议 |
|------|------|---------|
| `IDENTITY.md` | 身份定义 — 名字、物种、性格、Emoji | 给 Agent 一个名字和人设 |
| `SOUL.md` | 灵魂设定 — 核心人格、行为准则 | 定义工作风格和角色定位 |
| `USER.md` | 用户信息 — 关于你的基本信息 | 告诉 Agent 你是谁、你的偏好 |
| `TOOLS.md` | 工具配置 — 环境相关信息 | 描述服务器环境、可用工具 |
| `AGENTS.md` | 工作空间规则 — 流程和安全规则 | 设置 Session 流程、记忆管理 |

每个文件编辑前会提示：

```
编辑 IDENTITY.md — 身份定义 — 名字、物种、性格、Emoji
文件路径: /home/ubuntu/.openclaw/workspace/IDENTITY.md

是否打开编辑器编辑此文件? [Y/n]: _
```

不想编辑的文件直接输入 `n` 跳过。

#### 创建额外 Agent

```
是否创建新的 Agent? (直接回车默认 Yes) [Y/n]: y

Agent ID (英文标识, 如 development, testing, service): development
显示名称 (直接回车使用 Agent ID: development): 开发助手
说明: 仅启用沙箱时才需要 Docker 和专用沙箱镜像；非沙箱 Agent 无需 Docker。
是否启用 Docker 沙箱? (直接回车默认 Yes) [Y/n]: _
```

| 选项 | 说明 |
|------|------|
| **Agent ID** | 英文标识符，用于 API 调用和配置引用 |
| **显示名称** | 日志和统计中展示的名称，可以是中文 |
| **Docker 沙箱** | 启用后 Agent 在 Docker 容器内执行代码。仅沙箱 Agent 需要 Docker |

如果你选择启用沙箱，脚本会检查 Docker 和专用沙箱镜像是否已准备好：
- 已准备好：继续创建 Agent。
- 未准备好：在第一步和实际启用沙箱时都会提示你是否查看安装 Docker、配置镜像加速、构建沙箱镜像的命令；如果你选择查看，脚本会先退出，等你准备完成后再重新运行。

沙箱准备命令（仅沙箱 Agent 需要，脚本会按当前系统提示对应命令）：

```bash
# 1) 安装 Docker（Ubuntu / Debian）
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg \
  | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
  $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

```bash
# 1) 安装 Docker（RHEL / Rocky / AlmaLinux / CentOS）
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo \
  https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker
```

```bash
# 2) 配置镜像加速（各系统通用，腾讯云机器优先）
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'JSON'
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://hub-mirror.c.163.com",
    "https://mirror.baidubce.com"
  ]
}
JSON
sudo systemctl daemon-reload
sudo systemctl restart docker
docker info | sed -n '/Registry Mirrors/,$p'
```

```bash
# 3) 构建专用沙箱镜像
docker build \
  --build-arg OPENCLAW_SANDBOX_BASE_IMAGE=debian:bookworm-slim \
  -t openclaw-sandbox:gateway-devtools-bookworm \
  -f bin/openclaw-sandbox-devtools.Dockerfile \
  .
docker image inspect openclaw-sandbox:gateway-devtools-bookworm
```

启用沙箱后自动写入以下配置：

```json
{
  "id": "development",
  "name": "development",
  "workspace": "~/.openclaw/workspace-development",
  "agentDir": "~/.openclaw/agents/development/agent",
  "identity": {
    "name": "development"
  },
  "sandbox": {
    "mode": "all",
    "workspaceAccess": "rw",
    "scope": "agent",
    "docker": {
      "image": "openclaw-sandbox:gateway-devtools-bookworm",
      "network": "bridge",
      "readOnlyRoot": false,
      "binds": [
        "/home/ubuntu/.openclaw/workspace-development/shared:/app/shared/development:rw"
      ],
      "env": {
        "OPENCLAW_FILE_UPLOAD_GATEWAY_URL": "http://your-gateway:8000",
        "OPENCLAW_FILE_UPLOAD_TOKEN": "***",
        "OPENCLAW_FILE_UPLOAD_EXPIRES": "86400"
      }
    }
  },
  "tools": {
    "allow": [
      "group:fs",
      "group:runtime",
      "group:memory",
      "group:sessions"
    ],
    "deny": [
      "apply_patch"
    ]
  }
}
```

说明：
- 这里的 `sandbox.docker.env` 只针对**沙箱 Agent**。
- 非沙箱 Agent 不走这里，改为从宿主机 `~/.openclaw/.env` 读取 `OPENCLAW_FILE_UPLOAD_*`；修改后需要重启 OpenClaw。

| 字段 | 值 | 说明 |
|------|-----|------|
| `image` | `openclaw-sandbox:gateway-devtools-bookworm` | 需提前准备好的专用沙箱镜像；脚本仅检查，不自动构建 |
| `network` | `bridge` | 容器需要联网（API 调用等） |
| `readOnlyRoot` | `false` | 容器根文件系统可写 |
| `binds` | `~/.openclaw/workspace-<agent_id>/shared:/app/shared/<agent_id>:rw` | 显式挂载 workspace 内共享目录到 agent 固定对外路径 |
| `tools.allow` | `group:fs/group:runtime/group:memory/group:sessions` | Agent 允许的工具分组 |
| `tools.deny` | `apply_patch` | 禁止危险补丁工具 |

Gateway 对外下发的共享文件路径固定为 `/app/shared/<agent_id>`；宿主机上该路径通过软链指向 `~/.openclaw/workspace-<agent_id>/shared`。

> 说明：不要依赖 `setupCommand` 在沙箱启动时执行 `apt-get`。OpenClaw 默认会把沙箱用户映射成 workspace 对应的普通用户，运行时临时安装系统包很容易触发权限错误。需要的系统工具请直接预装到 `bin/openclaw-sandbox-devtools.Dockerfile`。

创建完成后同样会询问是否编辑人格设定。子 Agent 的模型配置（`auth-profiles.json`、`models.json`）会自动从主 Agent 同步。

---

### 2.1.4 第四步：Gateway 集成信息

脚本自动读取 OpenClaw 配置并输出连接信息：

```
企业微信 Gateway 连接 OpenClaw 所需信息:
  Gateway URL: http://localhost:18789
  Gateway Token: 1e443bcba0ed1327...

在 04-manage-agent.sh add 时使用以上信息配置每个 Agent 的 Gateway 地址和 Gateway Token。
新规则下 `agent_id` 同时作为：
- OpenClaw agent_id
- Gateway 路由名
- SQLite `agents.name`
- Agent 对外共享路径 `/app/shared/<agent_id>`
```

**记下这两个值**，后面添加企微 Agent 绑定时需要。

---

### 2.1.5 第五步：最终检查

脚本自动执行：
- 列出所有已配置的 Agent
- OpenClaw 健康检查
- 同步 Gateway token 配置
- 安装/刷新每个 Agent workspace 下的文件上传 Skill
- 校验共享目录契约和 token 健康状态

```
╔══════════════════════════════════════╗
║    OpenClaw 配置完成!                ║
╚══════════════════════════════════════╝

后续操作:
  1. 启动 OpenClaw:       openclaw gateway start
  2. 部署企微 Gateway:    sudo bash bin/02-install-gateway.sh
  3. 添加企微 Agent 绑定: /opt/openclaw/gateway/bin/04-manage-agent.sh add [agent_id]
  4. 查看 Agent 列表:     /opt/openclaw/gateway/bin/04-manage-agent.sh list
  5. 查看 OpenClaw 面板:  openclaw dashboard
```

---

### 2.1.6 OpenClaw onboard 初始化向导

首次安装 OpenClaw 或选择"清理重新配置"时，脚本会自动运行 OpenClaw 官方的交互式初始化向导；若当前环境支持托管服务则安装 daemon，否则自动跳过 daemon 安装以避免 `systemctl --user` 类报错。向导主要完成以下配置：

#### 步骤 1：选择运行模式

```
How would you like to run OpenClaw?

  1) Local mode   — runs on this machine only (default)
  2) Network mode — accessible from other machines

Select [1-2]: _
```

| 选项 | 说明 |
|------|------|
| **1 Local（默认）** | Gateway 仅监听 `127.0.0.1:18789`，只有本机能访问 |
| **2 Network** | Gateway 监听 `0.0.0.0:18789`，其他机器可通过 IP 访问。**如果企微 Gateway 和 OpenClaw 不在同一台机器上，选这个** |

#### 步骤 2：配置认证

```
Gateway authentication:

  1) Token auth  — use a shared secret token (recommended)
  2) No auth     — no authentication required

Select [1-2]: _
```

| 选项 | 说明 |
|------|------|
| **1 Token（推荐）** | 自动生成一个随机 Token，所有 API 请求需携带此 Token。**生产环境必选** |
| **2 No auth** | 无认证，仅适合本地开发测试 |

选择 Token auth 后会自动生成 Token 并显示，**务必记录下来**。

#### 步骤 3：配置模型

```
Set up your first AI model provider:

  1) Anthropic (Claude)
  2) OpenAI (ChatGPT)
  3) Skip for now

Select [1-3]: _
```

选择提供商后输入 API Key。也可以选 3 跳过，后续通过 `bin/03-install-openclaw.sh --add-provider` 添加。

#### 步骤 4：安装 Daemon

若当前环境支持托管服务，向导会自动注册系统服务（Linux 下为 systemd，macOS 下为 launchd），使 OpenClaw Gateway 开机自启；若当前环境不支持，则脚本会跳过此步骤，并提示使用 `openclaw gateway run` 兼容启动。

#### 完成

```
OpenClaw is ready!

  Gateway: http://127.0.0.1:18789
  Token:   1e443bcba0ed1327699b31cdee8f6150e97226386c375f75

  Run `openclaw health` to verify.
```

**重要**：记下 Gateway 地址和 Token，后续配置企微 Gateway 时需要。

---

### 2.2 检查 OpenClaw 是否运行

**如果 OpenClaw 已经安装**，在服务器上执行：

```bash
# 方法 1: 检查进程
ps aux | grep openclaw

# 方法 2: 检查端口
curl http://localhost:18789/health

# 方法 3: 查看配置
cat ~/.openclaw/openclaw.json | grep -A 5 gateway
```

**预期结果**：
```json
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "你的长串token"
    }
  }
}
```

⚠️ **记下这两个值，后面要用**：
- **Gateway 地址（OpenClaw 服务地址）**: `http://localhost:18789` （或服务器 IP）
- **Gateway Token（OpenClaw token）**: `你的长串token`

---

### 2.2.1 如果你是自行部署 OpenClaw（不使用 `03` 脚本）

当前代码对 `agent_id`、路由名和本地共享目录采用**强绑定设计**。如果你是手工安装 OpenClaw、手工编辑 `~/.openclaw/openclaw.json`，请务必满足以下约束，否则 `local` 文件模式下 Agent 会拿不到正确路径。

#### 强绑定规则

1. **`agent_id` = Gateway 路由名 = SQLite `agents.name`**
   - 例如你在 `04-manage-agent.sh` 里添加的是 `team-dev`
   - 那么 OpenClaw 里的 agent 也必须叫 `team-dev`
   - 企业微信回调地址就是 `https://your-domain/team-dev/wecom/callback`

2. **Gateway 对外共享路径固定为 `/app/shared/<agent_id>`**
   - 例如 `team-dev` 对应 `/app/shared/team-dev`
   - 宿主机上这个路径应软链到真实目录：`~/.openclaw/workspace-team-dev/shared`
   - Gateway 在 `FILE_STORAGE_MODE=local` 时，会把文件路径直接下发为这个绝对路径下的文件

3. **沙箱 Agent 必须使用“workspace 内 source + 固定 target”绑定**
   - 推荐 `scope: "agent"`
   - `binds` 必须包含：
     ```json
     ["~/.openclaw/workspace-team-dev/shared:/app/shared/team-dev:rw"]
     ```
   - 这样 bind source 位于 allowed roots 内，容器里仍统一看到 `/app/shared/team-dev`

4. **非沙箱 Agent 不需要额外 bind**
   - 因为 Agent 直接运行在宿主机
   - 只要 OpenClaw 进程本身有权限访问 `/app/shared/<agent_id>`（软链路径）即可

5. **上传 Skill 是另一条线**
   - `FILE_STORAGE_MODE=local|s3` 只决定“企业微信发来的文件”怎么交给 Agent
   - `gateway-file-upload` skill + `OPENCLAW_FILE_UPLOAD_*` 决定“Agent 能不能主动上传自己的产物”
   - 非沙箱 Agent：把 `OPENCLAW_FILE_UPLOAD_*` 写入 `~/.openclaw/.env`，并在修改后重启 OpenClaw
   - 沙箱 Agent：把 `OPENCLAW_FILE_UPLOAD_*` 写入对应 agent 的 `sandbox.docker.env`，并在修改后重建沙箱容器

6. **`/app/shared` 必须提前创建并放权**
   - 至少保证 Gateway 和 OpenClaw 运行用户可读写
   - 推荐：
     ```bash
     sudo mkdir -p /app/shared
     sudo chown <运行用户>:<运行组> /app/shared
     sudo chmod 775 /app/shared
     ```

#### 手工配置最小示例

假设你的 agent 是 `team-dev`，且启用了 Docker 沙箱：

```json
{
  "id": "team-dev",
  "name": "team-dev",
  "workspace": "/home/ubuntu/.openclaw/workspace-team-dev",
  "agentDir": "/home/ubuntu/.openclaw/agents/team-dev/agent",
  "sandbox": {
    "mode": "all",
    "workspaceAccess": "rw",
    "scope": "agent",
    "docker": {
      "image": "openclaw-sandbox:gateway-devtools-bookworm",
      "binds": [
        "/home/ubuntu/.openclaw/workspace-team-dev/shared:/app/shared/team-dev:rw"
      ]
    }
  }
}
```

然后再执行：

```bash
mkdir -p ~/.openclaw/workspace-team-dev/shared
sudo mkdir -p /app/shared
sudo ln -s ~/.openclaw/workspace-team-dev/shared /app/shared/team-dev
/opt/openclaw/gateway/bin/04-manage-agent.sh add team-dev
```

#### 什么时候必须重新建沙箱容器？

- 你修改了 `sandbox.docker.binds`
- 你删除或修改了旧版 `sandbox.docker.setupCommand`
- 你切换了 `FILE_STORAGE_MODE`
- 你给 Agent 新增了上传 Skill 相关环境变量

这几种情况都建议执行：

```bash
openclaw sandbox recreate --agent <agent_id>
```

> 注意：如果你把 sandbox `scope` 改成 `shared`，每个 Agent 的自定义 bind 可能不会按预期生效。当前项目文档和脚本都按 `scope: "agent"` 设计。
>
> 旧版本如果已经把 `setupCommand: "apt-get ..."` 写进了 `~/.openclaw/openclaw.json`，建议重新运行一次 `bash bin/03-install-openclaw.sh --skip-install` 同步配置，然后执行上面的 `recreate`。

---

### 2.3 安装 Python 和依赖

**检查 Python 版本**：
```bash
python3 --version
# 需要 Python 3.8 或更高版本
```

**如果没有 Python 3.8+，安装它**：

<details>
<summary>Ubuntu/Debian 系统</summary>

```bash
sudo apt update
sudo apt install -y python3 python3-pip
```
</details>

<details>
<summary>CentOS/RHEL 系统</summary>

```bash
sudo yum install -y python3 python3-pip
```
</details>

---

### 2.4 获取代码

```bash
# 进入你想要存放代码的目录
cd ~

# 克隆仓库（假设已经克隆，否则需要 git clone）
cd ~/openclaw-deploy

# 或者如果还没有代码，从 Git 克隆
# git clone <仓库地址> openclaw-deploy
# cd openclaw-deploy
```

---

## 3. 安装部署

### 3.1 一键安装（生产环境）

**强烈推荐**：适合正式使用

```bash
cd ~/openclaw-deploy
sudo bash bin/02-install-gateway.sh
```

**安装过程**：
1. ✅ 安装 Python 依赖
2. ✅ 创建数据目录 `/opt/openclaw/data/gateway`
3. ✅ 配置 systemd 服务（开机自启）
4. ✅ 启动 Gateway 服务

**验证安装**：
```bash
# 检查服务状态
sudo systemctl status openclaw-gateway

# 应该看到 "Active: active (running)" 字样
```

**查看日志**：
```bash
# 实时查看日志
sudo journalctl -u openclaw-gateway -f

# 查看最近 50 行
sudo journalctl -u openclaw-gateway -n 50
```

---

### 3.2 开发环境（本地测试）

**仅用于开发和测试**：

```bash
# 安装依赖
pip3 install -r src/gateway/requirements.txt

# 复制环境变量模板
cp .env.example .env

# 编辑配置（可选）
nano .env

# 启动 Gateway（前台运行）
python3 src/gateway/wecom_gateway.py
```

**停止**：按 `Ctrl+C`

---

### 3.3 验证安装成功

**检查健康状态**：

```bash
curl http://localhost:8000/health
```

**预期输出**：
```json
{
  "status": "ok",
  "service": "openclaw-wecom-gateway",
  "agents": 0,
  "agent_names": [],
  "timestamp": 1234567890
}
```

✅ 看到 `"status": "ok"` 就说明安装成功！

⚠️ 注意 `"agents": 0` 是正常的，因为还没添加 agent

---

## 4. 配置企业微信

### 4.1 创建企业微信机器人应用

1. **登录企业微信管理后台**：https://work.weixin.qq.com/
2. **进入"应用管理"**
3. **点击"创建应用"** → 选择 **"自建应用"**
4. **填写信息**：
   - 应用名称：`OpenClaw AI 助手`
   - 应用介绍：`智能 AI 编程助手`
   - 可见范围：选择需要使用的员工

5. **创建成功后，进入应用详情页**

---

### 4.2 获取企业微信配置信息

**在应用详情页找到以下信息**：

#### 📝 需要记录的 3 个值：

1. **AgentId** (应用 ID)
   - 位置：应用详情页顶部
   - 示例：`1000002`

2. **Secret** (应用密钥)
   - 位置：应用详情页 → "开发者接口" → "Secret"
   - 示例：`abc123def456...`（点击"查看"）

3. **Token** 和 **EncodingAESKey**（消息加密配置）
   - 位置：应用详情页 → "接收消息" → "设置API接收"
   - **第一次配置时，这里还是空的，需要先生成**

---

### 4.3 生成 Token 和 EncodingAESKey

**在"接收消息"配置页面**：

1. **点击"随机生成 Token"** → 复制保存
   - 示例：`32c4407bae780aeb92b0d7f504dc26c1`

2. **点击"随机生成 EncodingAESKey"** → 复制保存
   - 示例：`f7cTZKs4PQ1E0cLHrHArKpSoHYUzxUNE8mKTIauIkZA`

⚠️ **先不要点"保存"！** 继续下一步

---

### 4.4 配置回调 URL

**URL 格式**：
```
https://你的域名/{agent_id}/wecom/callback
```

**示例**：
```
https://ai.yourcompany.com/team-dev/wecom/callback
```

**填写步骤**：

1. **URL 填入** 上面的地址（`{agent_id}` 替换为你在 `04` 中填写的 Agent ID，如 `team-dev`）
2. **Token** 填入刚才生成的 Token
3. **EncodingAESKey** 填入刚才生成的 EncodingAESKey
4. **点击"保存"**

⚠️ **此时会验证 URL 可达性，必须先完成下一步（添加 Agent）才能保存成功！**

---

## 5. 添加 Agent

### 5.1 什么是 Agent？

**Agent** 是 Gateway 和企业微信机器人的绑定关系，包含：
- 企业微信机器人的加密配置（Token/AESKey）
- 对应的 OpenClaw 服务地址和 Token
- 绑定到哪个 OpenClaw Agent
- 本地文件共享目录

**一个 Agent 对应一个企业微信机器人**。

#### 当前版本的重要规则

从当前版本开始，新增/更新绑定时使用**强绑定规则**：

- `agent_id` = Gateway 路由名
- `agent_id` = OpenClaw agent_id
- `shared_dir` 固定为 `/app/shared/<agent_id>`（宿主机上通常是指向 workspace `shared` 的软链）

也就是说，**不再推荐**“企微路由名是 `team-dev`，但 OpenClaw Agent ID 写 `main`”这种拆分配置。旧数据仍有兼容逻辑，但新配置请保持同名。

---

### 5.2 交互式添加（推荐）

```bash
# 生产环境（systemd 服务）
/opt/openclaw/gateway/bin/04-manage-agent.sh add team-dev

# 开发环境
python3 scripts/manage-agent.py add team-dev
```

> 注意：`04` 和 `manage-agent.py` 都必须用**普通用户**执行，不要加 `sudo`。

**按照提示输入**：

```
Gateway 地址（回车使用默认 http://localhost:18789）: http://localhost:18789

Agent ID（路由名，同 OpenClaw agent_id）: team-dev

共享文件目录（自动生成，不可修改）: /app/shared/team-dev

Gateway Token（从 ~/.openclaw/openclaw.json 或 ~/.openclaw/.env 获取）: 1e443bcba0ed1327699b31cdee8f6150e97226386c375f75

企业微信 Token（随机生成的 32 位字符串）: 32c4407bae780aeb92b0d7f504dc26c1

企业微信 EncodingAESKey（随机生成的 43 位字符串）: f7cTZKs4PQ1E0cLHrHArKpSoHYUzxUNE8mKTIauIkZA

显示名（回车使用 team-dev）: 研发团队 AI 助手

已添加 agent 'team-dev'
企业微信回调地址: https://your-domain/team-dev/wecom/callback
```

> 如果 `04` 提示无法创建 `/app/shared/team-dev`，请先检查 `/app/shared` 是否已由 `02` 脚本创建，或手动按 [2.2.1](#221-如果你是自行部署-openclaw不使用-03-脚本) 放权。

---

### 5.3 验证 Agent 添加成功

```bash
# 查看所有 Agent
/opt/openclaw/gateway/bin/04-manage-agent.sh list

# 或开发环境
python3 scripts/manage-agent.py list
```

**预期现象**：列表中能看到 `team-dev` 这一行，并且共享目录为 `/app/shared/team-dev`。

**检查 Gateway API**：
```bash
curl http://localhost:8000/admin/agents
```

**预期输出**：
```json
{
  "agents": {
    "team-dev": {
      "display_name": "研发团队 AI 助手",
      "openclaw_url": "http://localhost:18789",
      "openclaw_agent_id": "team-dev"
    }
  }
}
```

✅ 看到你的 agent 信息就成功了！

---

### 5.4 回到企业微信完成配置

**现在可以回到企业微信管理后台了**：

1. **刷新"接收消息"配置页**
2. **再次填写 URL、Token、EncodingAESKey**（和之前一样）
3. **点击"保存"**

✅ **如果看到"验证成功"** → 恭喜，配置完成！

❌ **如果提示"URL 验证失败"** → 检查：
- Gateway 服务是否正常运行
- 域名是否解析正确
- 防火墙是否开放 8000 端口
- Nginx 是否正确转发（如果使用了 Nginx）

---

## 6. 测试验证

### 6.1 在企业微信发送测试消息

1. **打开企业微信移动端或桌面端**
2. **进入"工作台" → 找到你创建的应用**（如 "OpenClaw AI 助手"）
3. **点击进入**
4. **发送消息**：`你好`

**预期结果**：
- ⏳ 几秒后收到回复（可能是 "收到你的消息：你好" 或 AI 的实际回复）
- ✅ 如果收到回复，说明完全成功！

---

### 6.2 查看 Gateway 日志

**实时查看**：
```bash
# 生产环境
sudo journalctl -u openclaw-gateway -f

# 开发环境
tail -f data/gateway.log
```

**正常日志示例**：
```
2026-03-02 10:30:15 - INFO - [team-dev] 收到 POST 请求
2026-03-02 10:30:15 - INFO - [team-dev] 消息签名验证成功
2026-03-02 10:30:15 - INFO - [team-dev] 解密消息: {"msgtype":"text","from":{"userid":"zhangsan"},...}
2026-03-02 10:30:15 - INFO - [team-dev] 调用 OpenClaw: ws://localhost:18789/ws
2026-03-02 10:30:20 - INFO - [team-dev] 收到 OpenClaw 回复，发送到企业微信
```

---

### 6.3 检查数据库记录

```bash
# 生产环境
sqlite3 /opt/openclaw/data/gateway/gateway.db "SELECT * FROM task_logs ORDER BY created_at DESC LIMIT 5;"

# 开发环境
sqlite3 ./data/gateway.db "SELECT * FROM task_logs ORDER BY created_at DESC LIMIT 5;"
```

**预期输出**：
```
task_id_123|zhangsan|team-dev|你好|success|收到你的消息...|2026-03-02 10:30:15|2026-03-02 10:30:20
```

✅ 看到记录就说明消息已经被处理！

---

## 7. 日常使用

### 7.1 多个机器人（多 Agent）

**场景**：不同部门使用不同的机器人

```bash
# 添加第二个 agent（运维团队）
/opt/openclaw/gateway/bin/04-manage-agent.sh add team-ops

# 添加第三个 agent（产品团队）
/opt/openclaw/gateway/bin/04-manage-agent.sh add team-product
```

**每个 agent 对应一个企业微信机器人应用**，配置步骤和上面完全一样。

**URL 示例**：
- 研发团队：`https://ai.yourcompany.com/team-dev/wecom/callback`
- 运维团队：`https://ai.yourcompany.com/team-ops/wecom/callback`
- 产品团队：`https://ai.yourcompany.com/team-product/wecom/callback`

---

### 7.2 使用不同的 OpenClaw Agent

**场景**：想让机器人使用不同的 OpenClaw Agent

**步骤 1：在 OpenClaw 中创建 Agent**

参考 OpenClaw 文档创建新 agent，假设名为 `team-work`。

**步骤 2：添加 Gateway Agent 时指定**

```bash
/opt/openclaw/gateway/bin/04-manage-agent.sh add team-work
```

当前版本中，`04` 会把 `team-work` 同时写成：
- Gateway 路由名
- OpenClaw Agent ID
- 本地共享目录 `/app/shared/team-work`

因此这里**不再单独输入另一个 OpenClaw Agent ID**。如果你想让企微机器人走某个特定 Agent，请直接在 OpenClaw 里创建同名 Agent。

---

### 7.3 修改现有 Agent

```bash
# 更新 agent 配置
/opt/openclaw/gateway/bin/04-manage-agent.sh update team-dev
```

**按提示修改**（不想改的直接回车保持原值）：
```
当前显示名: 研发团队 AI 助手
新显示名（回车保持不变）: [直接回车保持不变]

当前 Gateway 地址: http://localhost:18789
新 Gateway 地址（回车保持不变）: http://new-server:18789  ← 修改了

... 其他配置 ...

✅ Agent 'team-dev' 更新成功！
```

---

### 7.4 删除 Agent

```bash
/opt/openclaw/gateway/bin/04-manage-agent.sh remove team-dev
```

**确认删除**：
```
⚠️  确定要删除 agent 'team-dev' 吗？(yes/no): yes
✅ Agent 'team-dev' 已删除
```

⚠️ **删除后**：
- Gateway 不再接受该机器人的消息
- 历史任务记录仍保留在数据库中
- 需要在企业微信管理后台停用或删除对应的机器人应用

---

### 7.5 服务管理（生产环境）

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
```

---

### 7.6 服务管理（快捷命令）

**安装后提供了便捷脚本**（脚本内部会自行调用 `sudo systemctl`；推荐仍以普通用户执行）：

```bash
# 启动
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh start

# 停止
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh stop

# 重启
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh restart

# 查看状态
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh status

# 查看日志
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh logs

# 查看 Agent 列表
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh list-agents
```

---

## 8. 常见问题

### 8.1 企业微信配置问题

#### Q1: URL 验证失败

**症状**：企业微信提示 "URL 验证失败"

**排查步骤**：

1. **检查 Gateway 是否运行**：
   ```bash
   curl http://localhost:8000/health
   ```

2. **检查域名解析**：
   ```bash
   ping ai.yourcompany.com
   ```

3. **检查防火墙**：
   ```bash
   sudo firewall-cmd --list-ports
   # 或
   sudo ufw status
   ```
   确保 8000 端口已开放。

4. **检查 Nginx 配置**（如果使用）：
   ```nginx
   location /team-dev/wecom/callback {
       proxy_pass http://localhost:8000/team-dev/wecom/callback;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
   }
   ```

5. **查看 Gateway 日志**：
   ```bash
   sudo journalctl -u openclaw-gateway -n 50
   ```
   查找 "回调验证" 相关日志。

---

#### Q2: 消息签名验证失败

**症状**：Gateway 日志显示 "消息签名验证失败"

**原因**：Token 或 EncodingAESKey 填错了

**解决**：

1. **检查数据库中的配置**：
   ```bash
   sqlite3 /opt/openclaw/data/gateway/gateway.db "SELECT name, wecom_token, wecom_aes_key FROM agents WHERE name='team-dev';"
   ```

2. **对比企业微信管理后台的配置**

3. **如果不一致，更新 agent**：
   ```bash
   /opt/openclaw/gateway/bin/04-manage-agent.sh update team-dev
   ```

---

#### Q3: 收不到回复

**症状**：发送消息后没有任何回复

**排查步骤**：

1. **检查 Gateway 日志**：
   ```bash
   sudo journalctl -u openclaw-gateway -f
   ```
   发送消息，观察是否有日志输出。

2. **检查 OpenClaw 是否运行**：
   ```bash
   curl http://localhost:18789/health
   ```

3. **检查 Gateway Token 是否正确**：
   ```bash
   # 查看 Gateway 配置的 Token
   sqlite3 /opt/openclaw/data/gateway/gateway.db "SELECT openclaw_token FROM agents WHERE name='team-dev';"
   
   # 对比 OpenClaw 配置
   cat ~/.openclaw/openclaw.json | grep token
   ```

4. **测试 OpenClaw 连接**：
   ```bash
   # 使用 Gateway 的测试脚本
   python3 testScripts/test-session-isolation.py
   ```

---

### 8.2 性能问题

#### Q4: 响应很慢

**症状**：发送消息后等待很久才收到回复（> 30 秒）

**可能原因**：

1. **OpenClaw 并发槽已满** → 参考 [进阶配置 - 提高并发限制](#92-提高-openclaw-并发限制)
2. **OpenClaw 服务器性能不足** → 升级 CPU/内存
3. **网络延迟** → 检查 Gateway 到 OpenClaw 的网络

**排查**：

1. **查看 OpenClaw 控制台 / 健康状态**：
   ```bash
   openclaw dashboard
   openclaw health
   ```
   如果你的 OpenClaw 版本提供统计页，再重点关注队列深度和活跃请求数。

2. **查看 Gateway 日志中的耗时**：
   ```bash
   sudo journalctl -u openclaw-gateway | grep "调用耗时"
   ```

---

#### Q5: 大量用户时出现超时

**症状**：同时有很多人使用时，部分用户收不到回复

**原因**：OpenClaw 并发限制（默认只有 4 个并发槽）

**解决**：参考 [进阶配置 - 多用户优化](#93-多用户优化)

---

### 8.3 数据问题

#### Q6: 如何查看历史消息？

```bash
# 查看最近 20 条消息
sqlite3 /opt/openclaw/data/gateway/gateway.db \
  "SELECT created_at, user_id, agent_id, task_content, status 
   FROM task_logs 
   ORDER BY created_at DESC 
   LIMIT 20;"
```

---

#### Q7: 如何清空历史记录？

```bash
# ⚠️ 慎用！会删除所有历史记录
sqlite3 /opt/openclaw/data/gateway/gateway.db "DELETE FROM task_logs;"
```

---

#### Q8: 数据库太大怎么办？

**定期清理旧记录**：

```bash
# 删除 30 天前的记录
sqlite3 /opt/openclaw/data/gateway/gateway.db \
  "DELETE FROM task_logs 
   WHERE created_at < datetime('now', '-30 days');"

# 压缩数据库
sqlite3 /opt/openclaw/data/gateway/gateway.db "VACUUM;"
```

**设置定时任务**（每周日凌晨 2 点清理）：
```bash
sudo crontab -e

# 添加以下行
0 2 * * 0 sqlite3 /opt/openclaw/data/gateway/gateway.db "DELETE FROM task_logs WHERE created_at < datetime('now', '-30 days'); VACUUM;"
```

---

### 8.4 升级和维护

#### Q9: 如何升级 Gateway？

```bash
# 1. 停止服务
sudo systemctl stop openclaw-gateway

# 2. 备份数据
sudo cp /opt/openclaw/data/gateway/gateway.db /opt/openclaw/data/gateway/gateway.db.backup

# 3. 拉取最新代码
cd ~/openclaw-deploy
git pull

# 4. 重新安装
sudo bash bin/02-install-gateway.sh

# 5. 启动服务
sudo systemctl start openclaw-gateway
```

---

#### Q10: 如何卸载？

```bash
cd ~/openclaw-deploy
sudo bash bin/05-cleanup.sh
```

清理脚本提供三个选项：
1. 卸载 Gateway 服务（停服务 + 删安装目录 + 删 systemd）
2. 清空 OpenClaw（停 gateway + 删 ~/.openclaw）
3. 全部清理（1+2 + 删数据目录）

**选项 1 不会删除**：
- `/opt/openclaw/data/gateway` 目录（数据保留）

**如果要完全删除（包括数据）**：
```bash
sudo rm -rf /opt/openclaw
```

---

## 9. 进阶配置

### 9.1 修改 Gateway 端口

**默认端口**：8000

**修改步骤**：

1. **编辑环境变量**：
   ```bash
   sudo nano /opt/openclaw/gateway/.env
   ```

2. **修改端口**：
   ```bash
   GATEWAY_PORT=8080  # 改为 8080
   ```

3. **重启服务**：
   ```bash
   sudo systemctl restart openclaw-gateway
   ```

4. **更新 Nginx 配置**（如果使用）：
   ```nginx
   proxy_pass http://localhost:8080;  # 改为新端口
   ```

---

### 9.2 提高 OpenClaw 并发限制

**适用场景**：用户数超过 10 人

**步骤**：

1. **编辑 OpenClaw 配置**：
   ```bash
   nano ~/.openclaw/openclaw.json
   ```

2. **修改并发限制**：
   ```json
   {
     "agents": {
       "defaults": {
         "maxConcurrent": 8  // 从默认的 4 改为 8
       }
     }
   }
   ```

3. **重启 OpenClaw**：
   ```bash
   # 查找 OpenClaw 进程
   ps aux | grep openclaw
   
   # 杀掉进程
   kill -9 <PID>
   
   # 重新启动（具体命令取决于你的 OpenClaw 启动方式）
   openclaw daemon start
   ```

4. **验证配置**：
   ```bash
   openclaw dashboard
   ```
   检查并发相关配置是否已经生效。

**推荐值**：
- 10-20 人：`maxConcurrent: 8`
- 20-50 人：`maxConcurrent: 16`
- 50+ 人：考虑多实例部署（参考并发分析文档）

---

### 9.3 多用户优化

**场景**：团队超过 30 人

**推荐方案**：

#### 方案 1：按部门分流（单 OpenClaw 实例）

```bash
# 研发部使用 dept-dev agent
/opt/openclaw/gateway/bin/04-manage-agent.sh add dept-dev

# 运维部使用 dept-ops agent
/opt/openclaw/gateway/bin/04-manage-agent.sh add dept-ops
```

**优点**：配置简单
**缺点**：仍受单实例并发限制

---

#### 方案 2：多 OpenClaw 实例（推荐）

**架构**：

```
Gateway
  ├─ dept-dev   → OpenClaw 实例 1 (server1:18789)
  ├─ dept-ops   → OpenClaw 实例 2 (server2:18789)
  └─ dept-sales → OpenClaw 实例 3 (server3:18789)
```

**配置步骤**：

1. **在不同服务器上启动 OpenClaw 实例**

2. **添加 agent 时使用不同的 Gateway 地址**：
   ```bash
   /opt/openclaw/gateway/bin/04-manage-agent.sh add dept-dev
   # Gateway 地址: http://server1:18789
   
   /opt/openclaw/gateway/bin/04-manage-agent.sh add dept-ops
   # Gateway 地址: http://server2:18789
   ```

**优点**：
- ✅ 线性扩展能力
- ✅ 故障隔离
- ✅ 性能大幅提升

**缺点**：
- ❌ 需要多台服务器
- ❌ 管理复杂度增加

---

### 9.4 启用 HTTPS

**生产环境强烈推荐使用 HTTPS**

**方案 1：使用 Nginx 反向代理（推荐）**

```nginx
# /etc/nginx/conf.d/openclaw-gateway.conf

server {
    listen 443 ssl;
    server_name ai.yourcompany.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**方案 2：使用 Let's Encrypt 免费证书**

```bash
# 安装 certbot
sudo apt install certbot python3-certbot-nginx

# 自动配置
sudo certbot --nginx -d ai.yourcompany.com
```

---

### 9.5 监控和告警

**定期检查脚本示例**（以下脚本需你自行保存，不是仓库内置文件）：

```bash
#!/bin/bash
# 例如保存为: /usr/local/bin/openclaw-health-check.sh

GATEWAY_URL="http://localhost:8000"

# 检查 Gateway
gateway_status=$(curl -s $GATEWAY_URL/health | jq -r .status)
if [ "$gateway_status" != "ok" ]; then
    echo "⚠️ Gateway 异常！"
    # 发送告警（邮件/钉钉/Slack）
fi

# 检查 systemd 服务
if ! systemctl is-active --quiet openclaw-gateway; then
    echo "⚠️ openclaw-gateway 服务异常！"
fi
```

**设置定时任务**（每 5 分钟检查一次）：

```bash
sudo crontab -e

# 添加以下行
*/5 * * * * /usr/local/bin/openclaw-health-check.sh >> /var/log/openclaw-health.log 2>&1
```

---

## 10. 附录

### 10.1 目录结构

```
/opt/openclaw/
├── gateway/
│   ├── bin/
│   │   └── 04-manage-agent.sh
│   ├── scripts/
│   │   ├── gateway-ctl.sh
│   │   ├── manage-agent.py
│   │   └── openclaw-gateway.service
│   ├── src/
│   │   └── gateway/
│   │       └── wecom_gateway.py
│   ├── venv/                 # Python 虚拟环境
│   └── .env                  # 环境变量
├── data/
│   └── gateway/
│       ├── gateway.db        # SQLite 数据库
│       └── files/            # 下载文件暂存目录
└── /var/log/openclaw/
    ├── gateway.log           # 标准输出日志
    └── gateway-error.log     # 错误日志
```

---

### 10.2 数据库表结构

#### agents 表（agent-企业微信绑定）

| 字段 | 类型 | 说明 |
|------|------|------|
| name | TEXT | Agent 名称（主键） |
| display_name | TEXT | 显示名称 |
| wecom_token | TEXT | 企业微信 Token |
| wecom_aes_key | TEXT | 企业微信 EncodingAESKey |
| openclaw_url | TEXT | OpenClaw 服务地址（`04` 交互中显示为 Gateway 地址） |
| openclaw_token | TEXT | OpenClaw Token（`04` 交互中显示为 Gateway Token） |
| openclaw_agent_id | TEXT | OpenClaw Agent ID；新规则下与 `name` 保持一致 |
| shared_dir | TEXT | 本地共享目录；新规则下固定为 `/app/shared/<agent_id>` |
| created_at | TEXT | 创建时间 |
| updated_at | TEXT | 更新时间 |

#### task_logs 表（任务日志）

| 字段 | 类型 | 说明 |
|------|------|------|
| task_id | TEXT | 任务 ID（主键） |
| user_id | TEXT | 用户 ID |
| agent_id | TEXT | Agent 名称 |
| task_content | TEXT | 消息内容 |
| status | TEXT | 状态（pending/processing/success/failed） |
| result | TEXT | 回复内容 |
| created_at | TIMESTAMP | 创建时间 |
| updated_at | TIMESTAMP | 更新时间 |

---

### 10.3 环境变量说明（必填 / 选填）

#### 通用配置

| 变量 | 默认值 | 是否必填 | 说明 |
|------|--------|----------|------|
| `DB_PATH` | `/opt/openclaw/data/gateway/gateway.db` | 是 | SQLite 数据库路径 |
| `GATEWAY_PORT` | `8000` | 是 | Gateway 监听端口 |
| `OPENCLAW_PROTOCOL` | `ws` | 否 | 通信协议（ws/sse/http） |
| `OPENCLAW_TIMEOUT` | `180` | 否 | 旧版兼容总超时（秒） |
| `OPENCLAW_CONNECT_TIMEOUT` | `10` | 否 | OpenClaw 连接超时（秒） |
| `OPENCLAW_WS_IDLE_TIMEOUT` | `30` | 否 | WS 空闲超时（秒） |
| `OPENCLAW_WS_TOTAL_TIMEOUT` | `180` | 否 | WS 总超时（秒） |
| `OPENCLAW_SSE_IDLE_TIMEOUT` | `30` | 否 | SSE 空闲超时（秒） |
| `OPENCLAW_SSE_TOTAL_TIMEOUT` | `180` | 否 | SSE 总超时（秒） |
| `OPENCLAW_HTTP_TIMEOUT` | `180` | 否 | HTTP 调用超时（秒） |
| `MAX_GATEWAY_WORKERS` | `8` | 否 | Gateway 全局 worker 池大小 |
| `MAX_PER_USER_PENDING` | `1` | 否 | 单用户最多等待消息数 |
| `MAX_QUEUE_WAIT_SECONDS` | `60` | 否 | 等待消息最大排队时长（秒） |
| `GATEWAY_URL` | `http://localhost:8000` | 是 | Gateway 对外访问地址（管理脚本重载通知、上传 Skill 回调依赖） |
| `FILE_STORAGE_MODE` | `local` | 是 | 文件存储模式（`local` / `s3`） |
| `FILE_STORAGE_PRESIGN_EXPIRES` | `86400` | 否 | 预签名下载链接有效期（秒） |
| `MAX_INTERNAL_UPLOAD_FILE_SIZE` | `52428800` | 否 | OpenClaw skill 通过内部接口上传时的大小限制 |
| `FILE_UPLOAD_INTERNAL_TOKEN` | 空 | 条件必填 | Gateway 内部上传接口鉴权；`03` 会据此生成 `OPENCLAW_FILE_UPLOAD_TOKEN` |

上传 Skill 运行时变量说明：
- `03-install-openclaw.sh` 会自动生成：
  - `OPENCLAW_FILE_UPLOAD_GATEWAY_URL` ← `GATEWAY_URL`
  - `OPENCLAW_FILE_UPLOAD_TOKEN` ← `FILE_UPLOAD_INTERNAL_TOKEN`
  - `OPENCLAW_FILE_UPLOAD_EXPIRES` ← `FILE_STORAGE_PRESIGN_EXPIRES`
- 非沙箱 Agent：写入 `~/.openclaw/.env`；如果 OpenClaw 当前已在运行，必须重启 OpenClaw 后生效。
- 沙箱 Agent：写入对应 agent 的 `sandbox.docker.env`；如果沙箱容器已存在，执行 `openclaw sandbox recreate --agent <agent_id>`。

#### S3 模式配置（`FILE_STORAGE_MODE=s3`）

| 变量 | 默认值 | 是否必填 | 说明 |
|------|--------|----------|------|
| `S3_BUCKET` | 空 | 是 | 目标桶名称 |
| `S3_ENDPOINT_URL` | 空 | 自建 S3 时是 | 自建 S3/兼容服务地址（例如 `http://minio.xxx:9000`） |
| `S3_ACCESS_KEY_ID` | 空 | 条件必填 | 无 IAM Role/实例角色时必填 |
| `S3_SECRET_ACCESS_KEY` | 空 | 条件必填 | 无 IAM Role/实例角色时必填 |
| `S3_REGION` | `us-east-1` | 建议 | 签名区域，建议与服务端配置一致 |
| `S3_SIGNATURE_VERSION` | `s3` | 建议 | 自建兼容模式建议 `s3`（等价 Java `S3SignerType`） |
| `S3_ADDRESSING_STYLE` | `path` | 建议 | 自建兼容模式建议 `path`（等价 Java `withPathStyleAccess(true)`） |
| `FILE_STORAGE_KEY_PREFIX` | `openclaw-gateway` | 否 | 统一对象 key 前缀 |
| `S3_KEY_PREFIX` | `openclaw-gateway` | 否 | 兼容旧配置（建议优先用 `FILE_STORAGE_KEY_PREFIX`） |
| `S3_SSE_MODE` | 空 | 否 | 服务端加密模式（如 `AES256` / `aws:kms`） |
| `S3_SSE_KMS_KEY_ID` | 空 | 条件必填 | 当 `S3_SSE_MODE=aws:kms` 时必填 |

---

### 10.4 有用的命令速查

```bash
# 查看 Gateway 状态
sudo systemctl status openclaw-gateway

# 查看实时日志
sudo journalctl -u openclaw-gateway -f

# 使用快捷运维脚本
bash /opt/openclaw/gateway/scripts/gateway-ctl.sh status

# 查看所有 Agent
/opt/openclaw/gateway/bin/04-manage-agent.sh list

# 查看最近 10 条任务
sqlite3 /opt/openclaw/data/gateway/gateway.db \
  "SELECT * FROM task_logs ORDER BY created_at DESC LIMIT 10;"

# 查看任务统计
sqlite3 /opt/openclaw/data/gateway/gateway.db \
  "SELECT status, COUNT(*) FROM task_logs GROUP BY status;"

# 检查 Gateway 健康状态
curl http://localhost:8000/health | jq

# 重启 Gateway
sudo systemctl restart openclaw-gateway
```

---

### 10.5 获取帮助

**遇到问题？**

1. 📖 查看日志：`sudo journalctl -u openclaw-gateway -n 100`
2. 📚 阅读并发分析文档：`docs/CONCURRENCY-ANALYSIS.md`
3. 🔍 搜索 GitHub Issues
4. 💬 联系团队技术支持

---

### 10.6 文件存储模式与上传 Skill

默认模式：`FILE_STORAGE_MODE=local`。

先记住一句话：
- **`FILE_STORAGE_MODE` 决定“企业微信发来的文件怎么交给 Agent”**。
- **`gateway-file-upload` skill 决定“Agent 能不能把自己的产物再上传出去”**。

#### 四种组合速查

| 组合 | 企微来件怎么交给 Agent | Agent 能否主动上传 |
|------|------------------------|--------------------|
| `local` + 无 skill | `/app/shared/<agent_id>/...` 本地绝对路径 | 否 |
| `local` + 有 skill | `/app/shared/<agent_id>/...` 本地绝对路径 | 是 |
| `s3` + 无 skill | S3 / 对象存储下载链接 | 否 |
| `s3` + 有 skill | S3 / 对象存储下载链接 | 是 |

#### 企业微信回复策略（markdown.content 限制）

- 企业微信主动回复 `markdown.content` 最大为 `20480` 字节（UTF-8）。
- Gateway 统一按 `20000` 字节阈值做安全截断后再回复。
- 无论 `local` 还是 `s3`，超长文本都不自动转下载链接。

#### 并发与超时策略

- 同一 `agent + user` 同时只执行 1 条消息。
- 当前有 1 条执行中时，最多再保留 1 条等待消息；第 3 条会被直接拒绝。
- 第 1 条被动回复固定为：`已收到，处理中...`
- 第 2 条等待消息被动回复：`前序任务处理中，已进入等待队列，请稍候...`
- 队列已满时被动回复：`当前已有任务处理中，请稍后再试`
- OpenClaw 执行超时后主动回复：`处理超时，请重试。`
- 等待消息排队超过 `MAX_QUEUE_WAIT_SECONDS` 后，会主动回复：`前序任务处理时间较长，本次请求未执行，请重试。`

#### 主动上传能力的开关

- `03-install-openclaw.sh` 会将 `gateway-file-upload` 安装到每个 Agent 的 `<workspace>/skills`。
- 这一步不区分 `FILE_STORAGE_MODE=local` 还是 `s3`。
- Agent 只有在以下条件同时满足时，才具备“主动上传文件/文本”的能力：
  - `gateway-file-upload` 已同步到该 Agent 的 workspace
  - `OPENCLAW_FILE_UPLOAD_GATEWAY_URL`
  - `OPENCLAW_FILE_UPLOAD_TOKEN`
  - `OPENCLAW_FILE_UPLOAD_EXPIRES`
- 这三个运行时变量来源于 Gateway 配置：
  - `OPENCLAW_FILE_UPLOAD_GATEWAY_URL` = `GATEWAY_URL`
  - `OPENCLAW_FILE_UPLOAD_TOKEN` = `FILE_UPLOAD_INTERNAL_TOKEN`
  - `OPENCLAW_FILE_UPLOAD_EXPIRES` = `FILE_STORAGE_PRESIGN_EXPIRES`
- 下发位置：
  - 非沙箱 Agent：写入 `~/.openclaw/.env`；若 OpenClaw 已在运行，必须重启 OpenClaw 后生效
  - 沙箱 Agent：写入对应 agent 的 `sandbox.docker.env`；若容器已存在，执行 `openclaw sandbox recreate --agent <agent_id>`

#### 启用 S3 模式

1. 在 Gateway `.env` 中设置（与 Java 代码兼容推荐）：

```bash
FILE_STORAGE_MODE=s3
S3_BUCKET=your-private-bucket
S3_ENDPOINT_URL=http://your-s3-endpoint:9000
S3_ACCESS_KEY_ID=your-ak
S3_SECRET_ACCESS_KEY=your-sk
S3_REGION=us-east-1
S3_SIGNATURE_VERSION=s3
S3_ADDRESSING_STYLE=path
S3_SSE_MODE=

# 仅当需要让 Agent 调用上传 Skill 时需要
FILE_UPLOAD_INTERNAL_TOKEN=your-random-token
```

2. 重新执行安装脚本并重启服务：

```bash
sudo bash bin/02-install-gateway.sh
bash bin/03-install-openclaw.sh --skip-install
```

说明：
- 微信文件会上传到 S3，并把预签名下载链接发给 Agent。
- 这只改变“企微来件怎么交给 Agent”，不等于自动开启 Agent 的主动上传能力。
- 如果还需要 Agent 主动上传文件/文本，请同时配置 `FILE_UPLOAD_INTERNAL_TOKEN`，让 `03-install-openclaw.sh` 继续生成 `OPENCLAW_FILE_UPLOAD_*`。
- 如果不使用上传 skill，可以不配置 `FILE_UPLOAD_INTERNAL_TOKEN`；此时 Skill 仍会被同步，但调用上传接口会失败。

#### local 模式行为

- `FILE_STORAGE_MODE=local` 时，企业微信文件会直接保存到本地，再把绝对路径交给 Agent。
- 这只改变“企微来件怎么交给 Agent”，不影响是否安装上传 Skill。
- 如果还需要 Agent 主动上传文件/文本，仍然要让 `OPENCLAW_FILE_UPLOAD_*` 生效：
  - 非沙箱 Agent 走 `~/.openclaw/.env`
  - 沙箱 Agent 走 `sandbox.docker.env`
- Gateway 会把企业微信文件保存到 `/app/shared/<agent_id>/<日期>/...`，并把这个绝对路径直接下发给 Agent。
- 宿主机上的 `/app/shared/<agent_id>` 建议做成软链，指向 `~/.openclaw/workspace-<agent_id>/shared`。
- 因此 `local` 模式下，最关键的约束是：`agent_id` 同名、`/app/shared/<agent_id>` 正确指向 workspace 内真实目录、沙箱 bind source 位于该 workspace 内。
- 如果你不是用 `03` 脚本安装 OpenClaw，请务必按 [2.2.1](#221-如果你是自行部署-openclaw不使用-03-脚本) 手工满足这些约束。

---

**最后更新**: 2026-03-07
**版本**: v2.1
