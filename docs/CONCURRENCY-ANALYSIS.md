# OpenClaw 多用户并发风险分析

> 基于 OpenClaw 源码分析 (2026-03-02)

## 执行摘要

**核心发现**：OpenClaw 的默认配置适合 **小团队使用**（1-10 人），在 **100+ 并发用户** 场景下存在性能瓶颈风险。

**主要风险**：
1. ⚠️ 并发请求限制（默认仅 4 个）
2. ⚠️ 会话文件锁竞争
3. ⚠️ 长时间请求阻塞队列（默认 10 分钟超时）
4. ⚠️ WebSocket 连接数限制

---

## 1. 并发控制机制

### 1.1 配置项

OpenClaw 使用 **并发槽（concurrency slots）** 机制限制同时处理的请求数量：

| 配置项 | 默认值 | 位置 | 说明 |
|--------|--------|------|------|
| `agents.defaults.maxConcurrent` | **4** | `openclaw.json` | 主 agent 最大并发数 |
| `agents.defaults.subagents.maxConcurrent` | **8** | `openclaw.json` | 子 agent 最大并发数 |
| `agents.list[].maxConcurrent` | 继承默认值 | `openclaw.json` | 单个 agent 可覆盖 |

**代码位置**：
- `packages/core/src/gateway/local/agents.ts` - Agent 配置加载
- `packages/core/src/gateway/local/command-lanes.ts` - 并发槽管理

### 1.2 工作原理

```
┌─────────────────────────────────────────────────────┐
│  请求队列 (Command Lane Queue)                        │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐        │
│  │ R1 │ │ R2 │ │ R3 │ │ R4 │ │ R5 │ │ R6 │ ...    │
│  └────┘ └────┘ └────┘ └────┘ └────┘ └────┘        │
└─────────────────────────────────────────────────────┘
         │        │        │        │
         ▼        ▼        ▼        ▼
    ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
    │ Slot1│ │ Slot2│ │ Slot3│ │ Slot4│  ◄── maxConcurrent = 4
    └──────┘ └──────┘ └──────┘ └──────┘
         │        │        │        │
         ▼        ▼        ▼        ▼
    Processing... (最长 10 分钟)
```

**关键点**：
- 超过并发限制的请求会 **排队等待**
- 如果队列满了，新请求会被 **延迟或拒绝**
- 每个请求占用一个槽位，直到完成（最长 10 分钟）

### 1.3 多用户风险场景

**场景 1：100 用户同时发送消息**
```
并发槽: 4 个
排队请求: 96 个
等待时间: 假设每个请求 30 秒，第 96 个用户需等待 12 分钟
结果: ❌ 用户体验极差，大部分用户超时
```

**场景 2：10 用户发送复杂任务（每个 5 分钟）**
```
并发槽: 4 个
占用时间: 5 分钟 × 4 = 20 分钟总处理时间
等待时间: 后面 6 个用户需等待 10-15 分钟
结果: ⚠️ 部分用户会遇到超时
```

---

## 2. 会话管理机制

### 2.1 存储方式

OpenClaw 使用 **文件系统** 存储会话数据：

```
~/.openclaw/workspace/
├── .sessions/
│   ├── agent:main:wecom:dev-main:user001.json
│   ├── agent:main:wecom:dev-main:user002.json
│   ├── agent:work:wecom:dev-work:user001.json
│   └── ...
```

**代码位置**：
- `packages/core/src/session/file-session-repo.ts`

### 2.2 关键参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| Session 缓存 TTL | **45 秒** | 内存缓存失效时间 |
| 文件锁超时 | **30 秒** | 等待文件锁的最长时间 |
| 文件锁重试间隔 | **50 毫秒** | 重试获取锁的间隔 |

### 2.3 并发写入风险

**问题**：多个请求同时修改同一个会话文件时，使用 **文件锁（file locking）** 机制：

