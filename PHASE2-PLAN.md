# 阶段 2 方案：动态角色管理架构

> 基于阶段 1（去除 Dispatcher，多 Agent 配置化部署）的成果，进行全面架构重构。
> 从分支 `20260302_feat_remove_dispatcher` 拉新分支实施。

---

## 一、原始诉求

| # | 诉求 | 说明 |
|---|------|------|
| 1 | 精简脚本 | 去除 local/ 和 production/ 下的冗余脚本，只保留 5 个核心脚本 |
| 2 | 自定义角色 | 放弃预设的 5 个固定角色，改为完全自定义。基于 openclaw 原有的 5 个 .md 文件，采用"在原有基础上追加"的方式 |
| 3 | SQLite + 交互式管理脚本 | 角色定义存储在 SQLite 中，提供交互式脚本支持新增/删除角色。新增后自动注册 Gateway、自动构建并启动容器 |
| 4 | 首次启动无 Agent | 服务首次启动时是空的，所有 Agent 通过管理脚本添加。同名角色支持更新（需确认提示） |
| 5 | workspace 持久化 | 容器重建不丢失 memory（记忆），设计合理的 workspace 管理方案 |

---

## 二、遗漏分析

### 诉求本身需要补充的点

| 诉求 | 遗漏 / 需要补充 |
|------|-----------------|
| 1. 精简脚本 | local/ 和 production/ 是否合并为统一脚本目录？scripts/ 下 12 个旧脚本如何处理？ |
| 2. 自定义角色 | 角色名的合法字符规则（用于容器名、URL 路径、环境变量前缀）；是否支持中文角色名 |
| 3. SQLite + 管理脚本 | Gateway 如何"热感知"新角色（重启 vs 信号 vs API）；docker-compose 是静态的，如何动态管理容器；端口分配策略 |
| 4. 首次启动无 Agent | Gateway 在无 Agent 时的行为（健康检查返回什么？）；管理入口是 Web 界面还是纯 CLI |
| 5. workspace 持久化 | 持久化的范围（memory? 对话历史? AGENTS.md 修改?）；更新角色时持久化数据如何处理；备份/恢复策略 |

### 额外遗漏的 6 个问题

| # | 遗漏点 | 说明 |
|---|--------|------|
| A | docker-compose 静态 vs 动态 | 现在 docker-compose.yml 里硬编码 5 个 service，动态角色场景下不能继续用静态 compose。方案：放弃 compose 管理 agent 容器，改用 `docker run` 直接管理 |
| B | 端口冲突检测 | 动态分配端口需要检测宿主机端口是否被占用 |
| C | 角色删除的清理 | 删除角色时需要：停容器 → 删容器 → 删镜像 → 清理 Gateway 注册 → 可选删除持久化数据 |
| D | Gateway 重启后的角色恢复 | Gateway 重启时需要从 SQLite 重新加载所有角色，而不是从环境变量。这是架构范式的根本转变 |
| E | 角色定义文件的默认内容 | openclaw 原生的 AGENTS.md / SOUL.md 等有默认内容，用户要"在此基础上追加"。需要把默认内容存储在代码仓库中作为模板 |
| F | 多机部署 / 迁移 | SQLite 是单机的，迁移到新服务器需要考虑 SQLite + 持久化数据的导出/导入 |

---

## 三、整体架构

