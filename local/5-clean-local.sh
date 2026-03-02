#!/bin/bash
#==============================================================================
# 脚本名称: 5-clean-local.sh
# 功能描述: 清理本地测试环境（容器、镜像、数据）
# 使用方法: ./5-clean-local.sh
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

echo -e "${RED}🧹 清理 OpenClaw 本地测试环境${NC}\n"
print_warning "此操作将删除容器、镜像和数据目录！"
echo ""
read -p "确认清理？(输入 yes 继续): " confirm
[ "$confirm" != "yes" ] && { print_info "已取消"; exit 0; }
echo ""

# 停止宿主机 Gateway
print_info "停止宿主机 Gateway..."
"$PROJECT_DIR/scripts/stop-gateway.sh" 2>/dev/null || true
print_success "Gateway 已停止"

# 停止并删除 Agent 容器
print_info "停止并删除 Agent 容器..."
docker compose -f ../config/docker-compose.agents.yml --env-file .env.local down -v 2>/dev/null || true
# 强制删除可能的残留容器
docker ps -a --format '{{.Names}}' | grep "^openclaw-agent-" | xargs -r docker rm -f 2>/dev/null || true
print_success "容器已删除"

# 删除 Docker 网络
docker network rm openclaw-network 2>/dev/null || true
print_success "Docker 网络已删除"

# 删除镜像
read -p "是否删除 Docker 镜像？(输入 yes 删除): " delete_images
if [ "$delete_images" == "yes" ]; then
    docker images | grep "openclaw-" | awk '{print $3}' | xargs -r docker rmi -f || true
    print_success "镜像已删除"
fi

# 删除数据目录
print_info "删除数据目录..."
rm -rf ../data/gateway ../data/agents
print_success "数据目录已删除"

# 删除 .env.local（可选）
read -p "是否删除 .env.local？(输入 yes 删除): " delete_env
if [ "$delete_env" == "yes" ]; then
    rm -f .env.local
    print_success ".env.local 已删除"
fi

echo ""
print_success "清理完成！重新开始：./1-init-local.sh"
echo ""
