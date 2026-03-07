# `20260307_fix` 相对 `main` 的升级总结

> 说明：当前仓库没有 `master` 分支，主线分支实际为 `main`。  
> 本文档基于 `20260307_fix` 对比 `main` 整理。

## 1. 升级概览

- 对比范围：`main..20260307_fix`
- 提交数量：20 个
- 变更文件：17 个
- 代码规模：约 `4432` 行新增，`1100` 行删除

本次升级不是单点修复，而是一次**部署链路 + OpenClaw 配置链路 + Gateway 文件能力**的整体增强，重点集中在：

1. Gateway 并发与超时治理
2. 企业微信文件处理与 S3 上传能力
3. OpenClaw 安装脚本 `03` 的沙箱、技能、共享目录、重启时机治理
4. Agent 绑定规则、共享目录规则收口
5. 文档、用户指引与运行期排障补齐

---

## 2. 主要升级点

### 2.1 Gateway 能力增强

#### 2.1.1 并发与超时控制细化

`src/gateway/wecom_gateway.py` 增加了更细的 OpenClaw 调用超时与队列控制：

- `OPENCLAW_CONNECT_TIMEOUT`
- `OPENCLAW_WS_IDLE_TIMEOUT`
- `OPENCLAW_WS_TOTAL_TIMEOUT`
- `OPENCLAW_SSE_IDLE_TIMEOUT`
- `OPENCLAW_SSE_TOTAL_TIMEOUT`
- `OPENCLAW_HTTP_TIMEOUT`
- `MAX_GATEWAY_WORKERS`
- `MAX_PER_USER_PENDING`
- `MAX_QUEUE_WAIT_SECONDS`

行为变化：

- 同一 `agent + user` 进入串行队列
- 第一条消息正常处理
- 第二条消息进入等待队列
- 第三条消息直接拒绝
- 等待超时会主动回复用户

这意味着升级后 Gateway 对高并发场景更可控，但默认行为会比 `main` 更严格。

#### 2.1.2 企业微信主动回复和异步处理更稳定

主动回复逻辑被统一封装，错误处理更清晰，异常与超时场景会给出更明确的被动/主动回复。

#### 2.1.3 文件处理能力增强

新增或增强了以下能力：

- 风险文件扩展名拦截
- 文件类型识别更完整
- 文件记录持久化（`file_records`）
- 企业微信来件支持 `local / s3` 分流
- 内部上传接口 `/internal/files/upload`

#### 2.1.4 S3 能力正式引入

Gateway 侧新增 `boto3` 依赖，支持对象存储上传与预签名下载链接。

新增 S3 配置：

- `S3_BUCKET`
- `S3_ENDPOINT_URL`
- `S3_ACCESS_KEY_ID`
- `S3_SECRET_ACCESS_KEY`
- `S3_REGION`
- `S3_SIGNATURE_VERSION`
- `S3_ADDRESSING_STYLE`
- `S3_KEY_PREFIX`
- `S3_SSE_MODE`
- `S3_SSE_KMS_KEY_ID`
- `FILE_STORAGE_KEY_PREFIX`

#### 2.1.5 文件流转规则发生了实质性变化

升级后的规则是：

- **企业微信来件**
  - `FILE_STORAGE_MODE=local`：落本地并下发 `/app/shared/<agent_id>/...`
  - `FILE_STORAGE_MODE=s3`：上传 S3 并下发下载链接
- **OpenClaw 主动上传**
  - 无论 `FILE_STORAGE_MODE` 是什么，统一通过 S3 上传
  - 依赖 `gateway-file-upload` skill + `FILE_UPLOAD_INTERNAL_TOKEN` + S3 配置

这和 `main` 相比，是一次明显的文件能力升级。

---

## 3. OpenClaw 安装 / Agent 配置链路升级

### 3.1 `03-install-openclaw.sh` 变化最大

