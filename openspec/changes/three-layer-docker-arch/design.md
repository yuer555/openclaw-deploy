## Context

当前系统（V1.4）所有虚拟员工共用同一个 openclaw 实例（主机端口 18789），消息路由通过 `ROUTING_KEYWORDS` 关键词字典匹配，Flask 网关（wecom_gateway.py + telegram_adapter.py）直接调用该实例。

问题：
- 关键词路由无法理解语义，误路由率高
- 所有角色共享一个 openclaw 进程，无法独立配置性格、模型参数
- 网关进程与 openclaw 进程混合在宿主机，无法 Docker 化整体部署
- 本地开发和生产环境缺乏统一的容器化方案

目标架构：三层 Docker 隔离，AI 意图路由。

```
┌─────────────────────────────────────────────────────────────────┐
│  Docker Network: openclaw-network                               │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Container: openclaw-gateway  (第一层)                     │  │
│  │                                                           │  │
│  │  ┌──────────────────────┐   ┌─────────────────────────┐  │  │
│  │  │  Flask Gateway :8000 │   │  openclaw (调度员)       │  │  │
│  │  │  - wecom_gateway.py  │──▶│  :18789 (container内部) │  │  │
│  │  │  - telegram_adapter  │   │  workspace: /workspace  │  │  │
│  │  │  - agent_registry.py │   │  CLAUDE.md: 调度员性格  │  │  │
│  │  └──────────────────────┘   └─────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
│       │ HTTP 路由到对应 agent 容器                               │
│       ▼                                                         │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐           │
│  │openclaw-agent│ │openclaw-agent│ │openclaw-agent│           │
│  │-operation    │ │-product      │ │-development  │           │
│  │:18791        │ │:18792        │ │:18793        │           │
│  └──────────────┘ └──────────────┘ └──────────────┘           │
│  ┌──────────────┐ ┌──────────────┐                             │
│  │openclaw-agent│ │openclaw-agent│                             │
│  │-testing      │ │-service      │                             │
│  │:18794        │ │:18795        │                             │
│  └──────────────┘ └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

## Goals / Non-Goals

**Goals:**
- Gateway 容器：Flask 网关 + 调度员 openclaw 合并为单一容器，对外暴露 :8000
- AI 意图路由：调度员通过 WebSocket RPC 调用容器内 openclaw 分析意图，返回目标 agent ID
- Agent 隔离：5 个虚拟员工各自独立容器，独立 openclaw 实例，独立性格配置
- 性格预置：通过 openclaw 原生 CLAUDE.md 机制（workspace 目录），在构建镜像时预置各角色性格
- 本地 Docker 化：`local/` 目录提供一键启动全部容器的完整方案
- 生产 Docker 化：`production/` 目录更新适配新架构

**Non-Goals:**
- 不引入 Kubernetes 或服务网格
- 不实现 agent 动态扩缩容
- 不修改 openclaw 核心代码
- 不支持跨容器共享会话状态（每个 agent 容器维护自己的会话）

## Decisions

### 决策 1：Gateway + 调度员合并为单容器

**选择**：Flask 网关进程与调度员 openclaw 进程运行在同一容器内，通过 `localhost:18789` 通信。

**理由**：
- 调度员 openclaw 仅供 Gateway 内部使用，无需对外暴露
- 同容器通信延迟最低（loopback），无网络跳转
- 简化部署：一个容器对外只暴露 :8000

**备选方案**：调度员单独容器 → 增加网络跳转，增加运维复杂度，无明显收益。

### 决策 2：openclaw 原生 CLAUDE.md 作为性格配置机制

**选择**：在构建 Docker 镜像时，将各角色的 `CLAUDE.md` 预置到 `/workspace/CLAUDE.md`（openclaw 默认读取路径）。

**理由**：
- CLAUDE.md 是 openclaw 的原生 workspace 配置机制，无需额外适配
- 构建时预置（而非运行时复制）：镜像即包含性格，无启动依赖
- 各角色镜像独立，性格差异通过不同 Dockerfile 或 build arg 实现

**备选方案**：运行时通过 entrypoint 复制 → 增加启动复杂度，且容器重启后若 volume 已有文件则不会覆盖，行为不一致。

**说明**：CLAUDE.md 是 openclaw 读取 workspace 上下文的标准方式，等同于"系统提示词"，这是 openclaw 的原生机制，不是外部注入。

### 决策 3：AI 意图路由替代关键词匹配

**选择**：删除 `ROUTING_KEYWORDS`，新增 `AIDispatcher` 类，通过 WebSocket RPC 调用调度员 openclaw，prompt 要求其只返回 agent ID（operation/product/development/testing/service），fallback 到 service。

**理由**：
- 语义理解优于关键词匹配，减少误路由
- 调度员 openclaw 已在 Gateway 容器内，调用成本低
- 失败时 fallback 到 service，保证可用性

**备选方案**：保留关键词匹配作为 fallback → 增加维护两套路由逻辑的负担，不采用。

### 决策 4：agent_registry.py 集中管理 URL

**选择**：新建 `src/gateway/agent_registry.py`，定义 `AGENT_REGISTRY` 字典，wecom_gateway 和 telegram_adapter 均从此导入。

**理由**：避免两个文件各自硬编码 agent URL，单一来源便于维护。

### 决策 5：本地用 localhost+port，生产用 Docker 固定 IP+PORT，不引入 Nginx

**选择**：
- **本地**：所有容器端口映射到宿主机，gateway 通过 `http://localhost:18791-18795` 访问 agent，开发者通过 `http://localhost:8000` 访问 gateway
- **生产**：Docker 自定义网络配置固定子网（`172.20.0.0/16`），各容器分配固定 IP（gateway: 172.20.0.10，agents: 172.20.0.11-15），gateway 通过 `http://172.20.0.1x:18789` 访问 agent，agent 不映射宿主机端口，外部只访问 gateway:8000

