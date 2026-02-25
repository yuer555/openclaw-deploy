## ADDED Requirements

### Requirement: Gateway 容器包含 Flask 网关和调度员 openclaw
Gateway 容器 SHALL 在同一 Docker 容器内同时运行 Flask 网关进程（:8000）和调度员 openclaw 进程（:18789 容器内部），两者通过 localhost 通信。

#### Scenario: 容器启动时两个进程均就绪
- **WHEN** `openclaw-gateway` 容器启动
- **THEN** openclaw 进程在 :18789 监听，Flask 进程在 :8000 监听，健康检查 `GET /health` 返回 200

#### Scenario: Flask 网关调用容器内调度员
- **WHEN** Flask 网关需要做意图分析
- **THEN** 通过 `ws://localhost:18789` WebSocket RPC 调用调度员 openclaw，无需跨容器网络

### Requirement: Gateway 容器对外只暴露 Flask 端口
Gateway 容器 SHALL 只对外暴露 :8000（Flask），调度员 openclaw :18789 不对外暴露。

#### Scenario: 外部只能访问 Flask 端口
- **WHEN** 外部服务访问 Gateway 容器
- **THEN** 只有 :8000 可达，:18789 不可从容器外访问

### Requirement: Gateway 容器使用独立 Dockerfile 构建
Gateway 容器 SHALL 使用 `src/gateway/Dockerfile.gateway` 构建，包含 Python 依赖（Flask、requests、pycryptodome、websocket-client）和 Node.js + openclaw。

#### Scenario: 镜像构建包含所有依赖
- **WHEN** 执行 `docker build -f src/gateway/Dockerfile.gateway`
- **THEN** 镜像包含 Python 3.11、Flask、openclaw（npm global），可直接运行
