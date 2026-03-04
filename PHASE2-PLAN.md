# 阶段 2 方案：企业微信桥接器 + 动态 Agent 绑定

> **核心转变**：Gateway 不再管理 openclaw 的部署/容器/镜像，退化为纯粹的"企业微信 <-> openclaw 桥接器"。
> openclaw 怎么部署、跑在哪里，完全不关心。Gateway 只需要知道 openclaw 的地址和 token。
>
> 分支：`20260302_feat_wecom_bridging`（基于 `20260302_feat_remove_dispatcher`）

---

## 一、诉求

| # | 诉求 |
|---|------|
| 1 | Gateway 仅做企业微信桥接，不管理 openclaw |
| 2 | 支持单 openclaw 实例多 agent + 多实例多 agent + 混合模式 |
| 3 | 一个 agent 对接一个企业微信机器人（一对一绑定） |
| 4 | session 按企业微信消息来源的 userId 隔离 |
| 5 | 使用 SQLite 做 agent 与企业微信机器人的绑定关系 |
| 6 | 提供 Python 管理脚本：新增/删除绑定 |
| 7 | 首次启动时无 agent，全部通过管理脚本添加 |

---

## 二、架构

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Gateway（Flask :8000）                          │
│                     纯企业微信桥接器，不管理 openclaw                │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐      │
│  │  SQLite: gateway.db                                       │      │
│  │   └─ agents 表（agent ↔ 企业微信机器人 绑定关系）          │      │
│  └───────────────────────────────────────────────────────────┘      │
│                                                                     │
│  路由: /{agent_name}/wecom/callback                                 │
│                                                                     │
│  收到企业微信消息后:                                                 │
│   1. 从 SQLite 查 agent_name → openclaw_url, token, agent_id       │
│   2. 解密企业微信消息 → user_id, content                            │
│   3. 调用 openclaw（WS/SSE/HTTP）                                   │
│   4. 把回复发回企业微信                                              │
└──────────┬──────────────────────────┬───────────────────────────────┘
           │                          │
           ▼                          ▼
  openclaw 实例 A                openclaw 实例 B
  (url_a, token_a)              (url_b, token_b)
  ┌──────────────┐              ┌──────────────┐
  │ agent: main  │              │ agent: main  │
  │ agent: dev   │              └──────────────┘
  │ agent: ops   │
  └──────────────┘
```

### 三种部署模式自动兼容

```
模式 A：单实例多 agent
══════════════════════════════════════════════════════
  企业微信A ──► /{dev}/wecom/callback   ──┐
  企业微信B ──► /{ops}/wecom/callback   ──┼──► 同一个 openclaw
  企业微信C ──► /{svc}/wecom/callback   ──┘    agent_id 不同

  agents 表:
  name  │ openclaw_url              │ openclaw_token │ openclaw_agent_id
  ──────┼───────────────────────────┼────────────────┼──────────────────
  dev   │ http://10.0.1.5:18789    │ secret-abc     │ dev
  ops   │ http://10.0.1.5:18789    │ secret-abc     │ ops
  svc   │ http://10.0.1.5:18789    │ secret-abc     │ svc


模式 B：多实例各一个 agent
══════════════════════════════════════════════════════
  企业微信A ──► /{dev}/wecom/callback   ──► openclaw 实例 1
  企业微信B ──► /{ops}/wecom/callback   ──► openclaw 实例 2

  agents 表:
  name  │ openclaw_url              │ openclaw_token │ openclaw_agent_id
  ──────┼───────────────────────────┼────────────────┼──────────────────
  dev   │ http://10.0.1.5:18789    │ secret-abc     │ (空，默认 main)
  ops   │ http://10.0.1.6:18789    │ secret-xyz     │ (空，默认 main)


