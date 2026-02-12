#!/bin/bash

# ====================================================
# 打包并上传优化脚本到服务器
# 目标服务器：139.199.200.144
# ====================================================

set -e

SERVER_IP="139.199.200.144"
SERVER_USER="ubuntu"
SERVER_PATH="/opt/openclaw"

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}打包并上传优化脚本到服务器${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

# 1. 检查脚本文件是否存在
echo -e "\n${COLOR_YELLOW}[1/5] 检查本地文件...${COLOR_RESET}"

FILES_TO_CHECK=(
    "scripts/setup_secrets.sh"
    "scripts/setup_network_isolation.sh"
    "scripts/setup_alerting.sh"
    "企业微信实际部署指南.md"
    "优化任务完成报告_2026-02-12.md"
)

for file in "${FILES_TO_CHECK[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${COLOR_RED}❌ 文件不存在: $file${COLOR_RESET}"
        exit 1
    fi
    echo -e "  ✅ $file"
done

# 2. 创建临时打包目录
echo -e "\n${COLOR_YELLOW}[2/5] 创建部署包...${COLOR_RESET}"

PACKAGE_DIR="openclaw-optimization-$(date +%Y%m%d)"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/scripts"
mkdir -p "$PACKAGE_DIR/docs"

# 复制脚本
cp scripts/setup_secrets.sh "$PACKAGE_DIR/scripts/"
cp scripts/setup_network_isolation.sh "$PACKAGE_DIR/scripts/"
cp scripts/setup_alerting.sh "$PACKAGE_DIR/scripts/"

# 复制文档
cp 企业微信实际部署指南.md "$PACKAGE_DIR/docs/"
cp 优化任务完成报告_2026-02-12.md "$PACKAGE_DIR/docs/"

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

### 在服务器上执行

```bash
# 1. 解压部署包
tar -xzf openclaw-optimization-*.tar.gz
cd openclaw-optimization-*/

# 2. 移动脚本到目标位置
sudo cp scripts/*.sh /opt/openclaw/scripts/
sudo chmod +x /opt/openclaw/scripts/*.sh

# 3. 按顺序执行优化
cd /opt/openclaw

# API Key 安全配置
sudo bash scripts/setup_secrets.sh

# 网络隔离配置
sudo bash scripts/setup_network_isolation.sh

# 监控告警配置
sudo bash scripts/setup_alerting.sh
```

## 📖 详细说明

请参考 `docs/企业微信实际部署指南.md`

## 📊 完成报告

请参考 `docs/优化任务完成报告_2026-02-12.md`
EOF

# 设置脚本执行权限
chmod +x "$PACKAGE_DIR/scripts"/*.sh

# 打包
tar -czf "${PACKAGE_DIR}.tar.gz" "$PACKAGE_DIR"
PACKAGE_SIZE=$(du -h "${PACKAGE_DIR}.tar.gz" | cut -f1)

echo -e "  ✅ 部署包已创建: ${PACKAGE_DIR}.tar.gz (${PACKAGE_SIZE})"

# 3. 测试 SSH 连接
echo -e "\n${COLOR_YELLOW}[3/5] 测试服务器连接...${COLOR_RESET}"

if ssh -o ConnectTimeout=5 -o BatchMode=yes ${SERVER_USER}@${SERVER_IP} "echo '连接成功'" 2>/dev/null; then
    echo -e "  ✅ SSH 连接正常"
else
    echo -e "${COLOR_RED}❌ SSH 连接失败${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}请确保：${COLOR_RESET}"
    echo "1. SSH 密钥已配置"
    echo "2. 服务器 IP 正确: ${SERVER_IP}"
    echo "3. 用户名正确: ${SERVER_USER}"
    echo ""
    echo -e "${COLOR_YELLOW}手动上传命令：${COLOR_RESET}"
    echo "scp ${PACKAGE_DIR}.tar.gz ${SERVER_USER}@${SERVER_IP}:~/"
    exit 1
fi

# 4. 上传到服务器
echo -e "\n${COLOR_YELLOW}[4/5] 上传部署包到服务器...${COLOR_RESET}"

scp "${PACKAGE_DIR}.tar.gz" ${SERVER_USER}@${SERVER_IP}:~/

echo -e "  ✅ 上传完成"

# 5. 在服务器上解压并移动到目标位置
echo -e "\n${COLOR_YELLOW}[5/5] 在服务器上部署...${COLOR_RESET}"

ssh ${SERVER_USER}@${SERVER_IP} << REMOTE_COMMANDS
set -e

# 解压
cd ~
tar -xzf ${PACKAGE_DIR}.tar.gz
cd ${PACKAGE_DIR}

# 确保目标目录存在
sudo mkdir -p ${SERVER_PATH}/scripts
sudo mkdir -p ${SERVER_PATH}/docs

# 复制脚本
sudo cp scripts/*.sh ${SERVER_PATH}/scripts/
sudo chmod +x ${SERVER_PATH}/scripts/*.sh

# 复制文档
sudo cp docs/*.md ${SERVER_PATH}/docs/

# 清理
cd ~
rm -rf ${PACKAGE_DIR} ${PACKAGE_DIR}.tar.gz

echo "✅ 部署完成！"
echo ""
echo "脚本位置："
ls -lh ${SERVER_PATH}/scripts/setup_*.sh
echo ""
echo "文档位置："
ls -lh ${SERVER_PATH}/docs/*.md | grep "企业微信\|优化任务"

REMOTE_COMMANDS

# 清理本地临时文件
rm -rf "$PACKAGE_DIR"

echo -e "\n${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}✅ 部署包已上传并解压！${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

echo -e "\n${COLOR_YELLOW}下一步操作：${COLOR_RESET}"
echo ""
echo "1. 登录服务器："
echo "   ssh ${SERVER_USER}@${SERVER_IP}"
echo ""
echo "2. 查看部署包内容："
echo "   ls -lh ${SERVER_PATH}/scripts/"
echo "   ls -lh ${SERVER_PATH}/docs/"
echo ""
echo "3. 按顺序执行优化脚本："
echo "   cd ${SERVER_PATH}"
echo "   sudo bash scripts/setup_secrets.sh"
echo "   sudo bash scripts/setup_network_isolation.sh"
echo "   sudo bash scripts/setup_alerting.sh"
echo ""
echo "4. 查看部署指南："
echo "   cat ${SERVER_PATH}/docs/企业微信实际部署指南.md"
echo ""
echo -e "${COLOR_YELLOW}或者直接执行一键部署：${COLOR_RESET}"
echo "   ssh ${SERVER_USER}@${SERVER_IP}"
echo "   cd ${SERVER_PATH}"
echo "   sudo bash scripts/setup_secrets.sh && \\"
echo "   sudo bash scripts/setup_network_isolation.sh && \\"
echo "   sudo bash scripts/setup_alerting.sh"
