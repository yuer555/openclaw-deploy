
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

OpenClaw V2.0 是一个基于 AI 的企业微信虚拟员工系统，采用三层 Docker 容器化架构，支持 AI 智能路由和多个独立虚拟员工角色。

## 核心架构

### 三层 Docker 架构

1. **Gateway 容器** (`src/gateway/`)
   - Flask 网关：处理企业微信消息
   - openclaw 调度员（:18789）：AI 意图分析，路由到对应员工
   - 角色性格：`config/agents/workspace/dispatcher.md` → `/workspace/CLAUDE.md`
   - 本地端口：8000；生产固定 IP：172.20.0.10

2. **虚拟员工容器** × 5（`config/docker-compose.agents.yml`）
   - 每个员工独立 Docker 容器，各自运行 openclaw（:18789）
   - 角色性格预置于镜像中（`config/agents/workspace/{role}.md`）
   - 本地端口：18791-18795；生产固定 IP：172.20.0.11-15

3. **AI 路由机制**
   - `AIDispatcher` 类通过 WebSocket RPC 调用调度员 openclaw
   - 调度员分析用户意图，返回目标 agent ID
   - Fallback 到 `service` agent

### 关键文件

- **角色性格**：`config/agents/workspace/{role}.md`（预置到镜像 `/workspace/CLAUDE.md`）
- **Agent 注册表**：`src/gateway/agent_registry.py`（URL 从环境变量读取）
- **Gateway 镜像**：`src/gateway/Dockerfile.gateway` + `src/gateway/entrypoint.sh`
- **Agent 镜像**：`config/Dockerfile.agents`（ARG ROLE 选择角色）
- **企业微信网关**：`src/gateway/wecom_gateway.py`

## 常用命令

### 本地测试

```bash
cd local/

# 首次运行
./1-init-local.sh          # 检查端口、创建目录、生成 .env.local
vi .env.local              # 填入 GITHUB_TOKEN 等配置
./0-build-images.sh        # 构建所有镜像（首次或代码变更后）
./2-start-local.sh         # 启动 gateway + 5 个 agent 容器

# 日常操作
./3-test-local.sh          # 健康检查 + AI 路由测试
./4-stop-local.sh          # 停止所有容器
./5-clean-local.sh         # 清理容器、镜像、数据
```

### 生产部署

```bash
cd production/

./1-prepare-server.sh      # 安装 Docker（服务器执行）
./2-upload-to-server.sh    # 上传代码（本地执行）
./3-deploy-production.sh   # 构建镜像 + 创建目录（服务器执行）
vi .env.prod               # 填入生产配置
./5-start-production.sh    # 启动所有容器
./6-health-check.sh        # 检查所有服务状态
```

### Docker 操作

```bash
# 查看容器状态
docker ps | grep openclaw

# 查看日志
docker logs openclaw-gateway -f
docker logs openclaw-agent-testing -f

# 进入容器
docker exec -it openclaw-gateway bash
docker exec -it openclaw-agent-operation sh

# 重启单个容器
docker restart openclaw-agent-service
```

## 目录结构

```
openclaw-deploy/
├── local/                         # 本地测试脚本
│   ├── 0-build-images.sh          # 构建镜像
│   ├── 1-init-local.sh            # 初始化
│   ├── 2-start-local.sh           # 启动
│   ├── 3-test-local.sh            # 测试
│   ├── 4-stop-local.sh            # 停止
│   ├── 5-clean-local.sh           # 清理
│   ├── docker-compose.local.yml   # Gateway compose
│   └── .env.local.example
├── production/                    # 生产部署脚本
│   ├── docker-compose.prod.yml    # 全量 compose（gateway + agents）
│   └── .env.prod.example
├── config/
│   ├── agents/workspace/          # 角色性格 CLAUDE.md 文件
│   │   ├── dispatcher.md
│   │   ├── operation.md
│   │   ├── product.md
│   │   ├── development.md
│   │   ├── testing.md
│   │   └── service.md
│   ├── Dockerfile.agents          # Agent 镜像（ARG ROLE）
│   └── docker-compose.agents.yml  # 本地 agent compose
├── src/gateway/
│   ├── wecom_gateway.py           # 企业微信网关 + AIDispatcher
│   ├── agent_registry.py          # Agent URL 注册表
│   ├── Dockerfile.gateway         # Gateway 镜像
│   └── entrypoint.sh              # 启动脚本（openclaw → Flask）
├── data/                          # 运行时数据（自动生成）
├── logs/                          # 日志（自动生成）
└── openspec/changes/              # OpenSpec 变更记录
```