**理由**：
- 生产环境非单一宿主机，容器间通信使用 Docker 网络 IP 而非宿主机 IP，避免跨主机端口冲突
- 固定 IP 使 `AGENT_*_URL` 可静态配置在 `.env.prod`，无需运行时 `docker inspect`
- agent 不暴露宿主机端口，安全性更好
- 无 Nginx，架构简单

**备选方案**：容器名 DNS 解析 → 需要所有容器在同一 compose 项目内，跨 compose 文件时 DNS 不可用；宿主机 IP+PORT → 生产非单一宿主机时不适用。

### 决策 6：本地部署使用独立 docker-compose 文件

**选择**：
- `local/docker-compose.local.yml`：启动 gateway 容器（含调度员）
- `config/docker-compose.agents.yml`：启动 5 个 agent 容器
- 本地脚本通过 `-f` 组合两个文件，或分步启动

**理由**：agent 容器可独立于 gateway 启动/重启，便于开发调试单个 agent。

## Risks / Trade-offs

- **[风险] 调度员 openclaw 启动慢** → Gateway 容器 entrypoint 先启动 openclaw，等待健康检查通过后再启动 Flask；或 Flask 启动时对调度员做 lazy connect
- **[风险] AI 路由延迟增加** → 调度员 prompt 设计要简洁，要求只返回一个单词；设置超时（5s），超时 fallback 到 service
- **[风险] agent 容器首次启动慢（npm install openclaw）** → 使用预构建镜像（Dockerfile.agents），将 npm install 移到构建阶段
- **[风险] 本地端口冲突** → 文档明确说明端口占用（8000, 18789-18795），init 脚本检查端口
- **[Trade-off] 镜像体积增大** → 每个 agent 容器包含完整 node:24 + openclaw，约 500MB/容器；可接受，换取隔离性

## Migration Plan

1. 构建新镜像（gateway + agent × 5）
2. 停止旧容器（openclaw-local）
3. 启动新容器组（gateway + agents）
4. 验证健康检查通过
5. 验证消息路由正确

**回滚**：保留旧 `docker-compose.local.yml` 备份，回滚只需 `docker compose up -d` 旧配置。

## Open Questions

- openclaw `--allow-unconfigured` 模式下，CLAUDE.md 是否在容器内 `/workspace/CLAUDE.md` 路径生效？需在构建后验证。
- 调度员 openclaw 的 session_key 格式：`agent:dispatcher:gateway-routing` 是否与 openclaw 路由规则兼容？
- 生产环境 agent 容器是否需要 Nginx 反向代理，还是 gateway 直接通过容器名访问？（当前方案：直接容器名访问，无需 Nginx）
