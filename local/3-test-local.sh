#!/bin/bash
#==============================================================================
# 脚本名称: 3-test-local.sh
# 功能描述: 测试本地服务健康状态和 AI 路由
# 使用方法: ./3-test-local.sh
# 版本: V2.0
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

test_passed=0
test_failed=0

check() {
    local name="$1"
    local url="$2"
    if curl -sf "$url" > /dev/null 2>&1; then
        print_success "$name"
        ((test_passed++))
    else
        print_error "$name - 无响应 ($url)"
        ((test_failed++))
    fi
}

echo -e "${GREEN}🧪 OpenClaw 本地服务测试${NC}\n"

#------------------------------------------------------------------------------
# 步骤 1: 容器状态
#------------------------------------------------------------------------------
print_step "步骤 1/3: 检查容器状态"

for NAME in openclaw-gateway openclaw-agent-operation openclaw-agent-product \
            openclaw-agent-development openclaw-agent-testing openclaw-agent-service; do
    if docker ps --format '{{.Names}}' | grep -q "^${NAME}$"; then
        print_success "容器运行中: $NAME"
        ((test_passed++))
    else
        print_error "容器未运行: $NAME"
        ((test_failed++))
    fi
done

#------------------------------------------------------------------------------
# 步骤 2: 健康检查
#------------------------------------------------------------------------------
print_step "步骤 2/3: 健康检查"

check "Gateway        :8000" "http://localhost:8000/health"
check "Agent operation:18791" "http://localhost:18791/health"
check "Agent product  :18792" "http://localhost:18792/health"
check "Agent develop  :18793" "http://localhost:18793/health"
check "Agent testing  :18794" "http://localhost:18794/health"
check "Agent service  :18795" "http://localhost:18795/health"

#------------------------------------------------------------------------------
# 步骤 3: 测试消息发送（AI 路由）
#------------------------------------------------------------------------------
print_step "步骤 3/3: 测试消息发送"

print_info "发送测试消息到 Gateway /test/send ..."
RESPONSE=$(curl -sf -X POST http://localhost:8000/test/send \
    -H "Content-Type: application/json" \
    -d '{"user_id":"test-user","content":"帮我写个测试用例"}' 2>&1 || echo "FAILED")

if echo "$RESPONSE" | grep -q '"success"'; then
    print_success "消息发送接口响应正常"
    echo "  响应: $RESPONSE"
    ((test_passed++))
else
    print_warning "消息发送接口未响应或返回错误（agent 可能尚未就绪）"
    echo "  响应: $RESPONSE"
    ((test_failed++))
fi

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
    echo "  docker logs openclaw-gateway --tail=50"
fi
echo ""