```
┌────────────────────────────────────────────────────────────────────┐
│                          宿主机                                    │
│                                                                    │
│  ┌──────────────────────────────────┐                              │
│  │      Gateway (Flask :8000)       │                              │
│  │                                  │                              │
│  │  /{role}/wecom/callback ─────────┼──► 动态路由表（从 SQLite）   │
│  │  /admin/agents (管理 API)        │                              │
│  │                                  │                              │
│  │  SQLite: gateway.db              │                              │
│  │   ├─ agents 表（角色注册信息）    │                              │
│  │   ├─ agent_files 表（角色定义）   │                              │
│  │   ├─ sessions 表                 │                              │
│  │   └─ message_queue 表            │                              │
│  └──────────┬───────────────────────┘                              │
│             │                                                      │
│  ┌──────────▼───────────────────────┐                              │
│  │    manage-agent.sh (管理脚本)     │                              │
│  │                                  │                              │
│  │  add <name>     → 交互式创建角色  │                              │
│  │  remove <name>  → 删除角色        │                              │
│  │  list           → 列出所有角色    │                              │
│  │  update <name>  → 更新角色定义    │                              │
│  │  status         → 查看容器状态    │                              │
│  └──────────────────────────────────┘                              │
│                                                                    │
│  /opt/openclaw/                                                    │
│   ├─ data/gateway/gateway.db          ← Gateway 数据库             │
│   ├─ data/agents/{role}/              ← 角色持久化数据             │
│   │   ├─ workspace/                   ← workspace 持久化           │
│   │   │   ├─ memory/                  ← 对话记忆                   │
│   │   │   ├─ MEMORY.md               ← 长期记忆                   │
│   │   │   └─ shared-files/            ← 共享文件                   │
│   │   └─ agents/                      ← openclaw 配置数据          │
│   └─ shared-files/                    ← 全局共享文件               │
│                                                                    │
│  Docker 容器（每个角色一个，docker run 管理）                       │
│  ┌─────────────────────┐  ┌─────────────────────┐                  │
│  │ openclaw-agent-XXX  │  │ openclaw-agent-YYY  │  ...             │
│  │  :自动分配端口→18789│  │  :自动分配端口→18789│                  │
│  │                     │  │                     │                  │
│  │  volumes:           │  │  volumes:           │                  │
│  │  宿主data→容器wksp  │  │  宿主data→容器wksp  │                  │
│  └─────────────────────┘  └─────────────────────┘                  │
└────────────────────────────────────────────────────────────────────┘
```

---

## 四、SQLite 表设计

### agents 表

```sql
CREATE TABLE agents (
    name            TEXT PRIMARY KEY,          -- 角色名（英文小写，如 'developer'）
    display_name    TEXT NOT NULL,             -- 显示名（中文，如 '开发工程师'）
    port            INTEGER NOT NULL UNIQUE,   -- 宿主机映射端口
    wecom_token     TEXT NOT NULL,             -- 企业微信 Token
    wecom_aes_key   TEXT NOT NULL,             -- 企业微信 EncodingAESKey
    container_name  TEXT NOT NULL,             -- Docker 容器名
    image_name      TEXT NOT NULL,             -- Docker 镜像名
    status          TEXT DEFAULT 'stopped',    -- running / stopped / building / error
    created_at      TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at      TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### agent_files 表

```sql
CREATE TABLE agent_files (
    agent_name  TEXT NOT NULL,
    filename    TEXT NOT NULL,             -- AGENTS.md / IDENTITY.md / SOUL.md / TOOLS.md / USER.md
    content     TEXT NOT NULL,             -- 文件内容
    PRIMARY KEY (agent_name, filename),
    FOREIGN KEY (agent_name) REFERENCES agents(name) ON DELETE CASCADE
);
```

---

## 五、角色创建流程

`./manage-agent.sh add my-developer` 执行步骤：

```
1. 交互式输入
   ├─ 显示名: "开发工程师小明"
   ├─ 企业微信 Token: xxx
   ├─ 企业微信 AES Key: xxx
   └─ 角色定义文件:
       ├─ IDENTITY.md  (打开编辑器，预填模板)
       ├─ SOUL.md      (打开编辑器，预填模板)
       ├─ AGENTS.md    (使用默认，可选编辑)
       ├─ TOOLS.md     (使用默认，可选编辑)
       └─ USER.md      (打开编辑器，预填模板)

2. 写入 SQLite
   ├─ agents 表插入记录
   └─ agent_files 表插入 5 个文件

3. 自动分配端口
   └─ 从 19001 开始，找第一个未使用的端口

4. 构建 Docker 镜像
   ├─ 从 SQLite 读取角色定义文件
   ├─ 写入临时目录 /tmp/openclaw-build-{name}/workspace/
   ├─ docker build -t openclaw-agent-{name}:latest
   └─ 清理临时目录

5. 启动容器
   ├─ docker run -d --name openclaw-agent-{name} \
   │     -p {port}:18789 \
   │     -v /opt/openclaw/data/agents/{name}/workspace/memory:/root/.openclaw/workspace/memory \
   │     -v /opt/openclaw/data/agents/{name}/workspace/MEMORY.md:/root/.openclaw/workspace/MEMORY.md \
   │     -v /opt/openclaw/shared-files:/root/.openclaw/workspace/shared-files:ro \
   │     -e API_BASE_URL=... -e API_KEY=... \
   │     --network openclaw-network \
   │     --restart unless-stopped \
   │     openclaw-agent-{name}:latest
   └─ 更新 agents 表 status = 'running'

