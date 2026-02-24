#!/bin/bash
#==============================================================================
# 脚本名称: 1-prepare-server.sh
# 功能描述: 准备生产服务器环境（安装 Docker、配置防火墙等）
# 使用方法: ./1-prepare-server.sh
# 执行位置: 可在本地或服务器上执行
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
# 主流程
#==============================================================================

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║     ██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗      █████╗ ║
║    ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║     ██╔══██╗║
║    ██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║     ██║     ███████║║
║    ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║     ██║     ██╔══██║║
║    ╚██████╔╝██║     ███████╗██║ ╚████║╚██████╗███████╗██║  ██║║
║     ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝  ╚═╝║
║                                                               ║
║               生产服务器环境准备脚本 V1.4                      ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

print_warning "此脚本将准备生产服务器环境，包括："
print_warning "• 更新系统软件包"
print_warning "• 安装 Docker 和 Docker Compose"
print_warning "• 配置防火墙"
print_warning "• 创建必要的目录"
echo ""

read -p "确认继续？(输入 yes): " confirm
if [ "$confirm" != "yes" ]; then
    print_info "已取消"
    exit 0
fi

#------------------------------------------------------------------------------
# 步骤 1: 检查系统信息
#------------------------------------------------------------------------------
print_step "步骤 1/7: 检查系统信息"

print_info "操作系统: $(lsb_release -d | cut -f2)"
print_info "内核版本: $(uname -r)"
print_info "CPU 核心数: $(nproc)"
print_info "总内存: $(free -h | awk '/^Mem:/ {print $2}')"
print_info "磁盘空间: $(df -h / | awk 'NR==2 {print $4}') 可用"

# 检查是否为 Ubuntu
if ! grep -q "Ubuntu" /etc/os-release; then
    print_warning "此脚本为 Ubuntu 22.04 LTS 优化，其他系统可能需要调整"
fi

#------------------------------------------------------------------------------
# 步骤 2: 更新系统
#------------------------------------------------------------------------------
print_step "步骤 2/7: 更新系统软件包"

print_info "更新软件包列表..."
sudo apt-get update

print_info "升级已安装的软件包..."
sudo apt-get upgrade -y

print_success "系统更新完成"

#------------------------------------------------------------------------------
# 步骤 3: 安装基础工具
#------------------------------------------------------------------------------
print_step "步骤 3/7: 安装基础工具"

print_info "安装基础工具包..."
sudo apt-get install -y \
    curl \
    wget \
    git \
    vim \
    htop \
    net-tools \
    ufw \
    ca-certificates \
    gnupg \
    lsb-release

print_success "基础工具安装完成"

#------------------------------------------------------------------------------
# 步骤 4: 安装 Docker
#------------------------------------------------------------------------------
print_step "步骤 4/7: 安装 Docker"

if command -v docker &> /dev/null; then
    print_warning "Docker 已安装: $(docker --version)"
    read -p "是否重新安装？(输入 yes): " reinstall
    if [ "$reinstall" != "yes" ]; then
        print_info "跳过 Docker 安装"
    fi
fi

if [ "$reinstall" == "yes" ] || ! command -v docker &> /dev/null; then
    print_info "添加 Docker 官方 GPG 密钥..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    print_info "添加 Docker 源..."
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    print_info "安装 Docker Engine..."
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    print_info "启动 Docker 服务..."
    sudo systemctl start docker
    sudo systemctl enable docker
    
    print_success "Docker 安装完成: $(docker --version)"
fi

# 将当前用户添加到 docker 组
if ! groups $USER | grep -q docker; then
    print_info "将用户 $USER 添加到 docker 组..."
    sudo usermod -aG docker $USER
    print_warning "需要重新登录以应用 docker 组权限"
fi

#------------------------------------------------------------------------------
# 步骤 5: 配置防火墙
#------------------------------------------------------------------------------
print_step "步骤 5/7: 配置防火墙"

print_info "配置 UFW 防火墙..."
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS

# 询问是否启用防火墙
read -p "是否立即启用防火墙？(输入 yes，注意：确保 SSH 已允许): " enable_ufw
if [ "$enable_ufw" == "yes" ]; then
    sudo ufw --force enable
    print_success "防火墙已启用"
else
    print_warning "防火墙未启用，请稍后手动启用: sudo ufw enable"
fi

#------------------------------------------------------------------------------
# 步骤 6: 创建目录结构
#------------------------------------------------------------------------------
print_step "步骤 6/7: 创建目录结构"

print_info "创建应用目录..."
sudo mkdir -p /opt/openclaw/{data,logs,config,backups}
sudo mkdir -p /opt/openclaw/data/{gateway,agents,database}
sudo mkdir -p /opt/openclaw/config/{agents,nginx,ssl}

# 设置权限
sudo chown -R $USER:$USER /opt/openclaw
chmod -R 755 /opt/openclaw

print_success "目录创建完成: /opt/openclaw"

#------------------------------------------------------------------------------
# 步骤 7: 系统优化
#------------------------------------------------------------------------------
print_step "步骤 7/7: 系统优化"

print_info "优化系统参数..."

# 增加文件描述符限制
sudo tee -a /etc/security/limits.conf > /dev/null << EOF
* soft nofile 65536
* hard nofile 65536
EOF

# 优化网络参数
sudo tee -a /etc/sysctl.conf > /dev/null << EOF
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048
EOF

sudo sysctl -p || true

print_success "系统优化完成"

#==============================================================================
# 完成总结
#==============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 服务器环境准备完成！${NC}\n"

echo -e "${YELLOW}📋 下一步操作：${NC}\n"
echo -e "${YELLOW}1. 如需从本地上传文件：${NC}"
echo -e "   在本地执行: ${BLUE}./2-upload-to-server.sh${NC}\n"

echo -e "${YELLOW}2. 如已在服务器上：${NC}"
echo -e "   继续执行: ${BLUE}./3-deploy-production.sh${NC}\n"

echo -e "${YELLOW}3. 重要提醒：${NC}"
echo -e "   • 如果添加了 docker 组，请重新登录以应用权限"
echo -e "   • 准备好域名和 SSL 证书"
echo -e "   • 准备好企业微信配置信息"
echo -e "   • 准备好 AI API Key（GitHub Token 或 OpenAI）\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

print_info "详细文档: ../docs/02-生产部署指南.md"
echo ""