`bin/03-install-openclaw.sh` 从一个基础安装脚本，演进成了一个包含以下能力的完整引导器：

- 前置依赖检查
- OpenClaw 初始化兼容模式
- Gateway token 自动生成与环境变量引用
- Agent 创建与人格编辑
- 沙箱镜像检查与引导
- 上传 skill 自动安装
- 共享目录契约修复与硬校验
- Gateway 重启时机收口

### 3.2 沙箱交互顺序优化

升级后，`03` 会在开头先问：

`本次是否计划创建 Docker 沙箱 Agent`

行为变化：

- 如果选择 **否**，不会一上来就打 Docker 准备命令
- 如果选择 **是**，但 Docker / 沙箱镜像未准备好，会直接停止后续引导并给出准备命令

这比 `main` 的体验更清晰，也更贴近实际操作顺序。

### 3.3 Gateway 重启时机被收口

升级后 `03` 不再在多个阶段频繁重启 Gateway，而是收口为：

1. **添加第一个新 Agent 前**统一重启一次
2. **脚本全部完成后**统一重启一次

这样能减少中间态问题，也更利于理解配置生效时机。

### 3.4 共享目录规则被彻底固定

这是本次升级中最重要的结构性变化之一。

当前规则：

- Gateway 对外共享路径固定为：`/app/shared/<agent_id>`
- 宿主机真实目录固定为：`~/.openclaw/workspace-<agent_id>/shared`
- 非 `main` Agent 的 workspace 固定为：`~/.openclaw/workspace-<agent_id>`
- `main` Agent 的 workspace 固定为：`~/.openclaw/workspace`

并且：

- `scripts/manage-agent.py` / `bin/04-manage-agent.sh` 不再让用户手填共享目录
- 会自动创建或修正 `/app/shared/<agent_id> -> ~/.openclaw/workspace-<agent_id>/shared` 软链

### 3.5 Agent 绑定规则更强

当前分支明确强化了以下绑定关系：

- Gateway 路由名
- SQLite `agents.name`
- OpenClaw `openclaw_agent_id`
- `/app/shared/<agent_id>`

升级后推荐视为同一个 `agent_id` 体系，避免出现一套名字多处不一致。

### 3.6 root / sudo 使用规则更严格

升级后明确禁止：

- 用 `root` 或 `sudo` 运行 `bin/03-install-openclaw.sh`
- 用 `root` 或 `sudo` 运行 `bin/04-manage-agent.sh`
- 用 `root` 或 `sudo` 运行 `scripts/manage-agent.py`

原因是防止 OpenClaw home 落到 `/root/.openclaw`，从而触发沙箱路径限制。

### 3.7 上传 Skill 自动下发

新增 `openclaw-skills/gateway-file-upload/`：

- `03` 会自动安装全局 skill
- 同步到每个 Agent 的 workspace 下：
  - `~/.openclaw/workspace/skills`
  - `~/.openclaw/workspace-<agent_id>/skills`

并自动下发：

- 非沙箱：写入 `~/.openclaw/.env`
- 沙箱：写入 `sandbox.docker.env`

其中沙箱场景支持：

- `localhost` 自动改写为 `host.docker.internal`
- 自动补 `extraHosts: ["host.docker.internal:host-gateway"]`

---

## 4. 部署脚本和运维侧升级

### 4.1 `01-upload.sh`

上传脚本增强了远端保留与恢复能力：

- 会额外保留 `/opt/openclaw/gateway/.env`
- 会尝试从 `gateway/.env` 读取 `DB_PATH`
- 会备份并恢复 Gateway 独立 `.env`

### 4.2 `02-install-gateway.sh`

Gateway 安装脚本新增：

- 更完整的默认 `.env`
- S3 相关配置项
- 文件处理配置项
- 自动清理无效 TLS 证书路径
- `certifi` 路径异常自动修复

这部分直接覆盖了你之前遇到的：

