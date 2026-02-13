#!/bin/bash
# OpenClaw 云服务虚拟员工一键部署脚本
# 服务器：139.199.200.144
# 执行方式：bash deploy.sh

set -e

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否在云服务器上运行
if [ "$(hostname)" != "VM-0-5-ubuntu" ]; then
    echo_warn "当前不在云服务器上，将通过 SSH 连接..."
    SERVER="ubuntu@139.199.200.144"
    
    # 上传脚本到服务器
    echo_info "上传部署文件到服务器..."
    rsync -avz --exclude='.git' --exclude='node_modules' ./ $SERVER:/tmp/openclaw-deploy/
    
    # 在服务器上执行部署
    echo_info "在服务器上执行部署..."
    ssh $SERVER "cd /tmp/openclaw-deploy && bash deploy.sh"
    exit 0
fi

# ===========================================
# 以下在服务器上执行
# ===========================================

echo_info "========================================="
echo_info "OpenClaw 云服务虚拟员工部署脚本"
echo_info "========================================="

# 1. 检查环境
echo_info "[1/8] 检查环境依赖..."
command -v docker >/dev/null 2>&1 || { echo_error "Docker 未安装"; exit 1; }
command -v node >/dev/null 2>&1 || { echo_error "Node.js 未安装"; exit 1; }
echo_info "✓ Docker $(docker --version | cut -d' ' -f3)"
echo_info "✓ Node.js $(node --version)"

# 2. 创建工作目录
echo_info "[2/8] 创建工作目录..."
sudo mkdir -p /opt/openclaw
sudo chown -R ubuntu:ubuntu /opt/openclaw
cd /opt/openclaw

# 3. 安装 OpenClaw
echo_info "[3/8] 安装 OpenClaw..."
if ! command -v openclaw >/dev/null 2>&1; then
    sudo npm install -g openclaw@latest
    echo_info "✓ OpenClaw $(openclaw --version)"
else
    echo_info "✓ OpenClaw 已安装: $(openclaw --version)"
fi

# 4. 配置 API Keys
echo_info "[4/8] 配置 API Keys..."
echo_warn "请输入以下凭证（或按回车跳过，稍后手动配置）："

read -p "Anthropic API Key (sk-ant-...): " ANTHROPIC_KEY
read -p "GitHub Copilot Token (可选): " GITHUB_TOKEN

# 保存到 .env 文件
cat > .env << EOF
# OpenClaw 配置
ANTHROPIC_API_KEY=${ANTHROPIC_KEY:-"sk-ant-your-key-here"}
GITHUB_COPILOT_TOKEN=${GITHUB_TOKEN:-""}

# 服务器配置
SERVER_IP=139.199.200.144
GATEWAY_PORT=18789

# 数据目录
DATA_DIR=/opt/openclaw/data
LOGS_DIR=/opt/openclaw/logs
EOF

echo_info "✓ 配置文件已保存: /opt/openclaw/.env"

# 5. 创建目录结构
echo_info "[5/8] 创建目录结构..."
mkdir -p {data,logs,config,agents/{operation,product,development,testing}}

# 6. 生成 Docker Compose 配置
echo_info "[6/8] 生成 Docker Compose 配置..."
cat > docker-compose.yml << 'EOF'
version: '3.8'

