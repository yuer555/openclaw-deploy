#!/bin/bash
# scripts/deploy.sh - 一键部署脚本

set -e

echo "=== OpenClaw 一键部署 ==="
echo ""

WORK_DIR="/opt/openclaw"

# 1. 前置检查
echo "【1】前置检查..."

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then 
    echo "⚠ 建议使用 root 或 sudo 运行此脚本"
fi

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "✗ Docker 未安装，请先运行 init_server.sh"
    exit 1
fi

# 检查 Docker Compose
if ! command -v docker-compose &> /dev/null; then
    echo "✗ Docker Compose 未安装，请先运行 init_server.sh"
    exit 1
fi

# 检查工作目录
if [ ! -d "$WORK_DIR" ]; then
    echo "✗ 工作目录不存在: $WORK_DIR"
    echo "请先运行 init_server.sh"
    exit 1
fi

# 检查 .env 文件
if [ ! -f "$WORK_DIR/.env" ]; then
    echo "✗ .env 文件不存在"
    echo "请先运行 init_server.sh 并配置 .env"
    exit 1
fi

# 检查数据库
if [ ! -f "$WORK_DIR/data/user_roles.db" ]; then
    echo "⚠ 数据库未初始化"
    read -p "是否现在初始化数据库？(y/n): " init_db
    if [ "$init_db" == "y" ]; then
        bash "$WORK_DIR/scripts/init_database.sh"
    else
        echo "✗ 需要先初始化数据库"
        exit 1
    fi
fi

# 检查 SSL 证书
if [ ! -f "$WORK_DIR/config/ssl/cert.pem" ] || [ ! -f "$WORK_DIR/config/ssl/key.pem" ]; then
    echo "⚠ SSL 证书未配置"
    read -p "是否现在配置 SSL？(y/n): " setup_ssl
    if [ "$setup_ssl" == "y" ]; then
        bash "$WORK_DIR/scripts/setup_ssl.sh"
    else
        echo "⚠ 跳过 SSL 配置（仅 HTTP 可用）"
    fi
fi

echo "✓ 前置检查通过"

# 2. 复制配置文件
echo ""
echo "【2】部署配置文件..."

