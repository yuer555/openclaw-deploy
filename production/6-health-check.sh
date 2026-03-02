#!/bin/bash
#==============================================================================
# 脚本名称: 6-health-check.sh
# 功能描述: 检查生产服务健康状态（多 Agent）
# 使用方法: ./6-health-check.sh
# 执行位置: 服务器
# 版本: V3.0
#==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error()   { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_step()    { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BLUE}📍 $1${NC}\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

# 加载环境变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
if [ -f ".env.prod" ]; then
    set -a; source .env.prod; set +a
fi

passed=0
failed=0

echo -e "${GREEN}🔍 OpenClaw 生产环境健康检查${NC}\n"

#------------------------------------------------------------------------------
# 步骤 1: 容器状态（只检查 enabled agents）
#------------------------------------------------------------------------------
print_step "1/4: 容器状态"

for ROLE in operation product development testing service; do
    ENABLE_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_ENABLE"
    if [ "${!ENABLE_VAR}" = "true" ]; then
        NAME="openclaw-agent-${ROLE}"
        if docker ps --format '{{.Names}}' | grep -q "^${NAME}$"; then
            print_success "容器运行中: $NAME"
            ((passed++))
        else
            print_error "容器未运行: $NAME"
            ((failed++))
        fi
    fi
done

#------------------------------------------------------------------------------
# 步骤 2: Gateway 健康检查
#------------------------------------------------------------------------------
print_step "2/4: Gateway 健康检查"

if curl -sf "http://localhost:8000/health" > /dev/null 2>&1; then
    print_success "Gateway :8000 健康检查通过"
    ((passed++))
else
    print_error "Gateway :8000 健康检查失败"
    ((failed++))
fi

#------------------------------------------------------------------------------
# 步骤 3: Agent 端口健康检查
#------------------------------------------------------------------------------
print_step "3/4: Agent 健康检查"

for ROLE in operation product development testing service; do
    ENABLE_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_ENABLE"
    PORT_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_PORT"
    if [ "${!ENABLE_VAR}" = "true" ]; then
        PORT="${!PORT_VAR}"
        if curl -sf "http://localhost:${PORT}/health" > /dev/null 2>&1; then
            print_success "Agent ${ROLE} :${PORT} 健康检查通过"
            ((passed++))
        else
            print_warning "Agent ${ROLE} :${PORT} 健康检查未通过（可能尚在启动中）"
            ((failed++))
        fi
    fi
done

#------------------------------------------------------------------------------
# 步骤 4: 资源使用
#------------------------------------------------------------------------------
print_step "4/4: 资源使用"

echo -e "${YELLOW}系统资源：${NC}"
if command -v free &> /dev/null; then
    echo "  内存: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
fi
echo "  磁盘: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " 已用)"}')"
echo ""
echo -e "${YELLOW}容器资源：${NC}"
docker stats --no-stream --format "  {{.Name}}\tCPU:{{.CPUPerc}}\tMEM:{{.MemUsage}}" \
    2>/dev/null | grep "openclaw-" || echo "  无数据"

#------------------------------------------------------------------------------
# 总结
#------------------------------------------------------------------------------
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ✅ 通过: ${GREEN}$passed${NC}  ❌ 失败: ${RED}$failed${NC}"
echo ""

if [ "$failed" -eq 0 ]; then
    print_success "服务运行正常！"
else
    print_error "存在 $failed 个异常，请检查日志："
    echo "  Gateway:  tail -f /tmp/openclaw/flask.log"
    echo "  Agent:    docker logs openclaw-agent-{role} --tail=50"
fi
echo ""