## 环境变量

### 必填

| 变量 | 说明 |
|------|------|
| `GITHUB_TOKEN` | GitHub Copilot Token（AI 模型） |
| `WECOM_CORP_ID` | 企业微信企业 ID |
| `WECOM_SECRET` | 企业微信应用 Secret |
| `WECOM_TOKEN` | 企业微信回调 Token |
| `WECOM_ENCODING_AES_KEY` | 企业微信加密 Key |
| `WECOM_AGENT_ID` | 企业微信应用 ID |

### Agent URL（本地默认 localhost，生产用 Docker 固定 IP）

| 变量 | 本地默认 | 生产默认 |
|------|---------|---------|
| `AGENT_OPERATION_URL` | http://localhost:18791 | http://172.20.0.11:18789 |
| `AGENT_PRODUCT_URL` | http://localhost:18792 | http://172.20.0.12:18789 |
| `AGENT_DEVELOPMENT_URL` | http://localhost:18793 | http://172.20.0.13:18789 |
| `AGENT_TESTING_URL` | http://localhost:18794 | http://172.20.0.14:18789 |
| `AGENT_SERVICE_URL` | http://localhost:18795 | http://172.20.0.15:18789 |

## 开发注意事项

- 修改 Python 网关代码后需重新构建 Gateway 镜像：`./0-build-images.sh`
- 修改角色性格（`config/agents/workspace/*.md`）后需重新构建对应 Agent 镜像
- `agent_registry.py` 是 agent URL 的唯一来源，`wecom_gateway.py` 从此导入
- 调度员 openclaw 运行在 Gateway 容器内部（:18789），不对外暴露


# 启动服务
./2-start-local.sh

# 测试服务
./3-test-local.sh

# 停止服务
./4-stop-local.sh

# 清理环境（删除所有数据）
./5-clean-local.sh

# 查看日志
docker logs openclaw-local -f

# 查看容器状态
docker ps | grep openclaw
```

### 生产部署

```bash
# 进入生产部署目录
cd production/

# 1. 准备服务器（在服务器上执行）
./1-prepare-server.sh

# 2. 上传文件到服务器（在本地执行）
./2-upload-to-server.sh

# 3. 部署服务（在服务器上执行）
./3-deploy-production.sh

# 4. 配置 SSL 证书（在服务器上执行）
./4-setup-ssl.sh

# 5. 启动生产服务（在服务器上执行）
./5-start-production.sh

# 6. 健康检查（在服务器上执行）
./6-health-check.sh

# 查看生产环境日志
docker logs openclaw-production -f
docker logs openclaw-nginx -f
```

### 运维脚本

```bash
# 进入脚本目录
cd scripts/

# 备份数据和配置
./backup.sh [backup_name]

# 恢复备份
./restore.sh <backup_file>

# 系统监控
./monitor.sh              # 单次检查
./monitor.sh --watch      # 持续监控

# 更新系统
./update.sh

# 回滚到上一个版本
./rollback.sh

# 清理旧数据和日志
./cleanup.sh

# 安全审计
./security-audit.sh

# 发送告警
./alert.sh "告警消息"
```

### Docker 操作

```bash
# 查看所有容器
docker ps -a

# 重启容器
docker restart openclaw-local          # 本地
docker restart openclaw-production     # 生产

# 进入容器
docker exec -it openclaw-local sh
docker exec -it openclaw-production sh

# 查看容器资源使用
docker stats openclaw-local

