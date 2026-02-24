#!/bin/bash
#==============================================================================
# 脚本名称: 4-setup-ssl.sh
# 功能描述: 配置 SSL 证书（Let's Encrypt）
# 使用方法: ./4-setup-ssl.sh
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
║              SSL 证书配置脚本 (Let's Encrypt)                 ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

print_warning "⚠️  配置 SSL 证书需要："
print_warning "  1. 域名已解析到本服务器"
print_warning "  2. 端口 80 和 443 已开放"
print_warning "  3. 有效的邮箱地址"
echo ""

read -p "确认继续配置 SSL？(输入 yes): " confirm
if [ "$confirm" != "yes" ]; then
    print_info "已取消"
    exit 0
fi

#------------------------------------------------------------------------------
# 步骤 1: 安装 Certbot
#------------------------------------------------------------------------------
print_step "步骤 1/5: 安装 Certbot"

if command -v certbot &> /dev/null; then
    print_success "Certbot 已安装"
else
    print_info "安装 Certbot..."
    sudo apt-get update
    sudo apt-get install -y certbot python3-certbot-nginx
    print_success "Certbot 安装完成"
fi

#------------------------------------------------------------------------------
# 步骤 2: 获取域名和邮箱
#------------------------------------------------------------------------------
print_step "步骤 2/5: 配置域名和邮箱"

read -p "输入你的域名（例如: openclaw.yourdomain.com）: " DOMAIN
if [ -z "$DOMAIN" ]; then
    print_error "域名不能为空！"
    exit 1
fi

read -p "输入你的邮箱（用于证书通知）: " EMAIL
if [ -z "$EMAIL" ]; then
    print_error "邮箱不能为空！"
    exit 1
fi

print_info "域名: $DOMAIN"
print_info "邮箱: $EMAIL"

#------------------------------------------------------------------------------
# 步骤 3: 验证域名解析
#------------------------------------------------------------------------------
print_step "步骤 3/5: 验证域名解析"

print_info "检查域名解析..."
SERVER_IP=$(curl -s ifconfig.me)
DOMAIN_IP=$(dig +short $DOMAIN | tail -n1)

print_info "服务器 IP: $SERVER_IP"
print_info "域名解析 IP: $DOMAIN_IP"

if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
    print_warning "⚠️  域名解析 IP 与服务器 IP 不一致！"
    print_warning "请确认域名已正确解析到本服务器"
    
    read -p "是否仍然继续？(输入 yes): " force_continue
    if [ "$force_continue" != "yes" ]; then
        print_info "已取消"
        exit 1
    fi
else
    print_success "域名解析正确"
fi

#------------------------------------------------------------------------------
# 步骤 4: 申请证书
#------------------------------------------------------------------------------
print_step "步骤 4/5: 申请 SSL 证书"

print_info "使用 Certbot 申请证书..."
print_warning "此过程需要停止 80 端口上的服务"

# 停止可能占用 80 端口的服务
sudo systemctl stop nginx 2>/dev/null || true
docker stop openclaw-nginx 2>/dev/null || true

# 申请证书（standalone 模式）
sudo certbot certonly --standalone \
    --non-interactive \
    --agree-tos \
    --email $EMAIL \
    -d $DOMAIN

if [ $? -eq 0 ]; then
    print_success "SSL 证书申请成功！"
else
    print_error "SSL 证书申请失败！"
    exit 1
fi

#------------------------------------------------------------------------------
# 步骤 5: 配置证书自动更新
#------------------------------------------------------------------------------
print_step "步骤 5/5: 配置证书自动更新"

print_info "配置 Certbot 自动更新..."

# 测试自动更新
sudo certbot renew --dry-run

if [ $? -eq 0 ]; then
    print_success "证书自动更新配置成功"
else
    print_warning "证书自动更新测试失败，请手动配置"
fi

# 复制证书到项目目录
print_info "复制证书到项目目录..."
sudo mkdir -p /opt/openclaw/config/ssl
sudo cp /etc/letsencrypt/live/$DOMAIN/fullchain.pem /opt/openclaw/config/ssl/
sudo cp /etc/letsencrypt/live/$DOMAIN/privkey.pem /opt/openclaw/config/ssl/
sudo chown $USER:$USER /opt/openclaw/config/ssl/*

print_success "证书已复制到 /opt/openclaw/config/ssl/"

#==============================================================================
# 完成总结
#==============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 SSL 证书配置完成！${NC}\n"

echo -e "${YELLOW}📋 证书信息：${NC}"
echo -e "   域名: ${BLUE}$DOMAIN${NC}"
echo -e "   证书路径: ${BLUE}/etc/letsencrypt/live/$DOMAIN/${NC}"
echo -e "   项目路径: ${BLUE}/opt/openclaw/config/ssl/${NC}\n"

echo -e "${YELLOW}📋 下一步操作：${NC}\n"
echo -e "${YELLOW}1. 启动生产服务：${NC}"
echo -e "   ${BLUE}./5-start-production.sh${NC}\n"

echo -e "${YELLOW}2. 证书将在 90 天后过期，Certbot 会自动更新${NC}\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
