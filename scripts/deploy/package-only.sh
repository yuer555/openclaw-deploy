#!/bin/bash

# ====================================================
# 仅打包脚本（不上传）
# 适用于手动上传或 SSH 连接有问题的情况
# ====================================================

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RESET='\033[0m'

echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}创建优化脚本部署包${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

PACKAGE_DIR="openclaw-optimization-$(date +%Y%m%d)"
PACKAGE_FILE="${PACKAGE_DIR}.tar.gz"

echo -e "\n${COLOR_YELLOW}[1/3] 创建部署包目录...${COLOR_RESET}"

rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/scripts"
mkdir -p "$PACKAGE_DIR/docs"

echo -e "\n${COLOR_YELLOW}[2/3] 复制文件...${COLOR_RESET}"

# 复制脚本
cp scripts/setup_secrets.sh "$PACKAGE_DIR/scripts/"
cp scripts/setup_network_isolation.sh "$PACKAGE_DIR/scripts/"
cp scripts/setup_alerting.sh "$PACKAGE_DIR/scripts/"
chmod +x "$PACKAGE_DIR/scripts"/*.sh

# 复制文档
cp 企业微信实际部署指南.md "$PACKAGE_DIR/docs/"
cp 优化任务完成报告_2026-02-12.md "$PACKAGE_DIR/docs/"

# 创建快速部署脚本
cat > "$PACKAGE_DIR/quick-deploy.sh" << 'EOF'
#!/bin/bash
# 快速部署脚本

set -e

echo "开始部署 OpenClaw 优化脚本..."

# 移动到目标位置
sudo mkdir -p /opt/openclaw/scripts
sudo mkdir -p /opt/openclaw/docs

sudo cp scripts/*.sh /opt/openclaw/scripts/
sudo chmod +x /opt/openclaw/scripts/*.sh

sudo cp docs/*.md /opt/openclaw/docs/

echo "✅ 脚本已部署到 /opt/openclaw/scripts/"
echo "✅ 文档已部署到 /opt/openclaw/docs/"
echo ""
echo "下一步："
echo "cd /opt/openclaw"
echo "sudo bash scripts/setup_secrets.sh"
echo "sudo bash scripts/setup_network_isolation.sh"
echo "sudo bash scripts/setup_alerting.sh"
EOF

chmod +x "$PACKAGE_DIR/quick-deploy.sh"

# 创建 README
cat > "$PACKAGE_DIR/README.md" << 'EOF'
# OpenClaw 优化脚本部署包

## 📦 包含内容

### 脚本（3个）
- `scripts/setup_secrets.sh` - API Key 安全配置
- `scripts/setup_network_isolation.sh` - 网络隔离配置
- `scripts/setup_alerting.sh` - 监控告警配置

### 文档（2个）
- `docs/企业微信实际部署指南.md` - 完整部署指南
- `docs/优化任务完成报告_2026-02-12.md` - 任务完成报告

## 🚀 快速部署

### 方法 1：使用快速部署脚本

```bash
# 解压后直接执行
tar -xzf openclaw-optimization-*.tar.gz
cd openclaw-optimization-*/
sudo bash quick-deploy.sh
```

### 方法 2：手动部署

```bash
# 1. 解压
tar -xzf openclaw-optimization-*.tar.gz
cd openclaw-optimization-*/

# 2. 移动文件
sudo cp scripts/*.sh /opt/openclaw/scripts/
sudo chmod +x /opt/openclaw/scripts/*.sh
sudo cp docs/*.md /opt/openclaw/docs/

# 3. 执行优化
cd /opt/openclaw
sudo bash scripts/setup_secrets.sh
sudo bash scripts/setup_network_isolation.sh
sudo bash scripts/setup_alerting.sh
```

## 📖 详细说明

查看完整部署指南：
```bash
cat docs/企业微信实际部署指南.md
```

## 📊 优化报告

查看优化完成报告：
```bash
cat docs/优化任务完成报告_2026-02-12.md
```

## 🔧 脚本说明

### setup_secrets.sh
- 配置 Docker Secrets 安全存储
- 保护 API Keys 和敏感凭证
- 设置文件权限为 400

### setup_network_isolation.sh
- 创建 3 层隔离网络
- 配置持久化防火墙规则
- 容器安全加固

### setup_alerting.sh
- 配置 Prometheus Alertmanager
- 企业微信/邮件告警
- 15+ 监控规则

## ⚠️ 注意事项

1. 所有脚本需要 sudo 权限
2. 执行前请阅读部署指南
3. 建议按顺序执行脚本
4. 配置过程中会交互式输入凭证

## 📞 获取帮助

如有问题，请查看：
- `docs/企业微信实际部署指南.md` 的故障排查章节
- OpenClaw 日志：`docker logs <container_name>`
EOF

echo -e "\n${COLOR_YELLOW}[3/3] 打包...${COLOR_RESET}"

tar -czf "$PACKAGE_FILE" "$PACKAGE_DIR"
rm -rf "$PACKAGE_DIR"

PACKAGE_SIZE=$(du -h "$PACKAGE_FILE" | cut -f1)

echo -e "\n${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}✅ 部署包已创建！${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

echo -e "\n📦 部署包信息："
echo "   文件名: $PACKAGE_FILE"
echo "   大小: $PACKAGE_SIZE"
echo "   位置: $(pwd)/$PACKAGE_FILE"

echo -e "\n${COLOR_YELLOW}上传方式：${COLOR_RESET}"
echo ""
echo "方法 1 - SCP 上传："
echo "   scp $PACKAGE_FILE ubuntu@139.199.200.144:~/"
echo ""
echo "方法 2 - SFTP 上传："
echo "   sftp ubuntu@139.199.200.144"
echo "   put $PACKAGE_FILE"
echo ""
echo "方法 3 - 使用其他工具："
echo "   - FileZilla"
echo "   - Transmit"
echo "   - 云服务商的文件管理"

echo -e "\n${COLOR_YELLOW}上传后在服务器执行：${COLOR_RESET}"
echo ""
echo "   tar -xzf $PACKAGE_FILE"
echo "   cd ${PACKAGE_DIR}/"
echo "   sudo bash quick-deploy.sh"
echo ""
echo "   # 或查看 README 了解更多部署方式"
echo "   cat README.md"

echo -e "\n${COLOR_GREEN}完成！${COLOR_RESET}"
