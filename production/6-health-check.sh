#!/bin/bash
#==============================================================================
# 脚本名称: 6-health-check.sh
# 功能描述: 检查生产服务健康状态（gateway + 5 个 agent 容器）
# 使用方法: ./6-health-check.sh
# 执行位置: 服务器
# 版本: V2.0
#==============================================================================

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

passed=0
failed=0

check_container() {
    local name="$1"
    if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
        print_success "容器运行中: $name"
        ((passed++))
    else
        print_error "容器未运行: $name"
        ((failed++))
    fi
}

check_http() {
    local name="$1"
    local url="$2"
    if curl -sf "$url" > /dev/null 2>&1; then
        print_success "健康检查通过: $name ($url)"
        ((passed++))
    else
        print_error "健康检查失败: $name ($url)"
        ((failed++))
    fi
}

echo -e "${GREEN}🔍 OpenClaw 生产环境健康检查${NC}\n"

#------------------------------------------------------------------------------
# 步骤 1: 容器状态
#------------------------------------------------------------------------------
print_step "1/3: 容器状态"

check_container "openclaw-gateway"
check_container "openclaw-agent-operation"
check_container "openclaw-agent-product"
check_container "openclaw-agent-development"
check_container "openclaw-agent-testing"
check_container "openclaw-agent-service"

#------------------------------------------------------------------------------
# 步骤 2: HTTP 健康检查
#------------------------------------------------------------------------------
print_step "2/3: HTTP 健康检查"

# Gateway 通过宿主机端口检查
check_http "Gateway        :8000" "http://localhost:8000/health"

# Agent 通过 Docker 固定 IP 检查
check_http "Agent operation 172.20.0.11" "http://172.20.0.11:18789/health"
check_http "Agent product   172.20.0.12" "http://172.20.0.12:18789/health"
check_http "Agent develop   172.20.0.13" "http://172.20.0.13:18789/health"
check_http "Agent testing   172.20.0.14" "http://172.20.0.14:18789/health"
check_http "Agent service   172.20.0.15" "http://172.20.0.15:18789/health"

#------------------------------------------------------------------------------
# 步骤 3: 资源使用
#------------------------------------------------------------------------------
print_step "3/3: 资源使用"

echo -e "${YELLOW}系统资源：${NC}"
echo "  内存: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
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
    print_success "所有服务运行正常！"
else
    print_error "存在 $failed 个异常，请检查日志："
    echo "  docker logs openclaw-gateway --tail=50"
fi
echo ""