6. 通知 Gateway 重载
   └─ curl -X POST http://localhost:8000/admin/reload
```

---

## 六、workspace 持久化方案

### 容器内目录结构

```
容器内 /root/.openclaw/
├── workspace/                      ← WORKDIR
│   ├── AGENTS.md                   ← 镜像内预置（不持久化，重建用最新版）
│   ├── IDENTITY.md                 ← 镜像内预置（只读，不持久化）
│   ├── SOUL.md                     ← 镜像内预置（不持久化）
│   ├── TOOLS.md                    ← 镜像内预置（不持久化）
│   ├── USER.md                     ← 镜像内预置（不持久化）
│   ├── MEMORY.md                   ← ★ 持久化（挂载文件）
│   ├── memory/                     ← ★ 持久化（挂载目录）
│   │   ├── 2026-03-01.md
│   │   └── 2026-03-02.md
│   └── shared-files/               ← ★ 持久化（全局共享，只读）
└── agents/                         ← openclaw 内部配置
    └── main/agent/                 ← 不持久化（CMD 启动时动态生成）
```

### 持久化策略（三层）

| 层级 | 内容 | 策略 | 理由 |
|------|------|------|------|
| 角色定义 | 5 个 .md 文件 | 存 SQLite，构建到镜像 | 更新需重建镜像，保证一致性 |
| 记忆数据 | memory/ + MEMORY.md | volume 挂载到宿主机 | AI 运行时写入，容器重建不丢失 |
| 共享文件 | shared-files/ | volume 挂载（只读） | 跨角色共享 |
| openclaw 配置 | agents/ | 不持久化 | CMD 启动时动态生成 |

### 更新角色时的行为

- 角色定义文件更新 → 重新 build 镜像 → 重建容器 → **记忆数据保留**（因为是 volume 挂载）
- 等效于：换了"知识/性格"，但保留了"记忆"

---

## 七、Gateway 改造要点

### 从环境变量加载 → 从 SQLite 加载

```python
# 之前：硬编码角色名，从环境变量加载
KNOWN_ROLES = ['operation', 'product', 'development', 'testing', 'service']
def load_agents_from_env(): ...

# 之后：完全动态，从 SQLite 加载
def load_agents_from_db():
    """从 SQLite 读取所有已注册的 agent"""
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        "SELECT name, port, wecom_token, wecom_aes_key, container_name "
        "FROM agents WHERE status != 'removed'"
    ).fetchall()
    agents = {}
    for name, port, token, aes_key, container in rows:
        agents[name] = {
            'wecom_token': token,
            'wecom_encoding_aes_key': aes_key,
            'port': port,
            'url': f'http://localhost:{port}',
            'container': container,
        }
    conn.close()
    return agents
```

### 新增管理 API

```python
@app.route('/admin/reload', methods=['POST'])
def admin_reload():
    """重新从 SQLite 加载 agent 列表（管理脚本调用）"""
    global AGENTS
    AGENTS = load_agents_from_db()
    return jsonify({'status': 'ok', 'agents': list(AGENTS.keys())})

@app.route('/admin/agents', methods=['GET'])
def admin_list_agents():
    """列出所有注册的 agent"""
    return jsonify({'agents': [...]})
```

### 无 Agent 时的行为

- Gateway 正常启动，`/health` 返回 `{"status": "ok", "agents": 0}`
- 访问任何 `/{role}/wecom/callback` 返回 404
- `/wecom/callback` 旧兼容路由返回提示"请先添加 Agent"

---

## 八、精简后的目录结构

```
openclaw-deploy/
├── scripts/
│   ├── 0-prepare.sh              ← 环境准备（安装 Docker/Python/Node/openclaw）
│   ├── 1-upload.sh               ← 上传代码到服务器（rsync）
│   ├── 2-build.sh                ← 构建 base 镜像 + Gateway 启动
│   ├── 3-deploy.sh               ← 启动 Gateway + 从 SQLite 恢复已注册的 Agent
│   ├── 4-clean.sh                ← 停止所有服务 + 可选清理数据
│   └── manage-agent.sh           ← ★ 角色管理（add/remove/update/list/status）
├── templates/                    ← 角色定义模板文件
│   ├── AGENTS.md.default         ← openclaw 默认 + 追加内容
│   ├── IDENTITY.md.template      ← 模板（需要填写名字/性格等）
│   ├── SOUL.md.template
│   ├── TOOLS.md.default
│   └── USER.md.template
├── src/gateway/                  ← Gateway 源码
│   ├── wecom_gateway.py
│   ├── requirements.txt
│   └── Dockerfile.gateway
├── config/
│   ├── Dockerfile.base
│   └── Dockerfile.agents         ← 改造：不再依赖固定角色目录
├── .env.example                  ← 统一的环境变量示例
├── PHASE2-PLAN.md                ← 本文档
└── AGENTS.md                     ← AI 编码助手指南