# 复制虚拟员工配置（如果存在）
if [ -d "config/agents" ]; then
    echo "复制虚拟员工配置..."
    cp -r config/agents/* "$WORK_DIR/agents/" 2>/dev/null || echo "⚠ 配置文件不存在，跳过"
fi

# 生成 docker-compose.yml
echo "生成 docker-compose.yml..."
cat > "$WORK_DIR/docker-compose.yml" <<'EOF'
version: '3.8'

services:
  # Nginx 反向代理
  nginx:
    image: nginx:alpine
    container_name: openclaw-nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./config/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./config/ssl:/etc/nginx/ssl:ro
      - ./logs/nginx:/var/log/nginx
    restart: always
    networks:
      - openclaw-network

  # 企业微信网关
  wecom-gateway:
    build: ./wecom_gateway
    container_name: openclaw-wecom-gateway
    environment:
      - WECOM_TOKEN=${WECOM_TOKEN}
      - WECOM_ENCODING_AES_KEY=${WECOM_ENCODING_AES_KEY}
      - WECOM_CORPID=${WECOM_CORPID}
      - WECOM_CORPSECRET=${WECOM_CORPSECRET}
    volumes:
      - ./data:/data
      - ./logs/wecom:/logs
    restart: always
    networks:
      - openclaw-network

  # 调度代理
  dispatcher-agent:
    image: openclaw/openclaw:latest
    container_name: dispatcher-agent
    command: openclaw start dispatcher-agent
    volumes:
      - ./agents/dispatcher:/root/.openclaw
      - ./data:/data:ro
    environment:
      - OPENCLAW_GATEWAY_PORT=18789
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    restart: always
    networks:
      - openclaw-network

  # 运营代理
  operation-agent:
    image: openclaw/openclaw:latest
    container_name: operation-agent
    command: openclaw start operation-agent
    volumes:
      - ./agents/operation:/root/.openclaw
      - ./data:/data:ro
    environment:
      - OPENCLAW_GATEWAY_PORT=18790
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    restart: always
    networks:
      - openclaw-network

  # 产品代理
  product-agent:
    image: openclaw/openclaw:latest
    container_name: product-agent
    command: openclaw start product-agent
    volumes:
      - ./agents/product:/root/.openclaw
      - ./data:/data:ro
    environment:
      - OPENCLAW_GATEWAY_PORT=18791
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    restart: always
    networks:
      - openclaw-network

  # 研发代理
  development-agent:
    image: openclaw/openclaw:latest
    container_name: development-agent
    command: openclaw start development-agent
    volumes:
      - ./agents/development:/root/.openclaw
      - ./data:/data:ro
      - ./workspace/projects:/workspace/projects
    environment:
      - OPENCLAW_GATEWAY_PORT=18792
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    restart: always
    networks:
      - openclaw-network

  # 测试代理
  testing-agent:
    image: openclaw/openclaw:latest
    container_name: testing-agent
    command: openclaw start testing-agent
    volumes:
      - ./agents/testing:/root/.openclaw
      - ./data:/data:ro
      - ./workspace/testing:/workspace/testing
    environment:
      - OPENCLAW_GATEWAY_PORT=18793
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    restart: always
    networks:
      - openclaw-network

  # 客服代理
  service-agent:
    image: openclaw/openclaw:latest
    container_name: service-agent
    command: openclaw start service-agent
    volumes:
      - ./agents/service:/root/.openclaw
      - ./data:/data:ro
      - ./workspace/service:/workspace/service
      - ./workspace/knowledge_base:/workspace/knowledge_base:ro
    environment:
      - OPENCLAW_GATEWAY_PORT=18794
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    restart: always
    networks:
      - openclaw-network

  # Prometheus 监控
  prometheus:
    image: prom/prometheus:latest
    container_name: openclaw-prometheus
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ./data/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
    ports:
      - "9090:9090"
    restart: always
    networks:
      - openclaw-network

  # Grafana 可视化
  grafana:
    image: grafana/grafana:latest
    container_name: openclaw-grafana
    volumes:
      - ./data/grafana:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=${GRAFANA_PASSWORD}
    ports:
      - "3000:3000"
    restart: always
    networks:
      - openclaw-network

networks:
  openclaw-network:
    driver: bridge
EOF

echo "✓ docker-compose.yml 已生成"

# 3. 拉取镜像
echo ""
echo "【3】拉取 Docker 镜像..."
cd "$WORK_DIR"
docker-compose pull

# 4. 构建企业微信网关
echo ""
echo "【4】构建企业微信网关..."

# 创建 wecom_gateway 目录和 Dockerfile
mkdir -p "$WORK_DIR/wecom_gateway"

cat > "$WORK_DIR/wecom_gateway/Dockerfile" <<'EOF'
FROM python:3.11-slim

WORKDIR /app

# 安装依赖
RUN pip install --no-cache-dir flask requests pycryptodome

# 复制代码
COPY wecom_gateway.py /app/

# 暴露端口
EXPOSE 8000

# 启动服务
CMD ["python", "wecom_gateway.py"]
EOF

# 创建企业微信网关代码（简化版）
cat > "$WORK_DIR/wecom_gateway/wecom_gateway.py" <<'EOF'
from flask import Flask, request, jsonify
import hashlib
import xml.etree.ElementTree as ET

app = Flask(__name__)

@app.route('/wecom/callback', methods=['GET', 'POST'])
def wecom_callback():
    if request.method == 'GET':
        # URL 验证
        return request.args.get('echostr', '')
    
    # 消息处理
    xml_data = request.data
    root = ET.fromstring(xml_data)
    
    msg_type = root.find('MsgType').text
    from_user = root.find('FromUserName').text
    content = root.find('Content').text if root.find('Content') is not None else ''
    
    # TODO: 实际调用 OpenClaw 代理
    response_text = f"收到消息: {content}"
    
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF

echo "✓ 企业微信网关代码已创建"
echo "⚠ 注意: wecom_gateway.py 是简化版，需要补充实际业务逻辑"

# 5. 启动服务
echo ""
echo "【5】启动服务..."
docker-compose build
docker-compose up -d

# 6. 等待服务启动
echo ""
echo "【6】等待服务启动..."
sleep 10

# 7. 检查服务状态
echo ""
echo "【7】检查服务状态..."
docker-compose ps

# 8. 验证端口
echo ""
echo "【8】验证端口监听..."
netstat -tuln | grep -E '80|443|9090|3000' || ss -tuln | grep -E '80|443|9090|3000'

# 9. 输出访问地址
echo ""
echo "=== 部署完成 ==="
echo ""
echo "服务状态:"
docker-compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "访问地址:"
echo "- 企业微信回调: https://your-domain.com/wecom/callback"
echo "- Prometheus: http://your-server:9090"
echo "- Grafana: http://your-server:3000 (用户名: admin, 密码: 见 .env)"
echo ""
echo "下一步操作:"
echo "1. 配置企业微信应用回调 URL"
echo "2. 添加用户绑定: ./scripts/add_user.sh"
echo "3. 健康检查: ./scripts/health_check.sh"
echo "4. 查看日志: docker-compose logs -f"
echo ""
echo "故障排查:"
echo "- 查看所有日志: docker-compose logs"
echo "- 重启服务: docker-compose restart"
echo "- 停止服务: docker-compose down"
