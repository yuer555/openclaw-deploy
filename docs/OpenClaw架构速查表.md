# OpenClaw 架构速查表

## 🏗️ 核心架构

```
外部设备 (Nodes)              消息渠道 (Channels)           客户端 (Control)
     ↓                              ↓                            ↓
  ┌──────┐                      ┌──────┐                    ┌──────┐
  │ iOS  │                      │WhatsApp│                   │ App  │
  │Android│────┐             ┌──│Telegram│──┐            ┌──│ CLI  │
  │macOS │    │             │  │Discord │  │            │  │ Web  │
  └──────┘    │             │  └──────┘  │            │  └──────┘
              │             │             │            │
              ┗━━━━━━━━━━━━━┷━━━━━━━━━━━━━┷━━━━━━━━━━━━┛
                                    │
                          WebSocket (18789)
                                    │
                    ┌───────────────┴───────────────┐
                    │   Gateway 守护进程 (核心)      │
                    ├───────────────────────────────┤
                    │ • WebSocket 服务器             │
                    │ • Token / 设备配对认证         │
                    │ • JSON Schema 验证             │
                    │ • 消息路由 (Bindings)          │
                    │ • 命令队列 (Lane System)       │
                    └───────────────┬───────────────┘
                                    │
             ┌──────────────────────┼──────────────────────┐
             │                      │                      │
        ┌────┴────┐            ┌────┴────┐          ┌────┴────┐
        │Agent:   │            │Agent:   │          │Agent:   │
        │ main    │            │ work    │          │ family  │
        ├─────────┤            ├─────────┤          ├─────────┤
        │Workspace│            │Workspace│          │Workspace│
        │Sessions │            │Sessions │          │Sessions │
        │Auth     │            │Auth     │          │Auth     │
        │Skills   │            │Skills   │          │Skills   │
        └─────┬───┘            └────┬────┘          └────┬────┘
              │                     │                    │
              └─────────────────────┼────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │  工具 & 能力层                 │
                    ├───────────────────────────────┤
                    │ • Tools (exec/read/browser)   │
                    │ • Skills (打包工具集)         │
                    │ • Hooks (事件脚本)            │
                    │ • Plugins (生命周期拦截)      │
                    │ • Sandbox (Docker 隔离)       │
                    └───────────────┬───────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    │  外部服务                      │
                    ├───────────────────────────────┤
                    │ • Claude / GPT / Copilot      │
                    │ • Canvas Host (:18793)        │
                    │ • 持久化存储 (JSONL)          │
                    └───────────────────────────────┘
```

---

## 🔄 核心流程

### 1. 消息路由 (Message Routing)

```
用户消息 → 渠道 → Gateway → 路由器 (Bindings)
                              ↓
                    匹配优先级（从高到低）：
                    1. peer (精确 DM/群组/频道)
                    2. guildId (Discord)
                    3. teamId (Slack)
                    4. accountId (渠道账号)
                    5. channel (渠道)
                    6. default (默认代理)
                              ↓
                        选定的 Agent
                              ↓
                        加入队列 (Lane)
                              ↓
                        执行 (串行化)
```

### 2. 代理执行循环 (Agent Loop)

```
接收消息
   ↓
验证参数 → 解析会话 (sessionKey)
   ↓
加入队列 → 获取会话锁 🔒
   ↓
准备环境：
  • 加载工作区 (Workspace)
  • 加载技能 (Skills)
  • 加载上下文 (Bootstrap)
  • 构建系统提示 (System Prompt)
   ↓
🪝 before_agent_start hook
   ↓
模型推理 (pi-agent-core)
   ↓
┌──────────────────┐
│  流式执行循环    │
├──────────────────┤
│ • 文本增量 → 用户│
│ • 工具调用 → 执行│
│ • 结果反馈 → 模型│
└──────────────────┘
   ↓
🪝 agent_end hook
   ↓
持久化会话 → 释放锁 🔓
   ↓
返回结果 ✅
```

### 3. 客户端连接 (Client Connection)

```
客户端/节点
   ↓
WebSocket 连接 → Gateway
   ↓
req:connect {deviceId, role, auth}
   ↓
Token 验证 or 设备配对
   ↓
┌─────────────────────────┐
│ 本地 (127.0.0.1)        │
│   ↓                     │
│ ✅ 自动批准             │
└─────────────────────────┘
   OR
┌─────────────────────────┐
│ 远程连接                │
│   ↓                     │
│ 已配对? ✅ 验证 Token   │
│   ↓                     │
│ 新设备? 🔐 需要配对批准 │
└─────────────────────────┘
   ↓
res:connect → hello-ok
   ↓
持续通信：
  • event:presence
  • event:tick
  • req:agent / req:send
  • res + events
```

---

## 🧩 核心组件

| 组件 | 职责 | 端口/路径 |
|------|------|----------|
| **Gateway** | WebSocket 服务、消息路由、认证 | `:18789` |
| **Agent** | 代理运行时、会话管理、上下文 | - |
| **Router** | 消息路由匹配（Bindings） | - |
| **Queue** | 命令队列、串行化、优先级 | - |
| **Tools** | 内置工具（exec/read/browser...） | - |
| **Skills** | 打包工具集（脚本+文档） | - |
| **Hooks** | 事件驱动脚本 | - |
| **Plugins** | 生命周期拦截器 | - |
| **Sandbox** | Docker 容器隔离 | - |
| **Canvas** | HTML/A2UI 渲染服务 | `:18793` |