删除：
├── local/                        ← 合并到 scripts/
├── production/                   ← 合并到 scripts/
├── scripts/ (旧的 12 个脚本)      ← 全部删除
└── config/agents/workspace/      ← 不再需要（角色定义存 SQLite）
```

### 关键变化

- `local/` 和 `production/` 合并为 `scripts/`，通过 `.env` 文件区分环境
- 旧 `scripts/` 下 12 个脚本全部删除
- 新增 `manage-agent.sh` 作为核心角色管理入口
- 新增 `templates/` 存放角色定义模板
- `config/agents/workspace/` 不再需要（角色定义从 SQLite 动态读取）

---

## 九、Dockerfile.agents 改造

```dockerfile
FROM openclaw-base:latest

# 不再依赖 config/agents/workspace/{ROLE}/
# 改为从构建上下文的临时目录读取
COPY workspace/ /root/.openclaw/workspace/

RUN chmod 444 /root/.openclaw/workspace/IDENTITY.md

WORKDIR /root/.openclaw/workspace
EXPOSE 18789

# CMD 保持不变（动态生成 openclaw 配置后启动 gateway）
CMD ["sh", "-c", "\
  mkdir -p /root/.openclaw/agents/main/agent && \
  ...（与现有相同）... && \
  npx openclaw gateway --allow-unconfigured --bind lan"]
```

构建方式变更：

```bash
# manage-agent.sh 准备临时构建上下文
mkdir -p /tmp/openclaw-build-{name}/workspace/
# 从 SQLite 导出 5 个 .md 文件到 workspace/
# 复制 Dockerfile.agents 到构建上下文
docker build -t openclaw-agent-{name}:latest /tmp/openclaw-build-{name}/
rm -rf /tmp/openclaw-build-{name}/
```

---

## 十、待确认的决策点

| # | 决策点 | 建议 |
|---|--------|------|
| 1 | local/ 和 production/ 是否合并？ | 合并为 scripts/，通过 .env 文件区分环境 |
| 2 | 角色名规则？ | 英文小写 + 数字 + 连字符，3-30 字符，如 `my-developer` |
| 3 | 端口分配策略？ | 自动分配，从 19001 起步，也支持手动指定 |
| 4 | Gateway 热加载方式？ | 管理脚本调用 `/admin/reload` API，Gateway 不需要重启 |
| 5 | 放弃 docker-compose 管理 agent？ | 是，改用 `docker run`，仅保留网络创建 |
| 6 | 更新角色时保留 memory？ | 默认保留，提供选项可清空 |
| 7 | 管理脚本用 Python 还是 Bash？ | Python（需要操作 SQLite，逻辑较复杂） |
| 8 | /admin/ API 需要鉴权吗？ | 用 OPENCLAW_INTERNAL_TOKEN 做简单 Bearer 认证 |

---

## 十一、实施计划（预估）

| 步骤 | 内容 | 依赖 |
|------|------|------|
| 1 | 从 `20260302_feat_remove_dispatcher` 拉新分支 | 决策点确认后开始 |
| 2 | 创建 templates/ 目录和模板文件 | 无 |
| 3 | 改造 Gateway：SQLite 加载 + 管理 API | 表结构确认 |
| 4 | 编写 manage-agent.sh (Python) | Gateway API 就绪 |
| 5 | 改造 Dockerfile.agents | 无 |
| 6 | 编写 scripts/ 下 5 个核心脚本 | 目录结构确认 |
| 7 | 清理旧文件（local/ production/ 旧 scripts/） | 新脚本就绪 |
| 8 | 更新文档 | 全部完成后 |

---

**创建日期**: 2026-03-02
**状态**: 待确认决策点后进入实施
