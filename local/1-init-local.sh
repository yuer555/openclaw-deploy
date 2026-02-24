#!/bin/bash
#==============================================================================
# 脚本名称: 1-init-local.sh
# 功能描述: 初始化本地测试环境
# 使用方法: ./1-init-local.sh
# 作者: OpenClaw Team
# 版本: V1.4
# 更新日期: 2026-02-24
#==============================================================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

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
║                                                               ║
║     ██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗      █████╗ ║
║    ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║     ██╔══██╗║
║    ██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║     ██║     ███████║║
║    ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║     ██║     ██╔══██║║
║    ╚██████╔╝██║     ███████╗██║ ╚████║╚██████╗███████╗██║  ██║║
║     ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝  ╚═╝║
║                                                               ║
║               本地测试环境 - 初始化脚本 V1.4                   ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

#------------------------------------------------------------------------------
# 步骤 1: 检查前置条件
#------------------------------------------------------------------------------
print_step "步骤 1/5: 检查前置条件"

# 检查 Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker 未安装！请先安装 Docker Desktop"
    print_info "下载地址: https://www.docker.com/products/docker-desktop"
    exit 1
fi
print_success "Docker 已安装: $(docker --version)"

# 检查 Docker 是否运行
if ! docker info &> /dev/null; then
    print_error "Docker 未运行！请启动 Docker Desktop"
    exit 1
fi
print_success "Docker 正在运行"

# 检查 Docker Compose
if ! docker compose version &> /dev/null; then
    print_error "Docker Compose 未安装！"
    exit 1
fi
print_success "Docker Compose 已安装: $(docker compose version)"

#------------------------------------------------------------------------------
# 步骤 2: 创建目录结构
#------------------------------------------------------------------------------
print_step "步骤 2/5: 创建目录结构"

# 创建必要的目录
mkdir -p ../data/local/{gateway,agents,database,logs}
mkdir -p ../config/{agents,nginx,ssl}
mkdir -p ../logs/local

print_success "目录结构创建完成"

#------------------------------------------------------------------------------
# 步骤 3: 创建环境变量文件
#------------------------------------------------------------------------------
print_step "步骤 3/5: 创建环境变量文件"

# 检查是否已存在 .env.local
if [ -f ".env.local" ]; then
    print_warning ".env.local 已存在，跳过创建"
else
    # 从模板复制
    if [ -f ".env.local.example" ]; then
        cp .env.local.example .env.local
        print_success ".env.local 创建成功"
        print_warning "请编辑 .env.local 文件，填入必要的配置（如 API Key）"
    else
        print_warning ".env.local.example 不存在，将创建默认配置"
        
        # 创建默认的 .env.local
        cat > .env.local << 'ENVEOF'
# OpenClaw 本地测试环境变量

# 基础配置
OPENCLAW_ENV=local
OPENCLAW_PORT=3000

# AI 模型配置（必填）
# 选项1: GitHub Copilot（推荐）
GITHUB_TOKEN=your_github_token_here

# 选项2: OpenAI
# OPENAI_API_KEY=your_openai_api_key_here

# 数据库配置
DATABASE_URL=sqlite:///data/local/openclaw.db

# 日志配置
LOG_LEVEL=debug
LOG_DIR=/data/local/logs

# 虚拟员工配置
AGENTS_ENABLED=dispatcher,operation,product,development,testing,service

# 安全配置
SECRET_KEY=local-secret-key-change-me-in-production
ENVEOF

        print_success "默认 .env.local 创建成功"
        print_warning "⚠️  重要：请编辑 .env.local 文件，填入你的 API Key！"
    fi
fi

#------------------------------------------------------------------------------
# 步骤 4: 检查配置文件
#------------------------------------------------------------------------------
print_step "步骤 4/5: 检查配置文件"

# 检查 Docker Compose 配置
if [ ! -f "docker-compose.local.yml" ]; then
    print_error "docker-compose.local.yml 不存在！"
    exit 1
fi
print_success "docker-compose.local.yml 配置正常"

# 检查虚拟员工配置
if [ ! -d "../config/agents" ]; then
    print_warning "虚拟员工配置目录不存在，将创建默认配置"
    mkdir -p ../config/agents
fi
print_success "配置文件检查完成"

#------------------------------------------------------------------------------
# 步骤 5: 显示下一步操作
#------------------------------------------------------------------------------
print_step "步骤 5/5: 初始化完成"

print_success "本地测试环境初始化成功！\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📋 下一步操作：${NC}\n"
echo -e "${YELLOW}1. 编辑配置文件（重要！）：${NC}"
echo -e "   vi .env.local"
echo -e "   ${BLUE}# 填入你的 GitHub Token 或 OpenAI API Key${NC}\n"

echo -e "${YELLOW}2. 启动本地服务：${NC}"
echo -e "   ./2-start-local.sh\n"

echo -e "${YELLOW}3. 测试服务：${NC}"
echo -e "   ./3-test-local.sh\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

print_info "如需帮助，请查看: ../docs/01-本地测试指南.md"
print_info "或访问: https://docs.openclaw.ai"

echo ""
