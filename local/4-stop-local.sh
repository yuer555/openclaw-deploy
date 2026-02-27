#!/bin/bash
#==============================================================================
# 脚本名称: 4-stop-local.sh
# 功能描述: 停止本地测试服务（宿主机 gateway + agents）
# 使用方法: ./4-stop-local.sh
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

echo -e "${YELLOW}🛑 停止 OpenClaw 本地测试服务${NC}\n"

print_info "停止宿主机 Gateway..."
"$PROJECT_DIR/scripts/stop-gateway.sh" 2>/dev/null || true

print_info "停止虚拟员工容器..."
docker compose -f ../config/docker-compose.agents.yml --env-file .env.local down 2>/dev/null || true

print_success "所有服务已停止"
echo ""
echo -e "${YELLOW}提示：${NC}"
echo "  数据已保留在: ../data/"
echo "  共享文件在:   ../shared-files/"
echo "  重新启动:     ./2-start-local.sh"
echo "  完全清理:     ./5-clean-local.sh"
echo ""
