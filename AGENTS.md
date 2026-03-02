# AGENTS.md - OpenClaw 企业微信桥接网关代码指南

> 本文档为 AI 编码助手提供项目开发规范和常用命令

## 项目概览

**项目名称**: OpenClaw 企业微信桥接网关  
**技术栈**: Python 3.13, Flask 3.0, SQLite, WebSocket  
**架构**: 纯桥接模式 — Gateway 仅做企业微信与 openclaw 之间的消息转发，不管理 openclaw 的部署/容器/镜像

### 核心概念
- **Gateway** (`src/gateway/wecom_gateway.py`): 企业微信消息桥接器
- **Agent 绑定**: 每个 agent 对接一个企业微信机器人，绑定关系存储在 SQLite
- **通信协议**: WS / SSE / HTTP（默认 WS）
- **管理工具**: `scripts/manage-agent.py` 管理 agent-企业微信绑定

### 三种部署模式（自动兼容）
- **模式 A**: 单 openclaw 实例 + 多 agent（同 URL/Token，不同 agent_id）
- **模式 B**: 多 openclaw 实例（不同 URL/Token，各自默认 main agent）
- **模式 C**: 混合模式

---

## 快速开始

### 安装依赖
```bash
pip3 install -r src/gateway/requirements.txt
```

### 启动 Gateway
```bash
# 复制环境变量
cp .env.example .env
# 编辑 .env 配置 DB_PATH 等

# 启动
python3 src/gateway/wecom_gateway.py
```

### 添加 Agent 绑定
```bash
python3 scripts/manage-agent.py add dev
python3 scripts/manage-agent.py list
```

### 健康检查
```bash
curl http://localhost:8000/health
curl http://localhost:8000/admin/agents
```

---

## Agent 管理

```bash
# 添加 agent（交互式）
python3 scripts/manage-agent.py add <name>

# 列出所有 agent
python3 scripts/manage-agent.py list

# 更新 agent（交互式，回车保持不变）
python3 scripts/manage-agent.py update <name>

# 删除 agent（需确认）
python3 scripts/manage-agent.py remove <name>
```

添加后，企业微信回调地址为: `https://your-domain/{name}/wecom/callback`

---

## 项目结构

```
openclaw-deploy/
├── src/gateway/
│   ├── wecom_gateway.py      # Gateway 主程序
│   └── requirements.txt      # Python 依赖
├── scripts/
│   └── manage-agent.py       # Agent 绑定管理工具
├── .env.example              # 环境变量示例
├── AGENTS.md                 # 本文档
└── PHASE2-PLAN.md            # 架构方案文档
```

---

## 依赖

```bash
pip3 install -r src/gateway/requirements.txt

# 主要依赖
flask==3.0.0
requests==2.31.0
pycryptodome==3.19.0
websocket-client==1.8.0
```

---

## 代码风格指南

### 导入顺序
```python
# 标准库
import os
import json
import logging
from datetime import datetime

# 第三方库
from flask import Flask, request, jsonify
import requests
```

### 命名约定
- **文件名**: 小写下划线 `wecom_gateway.py`
- **类名**: 大驼峰 `WXBizMsgCrypt`
- **函数名**: 小写下划线 `_call_openclaw_ws()`, `load_agents_from_db()`
- **常量**: 全大写 `OPENCLAW_TIMEOUT`, `DB_PATH`
- **私有方法**: 下划线前缀 `_extract_reply_text()`

### 日志规范
```python
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

logger.info("服务启动成功")
logger.warning(f"WS 调用失败: {e}，尝试重试")
logger.error(f"数据库连接失败: {e}")
```

### 环境变量管理
```python
# 从环境变量读取配置，提供默认值
DB_PATH = os.getenv('DB_PATH', '/opt/openclaw/data/gateway/gateway.db')
OPENCLAW_TIMEOUT = int(os.getenv('OPENCLAW_TIMEOUT', '2700'))
OPENCLAW_PROTOCOL = os.getenv('OPENCLAW_PROTOCOL', 'ws')
```

---

## 环境变量

仅 Gateway 自身运行参数（见 `.env.example`）:

```bash
DB_PATH=/opt/openclaw/data/gateway/gateway.db
GATEWAY_PORT=8000
OPENCLAW_PROTOCOL=ws
OPENCLAW_TIMEOUT=2700
GATEWAY_URL=http://localhost:8000
```

Agent 绑定关系全部存储在 SQLite 中，通过 `manage-agent.py` 管理。

---

## SQLite 数据库

### agents 表（agent-企业微信绑定）
```sql
CREATE TABLE agents (
    name              TEXT PRIMARY KEY,
    display_name      TEXT NOT NULL,
    wecom_token       TEXT NOT NULL,
    wecom_aes_key     TEXT NOT NULL,
    openclaw_url      TEXT NOT NULL,
    openclaw_token    TEXT NOT NULL,
    openclaw_agent_id TEXT DEFAULT '',
    created_at        TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at        TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### task_logs 表（任务日志）
```sql
CREATE TABLE task_logs (
    task_id TEXT PRIMARY KEY,
    user_id TEXT,
    agent_id TEXT,
    task_content TEXT,
    status TEXT,
    result TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### 常用查询
```bash
sqlite3 $DB_PATH ".schema"
sqlite3 $DB_PATH "SELECT name, display_name, openclaw_url FROM agents;"
sqlite3 $DB_PATH "SELECT COUNT(*), status FROM task_logs GROUP BY status;"
```

---

## API 接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET/POST | `/{agent_name}/wecom/callback` | 企业微信回调（按 agent 路由） |
| GET/POST | `/wecom/callback` | 旧版兼容路径（路由到第一个 agent） |
| GET | `/health` | 健康检查 |
| GET | `/stats` | 统计信息 |
| GET | `/admin/agents` | 列出所有 agent 绑定 |
| POST | `/admin/reload` | 重载 agent 绑定（manage-agent.py 自动调用） |

---

## 消息处理流程

```
企业微信用户 -> GET/POST /{agent_name}/wecom/callback
  -> 查 SQLite 获取 agent 配置
  -> 用 agent 的 wecom_token/aes_key 解密验签
  -> 提取 user_id, content
  -> session_key = "wecom:{agent_name}:{user_id}"
  -> 调用 openclaw (WS/SSE/HTTP):
       URL:      agent.openclaw_url
       Token:    agent.openclaw_token
       Agent ID: agent.openclaw_agent_id (默认 main)
  -> 收到回复 -> 通过企业微信 response_url 回复用户
```

---

## 注意事项

1. **安全**: 不要提交 `.env` 和 `*.db` 文件到 Git
2. **首次启动**: Gateway 正常启动，但无 agent — 需通过 manage-agent.py 添加
3. **重载**: 添加/删除 agent 后，manage-agent.py 自动通知 Gateway 重载
4. **数据**: `data/` 目录由运行时生成，已在 .gitignore

---

**更新日期**: 2026-03-02