- `Could not find a suitable TLS CA certificate bundle`

### 4.3 运行期 `docker.sock` 权限问题文档化

文档已明确区分：

- Docker 安装步骤
- 运行期排障步骤

当出现如下报错时：

```text
Failed to inspect sandbox image: permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```

说明是：

- 沙箱 Agent 已创建
- SQLite 已绑定
- 真正通信时才触发 Docker socket 权限问题

当前建议处理：

```bash
sudo chmod 777 /var/run/docker.sock
```

并且文档已明确说明：

- 这是**运行期权限修复**
- **不需要重启 Docker**
- **不需要重启 OpenClaw**
- **不需要重启 Gateway**

---

## 5. 数据与兼容性影响

### 5.1 SQLite 侧

`agents` 表继续使用，并兼容 `shared_dir` 字段。  
当前版本会更严格地把 `shared_dir` 收口到固定规则，不建议再手工自定义。

Gateway 新增 `file_records` 表用于记录文件元数据。

### 5.2 环境变量侧

从 `main` 升级到当前分支后，推荐补齐 `.env`：

- 并发 / 超时变量
- 文件处理变量
- S3 变量
- `FILE_UPLOAD_INTERNAL_TOKEN`

否则会出现：

- 上传 skill 调用失败
- 文件能力不完整
- 行为仍沿用旧默认值

### 5.3 OpenClaw 版本建议

当前文档已明确：

- Ubuntu 上不推荐使用 OpenClaw `2026.03.02`
- 更推荐使用 `2026.02.26`

如果你是 Ubuntu 环境，这条建议应视为升级时的默认版本策略。

---

## 6. 从 `main` 升级到当前分支的推荐操作

### 6.1 代码升级

```bash
git checkout 20260307_fix
```

### 6.2 备份建议

升级前建议至少备份：

- `/opt/openclaw/gateway/.env`
- `/opt/openclaw/data/gateway/gateway.db`
- `~/.openclaw/.env`
- `~/.openclaw/workspace`
- `~/.openclaw/workspace-*`
- `~/.openclaw/agents/*/sessions`

### 6.3 Gateway 升级

```bash
sudo bash bin/02-install-gateway.sh
```

### 6.4 OpenClaw / Agent 配置升级

```bash
bash bin/03-install-openclaw.sh --skip-install
```

建议目的：

- 同步新的 Gateway token 引用规则
- 同步新的共享目录规则
- 同步新的上传 skill
- 同步新的沙箱配置

### 6.5 如果使用沙箱 Agent

升级后请重点检查：

1. Docker 是否可用
2. 专用沙箱镜像是否存在
3. `/app/shared/<agent_id>` 是否正确指向 workspace 的 `shared`
4. `~/.openclaw/openclaw.json` 中的 bind 是否仍符合新规则

如容器已存在，建议执行：

```bash
openclaw sandbox recreate --agent <agent_id>
```

### 6.6 如果使用上传 Skill

除安装 skill 外，还必须配置：

- `FILE_UPLOAD_INTERNAL_TOKEN`
- S3 相关配置

否则 skill 虽然已安装，但上传接口会失败。

---

## 7. 升级结论

相对 `main`，当前分支不是简单的 bugfix，而是一次**可部署性、可运维性、文件能力、沙箱规则、文档闭环**的系统升级。

如果你准备从 `main` 切到当前分支，建议把升级理解为：

- **Gateway 侧**：建议直接重新执行 `02`
- **OpenClaw 侧**：建议重新执行一次 `03 --skip-install`
- **沙箱侧**：建议按新规则复核共享目录、镜像、容器与 `docker.sock`
- **文件能力侧**：建议补齐 S3 与 `FILE_UPLOAD_INTERNAL_TOKEN`

最值得关注的升级收益是：

1. 沙箱规则更稳定
2. 文件处理更完整
3. 主动上传能力正式可用
4. 部署与排障指引更接近真实现场

