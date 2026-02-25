## ADDED Requirements

### Requirement: 每个虚拟员工运行独立 Docker 容器
系统 SHALL 为 5 个虚拟员工（operation、product、development、testing、service）各自运行独立的 Docker 容器，每个容器内运行独立的 openclaw 实例。

#### Scenario: 5 个 agent 容器独立运行
- **WHEN** 执行 `docker compose -f config/docker-compose.agents.yml up -d`
- **THEN** 5 个容器（openclaw-agent-operation/product/development/testing/service）均处于 running 状态

#### Scenario: 单个 agent 容器重启不影响其他
- **WHEN** `openclaw-agent-operation` 容器重启
- **THEN** 其他 4 个 agent 容器继续正常运行，Gateway 路由到其他 agent 的消息不受影响

### Requirement: 各 agent 容器端口映射固定
各 agent 容器 SHALL 使用固定端口映射：operation:18791、product:18792、development:18793、testing:18794、service:18795，容器内 openclaw 监听 :18789。

#### Scenario: 端口映射正确
- **WHEN** agent 容器启动后
- **THEN** `curl http://localhost:18791/health` 返回 200（operation），其余端口同理

### Requirement: agent 容器使用预构建镜像
各 agent 容器 SHALL 使用基于 `config/Dockerfile.agents` 预构建的镜像（`openclaw-agent:latest`），npm install 在构建阶段完成，不在运行时安装。

#### Scenario: 容器启动无需网络下载依赖
- **WHEN** agent 容器从预构建镜像启动
- **THEN** 容器在 60 秒内完成启动，无需执行 npm install