```typescript
// packages/core/src/session/file-session-repo.ts
async acquireLock(sessionKey: string, timeoutMs = 30000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (!this.locks.has(sessionKey)) {
      this.locks.set(sessionKey, true);
      return;
    }
    await sleep(50); // 等待 50ms 后重试
  }
  throw new Error(`Failed to acquire lock for ${sessionKey}`);
}
```

**风险场景**：
- **场景 A**：100 用户 → 100 个会话文件 → ✅ 无锁竞争（不同文件）
- **场景 B**：1 用户快速发 10 条消息 → ⚠️ 同一文件锁竞争
- **场景 C**：1 用户 + 网络问题导致重复请求 → ❌ 可能死锁或锁超时

### 2.4 会话数量限制

**当前实现**：❌ **无硬性限制**

- 会话数量仅受文件系统限制
- 每个会话约 1-10 KB（取决于对话长度）
- 理论上可支持 10,000+ 会话

**潜在问题**：
- 大量会话文件会导致目录读取变慢
- 缓存失效后需要频繁读取文件

---

## 3. WebSocket 连接限制

### 3.1 Gateway 配置

**代码位置**：`packages/core/src/gateway/local/gateway-server.ts`

| 参数 | 默认值 | 说明 |
|------|--------|------|
| WebSocket 握手超时 | **10 秒** | 连接建立超时 |
| 最大消息大小 | **512 KB** | 单个 WS 消息最大尺寸 |
| 心跳间隔 | **30 秒** | Keep-alive ping 间隔 |

### 3.2 连接管理

OpenClaw Gateway 使用 `ws` 库（Node.js WebSocket 库），**无硬性连接数限制**，受限于：

1. **操作系统文件描述符限制**：
   - Linux 默认：1024 个打开文件（`ulimit -n`）
   - 每个 WebSocket 连接占用 1 个文件描述符
   - **实际限制**：约 900-1000 个并发连接（预留系统使用）

2. **内存限制**：
   - 每个连接约占用 1-5 MB 内存（取决于缓冲区大小）
   - 1000 连接 ≈ 1-5 GB 内存

### 3.3 企业微信桥接网关的影响

**我们的 Gateway (`openclaw-deploy`) 不保持长连接**：

```
企业微信用户 → [HTTP 请求] → 我们的 Gateway → [WebSocket] → OpenClaw
                                    ▲
                                    │
                            每个请求建立新连接
                            请求完成后关闭连接
```

**风险分析**：
- ✅ **优点**：不占用持久连接，支持更多并发用户
- ⚠️ **缺点**：每次请求都需要 WebSocket 握手（增加 100-200ms 延迟）
- ❌ **风险**：高并发时频繁建立/关闭连接，可能触发操作系统连接数限制

---

## 4. 超时和队列配置

### 4.1 请求超时

| 组件 | 参数 | 默认值 | 说明 |
|------|------|--------|------|
| OpenClaw Agent | `timeout` | **600 秒** (10 分钟) | 单个请求最长处理时间 |
| Gateway (我们的) | `OPENCLAW_WS_TOTAL_TIMEOUT` | **180 秒** | 等待 OpenClaw WS 完整回复的总超时 |
| Gateway (我们的) | `OPENCLAW_WS_IDLE_TIMEOUT` | **30 秒** | WS 空闲超时，长时间无事件直接中断 |
| Gateway (我们的) | `MAX_PER_USER_PENDING` | **1** | 单用户最多等待 1 条消息 |

**代码位置**：
- `packages/core/src/gateway/local/command-lanes.ts` - 队列超时
- `src/gateway/wecom_gateway.py:30` - Gateway 超时配置

### 4.2 队列模式

OpenClaw 支持 3 种队列模式（`packages/core/src/gateway/local/command-lanes.ts`）：

| 模式 | 行为 | 适用场景 |
|------|------|----------|
| `fifo` | 先进先出 | 公平排队 |
| `lifo` | 后进先出 | 优先处理最新请求 |
| `cancel-pending` | 取消旧请求，只处理最新 | 实时交互（默认） |

