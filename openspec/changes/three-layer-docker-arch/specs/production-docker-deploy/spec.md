## ADDED Requirements

### Requirement: 生产部署使用新三层架构 compose 文件，通过 Docker IP+PORT 访问
生产部署 SHALL 更新 `production/docker-compose.prod.yml`，包含 gateway 容器和 5 个 agent 容器。容器间通过 Docker 分配的容器 IP+PORT 通信（`AGENT_*_URL` 在运行时通过 `docker inspect` 或固定 IP 配置）。外部通过宿主机 IP:8000 访问 gateway。

```
外部请求
  http://<host-ip>:8000/wecom/callback
        │
        ▼
  openclaw-gateway（Docker IP: 172.x.x.x:8000，宿主机端口映射）
        │ http://<docker-ip-of-agent>:18789
        ▼
  openclaw-agent-* （各自 Docker IP，端口 18789 容器内部）
```

#### Scenario: 生产环境全部容器启动
- **WHEN** 在生产服务器执行 `./5-start-production.sh`
- **THEN** openclaw-gateway 和 5 个 agent 容器全部启动，健康检查通过

#### Scenario: gateway 通过 Docker IP 访问 agent
- **WHEN** gateway 容器路由消息到 operation agent
- **THEN** 通过 `http://<docker-ip-of-openclaw-agent-operation>:18789` 访问，使用 Docker 网络固定 IP 或容器名解析

#### Scenario: 外部通过宿主机 IP+PORT 访问 gateway
- **WHEN** 企业微信回调请求 `http://<host-ip>:8000/wecom/callback`
- **THEN** gateway 容器处理请求并返回响应

### Requirement: 生产部署使用 Docker 自定义网络固定子网
生产部署 SHALL 在 compose 文件中定义固定子网（如 `172.20.0.0/16`），并为各容器分配固定 IP，使 `AGENT_*_URL` 可在 `.env.prod` 中静态配置。

#### Scenario: 容器使用固定 Docker IP
- **WHEN** 查看 `production/docker-compose.prod.yml`
- **THEN** 各 agent 容器配置 `networks.openclaw-network.ipv4_address`（如 172.20.0.11-15），gateway 配置 172.20.0.10

#### Scenario: 环境变量使用固定 Docker IP
- **WHEN** 查看 `production/.env.prod.example`
- **THEN** 包含 `AGENT_OPERATION_URL=http://172.20.0.11:18789` 等 5 条固定 IP 配置

### Requirement: 生产部署 agent 容器不映射宿主机端口
生产环境中，5 个 agent 容器 SHALL 只使用 `expose: 18789`（Docker 网络内可见），不使用 `ports` 映射到宿主机。gateway 通过 Docker 固定 IP 访问 agent，外部无法直接访问 agent 容器。

#### Scenario: 生产环境 agent 端口不对外暴露
- **WHEN** 外部尝试访问生产服务器的任意 agent 端口
- **THEN** 连接被拒绝，agent 只在 Docker 网络内通过固定 IP:18789 可达

### Requirement: 生产部署提供健康检查脚本
生产部署 SHALL 更新 `production/6-health-check.sh`，检查 gateway 容器和全部 5 个 agent 容器的健康状态。

#### Scenario: 健康检查报告所有服务状态
- **WHEN** 执行 `./6-health-check.sh`
- **THEN** 输出每个容器（gateway + 5 agents + nginx）的运行状态和健康检查结果

### Requirement: 生产部署支持滚动更新单个 agent
生产部署 SHALL 支持在不停止 gateway 的情况下，单独更新某个 agent 容器镜像。

#### Scenario: 滚动更新 development agent
- **WHEN** 执行 `docker compose pull openclaw-agent-development && docker compose up -d openclaw-agent-development`
- **THEN** 只有 development 容器重建，gateway 和其他 agent 不中断

### Requirement: 生产部署环境变量包含 agent URL 配置
生产部署 SHALL 在 `production/.env.prod.example` 中包含各 agent 容器 URL 配置，使用 Docker 网络容器名作为默认值。

#### Scenario: 生产环境变量使用容器名 URL
- **WHEN** 查看 `production/.env.prod.example`
- **THEN** 包含 `AGENT_OPERATION_URL=http://openclaw-agent-operation:18789` 等 5 条配置
