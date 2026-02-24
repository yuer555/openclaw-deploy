# OpenClaw-Deploy 系统架构分析与部署指南

**版本**: V1.4
**日期**: 2026-02-24
**状态**: ✅ 生产就绪

---

## 📋 目录

1. [系统概述](#系统概述)
2. [架构设计](#架构设计)
3. [核心组件](#核心组件)
4. [与 OpenClaw 的集成](#与-openclaw-的集成)
5. [完整部署流程](#完整部署流程)
6. [配置说明](#配置说明)
7. [运维监控](#运维监控)
8. [故障排查](#故障排查)

---

## 1. 系统概述

### 1.1 项目定位

**OpenClaw-Deploy** 是基于 OpenClaw 核心系统的企业微信集成扩展，提供：

- 🔌 **企业微信网关**：连接企业微信与 OpenClaw AI 系统
- 🤖 **6 个虚拟员工**：调度员、运营、产品、开发、测试、客服
- 🚀 **一键部署**：本地测试和生产环境的完整部署方案
- 📊 **监控运维**：日志、监控、告警、备份完整方案

### 1.2 技术栈

| 层级 | 技术 | 说明 |
|------|------|------|
| **前端** | 企业微信客户端 | 用户交互界面 |
| **网关** | Python 3.11 + Flask | 企业微信消息处理 |
| **核心** | OpenClaw Gateway | AI Agent 调度和管理 |
| **AI** | GitHub Copilot / OpenAI | AI 模型服务 |
| **数据库** | SQLite / PostgreSQL | 用户和任务数据 |
| **容器** | Docker + Docker Compose | 容器化部署 |
| **代理** | Nginx | 反向代理和 SSL |

### 1.3 系统特性

✅ **高可用性**：健康检查、自动重启、故障恢复
✅ **安全性**：消息加密、签名验证、权限控制
✅ **可扩展性**：模块化设计、易于添加新 Agent
✅ **易部署**：一键脚本、Docker 容器化
✅ **可监控**：完整日志、性能指标、告警系统

---

## 2. 架构设计

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                         企业微信用户                             │
│                    (移动端 + PC 端)                              │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS
                             │ 企业微信消息
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      企业微信服务器                              │
│                  (qyapi.weixin.qq.com)                          │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS Callback
                             │ POST /wecom/callback
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Nginx 反向代理                            │
│                    (SSL 终止 + 负载均衡)                         │
│                         端口: 80/443                             │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTP
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              OpenClaw 企业微信网关 (本项目)                      │
│                   wecom_gateway.py                              │
│                      端口: 8000                                  │
├─────────────────────────────────────────────────────────────────┤
│ 功能模块:                                                        │
│ • 消息接收和验证 (/wecom/callback)                              │
│ • 消息加解密 (AES-CBC)                                          │
│ • 用户权限管理 (SQLite)                                         │
│ • 智能路由引擎 (关键词匹配)                                      │
│ • 任务日志记录                                                   │
│ • 异步消息处理                                                   │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTP POST
                             │ /api/v1/sessions/send
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              OpenClaw 核心系统 (原有系统)                        │
│                   OpenClaw Gateway                              │
│                      端口: 18789                                 │
├─────────────────────────────────────────────────────────────────┤
│ 功能模块:                                                        │
│ • Agent 管理和调度                                              │
│ • 会话管理 (Session Management)                                │
│ • AI 模型调用 (GitHub Copilot / OpenAI)                        │
│ • 上下文管理                                                     │
│ • 响应生成和优化                                                 │
└────────────────────────────┬────────────────────────────────────┘
                             │ API 调用
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                      AI 模型服务                                 │
│         GitHub Copilot API / OpenAI API                         │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 数据流图

```
用户发送消息
  │
  ├─ 1. 企业微信接收消息
  │   └─ 加密消息 + 签名
  │
  ├─ 2. 回调到网关 (POST /wecom/callback)
  │   ├─ 验证签名 (SHA1)
  │   ├─ 解密消息 (AES-CBC)
  │   └─ 解析 XML
  │
  ├─ 3. 查询用户权限
  │   └─ SELECT roles FROM user_roles WHERE user_id = ?
  │
  ├─ 4. 智能路由
  │   ├─ 关键词匹配
  │   ├─ 权限检查
  │   └─ 选择 Agent
  │
  ├─ 5. 记录任务日志
  │   └─ INSERT INTO task_logs (task_id, user_id, agent_id, ...)
  │
  ├─ 6. 调用 OpenClaw Gateway
  │   └─ POST /api/v1/sessions/send
  │       {
  │         "message": "用户消息",
  │         "agentId": "development-agent",
  │         "label": "wecom-userid"
  │       }
  │
  ├─ 7. OpenClaw 处理
  │   ├─ 加载 Agent 配置
  │   ├─ 准备上下文
  │   ├─ 调用 AI 模型
  │   └─ 生成回复
  │
  ├─ 8. 返回结果
  │   └─ { "reply": "AI 生成的回复" }
  │
  ├─ 9. 更新任务状态
  │   └─ UPDATE task_logs SET status='success', result=?
  │
  └─ 10. 发送回复到企业微信
      └─ POST https://qyapi.weixin.qq.com/cgi-bin/message/send
```

### 2.3 部署架构

#### 本地测试环境

```
┌─────────────────────────────────────────┐
│         开发者本机 (macOS/Linux)         │
├─────────────────────────────────────────┤
│                                         │
│  ┌───────────────────────────────────┐ │
│  │   Docker Container                │ │
│  │   openclaw-local                  │ │
│  │                                   │ │
│  │   • wecom_gateway.py (端口 8000) │ │
│  │   • SQLite 数据库                │ │
│  │   • 日志文件                      │ │
│  └───────────────────────────────────┘ │
│              ↕                          │
│         端口映射 3000:8000               │
│              ↕                          │
│  ┌───────────────────────────────────┐ │
│  │   本地访问                         │ │
│  │   http://localhost:3000           │ │
│  │   • /health - 健康检查            │ │
│  │   • /stats - 统计信息             │ │
│  └───────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

#### 生产环境

```
┌─────────────────────────────────────────────────────────────┐
│                    云服务器 (Ubuntu 22.04)                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │   Nginx (端口 80/443)                                 │ │
│  │   • SSL 终止                                          │ │
│  │   • 反向代理                                          │ │
│  │   • 负载均衡                                          │ │
│  └─────────────────────┬─────────────────────────────────┘ │
│                        │                                   │
│  ┌─────────────────────▼─────────────────────────────────┐ │
│  │   Docker Container: openclaw-production               │ │
│  │   • wecom_gateway.py (端口 3000)                     │ │
│  │   • PostgreSQL 数据库                                │ │
│  │   • 持久化存储 (/opt/openclaw/data)                  │ │
│  └───────────────────────────────────────────────────────┘ │
│                        │                                   │
│                        │ HTTP                              │
│                        ▼                                   │
│  ┌───────────────────────────────────────────────────────┐ │
│  │   OpenClaw Gateway (端口 18789)                       │ │
│  │   • Agent 管理                                        │ │
│  │   • AI 模型调用                                       │ │
│  └───────────────────────────────────────────────────────┘ │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐ │
│  │   监控和日志                                          │ │
│  │   • /opt/openclaw/logs/                              │ │
│  │   • 告警系统                                          │ │
│  │   • 备份任务                                          │ │
│  └───────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 核心组件

### 3.1 企业微信网关 (wecom_gateway.py)

**文件位置**: `src/gateway/wecom_gateway.py`
**代码行数**: 615 行
**主要职责**: 企业微信消息处理和 OpenClaw 系统集成

#### 核心类和函数

**1. AccessTokenManager (单例模式)**
```python
class AccessTokenManager:
    """企业微信 Access Token 管理器"""

    def get_token(self):
        # 获取有效的 access_token
        # 自动刷新机制（提前5分钟过期）
        # 线程安全
```

**功能**:
- 管理企业微信 access_token
- 自动刷新（7200秒有效期，提前300秒刷新）
- 线程安全的单例模式
- 错误处理和重试机制

**2. WXBizMsgCrypt (加解密工具)**
```python
class WXBizMsgCrypt:
    """企业微信消息加解密"""

    def verify_signature(self, signature, timestamp, nonce, echo_str):
        # SHA1 签名验证

    def decrypt(self, encrypt_msg):
        # AES-CBC 解密

    def encrypt(self, msg_text):
        # AES-CBC 加密
```

**功能**:
- SHA1 签名验证
- AES-CBC 加密/解密
- PKCS#7 补位处理
- CorpID 验证

**3. 数据库操作**
```python
def get_user_agents(user_id):
    """查询用户绑定的代理"""

def log_task(task_id, user_id, agent_id, content, status, result):
    """记录任务日志"""

def update_task_status(task_id, status, result):
    """更新任务状态"""
```

**4. 消息路由引擎**
```python
def route_message(content, user_agents):
    """智能路由消息到合适的代理"""
    # 1. 关键词匹配
    # 2. 权限检查
    # 3. 优先级排序
    # 4. 默认代理
```

**路由规则**:
```python
ROUTING_KEYWORDS = {
    'service-agent': ['客服', '咨询', '投诉', '售后'],
    'development-agent': ['开发', '代码', 'bug', '技术'],
    'testing-agent': ['测试', '用例', 'qa', '质量'],
    'operation-agent': ['文案', '活动', '运营', '数据'],
    'product-agent': ['需求', '原型', '竞品', 'prd'],
}
```

**5. OpenClaw API 调用**
```python
def call_openclaw_agent(agent_id, message, user_id, task_id):
    """调用 OpenClaw Gateway API"""
    url = f"{OPENCLAW_GATEWAY_URL}/api/v1/sessions/send"
    payload = {
        "message": message,
        "agentId": agent_id,
        "label": f"wecom-{user_id}",
        "timeoutSeconds": 30
    }
```

**6. Flask 路由**
```python
@app.route('/wecom/callback', methods=['GET', 'POST'])
def wecom_callback():
    # GET: 验证回调 URL
    # POST: 接收消息

@app.route('/health', methods=['GET'])
def health():
    # 健康检查

@app.route('/stats', methods=['GET'])
def stats():
    # 统计信息
```

---

## 4. 与 OpenClaw 的集成

### 4.1 集成方式

**OpenClaw-Deploy** 作为 OpenClaw 的扩展模块，通过 HTTP API 与核心系统通信：

```
OpenClaw-Deploy (企业微信网关)
         │
         │ HTTP POST
         │ /api/v1/sessions/send
         ▼
OpenClaw Gateway (核心系统)
         │
         ├─ Agent 调度
         ├─ AI 模型调用
         └─ 响应生成
```

### 4.2 API 接口规范

**请求格式**:
```http
POST /api/v1/sessions/send HTTP/1.1
Host: localhost:18789
Content-Type: application/json
Authorization: Bearer YOUR_API_KEY

{
  "message": "帮我分析一下代码性能问题",
  "agentId": "development-agent",
  "label": "wecom-user123",
  "timeoutSeconds": 30
}
```

**响应格式**:
```json
{
  "reply": "我来帮您分析代码性能问题...",
  "message": "处理成功",
  "sessionId": "sess_abc123",
  "agentId": "development-agent",
  "timestamp": 1708761234
}
```

### 4.3 配置关键点

**1. OPENCLAW_GATEWAY_URL**
```bash
# 本地测试
OPENCLAW_GATEWAY_URL=http://localhost:18789

# 生产环境（同一服务器）
OPENCLAW_GATEWAY_URL=http://openclaw-production:3000

# 生产环境（不同服务器）
OPENCLAW_GATEWAY_URL=https://openclaw.yourdomain.com/api
```

**2. 认证配置**
```bash
# API Key 认证
OPENCLAW_API_KEY=your_secure_api_key_here

# 在请求头中使用
Authorization: Bearer your_secure_api_key_here
```

**3. 超时配置**
```bash
# OpenClaw 处理超时（秒）
OPENCLAW_TIMEOUT=30

# HTTP 请求超时（稍微多给5秒）
timeout=OPENCLAW_TIMEOUT + 5
```

---

## 5. 完整部署流程

### 5.1 前置条件

**系统要求**:
- 操作系统: Ubuntu 22.04 LTS / macOS
- 内存: 8GB+ (推荐 16GB)
- 磁盘: 50GB+
- Docker: 20.10+
- Docker Compose: 2.0+

**必需的账号和密钥**:
- ✅ 企业微信企业账号
- ✅ GitHub Token (用于 Copilot) 或 OpenAI API Key
- ✅ 域名和 SSL 证书（生产环境）

### 5.2 本地测试部署

#### 步骤 1: 克隆项目
```bash
git clone https://github.com/your-org/openclaw-deploy.git
cd openclaw-deploy
```

#### 步骤 2: 配置环境变量
```bash
cd local/
cp .env.local.example .env.local

# 编辑配置文件
vim .env.local
```

**必填配置**:
```bash
GITHUB_TOKEN=ghp_your_token_here
# 或
OPENAI_API_KEY=sk-your_key_here
```

#### 步骤 3: 前置检查
```bash
./0-pre-check.sh
```

**检查项**:
- ✓ Docker 已安装并运行
- ✓ Docker Compose 已安装
- ✓ 端口 3000 可用
- ✓ 配置文件存在
- ✓ GitHub Token 已配置

#### 步骤 4: 初始化环境
```bash
./1-init-local.sh
```

**执行内容**:
- 创建目录结构 (data/, logs/)
- 验证配置文件
- 初始化数据库

#### 步骤 5: 启动服务
```bash
./2-start-local.sh
```

**执行内容**:
- 构建 Docker 镜像
- 启动容器
- 等待服务就绪

#### 步骤 6: 测试服务
```bash
./3-test-local.sh
```

**测试项**:
- ✓ 容器运行状态
- ✓ 健康检查接口
- ✓ 端口监听
- ✓ 日志输出

### 5.3 生产环境部署

#### 步骤 1: 准备服务器
```bash
cd production/
./1-prepare-server.sh
```

**执行内容**:
- 更新系统软件包
- 安装 Docker 和 Docker Compose
- 配置防火墙
- 创建目录结构

#### 步骤 2: 配置环境变量
```bash
# 在服务器上创建配置文件
sudo vim /opt/openclaw/.env
```

**生产配置模板**:
```bash
# 环境
OPENCLAW_ENV=production
NODE_ENV=production
LOG_LEVEL=info

# 数据库
DATABASE_URL=postgresql://user:password@localhost:5432/openclaw

# AI 模型
GITHUB_TOKEN=ghp_your_production_token

# 企业微信（必填）
WECOM_CORP_ID=ww1234567890abcdef
WECOM_AGENT_ID=1000001
WECOM_SECRET=your_secret_here
WECOM_TOKEN=your_token_here
WECOM_ENCODING_AES_KEY=your_aes_key_here

# OpenClaw Gateway
OPENCLAW_GATEWAY_URL=http://openclaw-production:3000
OPENCLAW_API_KEY=your_secure_api_key
OPENCLAW_TIMEOUT=30

# 安全
SECRET_KEY=your_secure_random_key_here
```

#### 步骤 3: 上传文件
```bash
./2-upload-to-server.sh your-server-ip
```

#### 步骤 4: 部署服务
```bash
# SSH 到服务器
ssh user@your-server-ip

# 执行部署
cd /opt/openclaw/production/
./3-deploy-production.sh
```

#### 步骤 5: 配置 SSL
```bash
./4-setup-ssl.sh your-domain.com
```

#### 步骤 6: 启动服务
```bash
./5-start-production.sh
```

#### 步骤 7: 健康检查
```bash
./6-health-check.sh
```

**检查项**:
- ✓ 容器运行状态
- ✓ 服务响应正常
- ✓ SSL 证书有效
- ✓ 企业微信连接正常

---

## 6. 配置说明

### 6.1 环境变量详解

| 变量名 | 必填 | 默认值 | 说明 |
|--------|------|--------|------|
| `OPENCLAW_ENV` | 否 | local | 环境标识 (local/production) |
| `OPENCLAW_PORT` | 否 | 3000 | 服务端口 |
| `GITHUB_TOKEN` | 是* | - | GitHub Copilot Token |
| `OPENAI_API_KEY` | 是* | - | OpenAI API Key |
| `DATABASE_URL` | 否 | sqlite:///data/openclaw.db | 数据库连接 |
| `LOG_LEVEL` | 否 | info | 日志级别 |
| `WECOM_CORP_ID` | 是** | - | 企业微信企业ID |
| `WECOM_AGENT_ID` | 是** | - | 企业微信应用ID |
| `WECOM_SECRET` | 是** | - | 企业微信应用密钥 |
| `WECOM_TOKEN` | 是** | - | 企业微信消息Token |
| `WECOM_ENCODING_AES_KEY` | 是** | - | 企业微信加密密钥 |
| `OPENCLAW_GATEWAY_URL` | 是 | http://localhost:18789 | OpenClaw 网关地址 |
| `OPENCLAW_API_KEY` | 否 | - | OpenClaw API 认证密钥 |
| `OPENCLAW_TIMEOUT` | 否 | 30 | OpenClaw 请求超时 |

*注: GITHUB_TOKEN 和 OPENAI_API_KEY 二选一
**注: 企业微信配置仅生产环境必填

### 6.2 Agent 配置

**配置文件位置**: `config/agents/*.yml`

**示例: development.yml**
```yaml
name: "开发工程师小王"
role: development
enabled: true
description: "负责代码审查、Bug诊断、技术支持"

ai:
  model: "github-copilot/claude-sonnet-4.5"
  temperature: 0.5
  max_tokens: 3000
  top_p: 0.9

skills:
  - name: "代码审查"
    description: "审查代码质量、规范、安全性"
    keywords: ["代码", "review", "审查", "代码质量"]

  - name: "Bug诊断"
    description: "分析和定位代码问题"
    keywords: ["bug", "错误", "报错", "异常", "崩溃"]

  - name: "性能优化"
    description: "分析和优化代码性能"
    keywords: ["性能", "优化", "慢", "卡顿", "内存"]

routing:
  triggers:
    - "代码"
    - "开发"
    - "bug"
    - "技术"
    - "接口"
    - "部署"
  priority: 8
  excludes:
    - "测试"
    - "产品"

prompts:
  system: |
    你是一位经验丰富的全栈开发工程师，擅长：
    - 代码审查和质量把控
    - Bug 诊断和问题定位
    - 性能优化和架构设计
    - 技术选型和方案设计

    工作风格：
    - 严谨细致，注重代码质量
    - 善于分析问题根源
    - 提供可行的解决方案
    - 考虑性能和可维护性

  greeting: |
    您好！我是开发工程师小王。
    我可以帮您：
    • 代码审查和优化建议
    • Bug 诊断和修复方案
    • 技术方案设计
    • 性能优化建议

    请告诉我您遇到的技术问题。

examples:
  - user: "这段代码有什么问题？"
    assistant: "让我帮您分析这段代码..."

  - user: "接口返回500错误"
    assistant: "500错误通常是服务器端问题，让我帮您排查..."
```

---

## 7. 运维监控

### 7.1 日志管理

**日志位置**:
```
logs/
├── local/              # 本地测试日志
│   ├── gateway.log     # 网关日志
│   └── error.log       # 错误日志
└── production/         # 生产环境日志
    ├── gateway.log
    ├── error.log
    └── access.log
```

**查看日志**:
```bash
# 实时查看
docker logs -f openclaw-local

# 查看最近100行
docker logs --tail 100 openclaw-local

# 查看错误日志
grep ERROR logs/local/gateway.log
```

### 7.2 监控指标

**健康检查**:
```bash
curl http://localhost:3000/health
```

**统计信息**:
```bash
curl http://localhost:3000/stats
```

**响应示例**:
```json
{
  "total_tasks": 1250,
  "success_tasks": 1180,
  "failed_tasks": 70,
  "total_users": 45,
  "success_rate": "94.40%",
  "timestamp": 1708761234
}
```

### 7.3 备份策略

**自动备份脚本**: `scripts/backup.sh`

```bash
# 每日备份
0 2 * * * /opt/openclaw/scripts/backup.sh

# 备份内容
- 数据库文件
- 配置文件
- 日志文件（最近7天）
```

---

## 8. 故障排查

### 8.1 常见问题

**问题 1: 容器无法启动**
```bash
# 检查日志
docker logs openclaw-local

# 检查端口占用
lsof -i :3000

# 重新构建
docker-compose -f docker-compose.local.yml build --no-cache
```

**问题 2: 企业微信回调失败**
```bash
# 检查配置
echo $WECOM_CORP_ID
echo $WECOM_TOKEN

# 检查签名验证
grep "签名验证" logs/local/gateway.log

# 测试回调 URL
curl -X GET "http://your-domain.com/wecom/callback?..."
```

**问题 3: OpenClaw 连接失败**
```bash
# 检查 Gateway URL
echo $OPENCLAW_GATEWAY_URL

# 测试连接
curl -X POST $OPENCLAW_GATEWAY_URL/api/v1/sessions/send \
  -H "Content-Type: application/json" \
  -d '{"message":"test","agentId":"dispatcher"}'
```

### 8.2 调试模式

**启用调试日志**:
```bash
# 修改 .env.local
LOG_LEVEL=debug
DEBUG=true
VERBOSE=true

# 重启服务
docker restart openclaw-local
```

---

## 9. 总结

### 9.1 系统优势

✅ **完整的企业微信集成**：开箱即用的企业微信网关
✅ **智能路由系统**：基于关键词的自动任务分发
✅ **模块化设计**：易于扩展和维护
✅ **容器化部署**：一键部署，环境一致
✅ **完善的文档**：详细的部署和运维文档

### 9.2 下一步建议

1. **完成 OpenClaw 核心系统部署**
   - 部署 OpenClaw Gateway (端口 18789)
   - 配置 AI 模型服务
   - 测试 API 接口

2. **配置企业微信**
   - 创建企业微信应用
   - 配置回调 URL
   - 测试消息收发

3. **生产环境部署**
   - 准备云服务器
   - 配置域名和 SSL
   - 部署完整系统

4. **监控和优化**
   - 配置监控告警
   - 优化性能
   - 定期备份

---

**文档版本**: V1.4
**最后更新**: 2026-02-24
**维护者**: OpenClaw Team
