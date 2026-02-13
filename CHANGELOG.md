# OpenClaw Deploy 项目变更日志

## [Unreleased]

### 新增
- 虚拟员工容器化部署支持（详见 docs/09-虚拟员工部署.md）
- GitHub Copilot 模型配置（详见 docs/10-GitHub-Copilot配置.md）

### 修复
- 修复 Alpine 镜像缺少 git 导致 npm 安装失败的问题

---

以下是虚拟员工部署相关的变更记录：

# 部署包更新日志

## 2026-02-13 - v1.1

### 🐛 修复
- **修复 Alpine 镜像缺少 git 的问题**
  - 问题：npm 安装 OpenClaw 时需要 git 克隆某些依赖（如 libsignal-node）
  - 错误：`npm error syscall spawn git` / `npm error path git` / `npm error errno -2`
  - 解决：在容器启动命令中添加 `apk add --no-cache git`
  - 影响文件：`deploy.sh`, `docker-compose.yml`

### 🔄 变更
- 更新 docker-compose.yml 启动命令：
  ```yaml
  command: sh -c "apk add --no-cache git && npm install -g openclaw@latest && openclaw gateway start"
  ```

### 📝 说明
使用 `node:24-alpine` 镜像部署时，需要先安装 git 才能正常安装 OpenClaw 及其依赖。

---

## 2026-02-13 - v1.0

### ✨ 初始版本
- 支持 4 个虚拟员工角色（运营、产品、研发、测试）
- Docker 容器化部署
- 安全隔离配置
- 一键部署脚本
- GitHub Copilot 模式支持