模式 C：混合
══════════════════════════════════════════════════════
  企业微信A ──► /{dev}/wecom/callback   ──┐
  企业微信B ──► /{ops}/wecom/callback   ──┼──► openclaw 实例 1
  企业微信C ──► /{svc}/wecom/callback   ──────► openclaw 实例 2

  agents 表:
  name  │ openclaw_url              │ openclaw_token │ openclaw_agent_id
  ──────┼───────────────────────────┼────────────────┼──────────────────
  dev   │ http://10.0.1.5:18789    │ secret-abc     │ dev
  ops   │ http://10.0.1.5:18789    │ secret-abc     │ ops
  svc   │ http://10.0.1.6:18789    │ secret-xyz     │ (空，默认 main)
```

---

## 三、SQLite 表设计

```sql
CREATE TABLE agents (
    name              TEXT PRIMARY KEY,          -- 路由名，URL路径标识（如 'dev'）
    display_name      TEXT NOT NULL,             -- 显示名（如 '开发工程师小明'）
    wecom_token       TEXT NOT NULL,             -- 企业微信 Token
    wecom_aes_key     TEXT NOT NULL,             -- 企业微信 EncodingAESKey
    openclaw_url      TEXT NOT NULL,             -- openclaw 地址（如 http://10.0.1.5:18789）
    openclaw_token    TEXT NOT NULL,             -- openclaw 认证 token
    openclaw_agent_id TEXT DEFAULT '',           -- openclaw agent id（空 = 默认 main）
    created_at        TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at        TEXT DEFAULT CURRENT_TIMESTAMP
);
```

**字段说明：**

| 字段 | 必填 | 说明 |
|------|------|------|
| `name` | 是 | 路由标识，用于 URL 路径 `/{name}/wecom/callback`。英文小写+数字+连字符，3-30 字符 |
| `display_name` | 是 | 中文显示名，管理/日志用 |
| `wecom_token` | 是 | 对应的企业微信机器人 Token |
| `wecom_aes_key` | 是 | 对应的企业微信机器人 EncodingAESKey |
| `openclaw_url` | 是 | 该 agent 连接的 openclaw 地址 |
| `openclaw_token` | 是 | 该 openclaw 的认证 token |
| `openclaw_agent_id` | 否 | 在 openclaw 中的 agent id，空串表示使用默认 main agent |

---

## 四、Gateway 改造要点

### 从环境变量加载 → 从 SQLite 加载

```python
# 之前
KNOWN_ROLES = ['operation', 'product', 'development', 'testing', 'service']
DEFAULT_PORTS = {...}
def load_agents_from_env(): ...

# 之后
def load_agents_from_db():
    """从 SQLite 加载所有 agent 绑定"""
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        "SELECT name, display_name, wecom_token, wecom_aes_key, "
        "openclaw_url, openclaw_token, openclaw_agent_id FROM agents"
    ).fetchall()
    agents = {}
    for name, display, token, aes_key, url, oc_token, agent_id in rows:
        agents[name] = {
            'display_name': display,
            'wecom_token': token,
            'wecom_encoding_aes_key': aes_key,
            'openclaw_url': url,
            'openclaw_token': oc_token,
            'openclaw_agent_id': agent_id or 'main',
        }
    conn.close()
    return agents
```

### 调用 openclaw 时传递 agent_id

```python
# HTTP/SSE 调用
headers = {
    'Authorization': f'Bearer {agent_cfg["openclaw_token"]}',
    'Content-Type': 'application/json',
    'x-openclaw-agent-id': agent_cfg['openclaw_agent_id'],
}

# WS 调用 — sessionKey 中包含 agent 信息
session_key = f"wecom:{user_id}"  # openclaw 侧由 agent_id 路由，session 按 user 隔离
```

### 删除的代码/概念

| 删除 | 说明 |
|------|------|
| `KNOWN_ROLES` | 不再有硬编码角色 |
| `DEFAULT_PORTS` | 不再管理端口 |
| `OPENCLAW_INTERNAL_TOKEN` 全局变量 | 每个 agent 有独立的 token |
| `OPENCLAW_PROTOCOL` 全局变量 | 保留但改为每 agent 可配（或全局默认） |
| `container` 参数 / exec 协议 | 不再管理容器，去掉 exec 协议 |
| `_call_openclaw_exec()` | 不再需要 |

### 新增管理 API

```python
@app.route('/admin/reload', methods=['POST'])
def admin_reload():
    """重新从 SQLite 加载绑定关系（管理脚本调用）"""
    global AGENTS
    AGENTS = load_agents_from_db()
    return jsonify({'status': 'ok', 'agents': list(AGENTS.keys())})

