#!/bin/bash
#==============================================================================
# 脚本名称: 2-start-local.sh
# 功能描述: 启动本地测试服务（agent 容器 + 宿主机 Gateway）
# 使用方法: ./2-start-local.sh
# 版本: V3.0
#==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_step()    { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BLUE}📍 $1${NC}\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

#------------------------------------------------------------------------------
# 步骤 1: 检查初始化
#------------------------------------------------------------------------------
print_step "步骤 1/4: 检查初始化状态"

if [ ! -f ".env.local" ]; then
    print_error ".env.local 不存在！请先运行: ./1-init-local.sh"
    exit 1
fi
print_success "环境变量文件存在"

# 加载环境变量
set -a
source .env.local
set +a

# 创建共享文件目录
SHARED_FILES_BASE="${SHARED_FILES_BASE:-$PROJECT_DIR/shared-files}"
mkdir -p "$SHARED_FILES_BASE"
export SHARED_FILES_BASE
export CONTAINER_FILES_BASE="${CONTAINER_FILES_BASE:-/root/.openclaw/workspace/shared-files}"

#------------------------------------------------------------------------------
# 步骤 2: 确保 Docker 网络存在
#------------------------------------------------------------------------------
print_step "步骤 2/4: 准备 Docker 网络"

if ! docker network inspect openclaw-network &> /dev/null; then
    docker network create openclaw-network
    print_success "openclaw-network 网络已创建"
else
    print_success "openclaw-network 网络已存在"
fi

#------------------------------------------------------------------------------
# 步骤 3: 启动 agent 容器
#------------------------------------------------------------------------------
print_step "步骤 3/4: 启动虚拟员工容器"

# 只启动 AGENT_*_ENABLE=true 的容器
ENABLED_SERVICES=""
for ROLE in operation product development testing service; do
    ENABLE_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_ENABLE"
    if [ "${!ENABLE_VAR}" = "true" ]; then
        ENABLED_SERVICES="$ENABLED_SERVICES openclaw-agent-${ROLE}"
    fi
done

if [ -z "$ENABLED_SERVICES" ]; then
    print_error "没有启用任何 Agent！请编辑 .env.local 设置 AGENT_*_ENABLE=true"
    exit 1
fi

docker compose -f ../config/docker-compose.agents.yml --env-file .env.local up -d --force-recreate --no-build $ENABLED_SERVICES
print_success "虚拟员工容器已启动"

#------------------------------------------------------------------------------
# 步骤 4: 启动宿主机 Gateway
#------------------------------------------------------------------------------
print_step "步骤 4/4: 启动宿主机 Gateway"

export DB_PATH="${DB_PATH:-$PROJECT_DIR/data/gateway/gateway.db}"
mkdir -p "$(dirname "$DB_PATH")"

"$PROJECT_DIR/scripts/start-gateway.sh"
print_success "Gateway 已启动"

echo ""
print_success "服务启动完成！"
echo ""
echo -e "${YELLOW}已启用的 Agent：${NC}"
for ROLE in operation product development testing service; do
    ENABLE_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_ENABLE"
    PORT_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_PORT"
    if [ "${!ENABLE_VAR}" = "true" ]; then
        echo "  ✅ ${ROLE}: http://localhost:${!PORT_VAR} → /:8000/${ROLE}/wecom/callback"
    fi
done
echo ""
echo -e "${YELLOW}常用命令：${NC}"
echo "  Gateway 日志:  tail -f /tmp/openclaw/flask.log"
echo "  运行测试:      ./3-test-local.sh"
echo "  停止服务:      ./4-stop-local.sh"
echo ""
