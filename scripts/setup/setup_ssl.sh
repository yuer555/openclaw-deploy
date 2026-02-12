#!/bin/bash
# scripts/setup_ssl.sh - SSL 证书配置脚本（Let's Encrypt）

set -e

echo "=== OpenClaw SSL 证书配置 ==="
echo ""

# 1. 检查域名
read -p "请输入您的域名（如 openclaw.example.com）: " DOMAIN

if [ -z "$DOMAIN" ]; then
    echo "✗ 域名不能为空"
    exit 1
fi

echo "域名: $DOMAIN"

# 2. 检查 DNS 解析
echo ""
echo "【1】检查 DNS 解析..."
SERVER_IP=$(curl -s ifconfig.me)
DOMAIN_IP=$(dig +short "$DOMAIN" | head -1)

echo "服务器 IP: $SERVER_IP"
echo "域名解析 IP: $DOMAIN_IP"

if [ "$SERVER_IP" != "$DOMAIN_IP" ]; then
    echo "⚠ 警告: 域名未正确解析到当前服务器"
    read -p "是否继续？(y/n): " continue_anyway
    if [ "$continue_anyway" != "y" ]; then
        echo "已取消配置"
        exit 1
    fi
fi

# 3. 选择证书方式
echo ""
echo "【2】选择证书配置方式..."
echo "1. 自动申请 Let's Encrypt 免费证书（推荐）"
echo "2. 使用已有证书文件"
echo "3. 生成自签名证书（仅测试用）"
read -p "请选择 (1-3): " cert_method

case $cert_method in
    1)
        # Let's Encrypt 自动申请
        echo ""
        echo "【3】安装 Certbot..."
        
        # 检测操作系统
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
        fi
        
        # 安装 Certbot
        if ! command -v certbot &> /dev/null; then
            case $OS in
                ubuntu|debian)
                    apt update
                    apt install -y certbot python3-certbot-nginx
                    ;;
                centos|rhel)
                    yum install -y certbot python3-certbot-nginx
                    ;;
                *)
                    echo "✗ 未识别的操作系统，请手动安装 Certbot"
                    exit 1
                    ;;
            esac
            echo "✓ Certbot 已安装"
        else
            echo "✓ Certbot 已存在"
        fi
        
        # 申请证书
        echo ""
        echo "【4】申请 SSL 证书..."
        read -p "请输入管理员邮箱: " EMAIL
        
        certbot certonly --standalone \
            --non-interactive \
            --agree-tos \
            --email "$EMAIL" \
            -d "$DOMAIN"
        
        # 复制证书到工作目录
        SSL_DIR="/opt/openclaw/config/ssl"
        mkdir -p "$SSL_DIR"
        
        cp "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "$SSL_DIR/cert.pem"
        cp "/etc/letsencrypt/live/$DOMAIN/privkey.pem" "$SSL_DIR/key.pem"
        
        chmod 600 "$SSL_DIR/key.pem"
        
        echo "✓ 证书已复制到: $SSL_DIR"
        
        # 配置自动续期
        echo ""
        echo "【5】配置证书自动续期..."
        
        # 创建续期脚本
        cat > /opt/openclaw/renew_ssl.sh <<'RENEW_SCRIPT'
