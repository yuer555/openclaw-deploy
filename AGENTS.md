# AGENTS.md - OpenClaw 企业微信虚拟员工系统代码指南

> 🤖 本文档为 AI 编码助手提供项目开发规范和常用命令

## 📋 项目概览

**项目名称**: OpenClaw V1.4 - 企业微信虚拟员工系统  
**技术栈**: Python 3.13, Flask 3.0, Docker, OpenClaw AI 框架  
**架构**: 微服务架构（1 个 Gateway + 5 个虚拟员工 Agent 容器）

### 核心组件
- **Gateway** (`src/gateway/`): 企业微信消息网关 + AI 调度员
- **Agents**: 运营、产品、开发、测试、客服 5 个虚拟员工
- **通信协议**: HTTP/SSE/WebSocket/Docker Exec（默认 WS）

---

## 🚀 快速开始命令

### 本地开发环境

```bash
# 初始化本地环境（首次运行）
cd local/
./1-init-local.sh

# 启动所有服务（Gateway 在宿主机 + 5 个 Agent 容器）
./2-start-local.sh

# 运行测试
./3-test-local.sh

# 停止服务
./4-stop-local.sh

# 清理环境
./5-clean-local.sh
```

### 生产部署

```bash
cd production/
./1-prepare-server.sh      # 准备服务器环境
./2-upload-to-server.sh    # 上传代码
./3-deploy-production.sh   # 部署服务
./4-setup-ssl.sh           # 配置 SSL 证书
./5-start-production.sh    # 启动服务
./6-health-check.sh        # 健康检查
./7-clean-production.sh    # 清理环境
```

---

## 🧪 测试命令

### 健康检查
```bash
# 本地服务健康检查
curl http://localhost:8000/health
curl http://localhost:18791/health  # Agent Operation
curl http://localhost:18792/health  # Agent Product
curl http://localhost:18793/health  # Agent Development
curl http://localhost:18794/health  # Agent Testing
curl http://localhost:18795/health  # Agent Service

# 容器状态
docker ps --filter "name=openclaw-"
```

### 功能测试
```bash
# 测试 Gateway 消息发送
curl -X POST http://localhost:8000/test/send \
  -H "Content-Type: application/json" \
  -d '{"user_id":"test-user","content":"帮我写个测试用例"}'

# 并发测试
python3 scripts/test-concurrent.py

# 查看日志
tail -f /tmp/openclaw/flask.log          # Gateway 日志（本地）
docker logs openclaw-gateway --tail=100  # Gateway 日志（生产）
docker logs openclaw-agent-development   # Agent 日志
```

### 单个测试运行
```bash
# 运行单个 Python 测试文件（如果有）
python3 -m pytest tests/test_gateway.py -v

# 运行特定测试函数
python3 -m pytest tests/test_gateway.py::test_health_check -v
```

---

## 📦 依赖管理

### Python 依赖
```bash
# 安装 Gateway 依赖
cd src/gateway
pip3 install -r requirements.txt

# 主要依赖
flask==3.0.0
requests==2.31.0
pycryptodome==3.19.0
websocket-client==1.8.0
```

### Docker 镜像构建
```bash
# 构建 Gateway 镜像
docker build -f src/gateway/Dockerfile.gateway -t openclaw-gateway:latest .

# 构建所有镜像
cd local/
./0-build-images.sh
```

---

## 💻 代码风格指南

### Python 代码规范

#### 1. 导入顺序
```python
# 标准库
import os
import json
import logging
from datetime import datetime

# 第三方库
from flask import Flask, request, jsonify
import requests

# 本地模块
from agent_registry import AGENT_REGISTRY
```

#### 2. 命名约定
- **文件名**: 小写下划线 `wecom_gateway.py`
- **类名**: 大驼峰 `AIDispatcher`, `MessageQueue`
- **函数名**: 小写下划线 `_call_openclaw_sse()`, `route_message()`
- **常量**: 全大写 `OPENCLAW_GATEWAY_URL`, `DB_PATH`
- **私有方法**: 下划线前缀 `_extract_reply_text()`

#### 3. 日志规范
```python
# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 使用日志
logger.info("服务启动成功")
logger.warning(f"WS 调用失败: {e}，尝试重试")
logger.error(f"数据库连接失败: {e}")
```

#### 4. 异常处理
```python
# 使用具体异常类型
try:
    return _call_openclaw_ws(url, message, session_key, timeout)
except (requests.exceptions.ConnectionError,
        requests.exceptions.ChunkedEncodingError,
        requests.exceptions.ReadTimeout) as e:
    logger.warning(f"连接断开: {e}，尝试重试")
    return _call_openclaw_sse(url, retry_msg, session_key, timeout)
```

