#!/bin/bash
# 本地一键上传并部署脚本
# 在 Mac 上执行：bash local-deploy.sh

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

SERVER="ubuntu@139.199.200.144"

echo_info "========================================="
echo_info "OpenClaw 云服务一键部署（本地执行）"
echo_info "========================================="

# 检查 SSH 连接
echo_info "检查服务器连接..."
if ! ssh -o ConnectTimeout=5 $SERVER "echo 'SSH OK'" > /dev/null 2>&1; then
    echo_warn "无法连接到服务器，请检查："
    echo "  1. 服务器 IP 是否正确：139.199.200.144"
    echo "  2. SSH 密钥是否配置"
    echo "  3. 网络是否正常"
    exit 1
fi
echo_info "✓ 服务器连接正常"

# 上传文件
echo_info "上传部署文件到服务器..."
rsync -avz --progress \
    deploy.sh \
    README.md \
    QUICKSTART.md \
    $SERVER:/tmp/openclaw-deploy/

echo_info "✓ 文件上传完成"

# 执行部署
echo_info ""
echo_info "========================================="
echo_info "开始远程部署..."
echo_info "========================================="
echo_info ""

ssh -t $SERVER << 'ENDSSH'
cd /tmp/openclaw-deploy
bash deploy.sh
ENDSSH

echo_info ""
echo_info "========================================="
echo_info "部署完成！"
echo_info "========================================="
echo_info ""
echo_info "接下来你可以："
echo_info "1. SSH 登录服务器：ssh $SERVER"
echo_info "2. 进入工作目录：cd /opt/openclaw"
echo_info "3. 启动服务：bash start.sh"
echo_info ""
echo_warn "提示：首次启动需要下载 Docker 镜像（约 500MB），请耐心等待 3-5 分钟"
echo_info ""