**当前配置**：默认 `cancel-pending`

**风险**：
- 用户快速发送多条消息时，前面的消息可能被 **自动取消**
- 适合单用户交互，不适合批量任务处理

---

## 5. 多用户并发风险矩阵

| 用户数 | 并发请求 | 风险等级 | 主要瓶颈 | 预期行为 |
|--------|----------|----------|----------|----------|
| 1-5 | ≤ 4 | 🟢 **低** | 无 | 流畅响应 |
| 10-20 | 4-8 | 🟡 **中** | 排队等待 | 部分用户等待 10-30 秒 |
| 50-100 | 10+ | 🟠 **高** | 队列堵塞 | 大部分用户等待 1-5 分钟 |
| 100+ | 20+ | 🔴 **严重** | 超时/拒绝 | 用户请求超时或失败 |

### 5.1 具体风险点

#### 风险 1：并发槽耗尽 ⚠️

**触发条件**：同时有 > 4 个请求

**影响**：
- 新请求进入队列等待
- 等待时间 = 平均响应时间 × (排队位置 / 并发槽数)
- 示例：平均 30 秒/请求，第 20 个用户需等待 150 秒

**缓解方案**：
```json
// ~/.openclaw/openclaw.json
{
  "agents": {
    "defaults": {
      "maxConcurrent": 16  // 从 4 提高到 16
    }
  }
}
```

#### 风险 2：长时间任务阻塞 ⚠️

**触发条件**：用户提交复杂任务（代码分析、文件处理等）

**影响**：
- 一个 10 分钟的任务会占用一个槽位 10 分钟
- 阻塞后续所有请求

**缓解方案**：
- 设置更合理的超时时间
- 使用多个 OpenClaw 实例（负载均衡）

#### 风险 3：会话文件锁竞争 ⚠️

**触发条件**：同一用户快速发送多条消息

**影响**：
- 后续请求等待锁释放（最多 30 秒）
- 可能触发锁超时错误

**缓解方案**：
- 企业微信侧实现防抖（debounce）
- Gateway 侧实现请求合并

#### 风险 4：WebSocket 连接风暴 ❌

**触发条件**：100+ 用户同时发送请求

**影响**：
- 短时间内建立大量 WebSocket 连接
- 可能触发操作系统文件描述符限制
- 连接建立失败 → 请求失败

**缓解方案**：
```bash
# 增加系统文件描述符限制
ulimit -n 65535

# 或永久修改 /etc/security/limits.conf
* soft nofile 65535
* hard nofile 65535
```

---

## 6. 推荐配置方案

### 6.1 小团队（1-10 人）

**场景**：企业内部使用，低频交互

**OpenClaw 配置** (`~/.openclaw/openclaw.json`)：
```json
{
  "agents": {
    "defaults": {
      "maxConcurrent": 4,
      "subagents": {
        "maxConcurrent": 8
      }
    }
  }
}
```

**Gateway 配置** (`.env`)：
```bash
OPENCLAW_TIMEOUT=180
OPENCLAW_WS_IDLE_TIMEOUT=30
OPENCLAW_WS_TOTAL_TIMEOUT=180
MAX_PER_USER_PENDING=1
MAX_QUEUE_WAIT_SECONDS=60
OPENCLAW_PROTOCOL=ws
```

**评估**：✅ 默认配置即可，无需调整

---

### 6.2 中型团队（10-50 人）

**场景**：活跃使用，中等并发

**OpenClaw 配置**：
```json
{
  "agents": {
    "defaults": {
      "maxConcurrent": 12,  // ↑ 提高 3 倍
      "subagents": {
        "maxConcurrent": 24
      }
    }
  }
}
```

**系统优化**：
```bash
# 增加文件描述符限制
ulimit -n 16384

# 监控队列深度
watch -n 5 'curl -s http://localhost:18789/api/stats | jq .queueDepth'
```

**风险**：⚠️ 中等，部分用户可能遇到等待

---

### 6.3 大型部署（50-100+ 人）