services:
  # 运营虚拟员工
  operation-agent:
    image: node:24-alpine
    container_name: operation-agent
    restart: unless-stopped
    working_dir: /workspace
    environment:
      - NODE_ENV=production
      - AGENT_ID=operation
      - AGENT_NAME=运营助手
    volumes:
      - ./agents/operation:/workspace
      - ./data:/data
      - ./logs:/logs
    networks:
      - openclaw-network
    command: sh -c "apk add --no-cache git && npm install -g openclaw@latest && openclaw gateway start"

  # 产品虚拟员工
  product-agent:
    image: node:24-alpine
    container_name: product-agent
    restart: unless-stopped
    working_dir: /workspace
    environment:
      - NODE_ENV=production
      - AGENT_ID=product
      - AGENT_NAME=产品经理
    volumes:
      - ./agents/product:/workspace
      - ./data:/data
      - ./logs:/logs
    networks:
      - openclaw-network
    command: sh -c "apk add --no-cache git && npm install -g openclaw@latest && openclaw gateway start"

  # 研发虚拟员工
  development-agent:
    image: node:24-alpine
    container_name: development-agent
    restart: unless-stopped
    working_dir: /workspace
    environment:
      - NODE_ENV=production
      - AGENT_ID=development
      - AGENT_NAME=开发工程师
    volumes:
      - ./agents/development:/workspace
      - ./data:/data
      - ./logs:/logs
    networks:
      - openclaw-network
    command: sh -c "apk add --no-cache git && npm install -g openclaw@latest && openclaw gateway start"

  # 测试虚拟员工
  testing-agent:
    image: node:24-alpine
    container_name: testing-agent
    restart: unless-stopped
    working_dir: /workspace
    environment:
      - NODE_ENV=production
      - AGENT_ID=testing
      - AGENT_NAME=测试工程师
    volumes:
      - ./agents/testing:/workspace
      - ./data:/data
      - ./logs:/logs
    networks:
      - openclaw-network
    command: sh -c "apk add --no-cache git && npm install -g openclaw@latest && openclaw gateway start"

networks:
  openclaw-network:
    driver: bridge
EOF

echo_info "✓ Docker Compose 配置已生成"

# 7. 创建角色配置文件
echo_info "[7/8] 创建角色配置文件..."

# 运营虚拟员工配置
cat > agents/operation/config.json << 'EOF'
{
  "agentId": "operation",
  "name": "运营助手",
  "systemPrompt": "你是一名专业的运营助手，擅长内容创作、活动策划、用户运营。你的任务包括：撰写文案、设计活动方案、分析用户数据、管理社群。请用专业且富有创意的方式完成任务。",
  "tools": {
    "allow": ["group:fs:read", "group:browser", "web_search", "web_fetch"],
    "deny": ["group:runtime", "group:fs:delete"]
  },
  "sandbox": {
    "mode": "all",
    "workspaceAccess": "ro"
  }
}
EOF

# 产品虚拟员工配置
cat > agents/product/config.json << 'EOF'
{
  "agentId": "product",
  "name": "产品经理",
  "systemPrompt": "你是一名经验丰富的产品经理，擅长需求分析、产品设计、竞品研究。你的任务包括：撰写需求文档、设计产品原型、分析竞品、制定产品规划。请用结构化和逻辑清晰的方式完成任务。",
  "tools": {
    "allow": ["group:fs:read", "group:fs:write", "group:browser", "web_search", "web_fetch"],
    "deny": ["group:runtime", "group:fs:delete"]
  },
  "sandbox": {
    "mode": "all",
    "workspaceAccess": "ro"
  }
}
EOF

# 研发虚拟员工配置
cat > agents/development/config.json << 'EOF'
{
  "agentId": "development",
  "name": "开发工程师",
  "systemPrompt": "你是一名高级开发工程师，擅长代码编写、架构设计、问题解决。你的任务包括：编写代码、Code Review、技术选型、解决技术问题。请用规范和高质量的代码完成任务。",
  "tools": {
    "allow": ["group:fs:read", "group:fs:write", "exec", "github"],
    "deny": ["sys_shutdown"]
  },
  "sandbox": {
    "mode": "all",
    "workspaceAccess": "rw"
  }
}
EOF

# 测试虚拟员工配置
cat > agents/testing/config.json << 'EOF'
{
  "agentId": "testing",
  "name": "测试工程师",
  "systemPrompt": "你是一名专业的测试工程师，擅长测试用例设计、自动化测试、质量保障。你的任务包括：编写测试用例、执行测试、Bug跟踪、生成测试报告。请用严谨和细致的方式完成任务。",
  "tools": {
    "allow": ["group:fs:read", "group:fs:write", "exec", "github"],
    "deny": ["group:fs:delete"]
  },
  "sandbox": {
    "mode": "all",
    "workspaceAccess": "ro"
  }
}
EOF

echo_info "✓ 角色配置文件已创建"

