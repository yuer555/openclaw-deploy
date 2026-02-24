# 🚀 生产部署环境

> 将 OpenClaw 虚拟员工系统部署到云服务器

## 📖 说明

本目录包含将 OpenClaw 系统部署到生产服务器所需的所有文件和脚本。

## 🎯 部署流程

### 前置要求
- ✅ Ubuntu 22.04 LTS 服务器
- ✅ 8核16GB+ 内存（推荐 16核32GB）
- ✅ 公网 IP 和域名（已备案、已解析）
- ✅ Root 或 sudo 权限
- ✅ 企业微信管理员权限

### 部署步骤

```bash
# 1️⃣ 准备服务器环境
./1-prepare-server.sh

# 2️⃣ 上传文件到服务器
./2-upload-to-server.sh

# 3️⃣ 在服务器上部署服务
# (登录服务器后执行)
./3-deploy-production.sh

# 4️⃣ 配置 SSL 证书
./4-setup-ssl.sh

# 5️⃣ 启动生产服务
./5-start-production.sh

# 6️⃣ 运行健康检查
./6-health-check.sh
```

## 📁 文件说明

| 文件 | 说明 | 执行位置 |
|------|------|---------|
| `1-prepare-server.sh` | 准备服务器：安装 Docker 等 | 🏠 本地或 🚀 服务器 |
| `2-upload-to-server.sh` | 上传文件到服务器 | 🏠 本地 |
| `3-deploy-production.sh` | 部署生产服务 | 🚀 服务器 |
| `4-setup-ssl.sh` | 配置 SSL 证书 | 🚀 服务器 |
| `5-start-production.sh` | 启动生产服务 | 🚀 服务器 |
| `6-health-check.sh` | 健康检查 | 🚀 服务器 |
| `docker-compose.prod.yml` | 生产环境 Docker 配置 | 🚀 服务器 |
| `.env.prod.example` | 生产环境变量模板 | 🚀 服务器 |

## 🔐 安全配置

生产部署包含以下安全特性：
- ✅ SSL/TLS 加密（Let's Encrypt）
- ✅ Nginx 反向代理
- ✅ Docker 网络隔离
- ✅ API Key 安全存储
- ✅ 防火墙配置
- ✅ 日志审计

## 📊 服务器配置推荐

### 最低配置
- CPU: 8 核
- 内存: 16GB
- 磁盘: 50GB SSD
- 带宽: 5Mbps

### 推荐配置
- CPU: 16 核
- 内存: 32GB
- 磁盘: 100GB SSD
- 带宽: 10Mbps+

## 🌐 域名配置

部署前需要完成：
1. 域名备案（中国大陆服务器必须）
2. DNS 解析到服务器 IP
3. 准备以下子域名：
   - `openclaw.yourdomain.com` - 主服务
   - `admin.yourdomain.com` - 管理后台（可选）

## 💬 企业微信配置

需要准备：
1. 企业 ID (`corp_id`)
2. 应用 ID (`agent_id`)
3. 应用 Secret (`secret`)
4. 回调 Token (`token`)
5. EncodingAESKey (`encoding_aes_key`)

详见：`../docs/03-企业微信配置.md`

## 🔧 常见操作

### 查看服务状态
```bash
docker ps
docker compose -f docker-compose.prod.yml ps
```

### 查看日志
```bash
docker logs openclaw-production -f
docker logs openclaw-nginx -f
```

### 重启服务
```bash
docker compose -f docker-compose.prod.yml restart
```

### 备份数据
```bash
../scripts/backup.sh
```

### 更新服务
```bash
# 拉取最新镜像
docker compose -f docker-compose.prod.yml pull

# 重启服务
docker compose -f docker-compose.prod.yml up -d
```

## 📚 详细文档

完整的生产部署指南请查看：`../docs/02-生产部署指南.md`

## ⚠️ 重要提示

1. **首次部署前**请仔细阅读所有文档
2. **备份重要数据**再进行任何操作
3. **测试环境验证**后再部署到生产
4. **企业微信配置**需要管理员权限
5. **SSL 证书**需要域名正确解析

---

**💡 提示**: 如有疑问，请查看 FAQ 或联系技术支持！
