#!/bin/bash
#==============================================================================
# 脚本名称: 1-init-local.sh
# 功能描述: 初始化本地测试环境
# 使用方法: ./1-init-local.sh
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
cd "$SCRIPT_DIR"

#------------------------------------------------------------------------------
# 步骤 1: 检查前置条件
#------------------------------------------------------------------------------
print_step "步骤 1/4: 检查前置条件"

if ! command -v docker &> /dev/null; then
    print_error "Docker 未安装！请先安装 Docker Desktop"
    exit 1
fi
print_success "Docker 已安装: $(docker --version)"

if ! docker info &> /dev/null; then
    print_error "Docker 未运行！请启动 Docker Desktop"
    exit 1
fi
print_success "Docker 正在运行"

if ! docker compose version &> /dev/null; then
    print_error "Docker Compose 未安装！"
    exit 1
fi
print_success "Docker Compose 已安装"

#------------------------------------------------------------------------------
# 步骤 2: 检查端口占用
#------------------------------------------------------------------------------
print_step "步骤 2/4: 检查端口占用"

PORTS=(8000 18791 18792 18793 18794 18795)
PORT_CONFLICT=0

for PORT in "${PORTS[@]}"; do
    if lsof -i ":${PORT}" &> /dev/null; then
        print_warning "端口 ${PORT} 已被占用"
        PORT_CONFLICT=1
    else
        print_success "端口 ${PORT} 可用"
    fi
done

if [ "$PORT_CONFLICT" -eq 1 ]; then
    print_warning "存在端口冲突，请先释放上述端口再继续"
    read -p "是否继续？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

#------------------------------------------------------------------------------
# 步骤 3: 创建目录结构
#------------------------------------------------------------------------------
print_step "步骤 3/4: 创建目录结构"

mkdir -p ../data/gateway
mkdir -p ../data/agents/operation
mkdir -p ../data/agents/product
mkdir -p ../data/agents/development
mkdir -p ../data/agents/testing
mkdir -p ../data/agents/service
mkdir -p ../shared-files
mkdir -p ../logs/gateway

print_success "目录结构创建完成"

#------------------------------------------------------------------------------
# 步骤 4: 创建环境变量文件
#------------------------------------------------------------------------------
print_step "步骤 4/4: 创建环境变量文件"

if [ -f ".env.local" ]; then
    print_warning ".env.local 已存在，跳过创建"
else
    if [ -f ".env.local.example" ]; then
        cp .env.local.example .env.local
        print_success ".env.local 创建成功"
        print_warning "请编辑 .env.local，配置 API 和启用的 Agent"
    else
        print_error ".env.local.example 不存在！"
        exit 1
    fi
fi

echo ""
print_success "初始化完成！"
echo ""
echo -e "${YELLOW}下一步：${NC}"
echo "  1. 编辑配置：vi .env.local（设置 API_KEY，启用 Agent）"
echo "  2. 构建镜像：./0-build-images.sh（首次或代码变更后）"
echo "  3. 启动服务：./2-start-local.sh"
echo ""
