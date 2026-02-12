#!/bin/bash

# ====================================================
# Docker Secrets 安全配置脚本
# 用途：将敏感凭证存储为 Docker Secrets
# 服务器：139.199.200.144
# ====================================================

set -e

SECRETS_DIR="/opt/openclaw/secrets"
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}Docker Secrets 安全配置${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

# 1. 创建 secrets 目录
echo -e "\n${COLOR_YELLOW}[1/6] 创建 Secrets 目录...${COLOR_RESET}"
sudo mkdir -p "$SECRETS_DIR"
sudo chmod 700 "$SECRETS_DIR"

# 2. 生成 secrets 文件（交互式输入）
echo -e "\n${COLOR_YELLOW}[2/6] 配置敏感凭证...${COLOR_RESET}"

# Anthropic API Key
echo -e "\n请输入 Anthropic API Key:"
read -s ANTHROPIC_API_KEY
echo "$ANTHROPIC_API_KEY" | sudo tee "$SECRETS_DIR/anthropic_api_key" > /dev/null

# 企业微信 Corp Secret
echo -e "\n请输入企业微信 Corp Secret:"
read -s WECOM_CORPSECRET
echo "$WECOM_CORPSECRET" | sudo tee "$SECRETS_DIR/wecom_corpsecret" > /dev/null

# 企业微信 Encoding AES Key
echo -e "\n请输入企业微信 Encoding AES Key:"
read -s WECOM_AES_KEY
echo "$WECOM_AES_KEY" | sudo tee "$SECRETS_DIR/wecom_aes_key" > /dev/null

# 企业微信 Token
echo -e "\n请输入企业微信 Token:"
read -s WECOM_TOKEN
echo "$WECOM_TOKEN" | sudo tee "$SECRETS_DIR/wecom_token" > /dev/null

# Grafana 管理员密码
echo -e "\n请输入 Grafana 管理员密码:"
read -s GRAFANA_PASSWORD
echo "$GRAFANA_PASSWORD" | sudo tee "$SECRETS_DIR/grafana_password" > /dev/null

# 3. 设置严格权限
echo -e "\n${COLOR_YELLOW}[3/6] 设置文件权限...${COLOR_RESET}"
sudo chmod 400 "$SECRETS_DIR"/*
sudo chown root:root "$SECRETS_DIR"/*

# 4. 创建 Docker Secrets（如果使用 Docker Swarm）
echo -e "\n${COLOR_YELLOW}[4/6] 检查 Docker Swarm 状态...${COLOR_RESET}"
if docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "Docker Swarm 已激活，创建 Docker Secrets..."
    
    docker secret create anthropic_api_key "$SECRETS_DIR/anthropic_api_key" 2>/dev/null || echo "Secret 已存在，跳过"
    docker secret create wecom_corpsecret "$SECRETS_DIR/wecom_corpsecret" 2>/dev/null || echo "Secret 已存在，跳过"
    docker secret create wecom_aes_key "$SECRETS_DIR/wecom_aes_key" 2>/dev/null || echo "Secret 已存在，跳过"
    docker secret create wecom_token "$SECRETS_DIR/wecom_token" 2>/dev/null || echo "Secret 已存在，跳过"
    docker secret create grafana_password "$SECRETS_DIR/grafana_password" 2>/dev/null || echo "Secret 已存在，跳过"
else
    echo "Docker Swarm 未激活，使用文件挂载模式（推荐用于单机部署）"
fi

# 5. 生成更新后的 docker-compose.yml
echo -e "\n${COLOR_YELLOW}[5/6] 生成安全版 docker-compose.yml...${COLOR_RESET}"

cat > /opt/openclaw/docker-compose-secrets.yml << 'EOF'
version: '3.8'

services:
  wecom-gateway:
    image: openclaw-wecom-gateway:latest
    container_name: wecom-gateway
    restart: always
    ports:
      - "8000:8000"
    secrets:
      - wecom_corpsecret
      - wecom_aes_key
      - wecom_token
    environment:
      - WECOM_CORPID=${WECOM_CORPID}
      - WECOM_CORPSECRET_FILE=/run/secrets/wecom_corpsecret
      - WECOM_AES_KEY_FILE=/run/secrets/wecom_aes_key
      - WECOM_TOKEN_FILE=/run/secrets/wecom_token
      - DATABASE_URL=/data/openclaw.db
    volumes:
      - /opt/openclaw/data:/data
      - /opt/openclaw/logs:/logs
    networks:
      - openclaw-network

  operation-agent:
    image: openclaw/openclaw:latest
    container_name: operation-agent
    restart: always
    secrets:
      - anthropic_api_key
    environment:
      - ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic_api_key
      - AGENT_ROLE=operation
    volumes:
      - /opt/openclaw/agents/operation:/root/.openclaw
    networks:
      - openclaw-network
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G

  product-agent:
    image: openclaw/openclaw:latest
    container_name: product-agent
    restart: always
    secrets:
      - anthropic_api_key
    environment:
      - ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic_api_key
      - AGENT_ROLE=product
    volumes:
      - /opt/openclaw/agents/product:/root/.openclaw
    networks:
      - openclaw-network
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G

  development-agent:
    image: openclaw/openclaw:latest
    container_name: development-agent
    restart: always
    secrets:
      - anthropic_api_key
    environment:
      - ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic_api_key
      - AGENT_ROLE=development
    volumes:
      - /opt/openclaw/agents/development:/root/.openclaw
    networks:
      - openclaw-network
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G

  testing-agent:
    image: openclaw/openclaw:latest
    container_name: testing-agent
    restart: always
    secrets:
      - anthropic_api_key
    environment:
      - ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic_api_key
      - AGENT_ROLE=testing
    volumes:
      - /opt/openclaw/agents/testing:/root/.openclaw
    networks:
      - openclaw-network
    deploy:
      resources:
        limits:
          cpus: '1.5'
          memory: 3G

  service-agent:
    image: openclaw/openclaw:latest
    container_name: service-agent
    restart: always
    secrets:
      - anthropic_api_key
    environment:
      - ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic_api_key
      - AGENT_ROLE=service
    volumes:
      - /opt/openclaw/agents/service:/root/.openclaw
    networks:
      - openclaw-network
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G

  dispatcher-agent:
    image: openclaw/openclaw:latest
    container_name: dispatcher-agent
    restart: always
    secrets:
      - anthropic_api_key
    environment:
      - ANTHROPIC_API_KEY_FILE=/run/secrets/anthropic_api_key
      - AGENT_ROLE=dispatcher
    volumes:
      - /opt/openclaw/agents/dispatcher:/root/.openclaw
    networks:
      - openclaw-network
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: always
    ports:
      - "9090:9090"
    volumes:
      - /opt/openclaw/config/prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus-data:/prometheus
    networks:
      - openclaw-network

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: always
    ports:
      - "3000:3000"
    secrets:
      - grafana_password
    environment:
      - GF_SECURITY_ADMIN_PASSWORD__FILE=/run/secrets/grafana_password
    volumes:
      - grafana-data:/var/lib/grafana
    networks:
      - openclaw-network

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /opt/openclaw/config/nginx.conf:/etc/nginx/nginx.conf
      - /etc/letsencrypt:/etc/letsencrypt
    networks:
      - openclaw-network
    depends_on:
      - wecom-gateway

secrets:
  anthropic_api_key:
    file: /opt/openclaw/secrets/anthropic_api_key
  wecom_corpsecret:
    file: /opt/openclaw/secrets/wecom_corpsecret
  wecom_aes_key:
    file: /opt/openclaw/secrets/wecom_aes_key
  wecom_token:
    file: /opt/openclaw/secrets/wecom_token
  grafana_password:
    file: /opt/openclaw/secrets/grafana_password

networks:
  openclaw-network:
    driver: bridge

volumes:
  prometheus-data:
  grafana-data:
EOF

# 6. 更新 .env 文件（移除敏感信息）
echo -e "\n${COLOR_YELLOW}[6/6] 更新 .env 配置文件...${COLOR_RESET}"

cat > /opt/openclaw/.env << 'EOF'
# 非敏感配置（公开信息）
WECOM_CORPID=your_corpid_here
DOMAIN=your_domain.com

# 敏感信息已移至 Docker Secrets
# 请勿在此文件中存储密钥！
EOF

sudo chmod 644 /opt/openclaw/.env

echo -e "\n${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}✅ Docker Secrets 配置完成！${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

echo -e "\n${COLOR_YELLOW}下一步操作：${COLOR_RESET}"
echo "1. 检查 secrets 文件："
echo "   ls -l $SECRETS_DIR"
echo ""
echo "2. 使用新的 docker-compose 文件部署："
echo "   cd /opt/openclaw"
echo "   docker-compose -f docker-compose-secrets.yml up -d"
echo ""
echo "3. 验证 secrets 挂载："
echo "   docker exec operation-agent ls -l /run/secrets/"
echo ""
echo -e "${COLOR_RED}⚠️  重要提示：${COLOR_RESET}"
echo "- Secrets 文件权限已设置为 400（仅 root 可读）"
echo "- 定期备份 $SECRETS_DIR 目录"
echo "- 每 90 天轮换一次 API Keys"