@app.route('/admin/agents', methods=['GET'])
def admin_list_agents():
    """列出所有绑定"""
    return jsonify({'agents': {name: cfg['display_name'] for name, cfg in AGENTS.items()}})
```

### 无 Agent 时的行为

- Gateway 正常启动，`/health` 返回 `{"status": "ok", "agents": 0}`
- 访问 `/{name}/wecom/callback` 返回 404
- 旧兼容路由 `/wecom/callback` 返回提示"请先通过管理脚本添加 agent"

### session key 构造

```python
# 隔离维度: agent_name + user_id
session_key = f"wecom:{agent_name}:{user_id}"
```

openclaw 侧通过 `x-openclaw-agent-id` header 路由到正确的 agent，
session 通过 `user` 字段（HTTP）或 `sessionKey`（WS）按企业微信用户隔离。

---

## 五、管理脚本（Python）

### 脚本: `scripts/manage-agent.py`

```
用法:
  python3 manage-agent.py add <name>       交互式添加 agent-企业微信绑定
  python3 manage-agent.py remove <name>    删除绑定（需确认）
  python3 manage-agent.py list             列出所有绑定
  python3 manage-agent.py update <name>    更新绑定（同名覆盖，需确认）
```

### add 流程

```
$ python3 manage-agent.py add dev

agent 路由名: dev
显示名: 开发工程师小明
企业微信 Token: xxxxxx
企业微信 AES Key: yyyyyy
openclaw 地址: http://10.0.1.5:18789
openclaw Token: secret-abc
openclaw Agent ID (回车跳过，默认 main):

确认添加？
  路由名:     dev
  显示名:     开发工程师小明
  企业微信:   Token=xxxx... AESKey=yyyy...
  openclaw:   http://10.0.1.5:18789 (agent: main)

[Y/n] y
✅ 已添加。企业微信回调地址: https://your-domain/dev/wecom/callback
✅ 已通知 Gateway 重载。
```

### remove 流程

```
$ python3 manage-agent.py remove dev

即将删除:
  路由名: dev (开发工程师小明)
  企业微信: Token=xxxx...
  openclaw: http://10.0.1.5:18789 (agent: main)

⚠️  确认删除？此操作不可恢复。[y/N] y
✅ 已删除。
✅ 已通知 Gateway 重载。
```

### update 流程

```
$ python3 manage-agent.py update dev

当前配置:
  显示名:     开发工程师小明
  企业微信:   Token=xxxx... AESKey=yyyy...
  openclaw:   http://10.0.1.5:18789 (agent: main)

