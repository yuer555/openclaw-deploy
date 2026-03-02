#!/bin/bash
#==============================================================================
# 脚本名称: 3-test-local.sh
# 功能描述: 测试本地服务健康状态
# 使用方法: ./3-test-local.sh
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
cd "$SCRIPT_DIR"

# 加载环境变量
if [ -f ".env.local" ]; then
    set -a; source .env.local; set +a
fi

test_passed=0
test_failed=0

echo -e "${GREEN}🧪 OpenClaw 本地服务测试${NC}\n"

#------------------------------------------------------------------------------
# 步骤 1: 容器状态（只检查 enabled agents）
#------------------------------------------------------------------------------
print_step "步骤 1/3: 检查容器状态"

for ROLE in operation product development testing service; do
    ENABLE_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_ENABLE"
    if [ "${!ENABLE_VAR}" = "true" ]; then
        NAME="openclaw-agent-${ROLE}"
        if docker ps --format '{{.Names}}' | grep -q "^${NAME}$"; then
            print_success "容器运行中: $NAME"
            ((test_passed++))
        else
            print_error "容器未运行: $NAME"
            ((test_failed++))
        fi
    fi
done

#------------------------------------------------------------------------------
# 步骤 2: 健康检查
#------------------------------------------------------------------------------
print_step "步骤 2/3: 健康检查"

# Gateway
if curl -sf "http://localhost:8000/health" > /dev/null 2>&1; then
    print_success "Gateway :8000 健康检查通过"
    ((test_passed++))
else
    print_error "Gateway :8000 健康检查失败"
    ((test_failed++))
fi

# Agent 端口
for ROLE in operation product development testing service; do
    ENABLE_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_ENABLE"
    PORT_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_PORT"
    if [ "${!ENABLE_VAR}" = "true" ]; then
        PORT="${!PORT_VAR}"
        if curl -sf "http://localhost:${PORT}/health" > /dev/null 2>&1; then
            print_success "Agent ${ROLE} :${PORT} 健康检查通过"
            ((test_passed++))
        else
            print_warning "Agent ${ROLE} :${PORT} 健康检查未通过（可能尚在启动中）"
            ((test_failed++))
        fi
    fi
done

#------------------------------------------------------------------------------
# 步骤 3: 回调路由检查
#------------------------------------------------------------------------------
print_step "步骤 3/3: 回调路由检查"

for ROLE in operation product development testing service; do
    ENABLE_VAR="AGENT_$(echo $ROLE | tr '[:lower:]' '[:upper:]')_ENABLE"
    if [ "${!ENABLE_VAR}" = "true" ]; then
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8000/${ROLE}/wecom/callback" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" != "000" ] && [ "$HTTP_CODE" != "404" ]; then
            print_success "路由 /${ROLE}/wecom/callback 可达 (HTTP $HTTP_CODE)"
            ((test_passed++))
        else
            print_warning "路由 /${ROLE}/wecom/callback 不可达 (HTTP $HTTP_CODE)"
            ((test_failed++))
        fi
    fi
done

#------------------------------------------------------------------------------
# 测试总结
#------------------------------------------------------------------------------
echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📊 测试总结${NC}"
echo -e "   ✅ 通过: ${GREEN}$test_passed${NC}"
echo -e "   ❌ 失败: ${RED}$test_failed${NC}"
echo ""

if [ $test_failed -eq 0 ]; then
    print_success "所有测试通过！"
else
    print_warning "部分测试失败，查看日志："
    echo "  tail -f /tmp/openclaw/flask.log"
    echo "  docker logs openclaw-agent-{role} --tail=50"
fi
echo ""
