#!/bin/bash
#==============================================================================
# 脚本名称: 5-start-production.sh
# 功能描述: 启动生产服务（gateway + 5 个 agent 容器）
# 使用方法: ./5-start-production.sh
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
cd "$SCRIPT_DIR"

if [ ! -f ".env.prod" ]; then
    print_error ".env.prod 不存在！请先运行: ./3-deploy-production.sh"
    exit 1
fi

#------------------------------------------------------------------------------
# 步骤 1: 停止已有服务
#------------------------------------------------------------------------------
print_step "步骤 1/3: 停止已有服务"

docker compose -f docker-compose.prod.yml --env-file .env.prod down 2>/dev/null || true
print_success "已有服务已停止"

#------------------------------------------------------------------------------
# 步骤 2: 启动所有容器
#------------------------------------------------------------------------------
print_step "步骤 2/3: 启动所有容器"

print_info "启动容器..."
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d
print_success "容器已启动"

#------------------------------------------------------------------------------
# 步骤 3: 等待健康检查
#------------------------------------------------------------------------------
print_step "步骤 3/3: 等待健康检查"

print_info "等待 Gateway 就绪（最多 90 秒）..."
for i in $(seq 1 18); do
    if curl -sf http://localhost:8000/health > /dev/null 2>&1; then
        print_success "Gateway 健康检查通过"
        break
    fi
    if [ "$i" -eq 18 ]; then
        print_warning "Gateway 健康检查超时，请查看日志"
    fi
    sleep 5
done

echo ""
docker compose -f docker-compose.prod.yml --env-file .env.prod ps
echo ""
print_success "服务启动完成！"
echo ""
echo -e "${YELLOW}访问地址：${NC}"
echo "  Gateway: http://$(hostname -I | awk '{print $1}'):8000"
echo ""
echo -e "${YELLOW}常用命令：${NC}"
echo "  查看日志:  docker logs openclaw-gateway -f"
echo "  健康检查:  ./6-health-check.sh"
echo "  停止服务:  docker compose -f docker-compose.prod.yml down"
echo ""
