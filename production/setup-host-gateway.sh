#!/bin/bash
#==============================================================================
# 脚本名称: setup-host-gateway.sh
# 功能描述: 在宿主机安装 Gateway 运行依赖（Python3, Node.js, openclaw）
# 使用方法: ./setup-host-gateway.sh
# 执行位置: 服务器
# 版本: V2.0
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

#------------------------------------------------------------------------------
# 步骤 1: 安装 Python3 + pip
#------------------------------------------------------------------------------
print_step "步骤 1/5: 安装 Python3"

if command -v python3 &> /dev/null; then
    print_success "Python3 已安装: $(python3 --version)"
else
    print_info "安装 Python3..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3 python3-pip
    else
        print_error "不支持的包管理器，请手动安装 Python3"
        exit 1
    fi
    print_success "Python3 安装完成: $(python3 --version)"
fi

# 确保 pip3 可用
if ! command -v pip3 &> /dev/null; then
    print_info "安装 pip3..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get install -y python3-pip
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3-pip
    else
        python3 -m ensurepip --upgrade
    fi
    print_success "pip3 安装完成"
fi

#------------------------------------------------------------------------------
# 步骤 2: 安装 Node.js 24 + npm
#------------------------------------------------------------------------------
print_step "步骤 2/5: 安装 Node.js"

if command -v node &> /dev/null; then
    print_success "Node.js 已安装: $(node --version)"
else
    print_info "安装 Node.js 24..."
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
    sudo apt-get install -y nodejs
    print_success "Node.js 安装完成: $(node --version)"
fi
# __CONTINUE_HERE__

#------------------------------------------------------------------------------
# 步骤 3: 安装 openclaw
#------------------------------------------------------------------------------
print_step "步骤 3/5: 安装 openclaw"

if command -v openclaw &> /dev/null || npx openclaw --version &> /dev/null 2>&1; then
    print_success "openclaw 已安装"
else
    print_info "安装 openclaw..."
    npm install -g openclaw@2026.2.26
    print_success "openclaw 安装完成"
fi

#------------------------------------------------------------------------------
# 步骤 4: 安装 Python 依赖（venv 隔离）
#------------------------------------------------------------------------------
print_step "步骤 4/5: 安装 Python 依赖"

VENV_DIR="/opt/openclaw/venv"
if [ ! -d "$VENV_DIR" ]; then
    print_info "创建 Python 虚拟环境: $VENV_DIR"
    if command -v apt-get &> /dev/null; then
        sudo apt-get install -y python3-venv python3-full 2>/dev/null || true
    fi
    python3 -m venv "$VENV_DIR"
fi
# 确保 pip 可用
if [ ! -f "$VENV_DIR/bin/pip" ]; then
    print_info "安装 pip 到 venv..."
    "$VENV_DIR/bin/python" -m ensurepip --upgrade
fi
"$VENV_DIR/bin/python" -m pip install -r "$PROJECT_DIR/src/gateway/requirements.txt"
print_success "Python 依赖安装完成（venv: $VENV_DIR）"

#------------------------------------------------------------------------------
# 步骤 5: 创建目录 + 复制 dispatcher workspace
#------------------------------------------------------------------------------
print_step "步骤 5/5: 创建目录和配置"

sudo mkdir -p /opt/openclaw/shared-files
sudo mkdir -p /opt/openclaw/data/gateway
sudo mkdir -p /opt/openclaw/data/agents/{operation,product,development,testing,service}
sudo mkdir -p /opt/openclaw/logs/gateway
sudo chown -R $USER:$USER /opt/openclaw
chmod -R 755 /opt/openclaw

# 复制 dispatcher workspace
WORKSPACE_DIR="$HOME/.openclaw/workspace"
mkdir -p "$WORKSPACE_DIR"
if [ -d "$PROJECT_DIR/config/agents/workspace/dispatcher" ]; then
    cp -r "$PROJECT_DIR/config/agents/workspace/dispatcher/"* "$WORKSPACE_DIR/"
    print_success "Dispatcher workspace 已复制到 $WORKSPACE_DIR"
elif [ -f "$PROJECT_DIR/config/agents/workspace/dispatcher.md" ]; then
    cp "$PROJECT_DIR/config/agents/workspace/dispatcher.md" "$WORKSPACE_DIR/CLAUDE.md"
    print_success "Dispatcher CLAUDE.md 已复制到 $WORKSPACE_DIR"
fi

mkdir -p /tmp/openclaw
print_success "目录创建完成"

echo ""
print_success "宿主机 Gateway 依赖安装完成！"
echo ""
echo -e "${YELLOW}下一步：${NC}"
echo "  1. 配置环境变量: vi .env.prod"
echo "  2. 部署服务:     ./3-deploy-production.sh"
echo ""
