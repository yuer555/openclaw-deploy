#!/bin/bash
#==============================================================================
# 脚本名称: 5-start-production.sh
# 功能描述: 启动 OpenClaw 生产服务
# 使用方法: ./5-start-production.sh
# 执行位置: 🚀 服务器
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

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║            OpenClaw 生产服务启动脚本 V1.4                     ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

#------------------------------------------------------------------------------
# 步骤 1: 检查前置条件
#------------------------------------------------------------------------------
print_step "步骤 1/5: 检查前置条件"

# 检查配置文件
if [ ! -f ".env.prod" ]; then
    print_error ".env.prod 不存在！请先运行: ./3-deploy-production.sh"
    exit 1
fi
print_success "环境配置存在"

if [ ! -f "docker-compose.prod.yml" ]; then
    print_error "docker-compose.prod.yml 不存在！"
    exit 1
fi
print_success "Docker Compose 配置存在"

#------------------------------------------------------------------------------
# 步骤 2: 停止已有服务
#------------------------------------------------------------------------------
print_step "步骤 2/5: 停止已有服务"

if docker ps | grep -q "openclaw-prod"; then
    print_warning "发现运行中的服务，正在停止..."
    docker compose -f docker-compose.prod.yml --env-file .env.prod down
    print_success "已有服务已停止"
else
    print_info "没有运行中的服务"
fi

#------------------------------------------------------------------------------
# 步骤 3: 启动服务
#------------------------------------------------------------------------------
print_step "步骤 3/5: 启动服务"

print_info "正在启动容器..."
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d

# 等待服务启动
print_info "等待服务启动（15秒）..."
sleep 15

#------------------------------------------------------------------------------
# 步骤 4: 检查服务状态
#------------------------------------------------------------------------------
print_step "步骤 4/5: 检查服务状态"

# 检查容器状态
print_info "检查容器状态..."
if docker ps | grep -q "openclaw-prod"; then
    print_success "容器正在运行"
    docker ps | grep openclaw
else
    print_error "容器启动失败！"
    print_info "查看日志:"
    docker compose -f docker-compose.prod.yml --env-file .env.prod logs --tail=50
    exit 1
fi

#------------------------------------------------------------------------------
# 步骤 5: 显示服务信息
#------------------------------------------------------------------------------
print_step "步骤 5/5: 服务信息"

# 获取服务 URL
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "获取失败")

echo -e "${YELLOW}📊 服务状态：${NC}"
docker compose -f docker-compose.prod.yml --env-file .env.prod ps

echo -e "\n${YELLOW}🌐 访问信息：${NC}"
if [ -f "/opt/openclaw/config/ssl/fullchain.pem" ]; then
    # 从配置文件获取域名
    DOMAIN=$(openssl x509 -noout -subject -in /opt/openclaw/config/ssl/fullchain.pem 2>/dev/null | sed -n 's/.*CN = \(.*\)/\1/p')
    echo -e "   HTTPS: ${BLUE}https://${DOMAIN}${NC}"
else
    echo -e "   HTTP: ${BLUE}http://${SERVER_IP}:80${NC}"
    echo -e "   ${YELLOW}(未配置 SSL，建议运行 ./4-setup-ssl.sh)${NC}"
fi

#==============================================================================
# 完成总结
#==============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 服务启动成功！${NC}\n"

echo -e "${YELLOW}📋 常用命令：${NC}\n"
echo -e "${YELLOW}查看日志：${NC}"
echo -e "   ${BLUE}docker logs openclaw-production -f${NC}"
echo -e "   ${BLUE}docker logs openclaw-nginx -f${NC}\n"

echo -e "${YELLOW}重启服务：${NC}"
echo -e "   ${BLUE}docker compose -f docker-compose.prod.yml restart${NC}\n"

echo -e "${YELLOW}停止服务：${NC}"
echo -e "   ${BLUE}docker compose -f docker-compose.prod.yml down${NC}\n"

echo -e "${YELLOW}健康检查：${NC}"
echo -e "   ${BLUE}./6-health-check.sh${NC}\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

print_info "服务正在后台运行，可以开始使用了！"
echo ""
