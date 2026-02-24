# 项目上下文

## 项目目的

**OpenClaw-Deploy** 是基于 OpenClaw 核心系统的企业微信集成扩展项目，旨在为企业提供智能虚拟员工服务。

### 核心目标
- 🔌 **企业微信集成**：将 OpenClaw AI 系统无缝集成到企业微信平台
- 🤖 **智能虚拟员工**：提供 6 个专业领域的 AI 虚拟员工（调度员、运营、产品、开发、测试、客服）
- 🚀 **快速部署**：提供本地测试和生产环境的一键部署方案
- 📊 **企业级运维**：完整的监控、日志、备份、告警系统

### 项目定位
- 作为 OpenClaw 核心系统的**扩展模块**，不是独立系统
- 充当企业微信和 OpenClaw AI 系统之间的**中间层网关**
- 提供消息路由、权限管理、任务调度等企业级功能

## 技术栈

### 后端技术
- **Python 3.11**：主要开发语言
- **Flask 2.3+**：Web 框架，用于企业微信网关
- **SQLite / PostgreSQL**：数据库（本地测试用 SQLite，生产环境用 PostgreSQL）
- **Requests**：HTTP 客户端，用于调用 OpenClaw API
- **PyCryptodome**：加密库，用于企业微信消息加解密

### 容器化和部署
- **Docker 20.10+**：容器化平台
- **Docker Compose 2.0+**：容器编排
- **Alpine Linux**：Docker 基础镜像（轻量级）
- **Nginx**：反向代理和 SSL 终止（生产环境）

### AI 模型服务
- **GitHub Copilot API**：主要 AI 模型（通过 GitHub Token）
- **OpenAI API**：备选 AI 模型（可选）
- **OpenClaw Gateway**：核心 AI 调度系统（端口 18789）

### 开发工具
- **Bash Shell**：自动化部署脚本
- **YAML**：配置文件格式（Agent 配置）
- **Git**：版本控制
- **Claude Code**：AI 辅助开发工具

### 监控和运维
- **Docker Healthcheck**：容器健康检查
- **JSON 日志**：结构化日志输出
- **Cron**：定时任务（备份、清理）

## 项目约定

### 代码风格

#### Python 代码规范
- **PEP 8**：遵循 Python 官方代码风格指南
- **缩进**：4 个空格（不使用 Tab）
- **行长度**：最大 120 字符
- **命名约定**：
  - 函数和变量：`snake_case`（如 `get_user_agents`）
  - 类名：`PascalCase`（如 `AccessTokenManager`）
  - 常量：`UPPER_SNAKE_CASE`（如 `OPENCLAW_GATEWAY_URL`）
  - 私有方法：前缀 `_`（如 `_internal_method`）

#### 文档字符串
```python
def function_name(param1, param2):
    """简短描述（一行）

    详细描述（可选）

    Args:
        param1: 参数1说明
        param2: 参数2说明

    Returns:
        返回值说明
    """
```

#### Shell 脚本规范
- **Shebang**：`#!/bin/bash`
- **错误处理**：使用 `set -e`（遇到错误立即退出）
- **变量命名**：大写（如 `CONTAINER_NAME`）
- **函数命名**：小写加下划线（如 `check_docker`）
- **注释**：每个主要步骤添加注释

### 架构模式

#### 分层架构
```
表现层 (Presentation Layer)
  └─ 企业微信客户端

网关层 (Gateway Layer)
  └─ wecom_gateway.py
      ├─ 消息接收和验证
      ├─ 加解密处理
      ├─ 路由引擎
      └─ 任务管理

集成层 (Integration Layer)
  └─ OpenClaw API 调用
      └─ HTTP POST /api/v1/sessions/send

核心层 (Core Layer)
  └─ OpenClaw Gateway
      ├─ Agent 管理
      ├─ AI 模型调用
      └─ 会话管理

数据层 (Data Layer)
  └─ SQLite / PostgreSQL
      ├─ 用户角色表
      └─ 任务日志表
```

