#!/bin/bash

# ====================================================
# OpenClaw 项目结构自动整理脚本
# 用途：将混乱的项目结构整理为规范的目录结构
# ====================================================

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

PROJECT_ROOT="$HOME/openclaw-deploy"
BACKUP_NAME="openclaw-deploy-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}OpenClaw 项目结构自动整理${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

# 安全检查
if [ ! -d "$PROJECT_ROOT" ]; then
    echo -e "${COLOR_RED}❌ 项目目录不存在: $PROJECT_ROOT${COLOR_RESET}"
    exit 1
fi

cd "$PROJECT_ROOT"

# 显示整理计划
echo -e "\n${COLOR_BLUE}📋 整理计划：${COLOR_RESET}"
echo "  ✅ 备份当前项目"
echo "  ✅ 创建新目录结构"
echo "  ✅ 移动核心文件"
echo "  ✅ 清理冗余文件"
echo "  ✅ 生成索引文档"

echo -e "\n${COLOR_YELLOW}⚠️  即将整理项目，是否继续？(y/n)${COLOR_RESET}"
read -r CONFIRM

if [ "$CONFIRM" != "y" ]; then
    echo "已取消"
    exit 0
fi

# ============================================
# 第一步：备份
# ============================================
echo -e "\n${COLOR_YELLOW}[1/5] 创建备份...${COLOR_RESET}"

tar -czf "../$BACKUP_NAME" . 2>/dev/null || true
if [ -f "../$BACKUP_NAME" ]; then
    BACKUP_SIZE=$(du -h "../$BACKUP_NAME" | cut -f1)
    echo -e "  ✅ 备份已创建: ../$BACKUP_NAME (${BACKUP_SIZE})"
else
    echo -e "${COLOR_RED}  ⚠️  备份失败，但继续执行${COLOR_RESET}"
fi

# ============================================
# 第二步：创建新目录结构
# ============================================
echo -e "\n${COLOR_YELLOW}[2/5] 创建新目录结构...${COLOR_RESET}"

# 创建主目录
mkdir -p docs/{archives}
mkdir -p scripts/{setup,deploy,user,ops,security,test,utils}
mkdir -p src/gateway
mkdir -p config/{agents,nginx,prometheus,alertmanager}
mkdir -p data logs backups

# 创建 .gitkeep 文件
touch data/.gitkeep logs/.gitkeep backups/.gitkeep

echo -e "  ✅ 目录结构已创建"

# ============================================
# 第三步：移动核心文件
# ============================================
echo -e "\n${COLOR_YELLOW}[3/5] 移动核心文件...${COLOR_RESET}"

# 3.1 移动优化脚本（最新）
echo -e "  📦 移动优化脚本..."
[ -f scripts/setup_secrets.sh ] && mv scripts/setup_secrets.sh scripts/setup/ 2>/dev/null || true
[ -f scripts/setup_network_isolation.sh ] && mv scripts/setup_network_isolation.sh scripts/setup/ 2>/dev/null || true
[ -f scripts/setup_alerting.sh ] && mv scripts/setup_alerting.sh scripts/setup/ 2>/dev/null || true

[ -f deploy-optimizations.sh ] && mv deploy-optimizations.sh scripts/deploy/ 2>/dev/null || true
[ -f package-only.sh ] && mv package-only.sh scripts/deploy/ 2>/dev/null || true

# 3.2 从 openclaw-wecom-project 复制脚本
echo -e "  📦 整合项目脚本..."
if [ -d openclaw-wecom-project/scripts ]; then
    # 初始化脚本
    cp openclaw-wecom-project/scripts/init_server.sh scripts/setup/ 2>/dev/null || true
    cp openclaw-wecom-project/scripts/init_database.sh scripts/setup/ 2>/dev/null || true
    cp openclaw-wecom-project/scripts/setup_ssl.sh scripts/setup/ 2>/dev/null || true
    
    # 部署脚本
    cp openclaw-wecom-project/scripts/deploy.sh scripts/deploy/ 2>/dev/null || true
    
    # 用户管理
    cp openclaw-wecom-project/scripts/add_user.sh scripts/user/ 2>/dev/null || true
    cp openclaw-wecom-project/scripts/batch_add_users.sh scripts/user/ 2>/dev/null || true
    cp openclaw-wecom-project/scripts/list_users.sh scripts/user/ 2>/dev/null || true
    cp openclaw-wecom-project/scripts/remove_user.sh scripts/user/ 2>/dev/null || true
    
    # 运维操作
    cp openclaw-wecom-project/scripts/backup.sh scripts/ops/ 2>/dev/null || true
    cp openclaw-wecom-project/scripts/restore.sh scripts/ops/ 2>/dev/null || true
    cp openclaw-wecom-project/scripts/health_check.sh scripts/ops/ 2>/dev/null || true
    cp openclaw-wecom-project/scripts/cleanup_logs.sh scripts/ops/ 2>/dev/null || true
    cp openclaw-wecom-project/scripts/query_tasks.sh scripts/ops/ 2>/dev/null || true
    
    # 安全管理
    cp openclaw-wecom-project/scripts/security_audit.sh scripts/security/ 2>/dev/null || true
    cp openclaw-wecom-project/scripts/network_isolation.sh scripts/security/ 2>/dev/null || true
    
    # 测试脚本
    cp openclaw-wecom-project/scripts/performance_test.sh scripts/test/ 2>/dev/null || true