**场景**：高并发，生产环境

**推荐架构**：❌ **不建议单实例**，应采用 **多实例 + 负载均衡**

#### 方案 A：多 OpenClaw 实例

```
                  ┌─────────────┐
企业微信用户 ──────►│   Gateway   │
                  └──────┬──────┘
                         │
          ┌──────────────┼──────────────┐
          ▼              ▼              ▼
    ┌──────────┐   ┌──────────┐   ┌──────────┐
    │OpenClaw 1│   │OpenClaw 2│   │OpenClaw 3│
    │ (main)   │   │ (work)   │   │(research)│
    └──────────┘   └──────────┘   └──────────┘
```

**Gateway 配置** (SQLite)：
```sql
INSERT INTO agents (name, openclaw_url, openclaw_agent_id) VALUES
  ('team-dev',  'http://server1:18789', 'main'),
  ('team-ops',  'http://server2:18789', 'main'),
  ('team-research', 'http://server3:18789', 'main');
```

**优点**：
- ✅ 线性扩展能力
- ✅ 故障隔离
- ✅ 按团队/功能分流

**缺点**：
- ❌ 需要多台服务器
- ❌ 配置管理复杂

#### 方案 B：OpenClaw 高并发配置（单实例极限）

```json
{
  "agents": {
    "defaults": {
      "maxConcurrent": 32,  // ⚠️ 谨慎调高
      "subagents": {
        "maxConcurrent": 64
      }
    }
  }
}
```

**系统要求**：
- CPU: 16+ 核
- 内存: 32+ GB
- 文件描述符: 65535

**监控**：
```bash
# CPU 使用率
top -p $(pgrep -f openclaw)

# 内存使用
ps aux | grep openclaw

# WebSocket 连接数
netstat -an | grep :18789 | grep ESTABLISHED | wc -l
```

**风险**：
- ⚠️ 单点故障
- ⚠️ 资源竞争
- ⚠️ 难以水平扩展

---

## 7. 监控和告警建议

### 7.1 关键指标

| 指标 | 正常值 | 告警阈值 | 获取方法 |
|------|--------|----------|----------|
| 队列深度 | 0-5 | > 10 | OpenClaw Stats API |
| 并发请求数 | 0-4 | = maxConcurrent | OpenClaw Stats API |
| WebSocket 连接数 | 0-10 | > 100 | `netstat` |
| 响应时间（P95） | < 30s | > 60s | Gateway 日志分析 |
| 错误率 | < 1% | > 5% | Gateway 日志分析 |

### 7.2 监控脚本示例

```bash
#!/bin/bash
# monitor-openclaw.sh

# 获取 OpenClaw 统计信息
stats=$(curl -s http://localhost:18789/api/stats)
queue_depth=$(echo $stats | jq '.queueDepth')
active_requests=$(echo $stats | jq '.activeRequests')

# 检查阈值
if [ "$queue_depth" -gt 10 ]; then
  echo "⚠️ 队列深度过高: $queue_depth"
  # 发送告警（邮件/钉钉/Slack）
fi

if [ "$active_requests" -ge 4 ]; then
  echo "⚠️ 并发槽已满: $active_requests/4"
fi

# 检查 WebSocket 连接数
ws_count=$(netstat -an | grep :18789 | grep ESTABLISHED | wc -l)
if [ "$ws_count" -gt 100 ]; then
  echo "⚠️ WebSocket 连接数过多: $ws_count"
fi
```

### 7.3 日志监控

**Gateway 日志关键字**：
```bash
# 超时错误
tail -f data/gateway.log | grep "调用 agent.*超时"

# 并发错误
tail -f data/gateway.log | grep "并发限制"

# WebSocket 错误
tail -f data/gateway.log | grep "WS.*失败"
```

---

## 8. 性能测试建议

### 8.1 基准测试

**目标**：确定单实例最大并发能力