# 8. 生成启动脚本
echo_info "[8/8] 生成管理脚本..."

cat > start.sh << 'EOF'
#!/bin/bash
cd /opt/openclaw
source .env
docker-compose up -d
echo "虚拟员工服务已启动！"
docker-compose ps
EOF

cat > stop.sh << 'EOF'
#!/bin/bash
cd /opt/openclaw
docker-compose down
echo "虚拟员工服务已停止！"
EOF

cat > logs.sh << 'EOF'
#!/bin/bash
cd /opt/openclaw
docker-compose logs -f "$@"
EOF

cat > status.sh << 'EOF'
#!/bin/bash
cd /opt/openclaw
echo "========================================="
echo "OpenClaw 虚拟员工服务状态"
echo "========================================="
docker-compose ps
echo ""
echo "容器日志（最近10行）："
docker-compose logs --tail=10
EOF

chmod +x start.sh stop.sh logs.sh status.sh

echo_info "✓ 管理脚本已生成"

# 生成 README
cat > README.md << 'EOF'
# OpenClaw 虚拟员工部署

## 快速开始

### 1. 配置 API Keys
编辑 `.env` 文件，填入你的 API Keys：
```bash
vim .env
```

### 2. 启动服务
```bash
bash start.sh
```

### 3. 查看状态
```bash
bash status.sh
```

### 4. 查看日志
```bash
# 查看所有服务日志
bash logs.sh

# 查看特定服务日志
bash logs.sh operation-agent
bash logs.sh product-agent
```

### 5. 停止服务
```bash
bash stop.sh
```

## 服务端口

- Gateway: 18789
- 各虚拟员工通过内网通信，不对外暴露端口

## 目录结构

```
/opt/openclaw/
├── agents/              # 虚拟员工工作区
│   ├── operation/       # 运营虚拟员工
│   ├── product/         # 产品虚拟员工
│   ├── development/     # 研发虚拟员工
│   └── testing/         # 测试虚拟员工
├── data/                # 持久化数据
├── logs/                # 日志文件
├── config/              # 配置文件
├── docker-compose.yml   # Docker 编排配置
├── .env                 # 环境变量
├── start.sh             # 启动脚本
├── stop.sh              # 停止脚本
├── logs.sh              # 日志查看脚本
└── status.sh            # 状态查看脚本
```

## 虚拟员工角色

| 角色 | 功能 | 权限 |
|------|------|------|
| 运营助手 | 内容创作、活动策划、用户运营 | 只读工作区 |
| 产品经理 | 需求分析、产品设计、竞品研究 | 只读工作区 |
| 开发工程师 | 代码编写、架构设计、问题解决 | 读写工作区 |
| 测试工程师 | 测试用例、自动化测试、质量保障 | 只读工作区 |

## 安全配置

- ✅ 所有虚拟员工运行在 Docker 容器内（隔离沙箱）
- ✅ 最小权限原则（按角色分配工具权限）
- ✅ 工作区访问控制（ro/rw）
- ✅ Gateway 仅监听本地（127.0.0.1）

## 故障排查

### 容器无法启动
```bash
# 查看详细日志
docker-compose logs operation-agent

# 检查配置
docker-compose config
```

### API Key 错误
```bash
# 编辑环境变量
vim .env

# 重启服务
bash stop.sh && bash start.sh
```

## 更多帮助

- OpenClaw 文档: https://docs.openclaw.ai
- 问题反馈: https://github.com/openclaw/openclaw/issues
EOF

echo_info "========================================="
echo_info "部署准备完成！"
echo_info "========================================="
echo_info ""
echo_info "下一步："
echo_info "1. 编辑 .env 文件，填入你的 API Keys"
echo_info "   vim /opt/openclaw/.env"
echo_info ""
echo_info "2. 启动服务"
echo_info "   cd /opt/openclaw && bash start.sh"
echo_info ""
echo_info "3. 查看状态"
echo_info "   bash status.sh"
echo_info ""
echo_warn "注意：首次启动会下载 Docker 镜像，可能需要几分钟"
echo_info ""
