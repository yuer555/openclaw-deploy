#!/bin/bash
#==============================================================================
# 脚本名称: 3-deploy-production.sh
# 功能描述: 部署 OpenClaw 生产环境（构建镜像、创建目录）
# 使用方法: ./3-deploy-production.sh
# 执行位置: 服务器
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
    print_error "Docker 未安装！请先运行: ./1-prepare-server.sh"
    exit 1
fi
print_success "Docker: $(docker --version)"

if ! docker compose version &> /dev/null; then
    print_error "Docker Compose 未安装！"
    exit 1
fi
print_success "Docker Compose: $(docker compose version)"

#------------------------------------------------------------------------------
# 步骤 2: 配置环境变量
#------------------------------------------------------------------------------
print_step "步骤 2/4: 配置环境变量"

if [ ! -f ".env.prod" ]; then
    cp .env.prod.example .env.prod
    print_warning "已创建 .env.prod，请编辑后重新运行此脚本"
    print_info "运行: vi .env.prod"
    exit 1
fi
print_success ".env.prod 已存在"

source .env.prod
if [ -z "$OPENAI_API_KEY" ] && [ -z "$API_KEY" ]; then
    print_error "必须配置 OPENAI_API_KEY 或 API_KEY + API_BASE_URL"
    exit 1
fi
print_success "配置验证通过"

#------------------------------------------------------------------------------
# 步骤 3: 创建数据目录
#------------------------------------------------------------------------------
print_step "步骤 3/4: 创建数据目录"

sudo mkdir -p /opt/openclaw/data/gateway
sudo mkdir -p /opt/openclaw/data/agents/{operation,product,development,testing,service}
sudo mkdir -p /opt/openclaw/shared-files
sudo mkdir -p /opt/openclaw/logs/gateway
sudo chown -R $USER:$USER /opt/openclaw
chmod -R 755 /opt/openclaw
print_success "数据目录创建完成"

#------------------------------------------------------------------------------
# 步骤 4: 构建 Docker 镜像
#------------------------------------------------------------------------------
print_step "步骤 4/4: 构建 Docker 镜像"

print_info "构建 openclaw-base:latest..."
docker build \
    -f ../config/Dockerfile.base \
    -t openclaw-base:latest \
    ..
print_success "openclaw-base:latest 构建完成"

for ROLE in operation product development testing service; do
    print_info "构建 openclaw-agent-${ROLE}:prod ..."
    docker build --no-cache \
        -f ../config/Dockerfile.agents \
        --build-arg ROLE=${ROLE} \
        -t openclaw-agent-${ROLE}:prod \
        ..
    print_success "openclaw-agent-${ROLE}:prod 构建完成"
done

echo ""
print_success "部署准备完成！"
echo ""
docker images | grep "openclaw-"
echo ""
echo -e "${YELLOW}下一步：${NC}"
echo "  1. 安装宿主机依赖: ./setup-host-gateway.sh"
echo "  2. 编辑配置: vi .env.prod（启用 Agent，填入 Token/Key）"
echo "  3. 启动服务: ./5-start-production.sh"
echo ""