# 清理未使用的镜像和容器
docker system prune -a
```

## 配置文件说明

### 环境变量配置

- **本地测试**：`local/.env.local`（从 `local/.env.local.example` 复制）
- **生产环境**：`production/.env.prod`（从 `production/.env.prod.example` 复制）
- **通用配置**：`config/.env.example`

必需配置项：
- `GITHUB_TOKEN` 或 `OPENAI_API_KEY`：AI 模型 API 密钥
- `WECOM_CORP_ID`：企业微信企业 ID
- `WECOM_SECRET`：企业微信应用 Secret
- `WECOM_AGENT_ID`：企业微信应用 ID
- `WECOM_TOKEN`：企业微信消息验证 Token
- `WECOM_ENCODING_AES_KEY`：企业微信消息加密密钥

### 虚拟员工配置

每个虚拟员工的配置文件位于 `config/agents/`：

- `dispatcher.yml`：智能调度员（任务路由）
- `operation.yml`：运营专员（数据分析）
- `product.yml`：产品经理（需求管理）
- `development.yml`：开发工程师（技术支持）
- `testing.yml`：测试工程师（质量保障）
- `service.yml`：客服专员（客户服务）

配置结构：
```yaml
name: "角色名称"
role: "角色标识"
enabled: true
ai:
  model: "github-copilot/claude-sonnet-4.5"
  temperature: 0.7
  max_tokens: 2000
skills: [...]
routing:
  triggers: [关键词列表]
```

## 开发工作流

### 添加新的虚拟员工角色

1. 在 `config/agents/` 创建新的 YAML 配置文件
2. 定义角色的 `name`、`role`、`skills`、`routing` 规则
3. 在环境变量 `AGENTS_ENABLED` 中添加新角色标识
4. 更新 `src/gateway/wecom_gateway.py` 中的 `ROUTING_KEYWORDS`
5. 重启服务测试

### 修改企业微信网关

主要文件：`src/gateway/wecom_gateway.py`

关键类和函数：
- `AccessTokenManager`：管理企业微信 access_token
- `WXBizMsgCrypt`：处理消息加解密
- `route_to_agent()`：根据关键词路由到对应虚拟员工
- `call_openclaw_gateway()`：调用 OpenClaw Gateway API
- `/callback` 路由：处理企业微信回调

修改后需要：
```bash
# 本地测试
cd local/
./4-stop-local.sh
./2-start-local.sh