#!/bin/bash
certbot renew --quiet
cp /etc/letsencrypt/live/*/fullchain.pem /opt/openclaw/config/ssl/cert.pem
cp /etc/letsencrypt/live/*/privkey.pem /opt/openclaw/config/ssl/key.pem
docker-compose -f /opt/openclaw/docker-compose.yml restart nginx
RENEW_SCRIPT
        
        chmod +x /opt/openclaw/renew_ssl.sh
        
        # 添加到 crontab
        (crontab -l 2>/dev/null; echo "0 3 * * * /opt/openclaw/renew_ssl.sh") | crontab -
        
        echo "✓ 自动续期已配置（每天凌晨3点检查）"
        ;;
    
    2)
        # 使用已有证书
        echo ""
        echo "【3】使用已有证书..."
        read -p "证书文件路径（.crt 或 .pem）: " CERT_FILE
        read -p "私钥文件路径（.key 或 .pem）: " KEY_FILE
        
        if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
            echo "✗ 证书或私钥文件不存在"
            exit 1
        fi
        
        SSL_DIR="/opt/openclaw/config/ssl"
        mkdir -p "$SSL_DIR"
        
        cp "$CERT_FILE" "$SSL_DIR/cert.pem"
        cp "$KEY_FILE" "$SSL_DIR/key.pem"
        
        chmod 600 "$SSL_DIR/key.pem"
        
        echo "✓ 证书已复制到: $SSL_DIR"
        ;;
    
    3)
        # 生成自签名证书
        echo ""
        echo "【3】生成自签名证书（仅测试用）..."
        
        SSL_DIR="/opt/openclaw/config/ssl"
        mkdir -p "$SSL_DIR"
        
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$SSL_DIR/key.pem" \
            -out "$SSL_DIR/cert.pem" \
            -subj "/CN=$DOMAIN/O=OpenClaw/C=CN"
        
        chmod 600 "$SSL_DIR/key.pem"
        
        echo "✓ 自签名证书已生成"
        echo "⚠ 警告: 浏览器会提示证书不受信任，仅供测试使用"
        ;;
    
    *)
        echo "✗ 无效选择"
        exit 1
        ;;
esac

# 6. 生成 Nginx 配置
echo ""
echo "【6】生成 Nginx SSL 配置..."

NGINX_CONF="/opt/openclaw/config/nginx.conf"

cat > "$NGINX_CONF" <<EOF
events {
    worker_connections 1024;
}

http {
    # 日志格式
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # 基础配置
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    client_max_body_size 10M;

    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

    # HTTP 重定向到 HTTPS
    server {
        listen 80;
        server_name $DOMAIN;
        
        # Let's Encrypt 验证路径
        location /.well-known/acme-challenge/ {
            root /var/www/html;
        }
        
        # 其他请求重定向到 HTTPS
        location / {
            return 301 https://\$server_name\$request_uri;
        }
    }

    # HTTPS 服务
    server {
        listen 443 ssl http2;
        server_name $DOMAIN;

        # SSL 证书
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;

        # SSL 安全配置
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
        ssl_prefer_server_ciphers on;
        ssl_session_cache shared:SSL:10m;
        ssl_session_timeout 10m;

        # 安全头
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        # 企业微信回调
        location /wecom/callback {
            proxy_pass http://wecom-gateway:8000;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            
            # 超时设置
            proxy_connect_timeout 10s;
            proxy_send_timeout 60s;
            proxy_read_timeout 60s;
        }

        # 健康检查
        location /health {
            access_log off;
            return 200 "OK";
        }

        # 默认拒绝其他请求
        location / {
            return 403;
        }
    }
}
EOF

echo "✓ Nginx 配置已生成: $NGINX_CONF"

# 7. 验证证书
echo ""
echo "【7】验证证书..."
openssl x509 -in "$SSL_DIR/cert.pem" -noout -text | grep -E "Subject:|Issuer:|Not Before|Not After"

# 8. 输出摘要
echo ""
echo "=== SSL 证书配置完成 ==="
echo ""
echo "✓ 域名: $DOMAIN"
echo "✓ 证书路径: $SSL_DIR/cert.pem"
echo "✓ 私钥路径: $SSL_DIR/key.pem"
echo "✓ Nginx 配置: $NGINX_CONF"

if [ "$cert_method" == "1" ]; then
    echo "✓ 自动续期: 已配置（每天凌晨3点）"
    echo ""
    echo "证书有效期: 90 天"
    echo "手动续期命令: certbot renew"
fi

echo ""
echo "下一步: 运行 docker-compose up -d 启动服务"
echo "验证 HTTPS: curl -I https://$DOMAIN/health"