fi

# 工具脚本
[ -f diagnose-ssh.sh ] && mv diagnose-ssh.sh scripts/utils/ 2>/dev/null || true
[ -f install-ssh-key.sh ] && mv install-ssh-key.sh scripts/utils/ 2>/dev/null || true

# 设置执行权限
chmod +x scripts/**/*.sh 2>/dev/null || true

# 3.3 移动配置文件
echo -e "  ⚙️  整合配置文件..."
if [ -d openclaw-wecom-project/config/agents ]; then
    cp openclaw-wecom-project/config/agents/*.yaml config/agents/ 2>/dev/null || true
fi

# Docker Compose
[ -f openclaw-wecom-project/deployments/docker-compose.yml ] && cp openclaw-wecom-project/deployments/docker-compose.yml config/ 2>/dev/null || true
[ -f docker-compose-minimal.yml ] && cp docker-compose-minimal.yml config/docker-compose.dev.yml 2>/dev/null || true

# .env 示例
if [ -f .env ]; then
    # 移除敏感信息，创建示例
    sed 's/=.*/=your_value_here/g' .env > config/.env.example 2>/dev/null || true
fi

# 3.4 移动源代码
echo -e "  💻 整合源代码..."
if [ -d openclaw-wecom-project/src/gateway ]; then
    cp openclaw-wecom-project/src/gateway/*.py src/gateway/ 2>/dev/null || true
    cp openclaw-wecom-project/requirements.txt src/gateway/ 2>/dev/null || true
fi

# 3.5 整理文档
echo -e "  📚 整理文档..."

# 核心文档
[ -f 企业微信实际部署指南.md ] && cp 企业微信实际部署指南.md docs/04-企业微信配置.md 2>/dev/null || true
[ -f 部署脚本使用说明.md ] && cp 部署脚本使用说明.md docs/03-部署指南.md 2>/dev/null || true

if [ -d openclaw-wecom-project/docs ]; then
    [ -f openclaw-wecom-project/docs/快速部署指南.md ] && cp openclaw-wecom-project/docs/快速部署指南.md docs/01-快速开始.md 2>/dev/null || true
    [ -f openclaw-wecom-project/docs/运维手册.md ] && cp openclaw-wecom-project/docs/运维手册.md docs/05-运维手册.md 2>/dev/null || true
    [ -f openclaw-wecom-project/docs/故障排查手册.md ] && cp openclaw-wecom-project/docs/故障排查手册.md docs/06-故障排查.md 2>/dev/null || true
    [ -f openclaw-wecom-project/docs/API接口文档.md ] && cp openclaw-wecom-project/docs/API接口文档.md docs/07-API文档.md 2>/dev/null || true
fi

# 归档历史文档
mv 优化任务完成报告_2026-02-12.md docs/archives/ 2>/dev/null || true
mv 今日完成报告-20260211.md docs/archives/ 2>/dev/null || true
mv DEPLOYMENT_SUCCESS.md docs/archives/ 2>/dev/null || true
mv Docker本地部署成功报告.md docs/archives/ 2>/dev/null || true
mv SERVER_DEPLOY_REPORT.md docs/archives/ 2>/dev/null || true
mv 文档工具更新清单.md docs/archives/ 2>/dev/null || true

echo -e "  ✅ 核心文件已移动"

# ============================================
# 第四步：清理冗余文件
# ============================================
echo -e "\n${COLOR_YELLOW}[4/5] 清理冗余文件...${COLOR_RESET}"

# 删除冗余目录
rm -rf openclaw-wecom-project/ 2>/dev/null || true
rm -rf deploy-package/ 2>/dev/null || true
rm -rf mission-control/ 2>/dev/null || true
rm -rf wecom_gateway/ 2>/dev/null || true
rm -rf workspace/ 2>/dev/null || true
rm -rf venv/ 2>/dev/null || true
rm -rf agents/ 2>/dev/null || true

# 删除过时文件
rm -f DEPLOYMENT_STATUS.md 2>/dev/null || true
rm -f QUICK_DEPLOY.md 2>/dev/null || true
rm -f SSH密钥配置指南.md 2>/dev/null || true
rm -f 企业微信API集成测试.md 2>/dev/null || true
rm -f 工程目录结构.md 2>/dev/null || true
rm -f 服务器部署命令-*.md 2>/dev/null || true
rm -f 一键复制命令.txt 2>/dev/null || true
rm -f 手动部署指南.md 2>/dev/null || true
rm -f 部署包使用说明.txt 2>/dev/null || true
rm -f 配置SSH密钥-快速版.txt 2>/dev/null || true

# 删除重复脚本
rm -f auto-deploy.sh auto-deploy.exp 2>/dev/null || true
rm -f install-ssh-key-remote.sh 2>/dev/null || true
rm -f 添加SSH密钥到服务器.sh 2>/dev/null || true
rm -f 远程服务器-配置公钥.sh 2>/dev/null || true
rm -f 部署指南-手动执行.sh 2>/dev/null || true

# 删除重复配置
rm -f docker-compose.yml docker-compose-minimal.yml 2>/dev/null || true

# 删除压缩包
rm -f *.tar.gz 2>/dev/null || true

# 删除空的旧 scripts 目录
[ -d scripts ] && [ -z "$(ls -A scripts 2>/dev/null)" ] && rm -rf scripts 2>/dev/null || true
[ -d config ] && [ -z "$(ls -A config/agents 2>/dev/null)" ] && rm -rf config 2>/dev/null || true

echo -e "  ✅ 冗余文件已清理"

# ============================================
# 第五步：生成索引文档
# ============================================
echo -e "\n${COLOR_YELLOW}[5/5] 生成索引文档...${COLOR_RESET}"

# 创建主 README
cat > README.md << 'EOF'
# OpenClaw 企业微信虚拟员工系统

## 📖 项目简介

基于 OpenClaw AI 代理框架，为企业微信构建的多角色虚拟员工系统。支持运营、产品、研发、测试、客服等多种角色，实现智能任务分发和自动化处理。

## 🚀 快速开始

### 1. 查看文档

```bash
cat docs/README.md         # 文档导航
cat docs/01-快速开始.md    # 新用户入门
```

### 2. 部署系统

```bash
# 自动打包上传
bash scripts/deploy/deploy-optimizations.sh

# 或手动打包
bash scripts/deploy/package-only.sh
```

### 3. 配置企业微信

参考 `docs/04-企业微信配置.md`

## 📁 项目结构

```
openclaw-deploy/
├── docs/           # 📚 文档中心
├── scripts/        # 🔧 运维脚本
├── config/         # ⚙️  配置文件
├── src/            # 💻 源代码
├── data/           # 🗄️  数据目录
├── logs/           # 📋 日志目录
└── backups/        # 💾 备份目录
```

详见 `docs/README.md`

## 🔧 核心脚本

### 初始化脚本
- `scripts/setup/init_server.sh` - 服务器初始化
- `scripts/setup/init_database.sh` - 数据库初始化
- `scripts/setup/setup_ssl.sh` - SSL 证书配置

### 优化脚本（最新）
- `scripts/setup/setup_secrets.sh` - API Key 安全配置
- `scripts/setup/setup_network_isolation.sh` - 网络隔离配置
- `scripts/setup/setup_alerting.sh` - 监控告警配置

### 部署脚本
- `scripts/deploy/deploy.sh` - 一键部署
- `scripts/deploy/deploy-optimizations.sh` - 优化部署
- `scripts/deploy/package-only.sh` - 仅打包

### 用户管理
- `scripts/user/add_user.sh` - 添加用户
- `scripts/user/list_users.sh` - 列出用户

### 运维操作
- `scripts/ops/health_check.sh` - 健康检查
- `scripts/ops/backup.sh` - 数据备份

## 📚 文档导航

- [快速开始](docs/01-快速开始.md) - 新用户入门
- [部署指南](docs/03-部署指南.md) - 完整部署流程
- [企业微信配置](docs/04-企业微信配置.md) - 企业微信对接
- [运维手册](docs/05-运维手册.md) - 日常运维操作
- [故障排查](docs/06-故障排查.md) - 问题诊断指南
- [API 文档](docs/07-API文档.md) - 接口说明

## 🎯 系统特性

- ✅ 多角色虚拟员工（运营、产品、研发、测试、客服）
- ✅ 智能任务路由
- ✅ Docker 容器化部署
- ✅ 完整的安全防护体系
- ✅ 监控告警系统
- ✅ 自动化运维脚本

## 🔒 安全特性

- API Key 安全存储（Docker Secrets）
- 多层网络隔离
- 容器安全加固
- 完整的告警监控

## 📊 系统要求

- **服务器**: 8核16G+ （推荐 16核32G）
- **操作系统**: Ubuntu 22.04 LTS
- **域名**: 已备案，已解析
- **SSL**: Let's Encrypt 证书
- **企业微信**: 管理员权限

## 🛠️ 技术栈

- OpenClaw AI Agent Framework
- Docker / Docker Compose
- Python 3.9+
- PostgreSQL / SQLite
- Prometheus + Grafana
- Nginx

## 📞 获取帮助

- 查看文档: `docs/`
- 运行健康检查: `bash scripts/ops/health_check.sh`
- 查看日志: `docker logs <container_name>`

## 📝 更新日志

参见 [CHANGELOG.md](CHANGELOG.md)

## 📄 许可证

[待添加]

---

**最后更新**: 2026-02-12  
**维护团队**: OpenClaw Team
EOF

# 创建文档导航
cat > docs/README.md << 'EOF'
# 📚 OpenClaw 文档中心

## 快速导航

### 🚀 入门指南
- [01-快速开始](01-快速开始.md) - 5分钟快速入门
- [02-架构设计](02-架构设计.md) - 系统架构说明
- [03-部署指南](03-部署指南.md) - 完整部署流程

### 🔧 配置指南
- [04-企业微信配置](04-企业微信配置.md) - 企业微信对接完整指南

### 📖 运维文档
- [05-运维手册](05-运维手册.md) - 日常运维操作
- [06-故障排查](06-故障排查.md) - 常见问题排查

### 💻 开发文档
- [07-API文档](07-API文档.md) - API 接口说明

### 📦 历史文档
- [archives/](archives/) - 历史报告和归档文档

---

## 文档结构

```
docs/
├── README.md                    # 📍 本文档
├── 01-快速开始.md              # 新用户入门
├── 02-架构设计.md              # 系统架构
├── 03-部署指南.md              # 部署流程
├── 04-企业微信配置.md          # 企业微信
├── 05-运维手册.md              # 运维操作
├── 06-故障排查.md              # 问题诊断
├── 07-API文档.md               # API 接口
└── archives/                    # 历史文档
    ├── 优化任务完成报告_2026-02-12.md
    └── ...
```

---

**提示**: 建议按顺序阅读 01-07 的文档
EOF

# 创建 .gitignore
cat > .gitignore << 'EOF'
# 环境变量
.env
*.env
!.env.example

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
venv/
env/
ENV/

# 数据和日志
data/*
!data/.gitkeep
logs/*
!logs/.gitkeep
backups/*
!backups/.gitkeep

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# 操作系统
.DS_Store
Thumbs.db

# 临时文件
*.tar.gz
*.zip
*.log
*.tmp

# 敏感信息
*credentials*
*secret*
!setup_secrets.sh
EOF

echo -e "  ✅ 索引文档已生成"

# ============================================
# 完成
# ============================================
echo -e "\n${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}✅ 项目结构整理完成！${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

# 显示新结构
echo -e "\n${COLOR_BLUE}📊 新项目结构：${COLOR_RESET}"
tree -L 2 -I 'venv|__pycache__|*.pyc' . 2>/dev/null || find . -maxdepth 2 -type d | grep -v "^\./\." | head -20

echo -e "\n${COLOR_YELLOW}📋 统计信息：${COLOR_RESET}"
echo "  脚本数量: $(find scripts -name "*.sh" 2>/dev/null | wc -l)"
echo "  文档数量: $(find docs -name "*.md" 2>/dev/null | wc -l)"
echo "  配置文件: $(find config -type f 2>/dev/null | wc -l)"

echo -e "\n${COLOR_YELLOW}🎯 下一步操作：${COLOR_RESET}"
echo "1. 查看主 README:"
echo "   cat README.md"
echo ""
echo "2. 查看文档导航:"
echo "   cat docs/README.md"
echo ""
echo "3. 开始部署:"
echo "   bash scripts/deploy/deploy-optimizations.sh"
echo ""
echo "4. 备份文件位置:"
echo "   ../$BACKUP_NAME"

echo -e "\n${COLOR_GREEN}完成！${COLOR_RESET}"