#### 5. 环境变量管理
```python
# 从环境变量读取配置，提供默认值
DB_PATH = os.getenv('DB_PATH', '/opt/openclaw/data/gateway/gateway.db')
OPENCLAW_TIMEOUT = int(os.getenv('OPENCLAW_TIMEOUT', '2700'))
OPENCLAW_PROTOCOL = os.getenv('OPENCLAW_PROTOCOL', 'ws')
```

#### 6. 类型提示（推荐）
```python
def route(self, message: str, user_id: str = 'anonymous') -> tuple:
    """分析消息意图，返回 (agent_id, agent_url, direct_reply, context)"""
    pass
```

---

## 🗂️ 项目结构

```
openclaw-deploy/
├── src/
│   └── gateway/              # Gateway 源码
│       ├── wecom_gateway.py  # 主程序（1149 行）
│       ├── agent_registry.py # Agent 注册表
│       ├── requirements.txt  # Python 依赖
│       └── Dockerfile.gateway
├── config/
│   ├── agents/workspace/     # Agent 配置
│   │   ├── dispatcher/
│   │   ├── operation/
│   │   ├── product/
│   │   ├── development/
│   │   ├── testing/
│   │   └── service/
│   │       ├── AGENTS.md     # Agent 工作空间指南
│   │       ├── SOUL.md       # Agent 灵魂设定
│   │       ├── IDENTITY.md   # Agent 身份设定
│   │       ├── USER.md       # 用户设定
│   │       └── TOOLS.md      # 工具配置
│   └── docker-compose.*.yml  # Docker Compose 配置
├── scripts/                  # 通用脚本
│   ├── start-gateway.sh
│   ├── stop-gateway.sh
│   ├── backup.sh
│   ├── restore.sh
│   └── test-concurrent.py
├── local/                    # 本地测试环境
├── production/               # 生产部署环境
├── docs/                     # 文档
└── tests/                    # 测试（目前为空）
```

---

## 🔧 常见操作

### 修改 Gateway 代码
```bash
# 1. 编辑代码
vim src/gateway/wecom_gateway.py

# 2. 重启 Gateway（本地）
pkill -f wecom_gateway.py
./scripts/start-gateway.sh

# 3. 查看日志
tail -f /tmp/openclaw/flask.log
```

### 添加新 Agent
```bash
# 1. 在 agent_registry.py 添加配置
# 2. 在 config/agents/workspace/ 创建对应目录和配置文件
# 3. 更新 docker-compose.agents.yml
# 4. 重启服务
```

### 数据库操作
```bash
# Gateway 使用 SQLite 存储会话和队列
DB_PATH=data/gateway/gateway.db

# 查看表结构
sqlite3 $DB_PATH ".schema"

# 清空消息队列
sqlite3 $DB_PATH "DELETE FROM message_queue;"
```

---

## 🌐 环境变量

### 必需变量（在 .env.local 或 .env.prod 中配置）
```bash
# 企业微信配置
WECOM_TOKEN=your_token
WECOM_ENCODING_AES_KEY=your_aes_key

# OpenClaw 配置
OPENCLAW_GATEWAY_URL=http://localhost:18789
OPENCLAW_API_KEY=your_api_key
OPENCLAW_INTERNAL_TOKEN=openclaw-internal-secret

# 通信协议：http / sse / ws / exec
OPENCLAW_PROTOCOL=ws

# Agent URL（本地开发默认 localhost）
AGENT_OPERATION_URL=http://localhost:18791
AGENT_PRODUCT_URL=http://localhost:18792
# ...
```

---

## 📚 参考文档

- **项目文档**: `docs/`
  - `00-项目介绍.md` - 系统架构
  - `01-本地测试指南.md` - 本地开发
  - `02-生产部署指南.md` - 生产部署
  - `07-API文档.md` - API 接口
- **Agent 配置**: `config/agents/workspace/*/AGENTS.md`
- **官方文档**: https://docs.openclaw.ai

---

## ⚠️ 注意事项

1. **安全**: 不要提交 `.env` 文件到 Git（已在 .gitignore）
2. **日志**: 日志文件自动生成，不要提交到 Git
3. **数据**: `data/` 目录由运行时生成，已忽略
4. **权限**: Shell 脚本需要执行权限 `chmod +x *.sh`
5. **Docker**: 确保 Docker Desktop 已启动（本地开发）
6. **端口冲突**: Gateway 8000, Agents 18791-18795

---

## 🐛 故障排查

```bash
# 检查服务状态
docker ps -a | grep openclaw

# 重启所有服务
cd local/
./4-stop-local.sh
./2-start-local.sh

# 查看详细错误
docker logs openclaw-gateway --tail=200
docker logs openclaw-agent-development --tail=200

# 健康检查脚本
./local/3-test-local.sh
./production/6-health-check.sh
```

详细排查指南见 `docs/06-故障排查.md`

---

**更新日期**: 2026-03-02  
**版本**: V1.4
