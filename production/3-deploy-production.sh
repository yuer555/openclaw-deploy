#!/bin/bash
#==============================================================================
# 脚本名称: 3-deploy-production.sh
# 功能描述: 部署 OpenClaw 生产环境
# 使用方法: ./3-deploy-production.sh
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
║              OpenClaw 生产环境部署脚本 V1.4                   ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

#------------------------------------------------------------------------------
# 步骤 1: 检查前置条件
#------------------------------------------------------------------------------
print_step "步骤 1/7: 检查前置条件"

# 检查 Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker 未安装！请先运行: ./1-prepare-server.sh"
    exit 1
fi
print_success "Docker 已安装"

# 检查 Docker Compose
if ! docker compose version &> /dev/null; then
    print_error "Docker Compose 未安装！"
    exit 1
fi
print_success "Docker Compose 已安装"

# 检查当前目录
if [ ! -f "3-deploy-production.sh" ]; then
    print_error "请在 production/ 目录下运行此脚本"
    exit 1
fi

#------------------------------------------------------------------------------
# 步骤 2: 配置环境变量
#------------------------------------------------------------------------------
print_step "步骤 2/7: 配置环境变量"

if [ ! -f ".env.prod" ]; then
    if [ -f ".env.prod.example" ]; then
        print_info "创建 .env.prod 配置文件..."
        cp .env.prod.example .env.prod
        print_warning "⚠️  重要：请立即编辑 .env.prod 文件，填入必要的配置！"
        print_info "运行: vi .env.prod"
        
        read -p "是否现在编辑配置文件？(输入 yes): " edit_now
        if [ "$edit_now" == "yes" ]; then
            vi .env.prod
        else
            print_warning "请稍后手动编辑 .env.prod 文件"
        fi
    else
        print_error ".env.prod.example 不存在！"
        exit 1
    fi
else
    print_success ".env.prod 已存在"
fi

# 验证必要的环境变量
print_info "验证配置文件..."
source .env.prod

if [ -z "$GITHUB_TOKEN" ] && [ -z "$OPENAI_API_KEY" ]; then
    print_error "必须配置 GITHUB_TOKEN 或 OPENAI_API_KEY"
    exit 1
fi
print_success "配置验证通过"

#------------------------------------------------------------------------------
# 步骤 3: 创建数据目录
#------------------------------------------------------------------------------
print_step "步骤 3/7: 创建数据目录"

print_info "创建必要的目录..."
sudo mkdir -p /opt/openclaw/{data,logs,backups,config}
sudo mkdir -p /opt/openclaw/data/{gateway,agents,database}
sudo mkdir -p /opt/openclaw/logs/{gateway,agents,nginx}
sudo mkdir -p /opt/openclaw/config/{agents,nginx,ssl}

# 设置权限
sudo chown -R $USER:$USER /opt/openclaw
chmod -R 755 /opt/openclaw

print_success "目录创建完成"

#------------------------------------------------------------------------------
# 步骤 4: 复制配置文件
#------------------------------------------------------------------------------
print_step "步骤 4/7: 复制配置文件"

print_info "复制虚拟员工配置..."
if [ -d "../config/agents" ]; then
    cp -r ../config/agents/* /opt/openclaw/config/agents/
    print_success "虚拟员工配置已复制"
else
    print_warning "虚拟员工配置目录不存在，将使用默认配置"
fi

# 复制 Nginx 配置（如果存在）
if [ -d "../config/nginx" ]; then
    cp -r ../config/nginx/* /opt/openclaw/config/nginx/ 2>/dev/null || true
fi

print_success "配置文件复制完成"

#------------------------------------------------------------------------------
# 步骤 5: 检查 Docker Compose 配置
#------------------------------------------------------------------------------
print_step "步骤 5/7: 检查 Docker Compose 配置"

if [ ! -f "docker-compose.prod.yml" ]; then
    print_error "docker-compose.prod.yml 不存在！"
    exit 1
fi
print_success "Docker Compose 配置存在"

# 验证配置文件语法
print_info "验证配置文件语法..."
if docker compose -f docker-compose.prod.yml config > /dev/null 2>&1; then
    print_success "配置文件语法正确"
else
    print_error "配置文件语法错误！"
    docker compose -f docker-compose.prod.yml config
    exit 1
fi

#------------------------------------------------------------------------------
# 步骤 6: 拉取 Docker 镜像
#------------------------------------------------------------------------------
print_step "步骤 6/7: 拉取 Docker 镜像"

print_info "拉取最新镜像（可能需要几分钟）..."
docker compose -f docker-compose.prod.yml --env-file .env.prod pull

print_success "镜像拉取完成"

#------------------------------------------------------------------------------
# 步骤 7: 生成部署报告
#------------------------------------------------------------------------------
print_step "步骤 7/7: 生成部署报告"

cat > /opt/openclaw/DEPLOYMENT_INFO.txt << EOFINFO
OpenClaw 生产环境部署信息
========================================
部署时间: $(date '+%Y-%m-%d %H:%M:%S')
部署用户: $USER
服务器: $(hostname)
系统: $(lsb_release -d | cut -f2)
Docker: $(docker --version)

配置文件:
  - Docker Compose: docker-compose.prod.yml
  - 环境变量: .env.prod
  - 数据目录: /opt/openclaw/data
  - 日志目录: /opt/openclaw/logs

下一步:
  1. 配置 SSL 证书: ./4-setup-ssl.sh
  2. 启动服务: ./5-start-production.sh
  3. 健康检查: ./6-health-check.sh
EOFINFO

print_success "部署报告已生成: /opt/openclaw/DEPLOYMENT_INFO.txt"

#==============================================================================
# 完成总结
#==============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 部署准备完成！${NC}\n"

echo -e "${YELLOW}📋 下一步操作：${NC}\n"
echo -e "${YELLOW}1. 配置 SSL 证书（如有域名）：${NC}"
echo -e "   ${BLUE}./4-setup-ssl.sh${NC}\n"

echo -e "${YELLOW}2. 或直接启动服务（测试环境）：${NC}"
echo -e "   ${BLUE}./5-start-production.sh${NC}\n"

echo -e "${YELLOW}3. 查看部署信息：${NC}"
echo -e "   ${BLUE}cat /opt/openclaw/DEPLOYMENT_INFO.txt${NC}\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

print_info "详细文档: ../docs/02-生产部署指南.md"
echo ""
