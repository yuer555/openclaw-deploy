#!/bin/bash
#==============================================================================
# 脚本名称: 2-start-local.sh
# 功能描述: 启动本地测试服务（gateway + 5 个 agent 容器）
# 使用方法: ./2-start-local.sh
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
cd "$SCRIPT_DIR"

#------------------------------------------------------------------------------
# 步骤 1: 检查初始化
#------------------------------------------------------------------------------
print_step "步骤 1/4: 检查初始化状态"

if [ ! -f ".env.local" ]; then
    print_error ".env.local 不存在！请先运行: ./1-init-local.sh"
    exit 1
fi
print_success "环境变量文件存在"

# 检查镜像是否已构建
if ! docker image inspect openclaw-gateway:local &> /dev/null; then
    print_warning "镜像 openclaw-gateway:local 不存在，请先运行: ./0-build-images.sh"
    exit 1
fi
print_success "Gateway 镜像已就绪"

#------------------------------------------------------------------------------
# 步骤 2: 确保 Docker 网络存在
#------------------------------------------------------------------------------
print_step "步骤 2/4: 准备 Docker 网络"

if ! docker network inspect openclaw-network &> /dev/null; then
    docker network create openclaw-network
    print_success "openclaw-network 网络已创建"
else
    print_success "openclaw-network 网络已存在"
fi

#------------------------------------------------------------------------------
# 步骤 3: 启动 agent 容器
#------------------------------------------------------------------------------
print_step "步骤 3/4: 启动虚拟员工容器"

docker compose -f ../config/docker-compose.agents.yml --env-file .env.local up -d
print_success "虚拟员工容器已启动"

#------------------------------------------------------------------------------
# 步骤 4: 启动 gateway 容器
#------------------------------------------------------------------------------
print_step "步骤 4/4: 启动 Gateway 容器"

docker compose -f docker-compose.local.yml --env-file .env.local up -d
print_success "Gateway 容器已启动"

# 等待健康检查
print_info "等待容器就绪（最多 60 秒）..."
for i in $(seq 1 12); do
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        print_success "Gateway 健康检查通过"
        break
    fi
    if [ "$i" -eq 12 ]; then
        print_warning "Gateway 健康检查超时，请查看日志: docker logs openclaw-gateway"
    fi
    sleep 5
done

echo ""
print_success "服务启动完成！"
echo ""
echo -e "${YELLOW}服务地址：${NC}"
echo "  Gateway:     http://localhost:8000"
echo "  Operation:   http://localhost:18791"
echo "  Product:     http://localhost:18792"
echo "  Development: http://localhost:18793"
echo "  Testing:     http://localhost:18794"
echo "  Service:     http://localhost:18795"
echo ""
echo -e "${YELLOW}常用命令：${NC}"
echo "  查看日志:  docker logs openclaw-gateway -f"
echo "  运行测试:  ./3-test-local.sh"
echo "  停止服务:  ./4-stop-local.sh"
echo ""
