#!/bin/bash
#==============================================================================
# 脚本名称: 4-stop-local.sh
# 功能描述: 停止本地测试服务
# 使用方法: ./4-stop-local.sh
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

#==============================================================================
# 主流程
#==============================================================================

echo -e "${YELLOW}🛑 停止 OpenClaw 本地测试服务${NC}\n"

# 检查配置文件
if [ ! -f "docker-compose.local.yml" ]; then
    print_error "docker-compose.local.yml 不存在！"
    exit 1
fi

if [ ! -f ".env.local" ]; then
    print_error ".env.local 不存在！"
    exit 1
fi

# 检查是否有运行中的容器
if ! docker ps | grep -q "openclaw-local"; then
    print_warning "没有运行中的 OpenClaw 容器"
    exit 0
fi

# 停止容器
print_info "正在停止容器..."
docker compose -f docker-compose.local.yml --env-file .env.local down

# 确认停止
sleep 2
if docker ps | grep -q "openclaw-local"; then
    print_error "容器停止失败"
    exit 1
else
    print_success "容器已停止"
fi

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ 服务已成功停止${NC}\n"

echo -e "${YELLOW}💡 提示：${NC}"
echo -e "   • 数据已保留在: ${BLUE}../data/local/${NC}"
echo -e "   • 重新启动: ${BLUE}./2-start-local.sh${NC}"
echo -e "   • 完全清理（删除数据）: ${BLUE}./5-clean-local.sh${NC}\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
