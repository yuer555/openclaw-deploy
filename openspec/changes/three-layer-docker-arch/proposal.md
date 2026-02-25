## Why

当前系统所有虚拟员工共用同一个 openclaw 实例，消息路由依赖关键词匹配，无法理解用户真实意图，且各角色之间没有隔离，无法独立扩展或配置。需要重构为三层 Docker 隔离架构，用 AI 意图分析替代关键词路由，并提供完整的本地和生产 Docker 化部署方案。

## What Changes

- **新增** Gateway 容器（`openclaw-gateway`）：将 Flask 网关（企业微信 + Telegram）与调度员 openclaw 实例合并到同一个 Docker 容器，调度员通过 WebSocket RPC 调用本容器内的 openclaw 做意图分析
- **新增** 5 个虚拟员工独立容器（`openclaw-agent-*`）：每个角色运行独立的 openclaw 实例，通过 openclaw 原生 workspace 配置初始性格，端口 18791-18795
- **替换** 关键词路由 → AI 意图路由：删除 `ROUTING_KEYWORDS`，改为调用 Gateway 容器内的调度员 openclaw 分析意图并返回目标 agent
- **新增** `agent_registry.py`：集中管理各虚拟员工容器 URL，供 wecom_gateway 和 telegram_adapter 共用
- **重写** `config/docker-compose.agents.yml`：5 个虚拟员工服务，使用 `Dockerfile.agents` 预构建镜像
- **新增** Gateway 容器 Dockerfile（`src/gateway/Dockerfile.gateway`）：包含 Flask 网关 + openclaw 调度员
- **新增** 本地 Docker 化完整部署方案：更新 `local/` 目录脚本和 `docker-compose.local.yml`，支持一键启动全部容器
- **更新** 生产部署方案：更新 `production/docker-compose.prod.yml` 和相关脚本，支持新架构
- **新增** 各角色 openclaw workspace 初始配置（`config/agents/workspace/`）：通过 openclaw 原生 CLAUDE.md 机制配置角色性格，在构建镜像时预置

## Capabilities

### New Capabilities

- `gateway-container`: Gateway 容器，包含 Flask 网关 + 调度员 openclaw，负责接收消息、AI 意图分析、路由转发
- `agent-isolation`: 5 个虚拟员工独立 Docker 容器，各自运行独立 openclaw 实例，互不干扰
- `ai-dispatcher`: AI 意图分析路由，替代关键词匹配，通过调度员 openclaw WebSocket RPC 分析用户意图
- `agent-personality`: 各角色 openclaw 初始性格配置，通过 openclaw 原生 workspace CLAUDE.md 机制预置
- `local-docker-deploy`: 本地 Docker 化完整部署方案，一键启动全部服务（gateway + 5 agents）
- `production-docker-deploy`: 生产 Docker 化部署方案，支持新三层架构

### Modified Capabilities

## Impact

- `src/gateway/wecom_gateway.py`：删除 `ROUTING_KEYWORDS`，新增 `AIDispatcher` 类，修改 `route_message()` 和 `call_openclaw_agent()`
- `src/gateway/telegram_adapter.py`：移除硬编码 `AGENTS` 字典，改用 `AGENT_REGISTRY`，支持 AI 路由
- `src/gateway/agent_registry.py`：新文件，集中管理 agent URL 注册表
- `config/docker-compose.agents.yml`：重写为 5 个服务，使用预构建镜像
- `config/agents/workspace/`：新目录，存放各角色 openclaw workspace 初始文件（CLAUDE.md）
- `src/gateway/Dockerfile.gateway`：新文件，Gateway 容器镜像定义
- `local/docker-compose.local.yml`：更新，引入 gateway 容器和 agent 容器
- `local/1-init-local.sh` ~ `local/5-clean-local.sh`：更新，适配新架构
- `production/docker-compose.prod.yml`：更新，适配新架构
- 环境变量新增：`AGENT_OPERATION_URL`、`AGENT_PRODUCT_URL`、`AGENT_DEVELOPMENT_URL`、`AGENT_TESTING_URL`、`AGENT_SERVICE_URL`
