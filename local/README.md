# 🏠 本地测试环境

> 在你的电脑上快速测试 OpenClaw 虚拟员工系统

## 📖 说明

本目录包含在本地测试 OpenClaw 系统所需的所有文件和脚本。

## 🚀 快速开始

### 前置要求
- ✅ Docker Desktop 已安装并运行
- ✅ macOS 或 Linux 系统
- ✅ 至少 8GB 内存

### 使用步骤

```bash
# 1️⃣ 初始化本地环境（首次运行）
./1-init-local.sh

# 2️⃣ 启动本地服务
./2-start-local.sh

# 3️⃣ 测试服务（在另一个终端）
./3-test-local.sh

# 4️⃣ 停止服务
./4-stop-local.sh

# 5️⃣ 清理环境（可选）
./5-clean-local.sh
```

## 📁 文件说明

| 文件 | 说明 |
|------|------|
| `1-init-local.sh` | 初始化脚本：创建配置文件和数据目录 |
| `2-start-local.sh` | 启动脚本：启动所有 Docker 容器 |
| `3-test-local.sh` | 测试脚本：检查服务是否正常运行 |
| `4-stop-local.sh` | 停止脚本：停止所有容器 |
| `5-clean-local.sh` | 清理脚本：删除容器和数据 |
| `docker-compose.local.yml` | Docker 编排配置 |
| `.env.local.example` | 环境变量模板 |

## 🎯 测试内容

本地测试将验证：
- ✅ Docker 容器正常启动
- ✅ 虚拟员工角色正常加载
- ✅ API 接口正常响应
- ✅ 日志输出正常

## 💡 常见问题

### Q: Docker Desktop 必须安装吗？
A: 是的，本地测试依赖 Docker。请从 https://www.docker.com/products/docker-desktop 下载安装。

### Q: 需要配置企业微信吗？
A: 本地测试不需要。如需测试企业微信集成，请查看生产部署文档。

### Q: 测试数据会保留吗？
A: 默认保留在 `../data/local/` 目录。运行 `5-clean-local.sh` 会删除。

### Q: 如何查看日志？
A: 运行 `docker logs openclaw-local` 或 `docker logs <container_name>`

## 📚 详细文档

完整的本地测试指南请查看：`../docs/01-本地测试指南.md`

---

**💡 提示**: 测试成功后，可以继续学习生产部署流程！
