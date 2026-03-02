# OpenClaw 企业微信桥接网关 - 用户指南

> 从零开始，10 分钟部署完成 🚀

---

## 📋 目录

1. [快速开始](#1-快速开始)
2. [环境准备](#2-环境准备)
3. [安装部署](#3-安装部署)
4. [配置企业微信](#4-配置企业微信)
5. [添加 Agent](#5-添加-agent)
6. [测试验证](#6-测试验证)
7. [日常使用](#7-日常使用)
8. [常见问题](#8-常见问题)
9. [进阶配置](#9-进阶配置)

---

## 1. 快速开始

### 1.1 这是什么？

**OpenClaw 企业微信桥接网关** 是一个让你的企业微信机器人能够使用 OpenClaw AI 助手的桥梁。

```
你在企业微信发消息 → 企业微信机器人 → 网关 → OpenClaw AI → 回复你
```

### 1.2 你需要什么？

- ✅ 一台 Linux 服务器（CentOS/Ubuntu）或 macOS
- ✅ OpenClaw 已安装并运行（未安装？用 `bash scripts/install-openclaw.sh` 一键搞定，需要 Node.js 22+）
- ✅ 企业微信管理员权限（能创建机器人应用）
- ✅ 基本的命令行操作能力（会复制粘贴命令即可）

### 1.3 需要多长时间？

- ⏱️ **首次部署**: 10-15 分钟
- ⏱️ **添加新机器人**: 2-3 分钟
- ⏱️ **日常维护**: 几乎为零

---

## 2. 环境准备

### 2.1 安装配置 OpenClaw（如尚未安装）

如果服务器上还没有安装 OpenClaw，可以使用项目提供的一键安装脚本：

```bash
cd ~/openclaw-deploy

# 一键安装 OpenClaw + 配置模型 + 创建 Agent + 编辑人格设定
bash scripts/install-openclaw.sh
```

**脚本会自动完成五个步骤**：

1. **检查环境 & 安装 OpenClaw**（需要 Node.js 22+）
2. **配置模型提供商**（Anthropic/OpenAI/DeepSeek 等官方 API + GMN 等第三方流量池）
3. **创建 Agent**（workspace、沙箱配置，用 `$EDITOR` 编辑人格设定文件）
4. **输出 Gateway 集成信息**（URL/Token，用于后续 manage-agent.py 配置）
5. **最终检查**（列出 Agent/模型，健康检查）

**快捷模式**（已安装 OpenClaw 的情况下）：

```bash
# 跳过安装，只做配置（OpenClaw 已安装）
bash scripts/install-openclaw.sh --skip-install

# 只添加新 Agent
bash scripts/install-openclaw.sh --add-agent

# 只添加模型提供商
bash scripts/install-openclaw.sh --add-provider
```

**安装完成后**，脚本会输出 OpenClaw 地址和 Token，记下这两个值用于后续配置 Gateway Agent。

---

### 2.2 检查 OpenClaw 是否运行

**如果 OpenClaw 已经安装**，在服务器上执行：

```bash
# 方法 1: 检查进程
ps aux | grep openclaw

# 方法 2: 检查端口
curl http://localhost:18789/health

# 方法 3: 查看配置
cat ~/.openclaw/openclaw.json | grep -A 5 gateway
```

**预期结果**：
```json
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "auth": {
      "mode": "token",
      "token": "你的长串token"
    }
  }
}
```

⚠️ **记下这两个值，后面要用**：
- **OpenClaw 地址**: `http://localhost:18789` （或服务器 IP）
- **OpenClaw Token**: `你的长串token`

---

### 2.3 安装 Python 和依赖

**检查 Python 版本**：
```bash
python3 --version
# 需要 Python 3.8 或更高版本
```

**如果没有 Python 3.8+，安装它**：

<details>
<summary>Ubuntu/Debian 系统</summary>

```bash
sudo apt update
sudo apt install -y python3 python3-pip
```
</details>

<details>
<summary>CentOS/RHEL 系统</summary>

```bash
sudo yum install -y python3 python3-pip
```
</details>

---

### 2.4 获取代码

```bash
# 进入你想要存放代码的目录
cd ~

# 克隆仓库（假设已经克隆，否则需要 git clone）
cd ~/openclaw-deploy

# 或者如果还没有代码，从 Git 克隆
# git clone <仓库地址> openclaw-deploy
# cd openclaw-deploy
```

---

## 3. 安装部署

### 3.1 一键安装（生产环境）

**强烈推荐**：适合正式使用

```bash
cd ~/openclaw-deploy
sudo bash deploy/install.sh
```

**安装过程**：
1. ✅ 安装 Python 依赖
2. ✅ 创建数据目录 `/opt/openclaw/data/gateway`
3. ✅ 配置 systemd 服务（开机自启）
4. ✅ 启动 Gateway 服务

**验证安装**：
```bash
# 检查服务状态
sudo systemctl status openclaw-gateway

# 应该看到 "Active: active (running)" 字样
```

**查看日志**：
```bash
# 实时查看日志
sudo journalctl -u openclaw-gateway -f

# 查看最近 50 行
sudo journalctl -u openclaw-gateway -n 50
```

---

### 3.2 开发环境（本地测试）

**仅用于开发和测试**：

```bash
# 安装依赖
pip3 install -r src/gateway/requirements.txt

# 复制环境变量模板
cp .env.example .env

# 编辑配置（可选）
nano .env

# 启动 Gateway（前台运行）
python3 src/gateway/wecom_gateway.py
```

**停止**：按 `Ctrl+C`

---

### 3.3 验证安装成功

**检查健康状态**：

```bash
curl http://localhost:8000/health
```

**预期输出**：
```json
{
  "status": "ok",
  "service": "openclaw-wecom-gateway",
  "agents": 0,
  "agent_names": [],
  "timestamp": 1234567890
}
```

✅ 看到 `"status": "ok"` 就说明安装成功！

⚠️ 注意 `"agents": 0` 是正常的，因为还没添加 agent

---

## 4. 配置企业微信

### 4.1 创建企业微信机器人应用

1. **登录企业微信管理后台**：https://work.weixin.qq.com/
2. **进入"应用管理"**
3. **点击"创建应用"** → 选择 **"自建应用"**
4. **填写信息**：
   - 应用名称：`OpenClaw AI 助手`
   - 应用介绍：`智能 AI 编程助手`
   - 可见范围：选择需要使用的员工

5. **创建成功后，进入应用详情页**

---

### 4.2 获取企业微信配置信息

**在应用详情页找到以下信息**：

#### 📝 需要记录的 3 个值：

1. **AgentId** (应用 ID)
   - 位置：应用详情页顶部
   - 示例：`1000002`

2. **Secret** (应用密钥)
   - 位置：应用详情页 → "开发者接口" → "Secret"
   - 示例：`abc123def456...`（点击"查看"）

3. **Token** 和 **EncodingAESKey**（消息加密配置）
   - 位置：应用详情页 → "接收消息" → "设置API接收"
   - **第一次配置时，这里还是空的，需要先生成**

---

### 4.3 生成 Token 和 EncodingAESKey

**在"接收消息"配置页面**：

1. **点击"随机生成 Token"** → 复制保存
   - 示例：`32c4407bae780aeb92b0d7f504dc26c1`

2. **点击"随机生成 EncodingAESKey"** → 复制保存
   - 示例：`f7cTZKs4PQ1E0cLHrHArKpSoHYUzxUNE8mKTIauIkZA`

⚠️ **先不要点"保存"！** 继续下一步

---

### 4.4 配置回调 URL

**URL 格式**：
```
https://你的域名/{agent_name}/wecom/callback
```

**示例**：
```
https://ai.yourcompany.com/team-dev/wecom/callback
```

**填写步骤**：

1. **URL 填入** 上面的地址（`{agent_name}` 替换为你想要的名字，如 `team-dev`）
2. **Token** 填入刚才生成的 Token
3. **EncodingAESKey** 填入刚才生成的 EncodingAESKey
4. **点击"保存"**

⚠️ **此时会验证 URL 可达性，必须先完成下一步（添加 Agent）才能保存成功！**

---

## 5. 添加 Agent

### 5.1 什么是 Agent？

**Agent** 是 Gateway 和企业微信机器人的绑定关系，包含：
- 企业微信机器人的加密配置（Token/AESKey）
- 对应的 OpenClaw 实例地址和 Token
- 使用哪个 OpenClaw Agent（`main` 或自定义）

**一个 Agent 对应一个企业微信机器人**。

---

### 5.2 交互式添加（推荐）

```bash
# 生产环境（systemd 服务）
sudo /opt/openclaw/gateway/manage-agent.sh add team-dev

# 开发环境
python3 scripts/manage-agent.py add team-dev
```

**按照提示输入**：

```
📝 添加新 Agent: team-dev

显示名称（用于日志和统计）: 研发团队 AI 助手

企业微信 Token（随机生成的 32 位字符串）: 32c4407bae780aeb92b0d7f504dc26c1

企业微信 EncodingAESKey（随机生成的 43 位字符串）: f7cTZKs4PQ1E0cLHrHArKpSoHYUzxUNE8mKTIauIkZA

OpenClaw 地址（如 http://localhost:18789 或 ws://IP:PORT）: http://localhost:18789

OpenClaw Token（从 ~/.openclaw/openclaw.json 获取）: 1e443bcba0ed1327699b31cdee8f6150e97226386c375f75

OpenClaw Agent ID（默认 main，按回车使用默认）: [直接回车]

✅ Agent 'team-dev' 添加成功！
```

---

### 5.3 验证 Agent 添加成功

```bash
# 查看所有 Agent
sudo /opt/openclaw/gateway/manage-agent.sh list

# 或开发环境
python3 scripts/manage-agent.py list
```

**预期输出**：
```
========================================
📋 当前已配置的 Agents
========================================

Agent: team-dev
  显示名称: 研发团队 AI 助手
  OpenClaw URL: http://localhost:18789
  OpenClaw Agent ID: main
  创建时间: 2026-03-02 10:00:00

总共 1 个 agent
```

**检查 Gateway API**：
```bash
curl http://localhost:8000/admin/agents
```

**预期输出**：
```json
{
  "agents": {
    "team-dev": {
      "display_name": "研发团队 AI 助手",
      "openclaw_url": "http://localhost:18789",
      "openclaw_agent_id": "main"
    }
  }
}
```

✅ 看到你的 agent 信息就成功了！

---

### 5.4 回到企业微信完成配置

**现在可以回到企业微信管理后台了**：

1. **刷新"接收消息"配置页**
2. **再次填写 URL、Token、EncodingAESKey**（和之前一样）
3. **点击"保存"**

✅ **如果看到"验证成功"** → 恭喜，配置完成！

❌ **如果提示"URL 验证失败"** → 检查：
- Gateway 服务是否正常运行
- 域名是否解析正确
- 防火墙是否开放 8000 端口
- Nginx 是否正确转发（如果使用了 Nginx）

---

## 6. 测试验证

### 6.1 在企业微信发送测试消息

1. **打开企业微信移动端或桌面端**
2. **进入"工作台" → 找到你创建的应用**（如 "OpenClaw AI 助手"）
3. **点击进入**
4. **发送消息**：`你好`

**预期结果**：
- ⏳ 几秒后收到回复（可能是 "收到你的消息：你好" 或 AI 的实际回复）
- ✅ 如果收到回复，说明完全成功！

---

### 6.2 查看 Gateway 日志

**实时查看**：
```bash
# 生产环境
sudo journalctl -u openclaw-gateway -f

# 开发环境
tail -f data/gateway.log
```

**正常日志示例**：
```
2026-03-02 10:30:15 - INFO - [team-dev] 收到 POST 请求
2026-03-02 10:30:15 - INFO - [team-dev] 消息签名验证成功
2026-03-02 10:30:15 - INFO - [team-dev] 解密消息: {"msgtype":"text","from":{"userid":"zhangsan"},...}
2026-03-02 10:30:15 - INFO - [team-dev] 调用 OpenClaw: ws://localhost:18789/ws
2026-03-02 10:30:20 - INFO - [team-dev] 收到 OpenClaw 回复，发送到企业微信
```

---

### 6.3 检查数据库记录

```bash
# 生产环境
sqlite3 /opt/openclaw/data/gateway/gateway.db "SELECT * FROM task_logs ORDER BY created_at DESC LIMIT 5;"

# 开发环境
sqlite3 ./data/gateway.db "SELECT * FROM task_logs ORDER BY created_at DESC LIMIT 5;"
```

**预期输出**：
```
task_id_123|zhangsan|team-dev|你好|success|收到你的消息...|2026-03-02 10:30:15|2026-03-02 10:30:20
```

✅ 看到记录就说明消息已经被处理！

---

## 7. 日常使用

### 7.1 多个机器人（多 Agent）

**场景**：不同部门使用不同的机器人

```bash
# 添加第二个 agent（运维团队）
sudo /opt/openclaw/gateway/manage-agent.sh add team-ops

# 添加第三个 agent（产品团队）
sudo /opt/openclaw/gateway/manage-agent.sh add team-product
```

**每个 agent 对应一个企业微信机器人应用**，配置步骤和上面完全一样。

**URL 示例**：
- 研发团队：`https://ai.yourcompany.com/team-dev/wecom/callback`
- 运维团队：`https://ai.yourcompany.com/team-ops/wecom/callback`
- 产品团队：`https://ai.yourcompany.com/team-product/wecom/callback`

---

### 7.2 使用不同的 OpenClaw Agent

**场景**：想让机器人使用不同的 OpenClaw Agent（如 `work` agent）

**步骤 1：在 OpenClaw 中创建 Agent**

参考 OpenClaw 文档创建新 agent，假设名为 `work`。

**步骤 2：添加 Gateway Agent 时指定**

```bash
sudo /opt/openclaw/gateway/manage-agent.sh add team-work
```

当提示输入 **OpenClaw Agent ID** 时，输入 `work`（而不是默认的 `main`）。

---

### 7.3 修改现有 Agent

```bash
# 更新 agent 配置
sudo /opt/openclaw/gateway/manage-agent.sh update team-dev
```

**按提示修改**（不想改的直接回车保持原值）：
```
当前显示名称: 研发团队 AI 助手
新显示名称（回车保持不变）: [直接回车保持不变]

当前 OpenClaw URL: http://localhost:18789
新 OpenClaw URL（回车保持不变）: http://new-server:18789  ← 修改了

... 其他配置 ...

✅ Agent 'team-dev' 更新成功！
```

---

### 7.4 删除 Agent

```bash
sudo /opt/openclaw/gateway/manage-agent.sh remove team-dev
```

**确认删除**：
```
⚠️  确定要删除 agent 'team-dev' 吗？(yes/no): yes
✅ Agent 'team-dev' 已删除
```

⚠️ **删除后**：
- Gateway 不再接受该机器人的消息
- 历史任务记录仍保留在数据库中
- 需要在企业微信管理后台停用或删除对应的机器人应用

---

### 7.5 服务管理（生产环境）

```bash
# 启动服务
sudo systemctl start openclaw-gateway

# 停止服务
sudo systemctl stop openclaw-gateway

# 重启服务
sudo systemctl restart openclaw-gateway

# 查看状态
sudo systemctl status openclaw-gateway

# 查看日志
sudo journalctl -u openclaw-gateway -f
```

---

### 7.6 服务管理（快捷命令）

**安装后提供了便捷脚本**：

```bash
# 启动
sudo gateway-ctl start

# 停止
sudo gateway-ctl stop

# 重启
sudo gateway-ctl restart

# 查看状态
sudo gateway-ctl status

# 查看日志
sudo gateway-ctl logs
```

---

## 8. 常见问题

### 8.1 企业微信配置问题

#### Q1: URL 验证失败

**症状**：企业微信提示 "URL 验证失败"

**排查步骤**：

1. **检查 Gateway 是否运行**：
   ```bash
   curl http://localhost:8000/health
   ```

2. **检查域名解析**：
   ```bash
   ping ai.yourcompany.com
   ```

3. **检查防火墙**：
   ```bash
   sudo firewall-cmd --list-ports
   # 或
   sudo ufw status
   ```
   确保 8000 端口已开放。

4. **检查 Nginx 配置**（如果使用）：
   ```nginx
   location /team-dev/wecom/callback {
       proxy_pass http://localhost:8000/team-dev/wecom/callback;
       proxy_set_header Host $host;
       proxy_set_header X-Real-IP $remote_addr;
   }
   ```

5. **查看 Gateway 日志**：
   ```bash
   sudo journalctl -u openclaw-gateway -n 50
   ```
   查找 "回调验证" 相关日志。

---

#### Q2: 消息签名验证失败

**症状**：Gateway 日志显示 "消息签名验证失败"

**原因**：Token 或 EncodingAESKey 填错了

**解决**：

1. **检查数据库中的配置**：
   ```bash
   sqlite3 /opt/openclaw/data/gateway/gateway.db "SELECT name, wecom_token, wecom_aes_key FROM agents WHERE name='team-dev';"
   ```

2. **对比企业微信管理后台的配置**

3. **如果不一致，更新 agent**：
   ```bash
   sudo /opt/openclaw/gateway/manage-agent.sh update team-dev
   ```

---

#### Q3: 收不到回复

**症状**：发送消息后没有任何回复

**排查步骤**：

1. **检查 Gateway 日志**：
   ```bash
   sudo journalctl -u openclaw-gateway -f
   ```
   发送消息，观察是否有日志输出。

2. **检查 OpenClaw 是否运行**：
   ```bash
   curl http://localhost:18789/health
   ```

3. **检查 OpenClaw Token 是否正确**：
   ```bash
   # 查看 Gateway 配置的 Token
   sqlite3 /opt/openclaw/data/gateway/gateway.db "SELECT openclaw_token FROM agents WHERE name='team-dev';"
   
   # 对比 OpenClaw 配置
   cat ~/.openclaw/openclaw.json | grep token
   ```

4. **测试 OpenClaw 连接**：
   ```bash
   # 使用 Gateway 的测试脚本
   python3 scripts/test-session-isolation.py
   ```

---

### 8.2 性能问题

#### Q4: 响应很慢

**症状**：发送消息后等待很久才收到回复（> 30 秒）

**可能原因**：

1. **OpenClaw 并发槽已满** → 参考 [进阶配置 - 提高并发限制](#92-提高-openclaw-并发限制)
2. **OpenClaw 服务器性能不足** → 升级 CPU/内存
3. **网络延迟** → 检查 Gateway 到 OpenClaw 的网络

**排查**：

1. **查看 OpenClaw 统计**：
   ```bash
   curl http://localhost:18789/api/stats
   ```
   关注 `queueDepth`（队列深度）和 `activeRequests`（活跃请求数）

2. **查看 Gateway 日志中的耗时**：
   ```bash
   sudo journalctl -u openclaw-gateway | grep "调用耗时"
   ```

---

#### Q5: 大量用户时出现超时

**症状**：同时有很多人使用时，部分用户收不到回复

**原因**：OpenClaw 并发限制（默认只有 4 个并发槽）

**解决**：参考 [进阶配置 - 多用户优化](#93-多用户优化)

---

### 8.3 数据问题

#### Q6: 如何查看历史消息？

```bash
# 查看最近 20 条消息
sqlite3 /opt/openclaw/data/gateway/gateway.db \
  "SELECT created_at, user_id, agent_id, task_content, status 
   FROM task_logs 
   ORDER BY created_at DESC 
   LIMIT 20;"
```

---

#### Q7: 如何清空历史记录？

```bash
# ⚠️ 慎用！会删除所有历史记录
sqlite3 /opt/openclaw/data/gateway/gateway.db "DELETE FROM task_logs;"
```

---

#### Q8: 数据库太大怎么办？

**定期清理旧记录**：

```bash
# 删除 30 天前的记录
sqlite3 /opt/openclaw/data/gateway/gateway.db \
  "DELETE FROM task_logs 
   WHERE created_at < datetime('now', '-30 days');"

# 压缩数据库
sqlite3 /opt/openclaw/data/gateway/gateway.db "VACUUM;"
```

**设置定时任务**（每周日凌晨 2 点清理）：
```bash
sudo crontab -e

# 添加以下行
0 2 * * 0 sqlite3 /opt/openclaw/data/gateway/gateway.db "DELETE FROM task_logs WHERE created_at < datetime('now', '-30 days'); VACUUM;"
```

---

### 8.4 升级和维护

#### Q9: 如何升级 Gateway？

```bash
# 1. 停止服务
sudo systemctl stop openclaw-gateway

# 2. 备份数据
sudo cp /opt/openclaw/data/gateway/gateway.db /opt/openclaw/data/gateway/gateway.db.backup

# 3. 拉取最新代码
cd ~/openclaw-deploy
git pull

# 4. 重新安装
sudo bash deploy/install.sh

# 5. 启动服务
sudo systemctl start openclaw-gateway
```

---

#### Q10: 如何卸载？

```bash
cd ~/openclaw-deploy
sudo bash deploy/uninstall.sh
```

**卸载会删除**：
- systemd 服务
- `/opt/openclaw/gateway` 目录

**不会删除**：
- `/opt/openclaw/data/gateway` 目录（数据保留）

**如果要完全删除（包括数据）**：
```bash
sudo rm -rf /opt/openclaw
```

---

## 9. 进阶配置

### 9.1 修改 Gateway 端口

**默认端口**：8000

**修改步骤**：

1. **编辑环境变量**：
   ```bash
   sudo nano /opt/openclaw/gateway/.env
   ```

2. **修改端口**：
   ```bash
   GATEWAY_PORT=8080  # 改为 8080
   ```

3. **重启服务**：
   ```bash
   sudo systemctl restart openclaw-gateway
   ```

4. **更新 Nginx 配置**（如果使用）：
   ```nginx
   proxy_pass http://localhost:8080;  # 改为新端口
   ```

---

### 9.2 提高 OpenClaw 并发限制

**适用场景**：用户数超过 10 人

**步骤**：

1. **编辑 OpenClaw 配置**：
   ```bash
   nano ~/.openclaw/openclaw.json
   ```

2. **修改并发限制**：
   ```json
   {
     "agents": {
       "defaults": {
         "maxConcurrent": 8  // 从默认的 4 改为 8
       }
     }
   }
   ```

3. **重启 OpenClaw**：
   ```bash
   # 查找 OpenClaw 进程
   ps aux | grep openclaw
   
   # 杀掉进程
   kill -9 <PID>
   
   # 重新启动（具体命令取决于你的 OpenClaw 启动方式）
   openclaw daemon start
   ```

4. **验证配置**：
   ```bash
   curl http://localhost:18789/api/stats | jq .maxConcurrent
   ```

**推荐值**：
- 10-20 人：`maxConcurrent: 8`
- 20-50 人：`maxConcurrent: 16`
- 50+ 人：考虑多实例部署（参考并发分析文档）

---

### 9.3 多用户优化

**场景**：团队超过 30 人

**推荐方案**：

#### 方案 1：按部门分流（单 OpenClaw 实例）

```bash
# 研发部使用 main agent
sudo /opt/openclaw/gateway/manage-agent.sh add dept-dev
# OpenClaw Agent ID: main

# 运维部使用 work agent
sudo /opt/openclaw/gateway/manage-agent.sh add dept-ops
# OpenClaw Agent ID: work
```

**优点**：配置简单
**缺点**：仍受单实例并发限制

---

#### 方案 2：多 OpenClaw 实例（推荐）

**架构**：

```
Gateway
  ├─ dept-dev   → OpenClaw 实例 1 (server1:18789)
  ├─ dept-ops   → OpenClaw 实例 2 (server2:18789)
  └─ dept-sales → OpenClaw 实例 3 (server3:18789)
```

**配置步骤**：

1. **在不同服务器上启动 OpenClaw 实例**

2. **添加 agent 时使用不同的 OpenClaw URL**：
   ```bash
   sudo /opt/openclaw/gateway/manage-agent.sh add dept-dev
   # OpenClaw URL: http://server1:18789
   
   sudo /opt/openclaw/gateway/manage-agent.sh add dept-ops
   # OpenClaw URL: http://server2:18789
   ```

**优点**：
- ✅ 线性扩展能力
- ✅ 故障隔离
- ✅ 性能大幅提升

**缺点**：
- ❌ 需要多台服务器
- ❌ 管理复杂度增加

---

### 9.4 启用 HTTPS

**生产环境强烈推荐使用 HTTPS**

**方案 1：使用 Nginx 反向代理（推荐）**

```nginx
# /etc/nginx/conf.d/openclaw-gateway.conf

server {
    listen 443 ssl;
    server_name ai.yourcompany.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**方案 2：使用 Let's Encrypt 免费证书**

```bash
# 安装 certbot
sudo apt install certbot python3-certbot-nginx

# 自动配置
sudo certbot --nginx -d ai.yourcompany.com
```

---

### 9.5 监控和告警

**定期检查脚本**：

```bash
#!/bin/bash
# /opt/openclaw/scripts/health-check.sh

GATEWAY_URL="http://localhost:8000"
OPENCLAW_URL="http://localhost:18789"

# 检查 Gateway
gateway_status=$(curl -s $GATEWAY_URL/health | jq -r .status)
if [ "$gateway_status" != "ok" ]; then
    echo "⚠️ Gateway 异常！"
    # 发送告警（邮件/钉钉/Slack）
fi

# 检查 OpenClaw
openclaw_status=$(curl -s $OPENCLAW_URL/health | jq -r .status)
if [ "$openclaw_status" != "ok" ]; then
    echo "⚠️ OpenClaw 异常！"
    # 发送告警
fi

# 检查队列深度
queue_depth=$(curl -s $OPENCLAW_URL/api/stats | jq -r .queueDepth)
if [ "$queue_depth" -gt 10 ]; then
    echo "⚠️ 队列深度过高: $queue_depth"
fi
```

**设置定时任务**（每 5 分钟检查一次）：

```bash
sudo crontab -e

# 添加以下行
*/5 * * * * /opt/openclaw/scripts/health-check.sh >> /var/log/openclaw-health.log 2>&1
```

---

## 10. 附录

### 10.1 目录结构

```
/opt/openclaw/
├── gateway/
│   ├── wecom_gateway.py      # Gateway 主程序
│   ├── manage-agent.sh       # Agent 管理脚本
│   ├── requirements.txt      # Python 依赖
│   └── .env                  # 环境变量
├── data/
│   └── gateway/
│       ├── gateway.db        # SQLite 数据库
│       ├── gateway.log       # 日志文件
│       └── files/            # 文件下载目录
└── scripts/
    └── health-check.sh       # 健康检查脚本
```

---

### 10.2 数据库表结构

#### agents 表（agent-企业微信绑定）

| 字段 | 类型 | 说明 |
|------|------|------|
| name | TEXT | Agent 名称（主键） |
| display_name | TEXT | 显示名称 |
| wecom_token | TEXT | 企业微信 Token |
| wecom_aes_key | TEXT | 企业微信 EncodingAESKey |
| openclaw_url | TEXT | OpenClaw 地址 |
| openclaw_token | TEXT | OpenClaw Token |
| openclaw_agent_id | TEXT | OpenClaw Agent ID（默认 main） |
| created_at | TEXT | 创建时间 |
| updated_at | TEXT | 更新时间 |

#### task_logs 表（任务日志）

| 字段 | 类型 | 说明 |
|------|------|------|
| task_id | TEXT | 任务 ID（主键） |
| user_id | TEXT | 用户 ID |
| agent_id | TEXT | Agent 名称 |
| task_content | TEXT | 消息内容 |
| status | TEXT | 状态（pending/processing/success/failed） |
| result | TEXT | 回复内容 |
| created_at | TIMESTAMP | 创建时间 |
| updated_at | TIMESTAMP | 更新时间 |

---

### 10.3 环境变量说明

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `DB_PATH` | `/opt/openclaw/data/gateway/gateway.db` | SQLite 数据库路径 |
| `GATEWAY_PORT` | `8000` | Gateway 监听端口 |
| `OPENCLAW_PROTOCOL` | `ws` | 通信协议（ws/sse/http） |
| `OPENCLAW_TIMEOUT` | `2700` | OpenClaw 超时时间（秒） |
| `GATEWAY_URL` | `http://localhost:8000` | Gateway 外部访问地址 |

---

### 10.4 有用的命令速查

```bash
# 查看 Gateway 状态
sudo systemctl status openclaw-gateway

# 查看实时日志
sudo journalctl -u openclaw-gateway -f

# 查看所有 Agent
sudo /opt/openclaw/gateway/manage-agent.sh list

# 查看最近 10 条任务
sqlite3 /opt/openclaw/data/gateway/gateway.db \
  "SELECT * FROM task_logs ORDER BY created_at DESC LIMIT 10;"

# 查看任务统计
sqlite3 /opt/openclaw/data/gateway/gateway.db \
  "SELECT status, COUNT(*) FROM task_logs GROUP BY status;"

# 检查 OpenClaw 统计
curl http://localhost:18789/api/stats | jq

# 检查 Gateway 健康状态
curl http://localhost:8000/health | jq

# 重启 Gateway
sudo systemctl restart openclaw-gateway
```

---

### 10.5 获取帮助

**遇到问题？**

1. 📖 查看日志：`sudo journalctl -u openclaw-gateway -n 100`
2. 📚 阅读并发分析文档：`docs/CONCURRENCY-ANALYSIS.md`
3. 🔍 搜索 GitHub Issues
4. 💬 联系团队技术支持

---

**最后更新**: 2026-03-02  
**版本**: v1.0