---

## 🔐 认证与安全

### Token 认证
- 环境变量：`OPENCLAW_GATEWAY_TOKEN`
- 配置文件：`gateway.auth.token`
- 命令行：`--token`

### 设备配对
- 基于 `deviceId` 的配对机制
- 本地连接自动批准
- 远程连接需要签名挑战

### 权限控制
```json5
{
  agents: {
    list: [
      {
        id: "restricted",
        tools: {
          allow: ["read", "sessions_list"],
          deny: ["exec", "write", "browser"]
        },
        sandbox: {
          mode: "all",
          scope: "agent"
        }
      }
    ]
  }
}
```

---

## 📁 目录结构

```
~/.openclaw/
├── openclaw.json                     # 主配置
├── workspace/                         # main 代理工作区
│   ├── AGENTS.md / SOUL.md / USER.md
│   ├── MEMORY.md
│   ├── memory/YYYY-MM-DD.md
│   └── skills/
├── workspace-<agentId>/               # 其他代理工作区
├── agents/
│   ├── main/
│   │   ├── agent/
│   │   │   ├── auth-profiles.json
│   │   │   └── model-registry.json
│   │   └── sessions/*.jsonl
│   └── <agentId>/
│       ├── agent/
│       └── sessions/
├── credentials/                       # 渠道认证
│   ├── whatsapp/{personal,biz}/
│   └── telegram/
├── skills/                            # 全局技能
└── canvas/                            # Canvas 文件
```

---

## 🚀 部署模式

### 单机部署
```bash
# macOS/Linux
openclaw gateway

# 客户端
openclaw chat  # CLI 聊天
# 或 macOS App
```

### 容器化部署
```yaml
services:
  agent:
    image: openclaw-agent:v1.4
    environment:
      - OPENCLAW_MODEL=github-copilot/claude-sonnet-4.5
      - OPENCLAW_GATEWAY_TOKEN=${TOKEN}
    command: npx openclaw gateway --allow-unconfigured
```

### 远程访问
```bash
# Tailscale VPN (推荐)
tailscale up

# SSH 隧道
ssh -N -L 18789:127.0.0.1:18789 user@host

# 反向代理 + TLS
# Nginx / Caddy + Let's Encrypt
```

---

## 📊 性能指标 (v1.4)

| 指标 | v1.3 | v1.4 | 提升 |
|------|------|------|------|
| 容器启动 | 5-10分钟 | 5-10秒 | 98% ⚡ |
| 原因 | 动态安装 | 预构建镜像 | - |
| 镜像大小 | 1GB | 1.5GB | +500MB |
| 安全性 | 无认证 | Token 认证 | ✅ |

---

## 🎯 典型场景

### 场景1：一个 WhatsApp 号，多人使用
```json5
{
  bindings: [
    {agentId: "alex", match: {channel:"whatsapp", peer:{kind:"direct", id:"+15551230001"}}},
    {agentId: "mia",  match: {channel:"whatsapp", peer:{kind:"direct", id:"+15551230002"}}}
  ]
}
```

### 场景2：两个 WhatsApp 号，个人+工作
```json5
{
  bindings: [
    {agentId: "home", match: {channel:"whatsapp", accountId:"personal"}},
    {agentId: "work", match: {channel:"whatsapp", accountId:"biz"}}
  ]
}
```

### 场景3：一个群组专用代理
```json5
{
  bindings: [
    {agentId: "family", match: {
      channel:"whatsapp",
      peer:{kind:"group", id:"120363...@g.us"}
    }}
  ]
}
```

### 场景4：跨渠道分流
```json5
{
  bindings: [
    {agentId: "chat", match: {channel:"whatsapp"}},
    {agentId: "opus", match: {channel:"telegram"}}
  ]
}
```

---

## 🛠️ 常用命令

```bash
# Gateway 管理
openclaw gateway                    # 启动 Gateway
openclaw gateway stop               # 停止
openclaw status                     # 状态检查

# 代理管理
openclaw agents add work            # 添加代理
openclaw agents list --bindings     # 列出代理和绑定

# 会话管理
openclaw chat                       # 开始聊天
openclaw history --limit 10         # 查看历史
openclaw /reset                     # 重置会话

# 配置
openclaw config get                 # 查看配置
openclaw config edit                # 编辑配置

# 技能
openclaw skills list                # 列出技能
openclaw skills sync                # 同步技能
```

---

## 📚 快速参考

| 需求 | 文档位置 |
|------|---------|
| 安装部署 | `/install/` |
| 配置说明 | `/gateway/config` |
| 多代理 | `/concepts/multi-agent` |
| 消息渠道 | `/channels/` |
| 工具与技能 | `/tools/` |
| 安全 | `/security/` |
| 故障排查 | `/help/troubleshooting` |

---

**速查表版本**: v1.0  
**适配 OpenClaw 版本**: 2026.2.12  
**最后更新**: 2026-02-14
