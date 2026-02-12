#!/bin/bash

# ====================================================
# Docker 网络隔离持久化配置
# 用途：配置持久化的容器网络隔离规则
# 服务器：139.199.200.144
# ====================================================

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}Docker 网络隔离持久化配置${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

# 1. 创建自定义 Docker 网络
echo -e "\n${COLOR_YELLOW}[1/5] 创建隔离的 Docker 网络...${COLOR_RESET}"

# 主网络（所有容器共享，但受限）
docker network create --driver bridge \
  --subnet=172.20.0.0/16 \
  --opt com.docker.network.bridge.name=openclaw-main \
  openclaw-network 2>/dev/null || echo "网络已存在"

# Agent 专用内部网络（仅 Agent 之间通信）
docker network create --driver bridge \
  --subnet=172.21.0.0/16 \
  --internal \
  --opt com.docker.network.bridge.name=openclaw-agents \
  openclaw-agents-internal 2>/dev/null || echo "网络已存在"

# 监控网络（Prometheus + Grafana）
docker network create --driver bridge \
  --subnet=172.22.0.0/16 \
  --opt com.docker.network.bridge.name=openclaw-monitor \
  openclaw-monitor 2>/dev/null || echo "网络已存在"

# 2. 生成网络隔离版 docker-compose.yml
echo -e "\n${COLOR_YELLOW}[2/5] 生成网络隔离配置...${COLOR_RESET}"

cat > /opt/openclaw/docker-compose-network.yml << 'EOF'
version: '3.8'

services:
  wecom-gateway:
    image: openclaw-wecom-gateway:latest
    container_name: wecom-gateway
    restart: always
    ports:
      - "8000:8000"
    networks:
      openclaw-network:
        ipv4_address: 172.20.0.10
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true
    privileged: false
    volumes:
      - /opt/openclaw/data:/data:rw
      - /opt/openclaw/logs:/logs:rw

  operation-agent:
    image: openclaw/openclaw:latest
    container_name: operation-agent
    restart: always
    networks:
      openclaw-agents-internal:
        ipv4_address: 172.21.0.11
      openclaw-network:
        ipv4_address: 172.20.0.11
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    privileged: false
    read_only: true
    tmpfs:
      - /tmp
    volumes:
      - /opt/openclaw/agents/operation:/root/.openclaw:rw
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G

  product-agent:
    image: openclaw/openclaw:latest
    container_name: product-agent
    restart: always
    networks:
      openclaw-agents-internal:
        ipv4_address: 172.21.0.12
      openclaw-network:
        ipv4_address: 172.20.0.12
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    privileged: false
    read_only: true
    tmpfs:
      - /tmp
    volumes:
      - /opt/openclaw/agents/product:/root/.openclaw:rw
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G

  development-agent:
    image: openclaw/openclaw:latest
    container_name: development-agent
    restart: always
    networks:
      openclaw-agents-internal:
        ipv4_address: 172.21.0.13
      openclaw-network:
        ipv4_address: 172.20.0.13
    cap_drop:
      - ALL
    cap_add:
      - NET_RAW  # 允许网络调试
    security_opt:
      - no-new-privileges:true
    privileged: false
    read_only: false  # 研发需要写文件
    volumes:
      - /opt/openclaw/agents/development:/root/.openclaw:rw
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G

  testing-agent:
    image: openclaw/openclaw:latest
    container_name: testing-agent
    restart: always
    networks:
      openclaw-agents-internal:
        ipv4_address: 172.21.0.14
      openclaw-network:
        ipv4_address: 172.20.0.14
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    privileged: false
    read_only: false  # 测试需要写日志
    volumes:
      - /opt/openclaw/agents/testing:/root/.openclaw:rw
    deploy:
      resources:
        limits:
          cpus: '1.5'
          memory: 3G

  service-agent:
    image: openclaw/openclaw:latest
    container_name: service-agent
    restart: always
    networks:
      openclaw-agents-internal:
        ipv4_address: 172.21.0.15
      openclaw-network:
        ipv4_address: 172.20.0.15
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    privileged: false
    read_only: true
    tmpfs:
      - /tmp
    volumes:
      - /opt/openclaw/agents/service:/root/.openclaw:rw
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G

  dispatcher-agent:
    image: openclaw/openclaw:latest
    container_name: dispatcher-agent
    restart: always
    networks:
      openclaw-agents-internal:
        ipv4_address: 172.21.0.16
      openclaw-network:
        ipv4_address: 172.20.0.16
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    privileged: false
    read_only: true
    tmpfs:
      - /tmp
    volumes:
      - /opt/openclaw/agents/dispatcher:/root/.openclaw:rw
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: always
    networks:
      openclaw-monitor:
        ipv4_address: 172.22.0.20
      openclaw-network:
        ipv4_address: 172.20.0.20
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    privileged: false
    volumes:
      - /opt/openclaw/config/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus:rw

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: always
    networks:
      openclaw-monitor:
        ipv4_address: 172.22.0.21
      openclaw-network:
        ipv4_address: 172.20.0.21
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    privileged: false
    volumes:
      - grafana-data:/var/lib/grafana:rw

  nginx:
    image: nginx:alpine
    container_name: nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    networks:
      openclaw-network:
        ipv4_address: 172.20.0.2
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
      - CHOWN
      - SETUID
      - SETGID
    security_opt:
      - no-new-privileges:true
    privileged: false
    volumes:
      - /opt/openclaw/config/nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro

networks:
  openclaw-network:
    external: true
  openclaw-agents-internal:
    external: true
  openclaw-monitor:
    external: true

volumes:
  prometheus-data:
  grafana-data:
EOF

# 3. 配置 iptables 规则（持久化）
echo -e "\n${COLOR_YELLOW}[3/5] 配置 iptables 防火墙规则...${COLOR_RESET}"

# 创建 iptables 规则文件
cat > /opt/openclaw/config/iptables-rules.sh << 'IPTABLES_EOF'
#!/bin/bash
# Docker 网络隔离 iptables 规则

# 清空现有规则
iptables -F DOCKER-USER 2>/dev/null || true
iptables -N DOCKER-USER 2>/dev/null || true

# 默认策略：拒绝所有跨网络流量
iptables -I DOCKER-USER -j DROP

# 允许 wecom-gateway 访问所有 agents（任务分发）
iptables -I DOCKER-USER -s 172.20.0.10 -d 172.21.0.0/16 -j ACCEPT

# 允许 agents 之间内部通信（通过 agents-internal 网络）
iptables -I DOCKER-USER -s 172.21.0.0/16 -d 172.21.0.0/16 -j ACCEPT

# 允许 agents 访问外部 API（Anthropic、企业微信等）
iptables -I DOCKER-USER -s 172.21.0.0/16 -o eth0 -j ACCEPT

# 允许 Prometheus 抓取 metrics
iptables -I DOCKER-USER -s 172.22.0.20 -d 172.20.0.0/16 -p tcp --dport 9090 -j ACCEPT

# 允许 Nginx 访问 wecom-gateway
iptables -I DOCKER-USER -s 172.20.0.2 -d 172.20.0.10 -p tcp --dport 8000 -j ACCEPT

# 允许已建立的连接返回
iptables -I DOCKER-USER -m state --state ESTABLISHED,RELATED -j ACCEPT

# 允许内部 DNS 查询
iptables -I DOCKER-USER -p udp --dport 53 -j ACCEPT

# 日志拒绝的连接（调试用）
iptables -A DOCKER-USER -j LOG --log-prefix "DOCKER-DENY: " --log-level 4

echo "✅ iptables 规则已应用"
IPTABLES_EOF

chmod +x /opt/openclaw/config/iptables-rules.sh

# 4. 创建 systemd 服务（开机自动加载规则）
echo -e "\n${COLOR_YELLOW}[4/5] 创建 systemd 服务...${COLOR_RESET}"

sudo tee /etc/systemd/system/openclaw-firewall.service > /dev/null << 'SYSTEMD_EOF'
[Unit]
Description=OpenClaw Docker Network Firewall Rules
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/opt/openclaw/config/iptables-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SYSTEMD_EOF

# 启用并启动服务
sudo systemctl daemon-reload
sudo systemctl enable openclaw-firewall.service
sudo systemctl start openclaw-firewall.service

# 5. 生成网络隔离验证脚本
echo -e "\n${COLOR_YELLOW}[5/5] 生成验证脚本...${COLOR_RESET}"

cat > /opt/openclaw/scripts/verify_network_isolation.sh << 'VERIFY_EOF'
#!/bin/bash

echo "========================================="
echo "Docker 网络隔离验证"
echo "========================================="

# 测试1：operation-agent 能否 ping product-agent（应该可以，内部网络）
echo -e "\n[测试1] operation-agent → product-agent (内部网络)"
docker exec operation-agent ping -c 2 172.21.0.12 && echo "✅ 通过" || echo "❌ 失败"

# 测试2：operation-agent 能否访问外网（应该可以）
echo -e "\n[测试2] operation-agent → 外网"
docker exec operation-agent ping -c 2 8.8.8.8 && echo "✅ 通过" || echo "❌ 失败"

# 测试3：Nginx 能否访问 wecom-gateway（应该可以）
echo -e "\n[测试3] nginx → wecom-gateway"
docker exec nginx wget -q --spider http://172.20.0.10:8000/health && echo "✅ 通过" || echo "❌ 失败"

# 测试4：Grafana 能否直接访问 operation-agent（应该失败）
echo -e "\n[测试4] grafana → operation-agent (应该被阻止)"
docker exec grafana timeout 2 wget -q --spider http://172.21.0.11:18789 2>/dev/null && echo "❌ 隔离失败！" || echo "✅ 正确阻止"

# 测试5：查看 iptables 规则
echo -e "\n[测试5] 当前 iptables 规则"
sudo iptables -L DOCKER-USER -n -v

echo -e "\n========================================="
echo "验证完成"
echo "========================================="
VERIFY_EOF

chmod +x /opt/openclaw/scripts/verify_network_isolation.sh

echo -e "\n${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}✅ 网络隔离配置完成！${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

echo -e "\n${COLOR_YELLOW}下一步操作：${COLOR_RESET}"
echo "1. 检查网络创建："
echo "   docker network ls | grep openclaw"
echo ""
echo "2. 使用新的 docker-compose 文件部署："
echo "   docker-compose -f docker-compose-network.yml up -d"
echo ""
echo "3. 验证网络隔离："
echo "   bash /opt/openclaw/scripts/verify_network_isolation.sh"
echo ""
echo "4. 查看防火墙状态："
echo "   sudo systemctl status openclaw-firewall"
echo ""
echo -e "${COLOR_YELLOW}网络架构：${COLOR_RESET}"
echo "- openclaw-network (172.20.0.0/16): 主网络，外部访问"
echo "- openclaw-agents-internal (172.21.0.0/16): Agent内部通信，隔离外网"
echo "- openclaw-monitor (172.22.0.0/16): 监控专用网络"
