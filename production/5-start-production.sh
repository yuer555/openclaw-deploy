#!/bin/bash
#==============================================================================
# 脚本名称: 5-start-production.sh
# 功能描述: 启动生产服务（Agent 容器 + 宿主机 Gateway）
# 使用方法: ./5-start-production.sh
# 执行位置: 服务器
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

if [ ! -f ".env.prod" ]; then
    print_error ".env.prod 不存在！请先运行: ./3-deploy-production.sh"
    exit 1
fi

# 加载环境变量
set -a
source .env.prod
set +a

# 创建共享文件目录
SHARED_FILES_BASE="${SHARED_FILES_BASE:-/opt/openclaw/shared-files}"
mkdir -p "$SHARED_FILES_BASE"
export SHARED_FILES_BASE
export CONTAINER_FILES_BASE="${CONTAINER_FILES_BASE:-/root/.openclaw/workspace/shared-files}"

#------------------------------------------------------------------------------
# 步骤 1: 停止已有服务
#------------------------------------------------------------------------------
print_step "步骤 1/4: 停止已有服务"

"$PROJECT_DIR/scripts/stop-gateway.sh" 2>/dev/null || true
# 停止所有 profiles 的容器
docker compose -f docker-compose.prod.yml --env-file .env.prod \
    --profile operation --profile product --profile development --profile testing --profile service \
    down 2>/dev/null || true
print_success "已有服务已停止"

#------------------------------------------------------------------------------
# 步骤 2: 确保 Docker 网络存在
#------------------------------------------------------------------------------
print_step "步骤 2/4: 准备 Docker 网络"

if ! docker network inspect openclaw-prod-net &> /dev/null; then
    docker network create --subnet=172.20.0.0/24 openclaw-prod-net
    print_success "openclaw-prod-net 网络已创建"
else
    print_success "openclaw-prod-net 网络已存在"
fi

#------------------------------------------------------------------------------
# 步骤 3: 启动 Agent 容器（只启动 enabled 的）
#------------------------------------------------------------------------------
print_step "步骤 3/4: 启动虚拟员工容器"

# 构建 profiles 参数：只启动 AGENT_*_ENABLE=true 的
PROFILES=""
for ROLE in operation product development testing service; do
    ENABLE_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_ENABLE"
    if [ "${!ENABLE_VAR}" = "true" ]; then
        PROFILES="$PROFILES --profile $ROLE"
    fi
done

if [ -z "$PROFILES" ]; then
    print_error "没有启用任何 Agent！请编辑 .env.prod 设置 AGENT_*_ENABLE=true"
    exit 1
fi

docker compose -f docker-compose.prod.yml --env-file .env.prod $PROFILES up -d --force-recreate --no-build
print_success "虚拟员工容器已启动"

#------------------------------------------------------------------------------
# 步骤 4: 启动宿主机 Gateway
#------------------------------------------------------------------------------
print_step "步骤 4/4: 启动宿主机 Gateway"

export DB_PATH="${DB_PATH:-/opt/openclaw/data/gateway/gateway.db}"
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
        echo "  ✅ ${ROLE}: http://localhost:${!PORT_VAR} → :8000/${ROLE}/wecom/callback"
    fi
done
echo ""
echo -e "${YELLOW}常用命令：${NC}"
echo "  Gateway 日志:  tail -f /tmp/openclaw/flask.log"
echo "  Agent 日志:    docker logs openclaw-agent-{role} -f"
echo "  健康检查:      ./6-health-check.sh"
echo "  停止服务:      docker compose -f docker-compose.prod.yml down && ../scripts/stop-gateway.sh"
echo ""
