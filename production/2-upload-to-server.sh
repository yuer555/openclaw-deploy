#!/bin/bash
#==============================================================================
# 脚本名称: 2-upload-to-server.sh
# 功能描述: 从本地上传项目文件到生产服务器
# 使用方法: ./2-upload-to-server.sh
# 执行位置: 🏠 本地
# 作者: OpenClaw Team
# 版本: V1.4
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📍 $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

#==============================================================================
# 配置
#==============================================================================

# 默认服务器配置
DEFAULT_SERVER_IP="139.199.200.144"
DEFAULT_SERVER_USER="ubuntu"
DEFAULT_REMOTE_DIR="/opt/openclaw"

#==============================================================================
# 主流程
#==============================================================================

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                  文件上传到生产服务器                          ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

#------------------------------------------------------------------------------
# 步骤 1: 获取服务器信息
#------------------------------------------------------------------------------
print_step "步骤 1/5: 配置服务器信息"

read -p "服务器 IP 地址 [${DEFAULT_SERVER_IP}]: " SERVER_IP
SERVER_IP=${SERVER_IP:-$DEFAULT_SERVER_IP}

read -p "服务器用户名 [${DEFAULT_SERVER_USER}]: " SERVER_USER
SERVER_USER=${SERVER_USER:-$DEFAULT_SERVER_USER}

read -p "远程部署目录 [${DEFAULT_REMOTE_DIR}]: " REMOTE_DIR
REMOTE_DIR=${REMOTE_DIR:-$DEFAULT_REMOTE_DIR}

print_info "目标服务器: ${SERVER_USER}@${SERVER_IP}"
print_info "部署目录: ${REMOTE_DIR}"

#------------------------------------------------------------------------------
# 步骤 2: 测试 SSH 连接
#------------------------------------------------------------------------------
print_step "步骤 2/5: 测试 SSH 连接"

print_info "测试 SSH 连接..."
if ssh -o ConnectTimeout=10 ${SERVER_USER}@${SERVER_IP} "echo 'SSH 连接成功'" 2>/dev/null; then
    print_success "SSH 连接正常"
else
    print_error "SSH 连接失败！"
    print_info "请检查："
    print_info "  1. 服务器 IP 是否正确"
    print_info "  2. SSH 密钥是否配置（运行 ssh-copy-id ${SERVER_USER}@${SERVER_IP}）"
    print_info "  3. 服务器防火墙是否允许 SSH（端口 22）"
    exit 1
fi

#------------------------------------------------------------------------------
# 步骤 3: 创建打包文件
#------------------------------------------------------------------------------
print_step "步骤 3/5: 打包项目文件"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_NAME="openclaw-deploy-${TIMESTAMP}.tar.gz"
TEMP_DIR="./temp_deploy"

print_info "创建临时目录..."
rm -rf ${TEMP_DIR}
mkdir -p ${TEMP_DIR}/openclaw-deploy

print_info "复制必要文件..."
# 复制生产部署文件
cp -r production ${TEMP_DIR}/openclaw-deploy/
cp -r config ${TEMP_DIR}/openclaw-deploy/
cp -r src ${TEMP_DIR}/openclaw-deploy/
cp -r scripts ${TEMP_DIR}/openclaw-deploy/
cp README.md ${TEMP_DIR}/openclaw-deploy/ 2>/dev/null || true
cp QUICK_START.md ${TEMP_DIR}/openclaw-deploy/ 2>/dev/null || true

# 复制文档
mkdir -p ${TEMP_DIR}/openclaw-deploy/docs
cp docs/02-生产部署指南.md ${TEMP_DIR}/openclaw-deploy/docs/ 2>/dev/null || true
cp docs/03-企业微信配置.md ${TEMP_DIR}/openclaw-deploy/docs/ 2>/dev/null || true
cp docs/04-虚拟员工配置.md ${TEMP_DIR}/openclaw-deploy/docs/ 2>/dev/null || true
cp docs/README.md ${TEMP_DIR}/openclaw-deploy/docs/ 2>/dev/null || true

print_info "打包文件..."
cd ${TEMP_DIR}
tar -czf ${PACKAGE_NAME} openclaw-deploy/
cd ..

print_success "打包完成: ${TEMP_DIR}/${PACKAGE_NAME}"

#------------------------------------------------------------------------------
# 步骤 4: 上传到服务器
#------------------------------------------------------------------------------
print_step "步骤 4/5: 上传文件到服务器"

print_info "创建远程目录..."
ssh ${SERVER_USER}@${SERVER_IP} "sudo mkdir -p ${REMOTE_DIR} && sudo chown ${SERVER_USER}:${SERVER_USER} ${REMOTE_DIR}"

print_info "上传打包文件（可能需要几分钟）..."
scp ${TEMP_DIR}/${PACKAGE_NAME} ${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/

print_success "文件上传完成"

#------------------------------------------------------------------------------
# 步骤 5: 解压文件
#------------------------------------------------------------------------------
print_step "步骤 5/5: 解压文件"

print_info "在服务器上解压文件..."
ssh ${SERVER_USER}@${SERVER_IP} << ENDSSH
cd ${REMOTE_DIR}
# 清除旧的代码文件（保留运行时数据和 .env.prod 配置）
if [ -f production/.env.prod ]; then cp production/.env.prod /tmp/.env.prod.bak; fi
rm -rf config src production scripts docs README.md QUICK_START.md openclaw-deploy 2>/dev/null || true
tar -xzf ${PACKAGE_NAME}
mv openclaw-deploy/* . 2>/dev/null || true
rmdir openclaw-deploy 2>/dev/null || true
rm ${PACKAGE_NAME}
if [ -f /tmp/.env.prod.bak ]; then mv /tmp/.env.prod.bak production/.env.prod; fi
chmod +x production/*.sh 2>/dev/null || true
chmod +x scripts/*.sh 2>/dev/null || true
ls -la
ENDSSH

print_success "文件解压完成"

#------------------------------------------------------------------------------
# 清理临时文件
#------------------------------------------------------------------------------
print_info "清理本地临时文件..."
rm -rf ${TEMP_DIR}

#==============================================================================
# 完成总结
#==============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 文件上传成功！${NC}\n"

echo -e "${YELLOW}📋 下一步操作：${NC}\n"
echo -e "${YELLOW}1. 登录到服务器：${NC}"
echo -e "   ${BLUE}ssh ${SERVER_USER}@${SERVER_IP}${NC}\n"

echo -e "${YELLOW}2. 进入部署目录：${NC}"
echo -e "   ${BLUE}cd ${REMOTE_DIR}/production${NC}\n"

echo -e "${YELLOW}3. 继续部署：${NC}"
echo -e "   ${BLUE}./3-deploy-production.sh${NC}\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