#### 设计模式
- **单例模式**：`AccessTokenManager`（Token 管理器）
- **工厂模式**：Agent 路由和创建
- **策略模式**：消息路由策略（关键词匹配）
- **异步处理**：后台线程处理耗时任务

#### 关键架构决策
1. **异步消息处理**：企业微信要求 5 秒内响应，使用后台线程异步处理
2. **Token 缓存**：企业微信 access_token 有效期 7200 秒，提前 300 秒刷新
3. **容器化部署**：使用 Docker 确保环境一致性
4. **配置外部化**：所有配置通过环境变量管理

### 测试策略

#### 测试层级
1. **单元测试**：核心函数测试（加解密、路由逻辑）
2. **集成测试**：API 接口测试（健康检查、统计接口）
3. **端到端测试**：完整消息流程测试（企业微信 → OpenClaw → 回复）

#### 测试工具
- **pytest**：Python 单元测试框架（计划中）
- **curl**：API 接口测试
- **Docker healthcheck**：容器健康检查
- **自定义脚本**：`3-test-local.sh`、`6-health-check.sh`

#### 测试覆盖要求
- 核心功能：100% 覆盖
- 工具函数：80%+ 覆盖
- 集成测试：覆盖所有 API 端点

### Git 工作流

#### 分支策略
- **main**：主分支，生产就绪代码
- **develop**：开发分支（如果需要）
- **feature/**：功能分支（如 `feature-init-20260212`）
- **hotfix/**：紧急修复分支

#### 提交规范
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type 类型**：
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `style`: 代码格式（不影响功能）
- `refactor`: 重构
- `test`: 测试相关
- `chore`: 构建/工具相关

**示例**：
```
feat(gateway): 新增虚拟员工容器化部署功能

- 创建 Dockerfile 使用 Alpine 基础镜像
- 修改 docker-compose.yml 支持本地构建
- 添加健康检查配置

Closes #123
```

#### 提交要求
- 每次提交应该是一个完整的功能单元
- 提交信息使用中文或英文（保持一致）
- 包含 Co-Authored-By 标记 AI 协作

## 领域上下文

### 企业微信集成
- **企业微信**：腾讯提供的企业通讯和办公平台
- **应用回调**：企业微信通过 HTTP 回调发送消息到第三方系统
- **消息加密**：使用 AES-CBC 加密，需要验证签名和解密
- **Access Token**：企业微信 API 认证令牌，有效期 7200 秒

### OpenClaw 系统
- **OpenClaw**：AI Agent 调度和管理系统
- **Agent**：虚拟员工，每个 Agent 有特定的技能和职责
- **Session**：会话管理，维护用户和 Agent 的对话上下文
- **Label**：会话标识，用于区分不同来源的会话（如 `wecom-userid`）

### AI 模型
- **GitHub Copilot**：GitHub 提供的 AI 编程助手，可通过 API 调用
- **Claude Sonnet 4.5**：Anthropic 的 AI 模型，通过 GitHub Copilot 访问
- **Temperature**：控制 AI 回复的随机性（0.0-1.0）
- **Max Tokens**：限制 AI 回复的最大长度

### 虚拟员工角色
1. **调度员 (Dispatcher)**：任务分发、意图识别、负载均衡
2. **运营专员 (Operation)**：数据分析、报表生成、趋势预测
3. **产品经理 (Product)**：需求分析、产品设计、竞品研究
4. **开发工程师 (Development)**：代码审查、Bug 诊断、技术支持
5. **测试工程师 (Testing)**：测试用例、质量保障、自动化测试
6. **客服专员 (Service)**：客户咨询、投诉处理、问题解答

## 重要约束

### 技术约束
- **企业微信回调超时**：必须在 5 秒内返回 200 响应，否则企业微信会重试
- **消息长度限制**：企业微信单条消息最大 2048 字节
- **Token 有效期**：企业微信 access_token 有效期 7200 秒，需要缓存和自动刷新
- **Docker 资源限制**：本地测试环境限制 CPU 2 核、内存 4GB

### 业务约束
- **用户权限管理**：用户只能访问已绑定的 Agent
- **任务日志记录**：所有任务必须记录日志，用于审计和分析
- **消息加密**：企业微信消息必须加密传输，确保安全性

### 安全约束
- **API 认证**：OpenClaw API 调用需要 Bearer Token 认证
- **环境变量保护**：敏感信息（Token、密钥）通过环境变量管理，不提交到代码库
- **SSL/TLS**：生产环境必须使用 HTTPS
- **防火墙规则**：只开放必要的端口（80、443）

### 运维约束
- **日志保留**：日志文件最大 50MB，保留最近 10 个文件
- **备份策略**：每日凌晨 2 点自动备份数据库和配置
- **监控告警**：服务异常时发送告警通知

## 外部依赖

### 核心依赖

#### OpenClaw 核心系统
- **服务地址**：`http://localhost:18789`（本地）或 `http://openclaw-production:3000`（生产）
- **API 端点**：`POST /api/v1/sessions/send`
- **认证方式**：Bearer Token（可选）
- **超时时间**：30 秒
- **依赖关系**：本项目依赖 OpenClaw 核心系统提供 AI 能力

#### 企业微信 API
- **服务地址**：`https://qyapi.weixin.qq.com`
- **主要接口**：
  - `GET /cgi-bin/gettoken`：获取 access_token
  - `POST /cgi-bin/message/send`：发送消息
- **认证方式**：CorpID + Secret
- **限流规则**：每分钟最多 600 次请求

#### AI 模型服务
- **GitHub Copilot API**：
  - 认证：GitHub Token
  - 模型：`claude-sonnet-4.5`
  - 限流：根据 GitHub 账号等级
- **OpenAI API**（备选）：
  - 认证：API Key
  - 模型：`gpt-4`、`gpt-3.5-turbo`
  - 限流：根据账号配额

### Python 依赖包

```python
# requirements.txt
Flask==2.3.0           # Web 框架
requests==2.31.0       # HTTP 客户端
pycryptodome==3.19.0   # 加密库
```

### 系统依赖
- **Docker**：20.10+ 版本
- **Docker Compose**：2.0+ 版本
- **Python**：3.11+ 版本
- **Nginx**：1.24+（生产环境）
- **PostgreSQL**：14+（生产环境，可选）

### 开发工具依赖
- **Git**：版本控制
- **curl**：API 测试
- **jq**：JSON 处理（可选）
- **vim/nano**：配置文件编辑

### 云服务依赖（生产环境）
- **云服务器**：Ubuntu 22.04 LTS，8GB+ 内存，50GB+ 磁盘
- **域名服务**：用于企业微信回调 URL
- **SSL 证书**：Let's Encrypt 或商业证书
- **防火墙**：云服务商提供的安全组

---

## 项目结构说明

```
openclaw-deploy/
├── docs/                    # 完整文档（104KB）
├── local/                   # 本地测试环境（88KB）
├── production/              # 生产部署环境（76KB）
├── config/                  # 配置文件中心（80KB）
│   └── agents/             # 6 个虚拟员工配置
├── scripts/                 # 通用工具脚本（80KB）
├── src/                     # 源代码（64KB）
│   └── gateway/            # 企业微信网关
│       ├── wecom_gateway.py         # 核心实现（615 行）
│       ├── Dockerfile               # Docker 镜像定义
│       └── requirements.txt         # Python 依赖
├── data/                    # 数据目录（运行时生成）
├── logs/                    # 日志目录（运行时生成）
├── openspec/                # 项目规范文档
│   └── project.md          # 本文件
├── SYSTEM_ANALYSIS.md       # 系统架构分析文档
├── DEEP_TODO_ANALYSIS.md   # TODO 分析
├── P0_IMPLEMENTATION_COMPLETE.md # P0 完成报告
└── README.md               # 项目总览
```

---

**文档版本**：V1.4
**最后更新**：2026-02-24
**维护者**：OpenClaw Team