# 生产环境
docker restart openclaw-production
```

### 调试技巧

1. **查看实时日志**：
   ```bash
   docker logs -f openclaw-local --tail=100
   ```

2. **检查容器健康状态**：
   ```bash
   docker inspect openclaw-local | grep -A 10 Health
   ```

3. **测试 API 端点**：
   ```bash
   curl http://localhost:3000/health
   ```

4. **进入容器调试**：
   ```bash
   docker exec -it openclaw-local sh
   # 查看进程
   ps aux
   # 查看环境变量
   env | grep OPENCLAW
   ```

## 目录结构

```
openclaw-deploy/
├── local/                    # 本地测试环境
│   ├── 1-init-local.sh       # 初始化脚本
│   ├── 2-start-local.sh      # 启动脚本
│   ├── 3-test-local.sh       # 测试脚本
│   ├── 4-stop-local.sh       # 停止脚本
│   ├── 5-clean-local.sh      # 清理脚本
│   ├── docker-compose.local.yml
│   └── .env.local.example
├── production/               # 生产部署环境
│   ├── 1-prepare-server.sh   # 服务器准备
│   ├── 2-upload-to-server.sh # 文件上传
│   ├── 3-deploy-production.sh # 部署脚本
│   ├── 4-setup-ssl.sh        # SSL 配置
│   ├── 5-start-production.sh # 启动脚本
│   ├── 6-health-check.sh     # 健康检查
│   ├── docker-compose.prod.yml
│   └── .env.prod.example
├── config/                   # 配置文件
│   ├── agents/               # 虚拟员工配置
│   │   ├── dispatcher.yml
│   │   ├── operation.yml
│   │   ├── product.yml
│   │   ├── development.yml
│   │   ├── testing.yml
│   │   └── service.yml
│   ├── nginx/                # Nginx 配置
│   ├── .env.example
│   └── docker-compose.*.yml
├── src/                      # 源代码
│   └── gateway/              # 企业微信网关
│       ├── wecom_gateway.py
│       └── requirements.txt
├── scripts/                  # 运维脚本
│   ├── backup.sh             # 备份
│   ├── restore.sh            # 恢复
│   ├── monitor.sh            # 监控
│   ├── update.sh             # 更新
│   ├── rollback.sh           # 回滚
│   ├── cleanup.sh            # 清理
│   ├── security-audit.sh     # 安全审计
│   └── alert.sh              # 告警
├── docs/                     # 文档
│   ├── 00-项目介绍.md
│   ├── 01-本地测试指南.md
│   ├── 02-生产部署指南.md
│   ├── 04-企业微信配置.md
│   ├── 05-运维手册.md
│   ├── 06-故障排查.md
│   ├── 07-API文档.md
│   ├── 10-GitHub-Copilot配置.md
│   └── README.md
├── openspec/                 # OpenSpec 规范
│   ├── project.md            # 项目上下文
│   ├── AGENTS.md             # Agent 规范
│   └── changes/              # 变更记录
├── data/                     # 数据目录（自动生成）
├── logs/                     # 日志目录（自动生成）
└── backups/                  # 备份目录（自动生成）
```

## 重要注意事项

### 安全性

1. **永远不要提交敏感信息**：
   - `.env.local` 和 `.env.prod` 已在 `.gitignore` 中
   - API Keys、Tokens、密码等必须通过环境变量配置

2. **生产环境必须配置 SSL**：
   - 使用 `production/4-setup-ssl.sh` 配置 Let's Encrypt 证书
   - 企业微信回调 URL 必须使用 HTTPS

3. **定期备份**：
   - 使用 `scripts/backup.sh` 定期备份数据和配置
   - 备份文件存储在 `backups/` 目录

### 企业微信集成

1. **消息加解密**：企业微信使用 AES 加密，网关自动处理加解密
2. **Access Token 管理**：自动刷新，提前 5 分钟过期
3. **路由规则**：基于关键词匹配，在 `ROUTING_KEYWORDS` 和各 agent 的 `routing.triggers` 中配置

### 资源限制

- **本地测试**：CPU 2核，内存 4GB
- **生产环境**：CPU 4核，内存 8GB（可在 docker-compose 中调整）

### 日志管理

- 日志自动轮转：本地 10MB×3 文件，生产 50MB×10 文件
- 查看日志：`docker logs <container_name> -f`
- 日志位置：`logs/local/` 或 `logs/gateway/`

## 故障排查

### 常见问题

1. **容器无法启动**：
   - 检查 Docker 是否运行：`docker info`
   - 检查端口占用：`lsof -i :3000`
   - 查看容器日志：`docker logs openclaw-local`

2. **API 调用失败**：
   - 验证 API Key 是否正确配置
   - 检查网络连接
   - 查看 `OPENCLAW_GATEWAY_URL` 配置

3. **企业微信回调失败**：
   - 验证 Token 和 EncodingAESKey 配置
   - 检查 URL 验证是否通过
   - 查看网关日志中的错误信息

4. **虚拟员工无响应**：
   - 检查 `AGENTS_ENABLED` 配置
   - 验证 agent 配置文件是否正确
   - 检查路由关键词是否匹配

详细故障排查步骤参见 `docs/06-故障排查.md`。

## 相关文档

- 项目介绍：`docs/00-项目介绍.md`
- 本地测试：`docs/01-本地测试指南.md`
- 生产部署：`docs/02-生产部署指南.md`
- 企业微信配置：`docs/03-企业微信配置.md`
- 运维手册：`docs/05-运维手册.md`
- API 文档：`docs/07-API文档.md`