输入新值（回车保持不变）:
显示名 [开发工程师小明]:
企业微信 Token [xxxx...]:
企业微信 AES Key [yyyy...]:
openclaw 地址 [http://10.0.1.5:18789]:
openclaw Token [secret-abc]:
openclaw Agent ID [main]: dev

确认更新？[Y/n] y
✅ 已更新。
✅ 已通知 Gateway 重载。
```

---

## 六、精简后的目录结构

```
openclaw-deploy/
├── src/gateway/
│   ├── wecom_gateway.py          ← Gateway 主程序（大幅精简）
│   └── requirements.txt          ← Python 依赖（flask, requests, pycryptodome, websocket-client）
├── scripts/
│   └── manage-agent.py           ← ★ agent-企业微信绑定管理
├── .env.example                  ← 环境变量示例（仅 Gateway 自身配置）
├── PHASE2-PLAN.md                ← 本文档
└── AGENTS.md                     ← AI 编码助手指南

删除:
├── config/Dockerfile.base        ← 不再构建镜像
├── config/Dockerfile.agents      ← 不再构建镜像
├── config/docker-compose.*       ← 不再编排容器
├── config/agents/workspace/      ← 不再管理角色定义
├── local/                        ← 不再需要本地环境脚本
├── production/                   ← 不再需要生产部署脚本
├── scripts/ (旧的 12 个脚本)      ← 全部删除
└── docs/                         ← 需要重写（大部分失效）
```

### .env.example 精简

```bash
# Gateway 自身配置
DB_PATH=/opt/openclaw/data/gateway/gateway.db
GATEWAY_PORT=8000

# 通信协议（全局默认，可被每个 agent 覆盖）
OPENCLAW_PROTOCOL=ws
OPENCLAW_TIMEOUT=2700
```

不再需要:
- `AGENT_*_ENABLE` / `AGENT_*_WECOM_TOKEN` 等环境变量（全部改为 SQLite）
- `OPENCLAW_INTERNAL_TOKEN`（每个 agent 独立 token）
- `OPENAI_API_KEY` / `API_BASE_URL` 等（openclaw 侧的事，Gateway 不关心）

---

## 七、Gateway 代码删减清单

| 删除 | 文件/函数 | 原因 |
|------|-----------|------|
| `KNOWN_ROLES` / `DEFAULT_PORTS` | wecom_gateway.py:42-44 | 不再硬编码 |
| `load_agents_from_env()` | wecom_gateway.py:47-63 | 改为 `load_agents_from_db()` |
| `validate_agents()` | wecom_gateway.py:66-80 | 校验逻辑简化 |
| `_call_openclaw_exec()` | wecom_gateway.py:158-196 | 不再管理容器 |
| `OPENCLAW_INTERNAL_TOKEN` | wecom_gateway.py:37 | 每 agent 独立 token |
| `container` 参数 | 多处 | 不再管理容器 |
| 文件操作相关路由 | 如 `/files/*` | 不再管理 workspace |

---

## 八、消息处理流程

```
企业微信用户发消息
       │
       ▼
GET/POST /{agent_name}/wecom/callback
       │
       ├─ AGENTS 字典查找 agent_name
       │  (未找到 → 404)
       │
       ├─ 用该 agent 的 wecom_token + wecom_aes_key 解密/验签
       │
       ├─ 提取 user_id, content
       │
       ├─ 构造 session_key = f"wecom:{agent_name}:{user_id}"
       │
       ├─ 调用 openclaw:
       │   URL:    agent_cfg['openclaw_url']
       │   Token:  agent_cfg['openclaw_token']
       │   Agent:  agent_cfg['openclaw_agent_id']  (默认 'main')
       │   Session: session_key
       │
       ├─ 收到回复
       │
       └─ 通过企业微信 response_url 回复用户
```

---

## 九、已确认的决策

| 决策 | 结论 |
|------|------|
| Gateway 是否管理 openclaw | **否**，纯桥接 |
| 单实例 vs 多实例 | **都支持**，由 SQLite 绑定关系决定 |
| agent_id 是否必填 | **否**，不配置默认为 main |
| session 隔离方式 | `agent_name + user_id` |
| 绑定关系存储 | SQLite |
| 管理脚本语言 | Python |
| exec 协议 | **删除**（不再管理容器） |
| Docker 相关代码 | **全部删除** |

---

## 十、实施计划

| # | 步骤 | 说明 |
|---|------|------|
| 1 | 改造 Gateway | 删除容器/镜像管理代码，SQLite 加载绑定，per-agent token/url |
| 2 | 编写 manage-agent.py | 交互式 add/remove/update/list |
| 3 | 清理旧文件 | config/ local/ production/ 旧 scripts/ docs/ |
| 4 | 更新 .env.example | 仅保留 Gateway 自身配置 |
| 5 | 更新 AGENTS.md | 适配新架构 |
| 6 | 测试 | 本地验证桥接 + 管理脚本 |

---

**创建日期**: 2026-03-02
**分支**: `20260302_feat_wecom_bridging`
**状态**: 方案已确认，待实施
