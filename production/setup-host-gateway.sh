#!/bin/bash
#==============================================================================
# 脚本名称: setup-host-gateway.sh
# 功能描述: 从零准备生产服务器（Docker + Python3 + Node.js + openclaw + 依赖）
# 使用方法: ./setup-host-gateway.sh
# 执行位置: 服务器（全新 Ubuntu/Debian/CentOS 环境）
# 版本: V3.0
#==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_step()    { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BLUE}📍 $1${NC}\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 检测包管理器
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
else
    print_error "不支持的系统，仅支持 apt (Ubuntu/Debian) 或 yum (CentOS/RHEL)"
    exit 1
fi

echo -e "${GREEN}🚀 OpenClaw 生产服务器环境准备（从零开始）${NC}\n"
print_info "检测到包管理器: $PKG_MANAGER"
echo ""

#------------------------------------------------------------------------------
# 步骤 1: 更新系统 + 安装基础工具
#------------------------------------------------------------------------------
print_step "步骤 1/7: 更新系统 + 安装基础工具"

if [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt-get update
    sudo apt-get install -y curl wget git vim htop net-tools ca-certificates gnupg lsb-release
elif [ "$PKG_MANAGER" = "yum" ]; then
    sudo yum update -y
    sudo yum install -y curl wget git vim htop net-tools ca-certificates gnupg2
fi
print_success "基础工具安装完成"

#------------------------------------------------------------------------------
# 步骤 2: 安装 Docker + Docker Compose
#------------------------------------------------------------------------------
print_step "步骤 2/7: 安装 Docker"

if command -v docker &> /dev/null; then
    print_success "Docker 已安装: $(docker --version)"
else
    print_info "安装 Docker..."
    if [ "$PKG_MANAGER" = "apt" ]; then
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    elif [ "$PKG_MANAGER" = "yum" ]; then
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    sudo systemctl start docker
    sudo systemctl enable docker
    print_success "Docker 安装完成: $(docker --version)"
fi

# Docker Compose 检查
if docker compose version &> /dev/null; then
    print_success "Docker Compose: $(docker compose version --short)"
else
    print_error "Docker Compose 未安装！"
    exit 1
fi

# 将当前用户添加到 docker 组
if ! groups $USER | grep -q docker; then
    print_info "将用户 $USER 添加到 docker 组..."
    sudo usermod -aG docker $USER
    print_warning "需要重新登录以应用 docker 组权限（或执行 newgrp docker）"
fi

#------------------------------------------------------------------------------
# 步骤 3: 安装 Python3 + pip
#------------------------------------------------------------------------------
print_step "步骤 3/7: 安装 Python3"

if command -v python3 &> /dev/null; then
    print_success "Python3 已安装: $(python3 --version)"
else
    print_info "安装 Python3..."
    if [ "$PKG_MANAGER" = "apt" ]; then
        sudo apt-get install -y python3 python3-pip python3-venv python3-full
    elif [ "$PKG_MANAGER" = "yum" ]; then
        sudo yum install -y python3 python3-pip
    fi
    print_success "Python3 安装完成: $(python3 --version)"
fi

# 确保 venv 模块可用（Ubuntu 某些版本需要单独装）
if [ "$PKG_MANAGER" = "apt" ]; then
    sudo apt-get install -y python3-venv python3-full 2>/dev/null || true
fi

#------------------------------------------------------------------------------
# 步骤 4: 安装 Node.js + npm
#------------------------------------------------------------------------------
print_step "步骤 4/7: 安装 Node.js"

if command -v node &> /dev/null; then
    print_success "Node.js 已安装: $(node --version)"
else
    print_info "安装 Node.js..."
    if [ "$PKG_MANAGER" = "apt" ]; then
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
    elif [ "$PKG_MANAGER" = "yum" ]; then
        curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash -
        sudo yum install -y nodejs
    fi
    print_success "Node.js 安装完成: $(node --version)"
fi

if command -v npm &> /dev/null; then
    print_success "npm: $(npm --version)"
else
    print_error "npm 未安装！"
    exit 1
fi

#------------------------------------------------------------------------------
# 步骤 5: 安装 openclaw CLI
#------------------------------------------------------------------------------
print_step "步骤 5/7: 安装 openclaw"

if command -v openclaw &> /dev/null; then
    print_success "openclaw 已安装: $(openclaw --version 2>/dev/null || echo '已安装')"
else
    print_info "安装 openclaw..."
    sudo npm install -g @anthropic-ai/claude-code
    print_success "openclaw 安装完成"
fi

#------------------------------------------------------------------------------
# 步骤 6: 安装 Python 依赖（venv 隔离）
#------------------------------------------------------------------------------
print_step "步骤 6/7: 安装 Python Gateway 依赖"

VENV_DIR="/opt/openclaw/venv"
sudo mkdir -p /opt/openclaw
sudo chown -R $USER:$USER /opt/openclaw

if [ ! -d "$VENV_DIR" ]; then
    print_info "创建 Python 虚拟环境: $VENV_DIR"
    python3 -m venv "$VENV_DIR"
fi

# 确保 pip 可用
if [ ! -f "$VENV_DIR/bin/pip" ]; then
    print_info "安装 pip 到 venv..."
    "$VENV_DIR/bin/python" -m ensurepip --upgrade
fi

# 升级 pip
"$VENV_DIR/bin/python" -m pip install --upgrade pip

# 安装依赖
"$VENV_DIR/bin/python" -m pip install -r "$PROJECT_DIR/src/gateway/requirements.txt"
print_success "Python 依赖安装完成（venv: $VENV_DIR）"

# 验证关键模块
"$VENV_DIR/bin/python" -c "import flask; import requests; import Crypto; import websocket; print('所有模块验证通过')"
print_success "模块验证通过: flask, requests, pycryptodome, websocket-client"

#------------------------------------------------------------------------------
# 步骤 7: 创建目录结构
#------------------------------------------------------------------------------
print_step "步骤 7/7: 创建目录结构"

mkdir -p /opt/openclaw/shared-files
mkdir -p /opt/openclaw/data/gateway
mkdir -p /opt/openclaw/data/agents/{operation,product,development,testing,service}
mkdir -p /opt/openclaw/logs/gateway
mkdir -p /tmp/openclaw

chmod -R 755 /opt/openclaw
print_success "目录结构创建完成"

#==============================================================================
# 完成总结
#==============================================================================
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 服务器环境准备完成！${NC}\n"

echo -e "${YELLOW}已安装：${NC}"
echo "  Docker:     $(docker --version 2>/dev/null | cut -d' ' -f3 || echo '未安装')"
echo "  Python3:    $(python3 --version 2>/dev/null || echo '未安装')"
echo "  Node.js:    $(node --version 2>/dev/null || echo '未安装')"
echo "  pip (venv): $($VENV_DIR/bin/pip --version 2>/dev/null | cut -d' ' -f2 || echo '未安装')"
echo "  Flask:      $($VENV_DIR/bin/python -c 'import flask; print(flask.__version__)' 2>/dev/null || echo '未安装')"
echo ""

echo -e "${YELLOW}下一步：${NC}"
echo "  1. 构建镜像:     ./3-deploy-production.sh"
echo "  2. 编辑配置:     vi .env.prod"
echo "  3. 启动服务:     ./5-start-production.sh"
echo ""
