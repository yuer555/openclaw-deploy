#!/bin/bash
#==============================================================================
# 脚本名称: 5-clean-local.sh
# 功能描述: 清理本地测试环境（删除容器和数据）
# 使用方法: ./5-clean-local.sh
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

echo -e "${RED}🧹 清理 OpenClaw 本地测试环境${NC}\n"

print_warning "⚠️  警告：此操作将删除所有本地测试数据！"
print_warning "⚠️  包括：容器、镜像、数据目录、日志等"
echo ""

# 询问确认
read -p "确认清理？(输入 yes 继续): " confirm

if [ "$confirm" != "yes" ]; then
    print_info "已取消清理"
    exit 0
fi

echo ""

#------------------------------------------------------------------------------
# 1. 停止并删除容器
#------------------------------------------------------------------------------
print_info "停止并删除容器..."

if [ -f "docker-compose.local.yml" ] && [ -f ".env.local" ]; then
    docker compose -f docker-compose.local.yml --env-file .env.local down -v || true
fi

# 强制删除相关容器
docker ps -a | grep "openclaw-local" | awk '{print $1}' | xargs -r docker rm -f || true

print_success "容器已删除"

#------------------------------------------------------------------------------
# 2. 删除镜像（可选）
#------------------------------------------------------------------------------
read -p "是否删除 Docker 镜像？(输入 yes 删除): " delete_images

if [ "$delete_images" == "yes" ]; then
    print_info "删除 Docker 镜像..."
    docker images | grep "openclaw" | awk '{print $3}' | xargs -r docker rmi -f || true
    print_success "镜像已删除"
fi

#------------------------------------------------------------------------------
# 3. 删除数据目录
#------------------------------------------------------------------------------
print_info "删除数据目录..."

if [ -d "../data/local" ]; then
    rm -rf ../data/local
    print_success "数据目录已删除: ../data/local"
fi

if [ -d "../logs/local" ]; then
    rm -rf ../logs/local
    print_success "日志目录已删除: ../logs/local"
fi

#------------------------------------------------------------------------------
# 4. 删除环境配置（可选）
#------------------------------------------------------------------------------
read -p "是否删除 .env.local 配置文件？(输入 yes 删除): " delete_env

if [ "$delete_env" == "yes" ]; then
    if [ -f ".env.local" ]; then
        rm .env.local
        print_success ".env.local 已删除"
    fi
fi

#==============================================================================
# 清理总结
#==============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ 清理完成${NC}\n"

echo -e "${YELLOW}💡 下一步：${NC}"
echo -e "   重新开始测试: ${BLUE}./1-init-local.sh${NC}\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
