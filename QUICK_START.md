# 🚀 OpenClaw V1.4 - 快速开始指南

> 5分钟快速上手 - 从零开始部署虚拟员工系统

## ⚡ 极速启动（本地测试）

### 1️⃣ 一键测试（推荐新手）
```bash
# 进入项目目录
cd /Users/marty/openclaw-deploy

# 进入本地测试目录
cd local

# 运行初始化（首次）
./1-init-local.sh

# 编辑配置文件，填入 API Key
vi .env.local
# 找到 GITHUB_TOKEN= 这一行
# 替换为你的真实 Token

# 启动服务
./2-start-local.sh

# 测试服务（新窗口）
./3-test-local.sh
```

**就这么简单！** 🎉

### 2️⃣ 停止和清理
```bash
# 停止服务（保留数据）
./4-stop-local.sh

# 完全清理（删除所有数据）
./5-clean-local.sh
```

---

## 🚀 生产部署（服务器）

### 准备工作
- ✅ Ubuntu 22.04 服务器
- ✅ 公网 IP 和域名
- ✅ Root 权限
- ✅ 企业微信管理员权限

### 部署步骤
```bash
# 进入生产部署目录
cd production

# 1. 准备服务器
./1-prepare-server.sh

# 2. 从本地上传文件（待完成）
# ./2-upload-to-server.sh

# 3. 部署服务（待完成）
# ./3-deploy-production.sh

# 4. 配置 SSL（待完成）
# ./4-setup-ssl.sh

# 5. 启动服务（待完成）
# ./5-start-production.sh

# 6. 健康检查（待完成）
# ./6-health-check.sh
```

> 📝 **注意**: 生产部署脚本正在完善中，建议先本地测试

---

## 📚 完整文档

### 入门必读
| 文档 | 路径 |
|------|------|
| 本地测试指南 | `docs/01-本地测试指南.md` |
| 生产部署指南 | `docs/02-生产部署指南.md`（待完成） |

### 配置指南
| 文档 | 路径 |
|------|------|
| 企业微信配置 | `docs/04-企业微信配置.md` |
| 虚拟员工配置 | `config/agents/*.yml` |
| GitHub Copilot | `docs/10-GitHub-Copilot配置.md` |

### 问题排查
| 文档 | 路径 |
|------|------|
| 常见问题 | `docs/06-常见问题.md`（待完成） |
| 故障排查 | `docs/06-故障排查.md` |

---

## 🎯 目录结构速览

```
openclaw-deploy/
├── 📄 README.md              # 项目总览（你在这里）
├── 🚀 QUICK_START.md         # 快速开始（就是本文档）
│
├── 🏠 local/                 # 本地测试环境（✅ 完全可用）
│   ├── 1-init-local.sh       # 初始化
│   ├── 2-start-local.sh      # 启动
│   ├── 3-test-local.sh       # 测试
│   ├── 4-stop-local.sh       # 停止
│   └── 5-clean-local.sh      # 清理
│
├── 🚀 production/            # 生产部署（⏳ 部分完成）
│   └── 1-prepare-server.sh   # 准备服务器（✅ 可用）
│
├── 📚 docs/                  # 文档中心
│   └── 01-本地测试指南.md     # 详细教程（✅ 完成）
│
└── ⚙️ config/                 # 配置文件
    └── agents/               # 虚拟员工配置
```

---

## ❓ 常见问题速查

### Q: Docker 没安装？
```bash
# macOS
brew install --cask docker

# 或访问 https://www.docker.com/products/docker-desktop
```

### Q: 需要什么 API Key？
选择其一：
- **GitHub Copilot Token**: https://github.com/settings/tokens （推荐，免费）
- **OpenAI API Key**: https://platform.openai.com/api-keys

### Q: 如何查看日志？
```bash
docker logs openclaw-local -f
```

### Q: 端口被占用？
修改 `.env.local` 中的 `OPENCLAW_PORT=3000` 为其他端口

### Q: 测试失败了？
```bash
# 查看详细日志
docker logs openclaw-local --tail=100

# 检查配置
cat .env.local

# 重启服务
./4-stop-local.sh
./2-start-local.sh
```

---

## 📞 获取帮助

- 📚 [查看完整文档](docs/README.md)
- 💬 [Discord 社区](https://discord.com/invite/clawd)
- 🐙 [GitHub Issues](https://github.com/openclaw/openclaw/issues)
- 📖 [官方文档](https://docs.openclaw.ai)

---

## 🎉 下一步

### 本地测试成功后
1. ✅ 学习[虚拟员工配置](config/agents/)
2. ✅ 配置[企业微信集成](docs/04-企业微信配置.md)
3. ✅ 准备[生产部署](docs/02-生产部署指南.md)

### 需要帮助？
- 📖 详细文档: `docs/01-本地测试指南.md`
- 🔧 故障排查: `docs/06-故障排查.md`

---

**💡 小贴士**: 
- 新手建议先完成本地测试
- 测试成功后再考虑生产部署
- 遇到问题先查文档，再提问

**版本**: V1.4  
**更新**: 2026-02-24  
**维护**: OpenClaw Team
