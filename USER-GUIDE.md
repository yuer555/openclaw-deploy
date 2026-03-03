# OpenClaw 企业微信桥接网关 - 用户指南

> 从零开始，10 分钟部署完成 🚀

---

## 快速部署流程

| 步骤 | 脚本 | 执行位置 | 说明 |
|------|------|---------|------|
| 1. 上传代码 | `bin/01-upload.sh` | 本地 | 打包项目文件并上传到服务器 |
| 2. 安装 Gateway | `sudo bash bin/02-install-gateway.sh` | 服务器 | 安装 Python 依赖、配置 systemd 服务 |
| 3. 安装 OpenClaw | `bash bin/03-install-openclaw.sh` | 服务器 | 安装 OpenClaw、配置模型和 Agent |
| 4. 添加 Agent 绑定 | `bin/04-manage-agent.sh add <name>` | 服务器 | 绑定企业微信机器人到 OpenClaw Agent |
| 5. 清理环境 | `sudo bash bin/05-cleanup.sh` | 服务器 | 卸载服务 / 清空 OpenClaw / 全部重置 |

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

脚本会自动检测 Node.js (22+)、npm、Docker，然后进入安装流程。

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

安装完成后会自动运行 `openclaw onboard --install-daemon` 进入 **OpenClaw 初始化向导**（见 [2.1.6](#216-openclaw-onboard-初始化向导)）。

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
是否启用 Docker 沙箱? (直接回车默认 Yes) [Y/n]: _
```

| 选项 | 说明 |
|------|------|
| **Agent ID** | 英文标识符，用于 API 调用和配置引用 |
| **显示名称** | 日志和统计中展示的名称，可以是中文 |
| **Docker 沙箱** | 启用后 Agent 在 Docker 容器内执行代码。需要服务器已安装 Docker |

启用沙箱后自动写入以下配置：

```json
{
  "sandbox": {
    "mode": "all",
    "scope": "agent",
    "workspaceAccess": "rw",
    "docker": {
      "network": "bridge",
      "readOnlyRoot": false
    }
  }
}
```

| 字段 | 值 | 说明 |
|------|-----|------|
| `network` | `bridge` | 容器需要联网（API 调用等） |
| `readOnlyRoot` | `false` | 容器根文件系统可写 |

共享文件目录默认位于 `~/.openclaw/workspace-<agent_id>/shared`，容器内通过 `/workspace/shared` 访问。

创建完成后同样会询问是否编辑人格设定。子 Agent 的模型配置（`auth-profiles.json`、`models.json`）会自动从主 Agent 同步。

---

### 2.1.4 第四步：Gateway 集成信息

脚本自动读取 OpenClaw 配置并输出连接信息：

```
企业微信 Gateway 连接 OpenClaw 所需信息:
  OPENCLAW_URL=ws://localhost:18789
  OPENCLAW_TOKEN=1e443bcba0ed1327...

在 04-manage-agent.sh add 时使用以上信息配置每个 Agent 的 openclaw_url 和 openclaw_token。
不同 Agent 通过 openclaw_agent_id 区分（如 main, development, testing）。
```

**记下这两个值**，后面添加企微 Agent 绑定时需要。

---

### 2.1.5 第五步：最终检查

脚本自动执行：
- 列出所有已配置的 Agent
- 列出所有已配置的模型
- OpenClaw Gateway 健康检查

```
╔══════════════════════════════════════╗
║    OpenClaw 配置完成!                ║
╚══════════════════════════════════════╝

后续操作:
  1. 启动 OpenClaw:       openclaw gateway start
  2. 部署企微 Gateway:    sudo bash bin/02-install-gateway.sh
  3. 添加企微 Agent 绑定: /opt/openclaw/gateway/bin/04-manage-agent.sh add <name>
  4. 查看 Agent 列表:     /opt/openclaw/gateway/bin/04-manage-agent.sh list
  5. 查看 OpenClaw 面板:  openclaw dashboard
```

---

### 2.1.6 OpenClaw onboard 初始化向导

首次安装 OpenClaw 或选择"清理重新配置"时，会自动运行 `openclaw onboard --install-daemon`。这是 OpenClaw 官方的交互式初始化向导，主要完成以下配置：

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

向导自动注册系统服务（Linux 下为 systemd，macOS 下为 launchd），使 OpenClaw Gateway 开机自启。

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
- **OpenClaw 地址**: `http://localhost:18789` （或服务器 IP）
- **OpenClaw Token**: `你的长串token`

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
https://你的域名/{agent_name}/wecom/callback
```

**示例**：
```
https://ai.yourcompany.com/team-dev/wecom/callback
```

**填写步骤**：

1. **URL 填入** 上面的地址（`{agent_name}` 替换为你想要的名字，如 `team-dev`）
2. **Token** 填入刚才生成的 Token
3. **EncodingAESKey** 填入刚才生成的 EncodingAESKey
4. **点击"保存"**

⚠️ **此时会验证 URL 可达性，必须先完成下一步（添加 Agent）才能保存成功！**

---

## 5. 添加 Agent

### 5.1 什么是 Agent？

**Agent** 是 Gateway 和企业微信机器人的绑定关系，包含：
- 企业微信机器人的加密配置（Token/AESKey）
- 对应的 OpenClaw 实例地址和 Token
- 使用哪个 OpenClaw Agent（`main` 或自定义）

**一个 Agent 对应一个企业微信机器人**。

---

### 5.2 交互式添加（推荐）

```bash
# 生产环境（systemd 服务）
/opt/openclaw/gateway/bin/04-manage-agent.sh add team-dev

# 开发环境
python3 scripts/manage-agent.py add team-dev
```

**按照提示输入**：

```
📝 添加新 Agent: team-dev

显示名称（用于日志和统计）: 研发团队 AI 助手

企业微信 Token（随机生成的 32 位字符串）: 32c4407bae780aeb92b0d7f504dc26c1

企业微信 EncodingAESKey（随机生成的 43 位字符串）: f7cTZKs4PQ1E0cLHrHArKpSoHYUzxUNE8mKTIauIkZA

OpenClaw 地址（如 http://localhost:18789 或 ws://IP:PORT）: http://localhost:18789

OpenClaw Token（从 ~/.openclaw/openclaw.json 获取）: 1e443bcba0ed1327699b31cdee8f6150e97226386c375f75

OpenClaw Agent ID（默认 main，按回车使用默认）: [直接回车]

✅ Agent 'team-dev' 添加成功！
```

---

### 5.3 验证 Agent 添加成功

```bash
# 查看所有 Agent
/opt/openclaw/gateway/bin/04-manage-agent.sh list

# 或开发环境
python3 scripts/manage-agent.py list
```

**预期输出**：
```
========================================
📋 当前已配置的 Agents
========================================

Agent: team-dev
  显示名称: 研发团队 AI 助手
  OpenClaw URL: http://localhost:18789
  OpenClaw Agent ID: main
  创建时间: 2026-03-02 10:00:00

总共 1 个 agent
```

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
      "openclaw_agent_id": "main"
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

**场景**：想让机器人使用不同的 OpenClaw Agent（如 `work` agent）

**步骤 1：在 OpenClaw 中创建 Agent**

参考 OpenClaw 文档创建新 agent，假设名为 `work`。

**步骤 2：添加 Gateway Agent 时指定**

```bash
/opt/openclaw/gateway/bin/04-manage-agent.sh add team-work
```

当提示输入 **OpenClaw Agent ID** 时，输入 `work`（而不是默认的 `main`）。

---

### 7.3 修改现有 Agent

```bash
# 更新 agent 配置
/opt/openclaw/gateway/bin/04-manage-agent.sh update team-dev
```

**按提示修改**（不想改的直接回车保持原值）：
```
当前显示名称: 研发团队 AI 助手
新显示名称（回车保持不变）: [直接回车保持不变]

当前 OpenClaw URL: http://localhost:18789
新 OpenClaw URL（回车保持不变）: http://new-server:18789  ← 修改了

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

**安装后提供了便捷脚本**：

```bash
# 启动
sudo gateway-ctl start

# 停止
sudo gateway-ctl stop

# 重启
sudo gateway-ctl restart

# 查看状态
sudo gateway-ctl status

# 查看日志
sudo gateway-ctl logs
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

3. **检查 OpenClaw Token 是否正确**：
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

1. **查看 OpenClaw 统计**：
   ```bash
   curl http://localhost:18789/api/stats
   ```
   关注 `queueDepth`（队列深度）和 `activeRequests`（活跃请求数）

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
   curl http://localhost:18789/api/stats | jq .maxConcurrent
   ```

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
# 研发部使用 main agent
/opt/openclaw/gateway/bin/04-manage-agent.sh add dept-dev
# OpenClaw Agent ID: main

# 运维部使用 work agent
/opt/openclaw/gateway/bin/04-manage-agent.sh add dept-ops
# OpenClaw Agent ID: work
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

2. **添加 agent 时使用不同的 OpenClaw URL**：
   ```bash
   /opt/openclaw/gateway/bin/04-manage-agent.sh add dept-dev
   # OpenClaw URL: http://server1:18789
   
   /opt/openclaw/gateway/bin/04-manage-agent.sh add dept-ops
   # OpenClaw URL: http://server2:18789
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

**定期检查脚本**：

```bash
#!/bin/bash
# /opt/openclaw/scripts/health-check.sh

GATEWAY_URL="http://localhost:8000"
OPENCLAW_URL="http://localhost:18789"

# 检查 Gateway
gateway_status=$(curl -s $GATEWAY_URL/health | jq -r .status)
if [ "$gateway_status" != "ok" ]; then
    echo "⚠️ Gateway 异常！"
    # 发送告警（邮件/钉钉/Slack）
fi

# 检查 OpenClaw
openclaw_status=$(curl -s $OPENCLAW_URL/health | jq -r .status)
if [ "$openclaw_status" != "ok" ]; then
    echo "⚠️ OpenClaw 异常！"
    # 发送告警
fi

# 检查队列深度
queue_depth=$(curl -s $OPENCLAW_URL/api/stats | jq -r .queueDepth)
if [ "$queue_depth" -gt 10 ]; then
    echo "⚠️ 队列深度过高: $queue_depth"
fi
```

**设置定时任务**（每 5 分钟检查一次）：

```bash
sudo crontab -e

# 添加以下行
*/5 * * * * /opt/openclaw/scripts/health-check.sh >> /var/log/openclaw-health.log 2>&1
```

---

## 10. 附录

### 10.1 目录结构

```
/opt/openclaw/
├── gateway/
│   ├── bin/                  # 部署步骤脚本
│   ├── scripts/              # 工具脚本
│   ├── src/                  # 应用代码
│   └── .env                  # 环境变量
├── data/
│   └── gateway/
│       ├── gateway.db        # SQLite 数据库
│       ├── gateway.log       # 日志文件
│       └── files/            # 文件下载目录
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
| openclaw_url | TEXT | OpenClaw 地址 |
| openclaw_token | TEXT | OpenClaw Token |
| openclaw_agent_id | TEXT | OpenClaw Agent ID（默认 main） |
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

### 10.3 环境变量说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DB_PATH` | `/opt/openclaw/data/gateway/gateway.db` | SQLite 数据库路径 |
| `GATEWAY_PORT` | `8000` | Gateway 监听端口 |
| `OPENCLAW_PROTOCOL` | `ws` | 通信协议（ws/sse/http） |
| `OPENCLAW_TIMEOUT` | `2700` | OpenClaw 超时时间（秒） |
| `GATEWAY_URL` | `http://localhost:8000` | Gateway 外部访问地址 |

---

### 10.4 有用的命令速查

```bash
# 查看 Gateway 状态
sudo systemctl status openclaw-gateway

# 查看实时日志
sudo journalctl -u openclaw-gateway -f

# 查看所有 Agent
/opt/openclaw/gateway/bin/04-manage-agent.sh list

# 查看最近 10 条任务
sqlite3 /opt/openclaw/data/gateway/gateway.db \
  "SELECT * FROM task_logs ORDER BY created_at DESC LIMIT 10;"

# 查看任务统计
sqlite3 /opt/openclaw/data/gateway/gateway.db \
  "SELECT status, COUNT(*) FROM task_logs GROUP BY status;"

# 检查 OpenClaw 统计
curl http://localhost:18789/api/stats | jq

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

**最后更新**: 2026-03-03
**版本**: v1.1
