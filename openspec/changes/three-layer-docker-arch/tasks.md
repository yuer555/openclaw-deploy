## 1. 角色性格配置文件

- [x] 1.1 创建 `config/agents/workspace/` 目录，编写 `dispatcher.md`（调度员 CLAUDE.md：意图分析、路由指令、只返回 agent ID）
- [x] 1.2 编写 `config/agents/workspace/operation.md`（运营专员性格：数据分析、运营策略、用户增长）
- [x] 1.3 编写 `config/agents/workspace/product.md`（产品经理性格：需求管理、产品规划、用户故事）
- [x] 1.4 编写 `config/agents/workspace/development.md`（开发工程师性格：代码实现、技术架构、Bug修复）
- [x] 1.5 编写 `config/agents/workspace/testing.md`（测试工程师性格：测试用例、质量保障、缺陷管理）
- [x] 1.6 编写 `config/agents/workspace/service.md`（客服专员性格：客户服务、问题解答、投诉处理）

## 2. Docker 镜像

- [x] 2.1 创建 `src/gateway/Dockerfile.gateway`：基于 python:3.11-slim + node:24，安装 Flask 依赖和 openclaw，COPY dispatcher.md 到 `/workspace/CLAUDE.md`
- [x] 2.2 更新 `config/Dockerfile.agents`：在构建阶段 COPY 对应角色 CLAUDE.md（通过 build arg `ROLE` 选择），预置到 `/workspace/CLAUDE.md`
- [x] 2.3 验证 Gateway 镜像构建：`docker build -f src/gateway/Dockerfile.gateway -t openclaw-gateway:local .`
- [x] 2.4 验证 Agent 镜像构建：`docker build --build-arg ROLE=testing -f config/Dockerfile.agents -t openclaw-agent:local .`

## 3. Python 网关代码

- [x] 3.1 创建 `src/gateway/agent_registry.py`：定义 `AGENT_REGISTRY`（从环境变量读取各 agent URL，默认 localhost:18791-18795）和 `DISPATCHER_URL`
- [x] 3.2 修改 `src/gateway/wecom_gateway.py`：删除 `ROUTING_KEYWORDS`，新增 `AIDispatcher` 类（WebSocket RPC 调用 localhost:18789，5s 超时，fallback service）
- [x] 3.3 修改 `src/gateway/wecom_gateway.py`：更新 `route_message()` 调用 `AIDispatcher.route()`，更新 `call_openclaw_agent()` 接受 `gateway_url` 参数
- [x] 3.4 修改 `src/gateway/telegram_adapter.py`：移除硬编码 `AGENTS` 字典，改从 `agent_registry` 导入 `AGENT_REGISTRY`，`_call_agent()` 接受 `openclaw_url` 参数
- [x] 3.5 修改 `src/gateway/telegram_adapter.py`：`_handle_message()` 中若用户未手动选择 agent，调用 `AIDispatcher.route()` 获取目标 URL；`/agents` 命令从 `AGENT_REGISTRY` 动态生成列表

## 4. Docker Compose 配置

- [x] 4.1 更新 `local/docker-compose.local.yml`：改为构建 `openclaw-gateway:local` 镜像，注入 `AGENT_*_URL` 环境变量（使用容器名），加入 `openclaw-network`
- [x] 4.2 重写 `config/docker-compose.agents.yml`：5 个服务（operation/product/development/testing/service），使用 `openclaw-agent:local` 镜像，端口 18791-18795，挂载 data volume，加入 `openclaw-network`
- [x] 4.3 更新 `production/docker-compose.prod.yml`：加入 gateway 容器（ports: 8000）和 5 个 agent 容器（expose: 18789，不映射宿主机），配置固定子网 `172.20.0.0/16`，各容器分配固定 IP（gateway: 172.20.0.10，agents: 172.20.0.11-15），移除 Nginx 服务
- [x] 4.4 更新 `production/.env.prod.example`：新增 `AGENT_OPERATION_URL=http://172.20.0.11:18789` 等 5 条固定 Docker IP 配置
- [x] 4.5 更新 `local/.env.local.example`：新增 `AGENT_*_URL=http://localhost:1879x` 5 条配置（本地 localhost+port）

## 5. 本地部署脚本

- [x] 5.1 新增 `local/0-build-images.sh`：构建 `openclaw-gateway:local` 和 `openclaw-agent:local` 镜像
- [x] 5.2 更新 `local/1-init-local.sh`：检查 8000、18791-18795 端口占用，创建 agent data 目录（`data/agents/{operation,product,development,testing,service}`）
- [x] 5.3 更新 `local/2-start-local.sh`：同时启动 gateway compose 和 agents compose，等待所有容器健康检查通过
- [x] 5.4 更新 `local/3-test-local.sh`：测试 gateway 健康检查（:8000/health）和各 agent 健康检查（:18791-18795/health），发送测试消息验证 AI 路由
- [x] 5.5 更新 `local/4-stop-local.sh`：停止 gateway 和 agents 两个 compose
- [x] 5.6 更新 `local/5-clean-local.sh`：清理所有容器、镜像和 data 目录

## 6. 生产部署脚本

- [x] 6.1 更新 `production/3-deploy-production.sh`：构建新架构镜像，处理 agent workspace 目录创建
- [x] 6.2 更新 `production/5-start-production.sh`：启动 gateway + agents，等待健康检查（无 Nginx）
- [x] 6.3 更新 `production/6-health-check.sh`：检查 gateway 和 5 个 agent 容器的运行状态，输出各服务 IP+PORT 访问地址

## 7. 文档更新

- [x] 7.1 更新 `docs/01-本地测试指南.md`：完整本地 Docker 化部署教程（前置条件、构建镜像、配置环境变量、启动、验证、常见问题）
- [x] 7.2 更新 `docs/02-生产部署指南.md`：新三层架构生产部署方案
- [x] 7.3 更新 `CLAUDE.md`（项目根目录）：更新目录结构说明，反映新架构

## 8. 验证

- [ ] 8.1 本地验证：启动全部容器，发送"帮我写个测试用例"，确认路由到 testing agent
- [ ] 8.2 本地验证：Telegram 发送 `/operation` 手动切换，再发消息确认路由到 operation agent
- [ ] 8.3 本地验证：停止单个 agent 容器，确认其他 agent 和 gateway 正常运行
- [ ] 8.4 本地验证：检查各 agent 容器内 `/workspace/CLAUDE.md` 内容正确
