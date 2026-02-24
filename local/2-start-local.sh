#!/bin/bash
#==============================================================================
# 脚本名称: 2-start-local.sh
# 功能描述: 启动本地测试服务
# 使用方法: ./2-start-local.sh
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
print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📍 $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

#==============================================================================
# 主流程
#==============================================================================

echo -e "${GREEN}🚀 启动 OpenClaw 本地测试服务${NC}\n"

#------------------------------------------------------------------------------
# 步骤 1: 检查初始化
#------------------------------------------------------------------------------
print_step "步骤 1/4: 检查初始化状态"

if [ ! -f ".env.local" ]; then
    print_error ".env.local 不存在！请先运行: ./1-init-local.sh"
    exit 1
fi
print_success "环境变量文件存在"

if [ ! -f "docker-compose.local.yml" ]; then
    print_error "docker-compose.local.yml 不存在！"
    exit 1
fi
print_success "Docker Compose 配置存在"

#------------------------------------------------------------------------------
# 步骤 2: 停止已有容器
#------------------------------------------------------------------------------
print_step "步骤 2/4: 停止已有容器"

if docker ps -a | grep -q "openclaw-local"; then
    print_info "发现已有容器，正在停止..."
    docker compose -f docker-compose.local.yml --env-file .env.local down
    print_success "已有容器已停止"
else
    print_info "没有运行中的容器"
fi

#------------------------------------------------------------------------------
# 步骤 3: 拉取镜像
#------------------------------------------------------------------------------
print_step "步骤 3/4: 拉取 Docker 镜像"

print_info "拉取最新镜像（可能需要几分钟）..."
docker compose -f docker-compose.local.yml --env-file .env.local pull || true
print_success "镜像准备完成"

#------------------------------------------------------------------------------
# 步骤 4: 启动服务
#------------------------------------------------------------------------------
print_step "步骤 4/4: 启动服务"

print_info "正在启动容器..."
docker compose -f docker-compose.local.yml --env-file .env.local up -d

# 等待服务启动
sleep 3

# 检查容器状态
if docker ps | grep -q "openclaw-local"; then
    print_success "服务启动成功！"
else
    print_error "服务启动失败，请查看日志"
    docker compose -f docker-compose.local.yml --env-file .env.local logs --tail=50
    exit 1
fi

#==============================================================================
# 显示服务信息
#==============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 服务启动成功！${NC}\n"

echo -e "${YELLOW}📋 服务信息：${NC}"
echo -e "   访问地址: ${BLUE}http://localhost:3000${NC}"
echo -e "   容器名称: ${BLUE}openclaw-local${NC}"
echo -e "   数据目录: ${BLUE}../data/local/${NC}"
echo -e "   日志目录: ${BLUE}../logs/local/${NC}\n"

echo -e "${YELLOW}📊 查看日志：${NC}"
echo -e "   docker logs openclaw-local -f\n"

echo -e "${YELLOW}🧪 运行测试：${NC}"
echo -e "   ./3-test-local.sh\n"

echo -e "${YELLOW}🛑 停止服务：${NC}"
echo -e "   ./4-stop-local.sh\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

print_info "服务正在后台运行，可以开始测试了！"
echo ""
