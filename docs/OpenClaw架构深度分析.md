# OpenClaw 架构深度分析

**版本**: 2026.2.12  
**分析日期**: 2026-02-14  
**架构类型**: WebSocket Gateway + 多代理系统

---

## 🏗️ 架构概览

OpenClaw 是一个**分布式多代理 AI 框架**，采用 **WebSocket Gateway** 作为核心通信枢纽，支持多渠道消息接入、多代理隔离运行、跨设备能力调用和实时流式交互。

### 核心设计原则

1. **单一 Gateway 架构** - 一台主机运行一个 Gateway 守护进程
2. **多代理隔离** - 每个代理拥有独立的工作区、会话和认证
3. **WebSocket 统一协议** - 所有客户端、节点和渠道通过 WS 连接
4. **事件驱动流式** - 实时流式响应和工具执行
5. **设备配对与信任** - 基于设备身份的配对和授权机制

---

## 📊 架构全景图

\`\`\`mermaid
%%{init: {
  'theme': 'base',
  'themeVariables': {
    'primaryColor': '#E8F4F8',
    'primaryTextColor': '#1a1a1a',
    'primaryBorderColor': '#2C5F7C',
    'lineColor': '#2C5F7C',
    'secondaryColor': '#FFF8E1',
    'tertiaryColor': '#F0F4F8',
    'clusterBkg': '#F9FAFB',
    'clusterBorder': '#4A90A4',
    'edgeLabelBackground': '#ffffff',
    'fontSize': '14px'
  }
}}%%

graph TB
    subgraph "外部设备层 (Nodes)"
        N1[iOS/Android<br/>节点]
        N2[macOS<br/>节点]
        N3[无头节点<br/>Headless]
        N4[其他设备]
    end

    subgraph "客户端层 (Control Plane)"
        C1[macOS App]
        C2[CLI 终端]
        C3[Web 管理界面]
        C4[WebChat UI]
    end

    subgraph "消息渠道层 (Messaging Surfaces)"
        M1[WhatsApp<br/>Baileys]
        M2[Telegram<br/>grammY]
        M3[Discord]
        M4[Slack]
        M5[Signal]
        M6[iMessage]
        M7[Google Chat]
    end

    subgraph "核心 Gateway 层"
        GW[Gateway 守护进程<br/>127.0.0.1:18789]
        
        subgraph "协议层"
            WS[WebSocket<br/>服务器]
            AUTH[认证模块<br/>Token/Pairing]
            SCHEMA[JSON Schema<br/>验证器]
        end
        
        subgraph "路由层"
            ROUTER[消息路由器<br/>Bindings]
            QUEUE[命令队列<br/>Lane System]
        end
        
        subgraph "代理运行时"
            A1[Agent: main<br/>主会话]
            A2[Agent: work<br/>工作会话]
            A3[Agent: family<br/>家庭会话]
            AN[Agent: N<br/>其他代理...]
        end
        
        subgraph "能力层"
            TOOLS[工具系统<br/>Tools]
            SKILLS[技能系统<br/>Skills]
            HOOKS[钩子系统<br/>Hooks/Plugins]
        end
    end

    subgraph "持久化层"
        DB[(会话数据库<br/>Sessions)]
        AUTH_DB[(认证存储<br/>Auth Profiles)]
        CONFIG[(配置文件<br/>openclaw.json)]
        WS_DIR[工作区文件<br/>Workspace)]
    end

    subgraph "Canvas 服务"
        CANVAS[Canvas Host<br/>:18793<br/>HTML/A2UI]
    end

    subgraph "外部模型层"
        LLM1[Anthropic<br/>Claude]
        LLM2[GitHub Copilot]
        LLM3[OpenAI]
        LLM4[其他 LLM...]
    end

    %% 连接关系
    N1 & N2 & N3 & N4 -.->|WS<br/>role:node| WS
    C1 & C2 & C3 & C4 -.->|WS<br/>control| WS
    M1 & M2 & M3 & M4 & M5 & M6 & M7 -->|Inbound| GW
    
    WS --> AUTH
    AUTH --> SCHEMA
    SCHEMA --> ROUTER
    ROUTER --> QUEUE
    QUEUE --> A1 & A2 & A3 & AN
    
    A1 & A2 & A3 & AN <--> TOOLS
    A1 & A2 & A3 & AN <--> SKILLS
    A1 & A2 & A3 & AN <--> HOOKS
    
    A1 & A2 & A3 & AN <-.->|读写| DB
    A1 & A2 & A3 & AN <-.->|读取| AUTH_DB
    A1 & A2 & A3 & AN <-.->|读取| CONFIG
    A1 & A2 & A3 & AN <-.->|读写| WS_DIR
    
    GW <-.->|HTTP| CANVAS
    
    A1 & A2 & A3 & AN <-.->|API 调用| LLM1 & LLM2 & LLM3 & LLM4
    
    GW -->|Outbound| M1 & M2 & M3 & M4 & M5 & M6 & M7

    %% 样式
    classDef nodeClass fill:#E3F2FD,stroke:#1976D2,stroke-width:2px
    classDef clientClass fill:#FFF3E0,stroke:#F57C00,stroke-width:2px
    classDef channelClass fill:#E8F5E9,stroke:#388E3C,stroke-width:2px
    classDef gatewayClass fill:#F3E5F5,stroke:#7B1FA2,stroke-width:3px
    classDef agentClass fill:#FCE4EC,stroke:#C2185B,stroke-width:2px
    classDef storageClass fill:#F5F5F5,stroke:#616161,stroke-width:2px
    classDef llmClass fill:#FFF9C4,stroke:#F9A825,stroke-width:2px
    
    class N1,N2,N3,N4 nodeClass
    class C1,C2,C3,C4 clientClass
    class M1,M2,M3,M4,M5,M6,M7 channelClass
    class GW,WS,AUTH,SCHEMA,ROUTER,QUEUE gatewayClass
    class A1,A2,A3,AN,TOOLS,SKILLS,HOOKS agentClass
    class DB,AUTH_DB,CONFIG,WS_DIR storageClass
    class CANVAS llmClass
    class LLM1,LLM2,LLM3,LLM4 llmClass
\`\`\`

---

## 🔄 数据流与交互流程

### 1. 消息接收与路由流程

\`\`\`mermaid
%%{init: {
  'theme': 'base',
  'themeVariables': {
    'primaryColor': '#ffffff',
    'primaryTextColor': '#000000',
    'primaryBorderColor': '#000000',
    'lineColor': '#000000',
    'secondaryColor': '#f9f9fb',
    'tertiaryColor': '#ffffff',
    'clusterBkg': '#f9f9fb',
    'clusterBorder': '#000000',
    'nodeBorder': '#000000',
    'mainBkg': '#ffffff',
    'edgeLabelBackground': '#ffffff'
  }
}}%%

sequenceDiagram
    participant User as 用户<br/>(WhatsApp/Telegram)
    participant Channel as 消息渠道<br/>(Baileys/grammY)
    participant Gateway as Gateway<br/>守护进程
    participant Router as 路由器<br/>Bindings
    participant Queue as 命令队列<br/>Lane
    participant Agent as 代理运行时<br/>Agent
    participant LLM as 大语言模型<br/>Claude/GPT

    User->>Channel: 📱 发送消息
    Channel->>Gateway: 🔄 转发消息事件
    Gateway->>Router: 🔍 解析路由规则
    
    alt 匹配到 peer 绑定
        Router->>Agent: ✅ 路由到特定代理
    else 匹配到 accountId
        Router->>Agent: ✅ 路由到账号代理
    else 匹配到 channel
        Router->>Agent: ✅ 路由到默认代理
    end
    
    Agent->>Queue: 🎯 加入会话队列
    Queue->>Agent: 🚀 执行（串行化）
    
    Agent->>Agent: 📝 加载上下文<br/>Workspace/Skills
    Agent->>LLM: 💭 推理请求
    
    loop 流式响应
        LLM-->>Agent: 📤 文本增量
        Agent-->>Gateway: 📡 流式事件
        Gateway-->>Channel: 💬 实时更新
        Channel-->>User: 📲 显示响应
    end
    
    alt 需要工具调用
        Agent->>Agent: 🔧 执行工具
        Agent->>Agent: 📊 记录结果
        Agent->>LLM: 💭 继续推理
    end
    
    Agent->>Gateway: ✅ 完成事件
    Gateway->>Channel: 📨 最终回复
    Channel->>User: 📲 消息送达
\`\`\`

---

### 2. 客户端连接生命周期

\`\`\`mermaid
%%{init: {
  'theme': 'base',
  'themeVariables': {
    'primaryColor': '#ffffff',
    'primaryTextColor': '#000000',
    'primaryBorderColor': '#000000',
    'lineColor': '#000000',
    'secondaryColor': '#f9f9fb',
    'tertiaryColor': '#ffffff',
    'clusterBkg': '#f9f9fb',
    'clusterBorder': '#000000',
    'nodeBorder': '#000000',
    'mainBkg': '#ffffff',
    'edgeLabelBackground': '#ffffff'
  }
}}%%

sequenceDiagram
    participant Client as 客户端/节点
    participant Gateway as Gateway
    participant Auth as 认证模块
    participant Pairing as 配对存储

    Client->>Gateway: 🔌 WebSocket 连接
    Client->>Gateway: req:connect<br/>{deviceId, role, auth}
    
    alt Token 认证
        Gateway->>Auth: 🔐 验证 Token
        Auth-->>Gateway: ✅ Token 有效
    else 设备配对
        Gateway->>Pairing: 🔍 查询设备信息
        alt 本地连接 (127.0.0.1)
            Pairing-->>Gateway: ✅ 自动批准
        else 远程连接
            alt 已配对设备
                Pairing-->>Gateway: ✅ 设备令牌有效
            else 新设备
                Gateway->>Client: ⚠️ 需要配对批准
                Gateway->>Pairing: 📝 记录待批准设备
                Client->>Gateway: req:pair<br/>{challenge签名}
                Gateway->>Pairing: ✅ 批准并保存
            end
        end
    end
    
    Gateway-->>Client: res:connect<br/>payload:hello-ok
    Note right of Client: 快照: presence + health
    
    Gateway-->>Client: event:presence
    Gateway-->>Client: event:tick
    
    loop 正常通信
        Client->>Gateway: req:agent / req:send
        Gateway-->>Client: res + events
    end
    
    alt 连接断开
        Client->>Gateway: ❌ close
        Gateway->>Gateway: 🧹 清理资源
    end
\`\`\`

---

### 3. 代理执行循环 (Agent Loop)

\`\`\`mermaid
%%{init: {
  'theme': 'base',
  'themeVariables': {
    'primaryColor': '#E8F4F8',
    'primaryTextColor': '#1a1a1a',
    'primaryBorderColor': '#2C5F7C',
    'lineColor': '#2C5F7C',
    'secondaryColor': '#FFF8E1',
    'tertiaryColor': '#F0F4F8',
    'clusterBkg': '#F9FAFB',
    'clusterBorder': '#4A90A4',
    'fontSize': '13px'
  }
}}%%

flowchart TD
    START([接收消息]) --> VALIDATE{验证参数}
    VALIDATE -->|失败| ERROR1[返回错误]
    VALIDATE -->|成功| RESOLVE[解析会话<br/>sessionKey]
    
    RESOLVE --> QUEUE{加入队列}
    QUEUE --> LOCK[🔒 获取会话锁]
    
    LOCK --> PREPARE[准备运行环境]
    
    subgraph "环境准备"
        PREPARE --> LOAD_WS[加载工作区<br/>Workspace]
        LOAD_WS --> LOAD_SKILLS[加载技能<br/>Skills]
        LOAD_SKILLS --> LOAD_CTX[加载上下文<br/>Bootstrap]
        LOAD_CTX --> BUILD_PROMPT[构建系统提示]
    end
    
    BUILD_PROMPT --> RUN_HOOK1[🪝 before_agent_start]
    RUN_HOOK1 --> INFERENCE[💭 模型推理<br/>pi-agent-core]
    
    subgraph "流式执行"
        INFERENCE --> STREAM_START[📡 lifecycle:start]
        STREAM_START --> LOOP{持续流式}
        
        LOOP -->|文本增量| STREAM_TEXT[📤 assistant delta]
        LOOP -->|工具调用| STREAM_TOOL[🔧 tool event]
        
        STREAM_TOOL --> EXEC_TOOL[执行工具]
        EXEC_TOOL --> TOOL_RESULT[工具结果]
        TOOL_RESULT --> LOOP
        
        STREAM_TEXT --> LOOP
    end
    
    LOOP -->|完成| STREAM_END[📡 lifecycle:end]
    STREAM_END --> RUN_HOOK2[🪝 agent_end]
    
    RUN_HOOK2 --> PERSIST[💾 持久化会话]
    PERSIST --> UNLOCK[🔓 释放会话锁]
    
    UNLOCK --> RETURN[✅ 返回结果]
    
    INFERENCE -.->|超时| TIMEOUT[⏱️ 超时中止]
    TIMEOUT --> STREAM_ERROR[📡 lifecycle:error]
    STREAM_ERROR --> UNLOCK
    
    EXEC_TOOL -.->|失败| TOOL_ERROR[❌ 工具错误]
    TOOL_ERROR --> LOOP

    %% 样式
    classDef startEnd fill:#4CAF50,stroke:#2E7D32,color:#fff,stroke-width:2px
    classDef process fill:#2196F3,stroke:#1565C0,color:#fff,stroke-width:2px
    classDef decision fill:#FF9800,stroke:#E65100,color:#fff,stroke-width:2px
    classDef stream fill:#9C27B0,stroke:#6A1B9A,color:#fff,stroke-width:2px
    classDef error fill:#F44336,stroke:#C62828,color:#fff,stroke-width:2px
    classDef hook fill:#00BCD4,stroke:#00838F,color:#fff,stroke-width:2px
    
    class START,RETURN startEnd
    class RESOLVE,LOCK,PREPARE,LOAD_WS,LOAD_SKILLS,LOAD_CTX,BUILD_PROMPT,PERSIST,UNLOCK process
    class VALIDATE,QUEUE,LOOP decision
    class STREAM_START,STREAM_TEXT,STREAM_TOOL,STREAM_END,STREAM_ERROR stream
    class ERROR1,TIMEOUT,TOOL_ERROR error
    class RUN_HOOK1,RUN_HOOK2 hook
\`\`\`

---

## 🧩 核心组件详解

### 1. Gateway 守护进程

**职责**：
- 维护所有消息渠道连接（WhatsApp, Telegram, Discord...）
- 提供 WebSocket API（18789 端口）
- 验证入站消息帧（JSON Schema）
- 发出系统事件（agent, chat, presence, health, heartbeat, cron）
- 管理设备配对和认证

**协议**：
- 传输：WebSocket（文本帧 + JSON）
- 首帧必须：`connect`
- 请求：`{type:"req", id, method, params}`
- 响应：`{type:"res", id, ok, payload|error}`
- 事件：`{type:"event", event, payload, seq?, stateVersion?}`

**端口**：
- WebSocket：`127.0.0.1:18789`（可配置）
- Canvas：`127.0.0.1:18793`（可配置）

---

### 2. 多代理系统 (Multi-Agent)

**代理隔离**：

每个代理（agentId）拥有：
- ✅ **独立工作区** (`~/.openclaw/workspace-<agentId>`)
- ✅ **独立状态目录** (`~/.openclaw/agents/<agentId>/agent`)
- ✅ **独立会话存储** (`~/.openclaw/agents/<agentId>/sessions`)
- ✅ **独立认证配置** (`auth-profiles.json`)
- ✅ **独立技能目录** (`workspace/skills/`)

**路由规则**（优先级从高到低）：

1. **peer 匹配** - 精确 DM/群组/频道 ID
2. **guildId 匹配** - Discord 服务器 ID
3. **teamId 匹配** - Slack 工作区 ID
4. **accountId 匹配** - 渠道账号 ID
5. **channel 匹配** - 渠道级匹配
6. **默认代理** - 配置的默认代理或列表首项

**典型场景**：

| 场景 | 绑定策略 | 示例 |
|------|----------|------|
| 一个 WhatsApp 号，多人使用 | 按 peer.id（E.164）路由 | `+15551230001` → alex agent<br/>`+15551230002` → mia agent |
| 两个 WhatsApp 号，个人+工作 | 按 accountId 路由 | `personal` → home agent<br/>`biz` → work agent |
| 一个群组专用代理 | 按 peer（群组 ID）路由 | `120363...@g.us` → family agent |
| 跨渠道分流 | 按 channel 路由 | WhatsApp → chat agent<br/>Telegram → opus agent |

---

### 3. 命令队列系统 (Queue)

**目的**：
- 串行化同一会话的运行（防止会话状态冲突）
- 全局队列防止资源争用
- 支持优先级和超时

**队列模式**（消息渠道可配置）：

| 模式 | 行为 | 适用场景 |
|------|------|----------|
| **collect** | 收集后续消息，合并执行 | 快速连续消息 |
| **steer** | 中止当前运行，立即执行新消息 | 用户改变主意 |
| **followup** | 顺序排队执行 | 确保所有消息处理 |

**实现**：
- 每个会话一个 Lane（通道）
- 全局 Lane（可选）
- 使用 Promise + 锁机制

---

### 4. 工具与技能系统

**工具 (Tools)**：

内置工具（部分示例）：
- `exec` - 执行 Shell 命令
- `read/write/edit` - 文件操作
- `browser` - 浏览器自动化
- `canvas` - Canvas 渲染
- `nodes` - 节点设备控制
- `cron` - 定时任务
- `memory_search` - 语义搜索记忆
- `sessions_*` - 会话管理
- `message` - 发送消息

**技能 (Skills)**：

- 技能是打包的工具集合（脚本 + 文档 + 资源）
- 位置：
  - 全局：`~/.openclaw/skills/`
  - 代理：`<workspace>/skills/`
- 技能通过 `SKILL.md` 定义行为
- 代理自动扫描并注入技能提示

**工具权限控制**（per-agent）：

```json5
{
  agents: {
    list: [
      {
        id: "restricted",
        tools: {
          allow: ["read", "sessions_list"],
          deny: ["exec", "write", "browser"]
        }
      }
    ]
  }
}
```

---

### 5. 钩子与插件系统

**内部钩子 (Hooks)**：

事件驱动脚本：
- `agent:bootstrap` - 系统提示构建前
- `/new`, `/reset`, `/stop` - 命令事件
- 其他自定义命令

**插件钩子 (Plugins)**：

生命周期拦截点：
- `before_agent_start` - 运行前注入上下文
- `agent_end` - 运行后检查结果
- `before_tool_call` / `after_tool_call` - 工具拦截
- `tool_result_persist` - 工具结果转换
- `message_received` / `message_sending` / `message_sent` - 消息管道
- `session_start` / `session_end` - 会话生命周期
- `gateway_start` / `gateway_stop` - Gateway 生命周期

---

### 6. 沙箱系统 (Sandbox)

**模式**：
- `off` - 无沙箱（直接主机执行）
- `all` - 所有工具在沙箱中运行
- `exec-only` - 仅 exec 工具沙箱化

**作用域**：
- `shared` - 所有代理共享一个 Docker 容器
- `agent` - 每个代理一个独立容器

**配置示例**：

```json5
{
  agents: {
    list: [
      {
        id: "untrusted",
        sandbox: {
          mode: "all",
          scope: "agent",
          docker: {
            setupCommand: "apt-get update && apt-get install -y git"
          }
        }
      }
    ]
  }
}
```

---

## 🔐 安全与认证

### 认证机制

**Token 认证**：
- 环境变量：`OPENCLAW_GATEWAY_TOKEN`
- 配置文件：`gateway.auth.token`
- 命令行参数：`--token`

**设备配对**：
- 基于设备身份（deviceId）
- 本地连接（127.0.0.1）可自动批准
- 远程连接需要签名挑战（challenge）
- 配对后颁发设备令牌（device token）

**权限控制**：
- 工具白名单/黑名单（per-agent）
- 沙箱隔离（容器级）
- 渠道 allowlist（DM/群组级）

---

## 🗂️ 数据持久化

### 目录结构

\`\`\`
~/.openclaw/
├── openclaw.json              # 主配置文件
├── workspace/                 # 默认工作区（main agent）
│   ├── AGENTS.md
│   ├── SOUL.md
│   ├── USER.md
│   ├── MEMORY.md
│   ├── memory/
│   │   └── YYYY-MM-DD.md
│   └── skills/
├── workspace-<agentId>/       # 其他代理工作区
├── agents/
│   ├── main/
│   │   ├── agent/
│   │   │   ├── auth-profiles.json
│   │   │   └── model-registry.json
│   │   └── sessions/
│   │       └── *.jsonl
│   └── <agentId>/
│       ├── agent/
│       └── sessions/
├── credentials/               # 渠道认证凭证
│   ├── whatsapp/
│   │   ├── personal/
│   │   └── biz/
│   └── telegram/
├── skills/                    # 全局技能
└── canvas/                    # Canvas 文件
\`\`\`

### 会话存储

- 格式：JSONL（每行一条消息）
- 位置：`~/.openclaw/agents/<agentId>/sessions/*.jsonl`
- 字段：
  - `role`: system / user / assistant / tool
  - `content`: 消息内容
  - `timestamp`: 时间戳
  - `metadata`: 元数据（工具调用、使用量等）

---

## 📡 流式与事件

### 事件类型

| 事件类型 | 流 | 说明 |
|---------|-----|------|
| `lifecycle` | lifecycle | 代理运行生命周期（start/end/error）|
| `assistant` | assistant | 文本增量（streaming delta）|
| `tool` | tool | 工具执行事件（start/update/end）|
| `presence` | - | 在线状态变更 |
| `tick` | - | 心跳事件 |
| `compaction` | - | 压缩事件 |

### 流式响应

**文本流**：
- 模型生成的文本增量
- 实时发送到客户端
- 支持 block streaming（按块）

**工具流**：
- 工具开始/更新/结束
- 包含工具名称、参数、结果
- 可配置详细程度（verbose）

---

## 🚀 部署模式

### 单机部署

**典型配置**：
- macOS/Linux 主机
- 本地 Gateway（127.0.0.1:18789）
- macOS App / CLI 客户端
- WhatsApp/Telegram 等渠道

**适用场景**：
- 个人助手
- 开发测试
- 小规模使用

---

### 容器化部署（虚拟员工）

**架构**：
- Docker Compose 编排
- 每个虚拟员工一个容器
- 预构建镜像（含 OpenClaw）
- 环境变量注入配置

**优势**：
- 快速启动（5-10 秒）
- 资源隔离
- 易于扩展
- 适合云服务器

**示例**（本次部署）：
\`\`\`yaml
services:
  operation-agent:
    image: openclaw-agent:v1.4
    environment:
      - OPENCLAW_MODEL=github-copilot/claude-sonnet-4.5
      - OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN}
    command: npx openclaw gateway --allow-unconfigured
\`\`\`

---

### 远程访问

**推荐方式**：

1. **Tailscale VPN**（推荐）
   - 点对点加密
   - 无需公网 IP
   - 自动发现

2. **SSH 隧道**
   \`\`\`bash
   ssh -N -L 18789:127.0.0.1:18789 user@host
   \`\`\`

3. **反向代理 + TLS**
   - Nginx / Caddy
   - Let's Encrypt 证书
   - WebSocket 支持

---

## 🔄 关键流程详解

### 压缩 (Compaction)

**触发条件**：
- 上下文窗口接近限制
- 手动触发 `/compact`

**流程**：
1. 提取会话历史
2. 生成摘要（summary）
3. 替换历史消息
4. 保留最近消息
5. 可选：触发重试（retry）

**事件**：
- `before_compaction` hook
- `compaction` stream event
- `after_compaction` hook

---

### 模型切换与故障转移

**配置**：
\`\`\`json5
{
  agents: {
    list: [
      {
        id: "main",
        model: "github-copilot/claude-sonnet-4.5",
        failover: [
          "anthropic/claude-sonnet-4-5",
          "openai/gpt-4o"
        ]
      }
    ]
  }
}
\`\`\`

**行为**：
- 主模型失败时自动切换
- 按 failover 列表顺序尝试
- 记录切换事件

---

## 📈 性能与优化

### 启动优化（v1.4）

| 指标 | v1.3 | v1.4 | 提升 |
|------|------|------|------|
| 容器启动时间 | 5-10 分钟 | 5-10 秒 | 98% |
| 原因 | 动态安装 OpenClaw | 预构建镜像 | - |
| 镜像大小 | 1GB | 1.5GB | +500MB |

### 并发控制

- **串行化**：同一会话的运行串行执行
- **队列**：全局 Lane 控制总并发
- **超时**：默认 600 秒，可配置

### 内存管理

- **压缩**：自动压缩长会话
- **清理**：定期删除旧会话（session pruning）
- **流式**：增量响应减少内存占用

---

## 🛠️ 运维与监控

### 健康检查

**WebSocket 方式**：
\`\`\`json
{
  "type": "req",
  "id": "health-check",
  "method": "health",
  "params": {}
}
\`\`\`

**响应**：
\`\`\`json
{
  "type": "res",
  "id": "health-check",
  "ok": true,
  "payload": {
    "status": "ok",
    "version": "2026.2.12",
    "uptime": 123456
  }
}
\`\`\`

### 日志

**位置**：
- stdout（前台运行）
- `/tmp/openclaw/openclaw-YYYY-MM-DD.log`

**级别**：
- DEBUG / INFO / WARN / ERROR

### 监控指标

建议监控：
- Gateway 进程状态
- WebSocket 连接数
- 代理运行成功率
- 模型 API 延迟
- 会话队列长度
- 内存/CPU 占用

---

## 🎯 最佳实践

### 多代理配置

1. **明确隔离需求**：不同人/不同场景用不同代理
2. **精确绑定**：peer > account > channel，避免路由冲突
3. **权限最小化**：限制不受信任代理的工具权限
4. **沙箱保护**：公共/家庭代理启用沙箱

### 安全配置

1. **启用 Token 认证**：生产环境必须
2. **使用 VPN**：Tailscale 优于公网暴露
3. **定期轮换凭证**：Token、API key 等
4. **审计日志**：记录敏感操作

### 性能优化

1. **预构建镜像**：容器化部署用预构建镜像
2. **合理压缩**：避免上下文窗口浪费
3. **技能优化**：移除不必要的技能
4. **模型选择**：任务匹配模型（Sonnet vs Opus）

---

## 🔮 架构演进方向

### 已实现（v2026.2.12）

- ✅ WebSocket Gateway 架构
- ✅ 多代理隔离系统
- ✅ 设备配对机制
- ✅ 流式响应
- ✅ 工具与技能系统
- ✅ 钩子与插件
- ✅ 沙箱隔离

### 可能的演进

- 🔄 **分布式 Gateway**：多个 Gateway 负载均衡
- 🔄 **代理间协作**：多代理协同完成任务
- 🔄 **更细粒度权限**：RBAC、策略引擎
- 🔄 **云原生支持**：Kubernetes 编排、服务网格
- 🔄 **AI 编排**：多模型编排、模型路由

---

## 📚 参考资源

- **官方文档**: https://docs.openclaw.ai
- **GitHub**: https://github.com/openclaw/openclaw
- **技能市场**: https://clawhub.com
- **社区**: https://discord.com/invite/clawd

---

**分析完成**  
**版本**: v1.0  
**日期**: 2026-02-14  
**作者**: OpenClaw Assistant
