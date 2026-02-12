#!/bin/bash
# scripts/init_server.sh - 服务器初始化脚本

set -e

echo "=== OpenClaw 服务器初始化 ==="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 root 或 sudo 运行此脚本"
    exit 1
fi

# 1. 检测操作系统
echo "【1】检测操作系统..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    echo "操作系统: $OS $VERSION"
else
    echo "✗ 无法检测操作系统"
    exit 1
fi

# 2. 更新系统包
echo ""
echo "【2】更新系统包..."
case $OS in
    ubuntu|debian)
        apt update && apt upgrade -y
        apt install -y curl wget git vim net-tools
        ;;
    centos|rhel)
        yum update -y
        yum install -y curl wget git vim net-tools
        ;;
    *)
        echo "⚠ 未识别的操作系统，跳过包更新"
        ;;
esac

# 3. 安装 Docker
echo ""
echo "【3】安装 Docker..."
if command -v docker &> /dev/null; then
    echo "✓ Docker 已安装: $(docker --version)"
else
    echo "正在安装 Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo "✓ Docker 安装完成"
fi

# 4. 安装 Docker Compose
echo ""
echo "【4】安装 Docker Compose..."
if command -v docker-compose &> /dev/null; then
    echo "✓ Docker Compose 已安装: $(docker-compose --version)"
else
    echo "正在安装 Docker Compose..."
    COMPOSE_VERSION="2.24.5"
    curl -L "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo "✓ Docker Compose 安装完成"
fi

# 5. 配置防火墙
echo ""
echo "【5】配置防火墙..."
read -p "是否配置防火墙？(y/n): " setup_firewall

if [ "$setup_firewall" == "y" ]; then
    case $OS in
        ubuntu|debian)
            apt install -y ufw
            ufw --force enable
            ufw default deny incoming
            ufw default allow outgoing
            ufw allow 22/tcp comment 'SSH'
            ufw allow 80/tcp comment 'HTTP'
            ufw allow 443/tcp comment 'HTTPS'
            ufw status
            echo "✓ UFW 防火墙已配置"
            ;;
        centos|rhel)
            systemctl enable firewalld
            systemctl start firewalld
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --permanent --add-service=http
            firewall-cmd --permanent --add-service=https
            firewall-cmd --reload
            echo "✓ Firewalld 防火墙已配置"
            ;;
    esac
fi

# 6. 创建工作目录
echo ""
echo "【6】创建工作目录..."
WORK_DIR="/opt/openclaw"
mkdir -p $WORK_DIR/{config,agents,data,logs,workspace,backups}
mkdir -p $WORK_DIR/config/{nginx,ssl}
mkdir -p $WORK_DIR/agents/{dispatcher,operation,product,development,testing,service}
mkdir -p $WORK_DIR/logs/{nginx,wecom}
mkdir -p $WORK_DIR/workspace/{projects,testing,service,knowledge_base}

echo "✓ 目录结构创建完成"
tree -L 2 $WORK_DIR 2>/dev/null || ls -R $WORK_DIR

# 7. 生成 .env 模板
echo ""
echo "【7】生成环境变量模板..."
cat > $WORK_DIR/.env <<'EOF'
# 企业微信配置
# 获取方式：企业微信管理后台 → 应用管理 → 自建应用
WECOM_TOKEN=your_token_here
WECOM_ENCODING_AES_KEY=your_aes_key_here
WECOM_CORPID=your_corpid_here
WECOM_CORPSECRET=your_secret_here

# Anthropic API Key
# 获取方式：https://console.anthropic.com/settings/keys
ANTHROPIC_API_KEY=sk-ant-xxxxx

# Grafana 管理员密码
GRAFANA_PASSWORD=change_me_to_strong_password

# 数据库配置（可选，默认使用 SQLite）
# DB_TYPE=sqlite  # 或 postgresql
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=openclaw
# DB_USER=openclaw
# DB_PASSWORD=your_db_password
EOF

chmod 600 $WORK_DIR/.env
echo "✓ .env 文件已生成: $WORK_DIR/.env"
echo "⚠ 请编辑 .env 文件填入真实配置"

# 8. 安装 SQLite（如果需要）
echo ""
echo "【8】安装 SQLite..."
if command -v sqlite3 &> /dev/null; then
    echo "✓ SQLite 已安装: $(sqlite3 --version)"
else
    case $OS in
        ubuntu|debian)
            apt install -y sqlite3
            ;;
        centos|rhel)
            yum install -y sqlite
            ;;
    esac
    echo "✓ SQLite 安装完成"
fi

# 9. 配置系统参数优化
echo ""
echo "【9】优化系统参数..."
cat >> /etc/sysctl.conf <<'EOF'

# OpenClaw 优化参数
net.core.somaxconn = 1024
net.ipv4.tcp_max_syn_backlog = 2048
vm.overcommit_memory = 1
fs.file-max = 65536
EOF

sysctl -p
echo "✓ 系统参数已优化"

# 10. 安装监控工具（可选）
echo ""
echo "【10】安装监控工具..."
read -p "是否安装 htop、iotop、nethogs？(y/n): " install_tools

if [ "$install_tools" == "y" ]; then
    case $OS in
        ubuntu|debian)
            apt install -y htop iotop nethogs
            ;;
        centos|rhel)
            yum install -y htop iotop nethogs
            ;;
    esac
    echo "✓ 监控工具已安装"
fi

# 11. 设置 fail2ban（防暴力破解）
echo ""
echo "【11】配置 fail2ban..."
read -p "是否安装 fail2ban 防止 SSH 暴力破解？(y/n): " setup_fail2ban

if [ "$setup_fail2ban" == "y" ]; then
    case $OS in
        ubuntu|debian)
            apt install -y fail2ban
            systemctl enable fail2ban
            systemctl start fail2ban
            ;;
        centos|rhel)
            yum install -y fail2ban
            systemctl enable fail2ban
            systemctl start fail2ban
            ;;
    esac
    echo "✓ fail2ban 已启用"
fi

# 12. 输出摘要
echo ""
echo "=== 初始化完成 ==="
echo ""
echo "✓ Docker: $(docker --version)"
echo "✓ Docker Compose: $(docker-compose --version)"
echo "✓ 工作目录: $WORK_DIR"
echo "✓ 环境变量: $WORK_DIR/.env (需要编辑)"
echo ""
echo "下一步操作："
echo "1. 编辑 $WORK_DIR/.env 填入企业微信和 API 配置"
echo "2. 运行 init_database.sh 初始化数据库"
echo "3. 运行 setup_ssl.sh 配置 SSL 证书"
echo "4. 运行 deploy.sh 部署服务"
echo ""
echo "详细文档："
echo "- 企业微信配置指南: docs/wecom_setup.md"
echo "- 部署文档: README.md"
