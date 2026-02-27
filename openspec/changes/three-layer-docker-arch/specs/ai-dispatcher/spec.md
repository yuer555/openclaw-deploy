## ADDED Requirements

### Requirement: AIDispatcher 通过 WebSocket RPC 分析意图
系统 SHALL 实现 `AIDispatcher` 类，通过 WebSocket RPC 调用 Gateway 容器内的调度员 openclaw（`ws://localhost:18789`），发送用户消息，要求调度员只返回目标 agent ID（operation/product/development/testing/service）。

#### Scenario: 意图分析返回正确 agent ID
- **WHEN** 用户发送消息"帮我写个登录功能的测试用例"
- **THEN** `AIDispatcher.route()` 返回 `("testing", "http://openclaw-agent-testing:18789")`

#### Scenario: 意图分析超时 fallback
- **WHEN** 调度员 openclaw 在 5 秒内未返回结果
- **THEN** `AIDispatcher.route()` 返回 `("service", <service_url>)`，并记录 warning 日志

#### Scenario: 意图分析返回无效 ID fallback
- **WHEN** 调度员 openclaw 返回不在 AGENT_REGISTRY 中的字符串
- **THEN** `AIDispatcher.route()` fallback 到 `("service", <service_url>)`

### Requirement: 删除关键词路由
系统 SHALL 删除 `wecom_gateway.py` 中的 `ROUTING_KEYWORDS` 字典和基于关键词的 `route_message()` 实现，改为调用 `AIDispatcher.route()`。

#### Scenario: 消息路由不再依赖关键词
- **WHEN** 用户发送不含任何预设关键词的消息"最近业务怎么样"
- **THEN** 系统仍能通过 AI 意图分析路由到合适的 agent（如 operation）

### Requirement: agent_registry.py 集中管理 agent URL

#### Scenario: 环境变量覆盖默认 URL
- **WHEN** 设置环境变量 `AGENT_OPERATION_URL=http://openclaw-agent-operation:18789`
- **THEN** `AGENT_REGISTRY["operation"]["url"]` 返回该值
