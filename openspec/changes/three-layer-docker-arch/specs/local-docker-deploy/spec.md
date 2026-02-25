## ADDED Requirements

### Requirement: 本地一键启动全部容器
本地部署 SHALL 提供 `local/2-start-local.sh` 脚本，一键启动 gateway 容器和全部 5 个 agent 容器，无需手动执行多条命令。

#### Scenario: 一键启动所有服务
- **WHEN** 在 `local/` 目录执行 `./2-start-local.sh`
- **THEN** openclaw-gateway（:8000）和 5 个 agent 容器（:18791-18795）全部启动，健康检查通过

#### Scenario: 启动前检查端口占用
- **WHEN** 执行 `./1-init-local.sh`
- **THEN** 脚本检查 8000、18791-18795 端口是否被占用，若占用则提示用户并退出

### Requirement: 本地部署使用 localhost+port 访问各服务
本地部署 SHALL 将所有容器端口映射到宿主机，gateway 通过 `http://localhost:18791-18795` 访问各 agent 容器，开发者通过 `http://localhost:8000` 访问 gateway。

#### Scenario: gateway 通过 localhost 访问 agent
- **WHEN** 两个 compose 文件启动后
- **THEN** gateway 容器通过 `http://localhost:18791`（operation）等访问各 agent，所有端口映射到宿主机

#### Scenario: 开发者直接访问各服务
- **WHEN** 开发者需要调试某个 agent
- **THEN** 可直接通过 `http://localhost:18791-18795` 访问对应 agent，通过 `http://localhost:8000` 访问 gateway

### Requirement: 本地部署提供详细教程文档
本地部署 SHALL 提供 `docs/01-本地测试指南.md` 更新版，包含：前置条件、环境变量配置说明、分步启动教程、验证步骤、常见问题排查。

#### Scenario: 新用户按文档完成本地部署
- **WHEN** 用户按照 `docs/01-本地测试指南.md` 操作
- **THEN** 能在 30 分钟内完成本地环境搭建并验证消息路由正常

### Requirement: 本地部署支持单独重启单个 agent
本地部署 SHALL 支持单独重启某个 agent 容器而不影响其他服务。

#### Scenario: 单独重启 operation agent
- **WHEN** 执行 `docker restart openclaw-agent-operation`
- **THEN** 只有 operation 容器重启，其他容器和 gateway 不受影响

### Requirement: 本地部署提供镜像预构建脚本
本地部署 SHALL 提供 `local/0-build-images.sh` 脚本，在首次启动前预构建 gateway 镜像和 agent 镜像。

#### Scenario: 预构建镜像成功
- **WHEN** 执行 `./0-build-images.sh`
- **THEN** `openclaw-gateway:local` 和 `openclaw-agent:local` 镜像构建成功，后续启动无需重新构建
