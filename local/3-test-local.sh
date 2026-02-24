#!/bin/bash
#==============================================================================
# 脚本名称: 3-test-local.sh
# 功能描述: 测试本地服务是否正常运行
# 使用方法: ./3-test-local.sh
# 作者: OpenClaw Team
# 版本: V1.4
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_step() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📍 $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

#==============================================================================
# 测试函数
#==============================================================================

test_passed=0
test_failed=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    print_info "测试: $test_name"
    
    if eval "$test_command"; then
        print_success "$test_name - 通过"
        ((test_passed++))
        return 0
    else
        print_error "$test_name - 失败"
        ((test_failed++))
        return 1
    fi
}

#==============================================================================
# 主流程
#==============================================================================

echo -e "${GREEN}🧪 OpenClaw 本地服务测试${NC}\n"

#------------------------------------------------------------------------------
# 步骤 1: 检查容器状态
#------------------------------------------------------------------------------
print_step "步骤 1/5: 检查容器状态"

run_test "Docker 容器运行检查" "docker ps | grep -q openclaw-local"

if [ $test_failed -gt 0 ]; then
    print_error "容器未运行！请先运行: ./2-start-local.sh"
    exit 1
fi

#------------------------------------------------------------------------------
# 步骤 2: 检查容器健康状态
#------------------------------------------------------------------------------
print_step "步骤 2/5: 检查容器健康状态"

# 获取容器 ID
CONTAINER_ID=$(docker ps -qf "name=openclaw-local")

if [ -z "$CONTAINER_ID" ]; then
    print_error "无法找到容器 ID"
    exit 1
fi

# 检查容器是否正常运行
run_test "容器运行状态" "docker inspect -f '{{.State.Running}}' $CONTAINER_ID | grep -q true"

#------------------------------------------------------------------------------
# 步骤 3: 检查服务端口
#------------------------------------------------------------------------------
print_step "步骤 3/5: 检查服务端口"

# 等待服务完全启动
print_info "等待服务启动（10秒）..."
sleep 10

# 检查端口
run_test "端口 3000 监听" "docker port $CONTAINER_ID | grep -q 3000" || print_warning "端口未暴露，这可能是正常的"

#------------------------------------------------------------------------------
# 步骤 4: 检查日志
#------------------------------------------------------------------------------
print_step "步骤 4/5: 检查日志输出"

print_info "查看最近的日志..."
docker logs $CONTAINER_ID --tail=20

echo ""
print_info "检查日志中是否有错误..."
if docker logs $CONTAINER_ID --tail=100 | grep -i "error\|fatal\|exception" | grep -v "test"; then
    print_warning "发现错误日志（可能需要关注）"
    ((test_failed++))
else
    print_success "日志检查通过 - 无明显错误"
    ((test_passed++))
fi

#------------------------------------------------------------------------------
# 步骤 5: API 测试（如果有）
#------------------------------------------------------------------------------
print_step "步骤 5/5: API 接口测试"

# 尝试访问健康检查端点
if command -v curl &> /dev/null; then
    run_test "健康检查接口" "curl -f -s http://localhost:3000/health > /dev/null 2>&1" || \
        print_warning "健康检查接口未响应（如果没有该接口，这是正常的）"
else
    print_warning "curl 未安装，跳过 API 测试"
fi

#==============================================================================
# 测试总结
#==============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📊 测试总结${NC}\n"
echo -e "   ✅ 通过: ${GREEN}$test_passed${NC}"
echo -e "   ❌ 失败: ${RED}$test_failed${NC}\n"

if [ $test_failed -eq 0 ]; then
    echo -e "${GREEN}🎉 所有测试通过！服务运行正常！${NC}\n"
    
    echo -e "${YELLOW}📋 下一步操作：${NC}"
    echo -e "   1. 查看完整日志: ${BLUE}docker logs openclaw-local -f${NC}"
    echo -e "   2. 进入容器调试: ${BLUE}docker exec -it openclaw-local /bin/bash${NC}"
    echo -e "   3. 停止服务: ${BLUE}./4-stop-local.sh${NC}\n"
    
    exit 0
else
    echo -e "${RED}⚠️  部分测试失败，请检查日志${NC}\n"
    
    echo -e "${YELLOW}🔧 调试建议：${NC}"
    echo -e "   1. 查看详细日志: ${BLUE}docker logs openclaw-local --tail=100${NC}"
    echo -e "   2. 检查配置文件: ${BLUE}cat .env.local${NC}"
    echo -e "   3. 重新启动: ${BLUE}./4-stop-local.sh && ./2-start-local.sh${NC}\n"
    
    exit 1
fi
