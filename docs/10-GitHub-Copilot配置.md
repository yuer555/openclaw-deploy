# GitHub Copilot 部署完成指南

## ✅ 已完成

1. **服务器环境**：
   - ✅ Docker 28.2.2
   - ✅ Node.js v24.13.1
   - ✅ OpenClaw 2026.2.12
   - ✅ GitHub CLI 2.86.0

2. **配置文件**：
   - ✅ docker-compose.yml
   - ✅ config/openclaw.json（GitHub Copilot 模式）
   - ✅ 启动脚本（start.sh, stop.sh, status.sh）

## 🔑 下一步：GitHub 认证（必需）

### 方式1：使用 GitHub Token（推荐）⭐

```bash
# 1. 创建 token（在浏览器）
# 访问：https://github.com/settings/tokens
# 点击：Generate new token (classic)
# 勾选：read:user, copilot
# 复制 token（ghp_xxxxx）

# 2. SSH 登录服务器
ssh ubuntu@139.199.200.144

# 3. 使用 token 认证
echo "ghp_你的token" | gh auth login --with-token

# 4. 验证
gh auth status
```

### 方式2：交互式登录

```bash
ssh ubuntu@139.199.200.144
gh auth login
# 按提示操作（需要浏览器授权）
```

---

## 🚀 启动服务

认证完成后：

```bash
# 在服务器上
cd /opt/openclaw
bash start.sh

# 查看状态
bash status.sh

# 查看日志
docker-compose logs -f
```

---

## 📊 验证部署

```bash
# 检查容器是否运行
docker ps

# 应该看到类似：
# operation-agent    Up
# product-agent      Up
```

---

## 🎯 当前状态

**服务器**: 139.199.200.144  
**位置**: /opt/openclaw  
**模型**: github-copilot/claude-sonnet-4.5  
**需要**: GitHub 认证（未完成）

---

## ⚠️ 注意事项

1. **GitHub Token 权限**：
   - 必需：`read:user`（读取用户信息）
   - 必需：`copilot`（使用 Copilot API）

2. **Token 安全**：
   - 不要分享 token
   - 不要提交到 Git
   - 定期轮换

3. **配额管理**：
   - GitHub Copilot 有使用配额
   - 监控使用情况

---

## 🔍 故障排查

### 问题1：gh auth 失败
```bash
# 检查 gh 版本
gh --version

# 重新认证
gh auth logout
gh auth login
```

### 问题2：容器无法启动
```bash
# 查看日志
docker-compose logs

# 检查配置
docker-compose config
```

### 问题3：模型调用失败
```bash
# 验证 GitHub 认证
gh auth status

# 测试 Copilot 访问
gh copilot explain "hello world"
```

---

## 📞 下一步

1. **完成 GitHub 认证**（上面的步骤）
2. **启动服务**：`bash start.sh`
3. **测试虚拟员工**
4. **配置更多功能**（Discord、定时任务等）

---

**文件位置**: `~/.openclaw/workspace/scripts/cloud-deploy/GITHUB_COPILOT_SETUP.md`
