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

**方式A：企业微信网关部署（企业微信集成）**

```bash
# 自动打包上传
bash scripts/deploy/deploy-optimizations.sh

# 或手动打包
bash scripts/deploy/package-only.sh
```

**方式B：虚拟员工容器部署（独立运行）** 🆕

```bash
# 本地一键部署到服务器
bash scripts/deploy/local-deploy-agents.sh

# 或手动上传后部署
bash scripts/deploy/deploy-agents.sh
```

详见 `docs/09-虚拟员工部署.md`

### 3. 配置认证

- **企业微信**：参考 `docs/04-企业微信配置.md`
- **GitHub Copilot**：参考 `docs/10-GitHub-Copilot配置.md` 🆕

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
- ✅ 虚拟员工容器化部署 🆕（独立运行模式）
- ✅ GitHub Copilot 模型支持 🆕

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
