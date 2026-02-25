## ADDED Requirements

### Requirement: 各角色 openclaw workspace 预置 CLAUDE.md
每个 Docker 镜像（gateway 调度员 + 5 个 agent）SHALL 在构建时将对应角色的 `CLAUDE.md` 预置到 `/workspace/CLAUDE.md`，作为 openclaw 的初始性格配置（系统提示词）。

#### Scenario: 调度员容器包含调度员性格
- **WHEN** `openclaw-gateway` 容器启动
- **THEN** `/workspace/CLAUDE.md` 存在，内容为调度员角色定义（意图分析、路由决策、只返回 agent ID）

#### Scenario: agent 容器包含对应角色性格
- **WHEN** `openclaw-agent-testing` 容器启动
- **THEN** `/workspace/CLAUDE.md` 存在，内容为测试工程师角色定义（测试用例、质量保障等）

#### Scenario: volume 挂载不覆盖预置性格
- **WHEN** agent 容器挂载 data volume 到 `/workspace`
- **THEN** 若 volume 中已有 `CLAUDE.md`，保留 volume 中的版本（用户自定义优先）；若无，使用镜像预置版本

### Requirement: 性格配置文件存放在 config/agents/workspace/
各角色的 `CLAUDE.md` 源文件 SHALL 存放在 `config/agents/workspace/<role>.md`，在 Dockerfile 构建时 COPY 到镜像的 `/workspace/CLAUDE.md`。

#### Scenario: 源文件结构清晰
- **WHEN** 查看 `config/agents/workspace/` 目录
- **THEN** 包含 dispatcher.md、operation.md、product.md、development.md、testing.md、service.md 共 6 个文件

### Requirement: CLAUDE.md 包含角色定位和行为规范
每个角色的 `CLAUDE.md` SHALL 包含：角色名称与定位、核心能力描述、工作风格、输出格式规范，调度员的 CLAUDE.md 还 SHALL 包含可用 agent 列表和路由指令（只返回 agent ID）。

#### Scenario: 调度员 CLAUDE.md 包含路由指令
- **WHEN** 调度员 openclaw 收到路由请求
- **THEN** 根据 CLAUDE.md 中的指令，只返回一个 agent ID 字符串，不返回其他内容