**步骤**：
1. 启动 Gateway 和 OpenClaw
2. 使用 `scripts/test-concurrent.py` 逐步增加并发：
   - 10 用户 × 3 消息 = 30 请求
   - 20 用户 × 3 消息 = 60 请求
   - 50 用户 × 3 消息 = 150 请求
3. 记录 P50/P95/P99 响应时间和错误率
4. 找到性能拐点（错误率 > 5% 或 P95 > 60s）

### 8.2 压力测试

**工具**：`ab` (Apache Bench) 或 `wrk`

```bash
# 模拟 100 并发用户
ab -n 1000 -c 100 -T 'application/json' \
   -p test-payload.json \
   http://localhost:8000/dev-main/wecom/callback
```

### 8.3 长时间稳定性测试

**场景**：模拟 24 小时持续使用

```bash
# 每 30 秒发送一次请求，持续 24 小时
for i in {1..2880}; do
  python3 scripts/test-concurrent.py
  sleep 30
done
```

**监控**：
- 内存是否持续增长（内存泄漏）
- 响应时间是否逐渐变慢
- 会话文件是否堆积

---

## 9. 结论和建议

### 9.1 当前配置适用范围

| 用户规模 | 适用性 | 备注 |
|----------|--------|------|
| 1-10 人 | ✅ **完全适用** | 默认配置即可 |
| 10-30 人 | 🟡 **基本适用** | 建议提高 maxConcurrent 到 8-12 |
| 30-50 人 | 🟠 **需要优化** | 必须提高并发限制 + 监控 |
| 50-100 人 | 🔴 **不建议** | 强烈建议多实例部署 |
| 100+ 人 | ❌ **不适用** | 必须使用多实例 + 负载均衡 |

### 9.2 立即行动项

**针对当前部署**（假设 < 30 人）：

1. ✅ **修改 OpenClaw 配置**：
   ```bash
   # 编辑 ~/.openclaw/openclaw.json
   "maxConcurrent": 8  # 从 4 提高到 8
   ```

2. ✅ **增加系统限制**：
   ```bash
   ulimit -n 16384
   ```

3. ✅ **启用监控**：
   ```bash
   # 定时任务
   */5 * * * * /path/to/monitor-openclaw.sh >> /var/log/openclaw-monitor.log
   ```

4. ✅ **压力测试**：
   ```bash
   python3 scripts/test-concurrent.py  # 观察响应时间
   ```

### 9.3 未来扩展路径

**当用户数超过 30 人时**：

1. **短期方案**（1-3 个月）：
   - 继续提高 maxConcurrent（最多到 16-32）
   - 优化 OpenClaw 服务器资源（CPU/内存）
   - 实施用户分流（按部门/团队分配不同 agent）

2. **长期方案**（3-6 个月）：
   - 部署多个 OpenClaw 实例
   - 实施负载均衡（Nginx / HAProxy）
   - 考虑 Kubernetes 自动扩缩容

3. **企业级方案**（6+ 个月）：
   - 建立 OpenClaw 集群（3+ 实例）
   - 中心化会话存储（Redis / PostgreSQL）
   - 实时监控和告警系统（Prometheus + Grafana）
   - 自动容量规划和扩缩容

---

## 10. 参考资料

### 10.1 源码位置

- **并发控制**: `packages/core/src/gateway/local/command-lanes.ts`
- **会话管理**: `packages/core/src/session/file-session-repo.ts`
- **WebSocket 服务**: `packages/core/src/gateway/local/gateway-server.ts`
- **Agent 配置**: `packages/core/src/gateway/local/agents.ts`

### 10.2 配置文件

- **OpenClaw 配置**: `~/.openclaw/openclaw.json`
- **Gateway 配置**: `.env`
- **Agent 绑定**: `data/gateway.db` (SQLite)

### 10.3 相关文档

- `PHASE2-PLAN.md` - Gateway 架构设计
- `AGENTS.md` - AI 编码助手指南
- `README.md` - 部署和使用说明

---

**最后更新**: 2026-03-02  
**分析基于**: OpenClaw 2026.3.1
