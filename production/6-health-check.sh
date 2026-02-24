#!/bin/bash
#==============================================================================
# 脚本名称: 6-health-check.sh
# 功能描述: 检查 OpenClaw 生产服务健康状态
# 使用方法: ./6-health-check.sh
# 执行位置: 🚀 服务器
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
# 测试统计
#==============================================================================

test_passed=0
test_failed=0
test_warnings=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    local is_critical="${3:-true}"
    
    print_info "检查: $test_name"
    
    if eval "$test_command" > /dev/null 2>&1; then
        print_success "$test_name - 通过"
        ((test_passed++))
        return 0
    else
        if [ "$is_critical" == "true" ]; then
            print_error "$test_name - 失败"
            ((test_failed++))
        else
            print_warning "$test_name - 警告"
            ((test_warnings++))
        fi
        return 1
    fi
}

#==============================================================================
# 主流程
#==============================================================================

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║              OpenClaw 健康检查脚本 V1.4                       ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

#------------------------------------------------------------------------------
# 系统检查
#------------------------------------------------------------------------------
print_step "1/6: 系统环境检查"

run_test "Docker 运行状态" "docker info" true
run_test "Docker Compose 可用" "docker compose version" true
run_test "磁盘空间充足 (>10GB)" "[ \$(df / | awk 'NR==2 {print \$4}') -gt 10000000 ]" false

#------------------------------------------------------------------------------
# 容器检查
#------------------------------------------------------------------------------
print_step "2/6: 容器状态检查"

run_test "OpenClaw 主容器运行" "docker ps | grep -q openclaw-prod" true

if [ $? -eq 0 ]; then
    CONTAINER_ID=$(docker ps -qf "name=openclaw-prod")
    run_test "容器健康状态" "docker inspect -f '{{.State.Running}}' $CONTAINER_ID | grep -q true" true
    run_test "容器内存正常" "[ \$(docker stats --no-stream --format '{{.MemPerc}}' $CONTAINER_ID | sed 's/%//') -lt 90 ]" false
fi

# 检查 Nginx（如果有）
if docker ps | grep -q "openclaw-nginx"; then
    run_test "Nginx 容器运行" "docker ps | grep -q openclaw-nginx" false
fi

#------------------------------------------------------------------------------
# 网络检查
#------------------------------------------------------------------------------
print_step "3/6: 网络连接检查"

run_test "端口 80 监听" "netstat -tuln | grep -q ':80 '" false
run_test "端口 443 监听" "netstat -tuln | grep -q ':443 '" false

# 测试 HTTP 接口
if command -v curl &> /dev/null; then
    run_test "本地 HTTP 响应" "curl -f -s http://localhost:80 > /dev/null" false
fi

#------------------------------------------------------------------------------
# 日志检查
#------------------------------------------------------------------------------
print_step "4/6: 日志检查"

print_info "检查最近日志中的错误..."
if docker logs openclaw-production --tail=100 2>&1 | grep -i "error\|fatal\|exception" | grep -v "test" > /dev/null; then
    print_warning "发现错误日志"
    docker logs openclaw-production --tail=20 2>&1 | grep -i "error\|fatal" | head -5
    ((test_warnings++))
else
    print_success "日志检查 - 无明显错误"
    ((test_passed++))
fi

#------------------------------------------------------------------------------
# 配置检查
#------------------------------------------------------------------------------
print_step "5/6: 配置文件检查"

run_test "环境配置文件存在" "[ -f .env.prod ]" true
run_test "Docker Compose 配置存在" "[ -f docker-compose.prod.yml ]" true
run_test "数据目录存在" "[ -d /opt/openclaw/data ]" true
run_test "日志目录存在" "[ -d /opt/openclaw/logs ]" true

# SSL 证书检查
if [ -f "/opt/openclaw/config/ssl/fullchain.pem" ]; then
    run_test "SSL 证书存在" "[ -f /opt/openclaw/config/ssl/fullchain.pem ]" false
    
    # 检查证书过期时间
    EXPIRY_DATE=$(openssl x509 -enddate -noout -in /opt/openclaw/config/ssl/fullchain.pem 2>/dev/null | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
    
    if [ $DAYS_LEFT -gt 0 ]; then
        print_success "SSL 证书有效 (剩余 $DAYS_LEFT 天)"
        ((test_passed++))
    else
        print_warning "SSL 证书即将过期或已过期"
        ((test_warnings++))
    fi
fi

#------------------------------------------------------------------------------
# 资源使用情况
#------------------------------------------------------------------------------
print_step "6/6: 资源使用情况"

echo -e "${YELLOW}💻 系统资源：${NC}"
echo -e "   CPU: $(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1"%"}')"
echo -e "   内存: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
echo -e "   磁盘: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 " 已用)"}')"

echo -e "\n${YELLOW}🐳 Docker 容器资源：${NC}"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep openclaw || echo "   无运行中的容器"

#==============================================================================
# 测试总结
#==============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📊 健康检查总结${NC}\n"
echo -e "   ✅ 通过: ${GREEN}$test_passed${NC}"
echo -e "   ⚠️  警告: ${YELLOW}$test_warnings${NC}"
echo -e "   ❌ 失败: ${RED}$test_failed${NC}\n"

# 综合评分
total_tests=$((test_passed + test_warnings + test_failed))
health_score=$((test_passed * 100 / total_tests))

echo -e "${YELLOW}健康评分: ${NC}"
if [ $health_score -ge 90 ]; then
    echo -e "   ${GREEN}$health_score/100 - 优秀 ✨${NC}"
    exit_code=0
elif [ $health_score -ge 70 ]; then
    echo -e "   ${YELLOW}$health_score/100 - 良好 👍${NC}"
    exit_code=0
elif [ $health_score -ge 50 ]; then
    echo -e "   ${YELLOW}$health_score/100 - 一般 ⚠️${NC}"
    exit_code=1
else
    echo -e "   ${RED}$health_score/100 - 需要关注 ❗${NC}"
    exit_code=1
fi

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ $test_failed -gt 0 ]; then
    echo -e "${RED}⚠️  发现严重问题，请检查！${NC}\n"
    print_info "建议操作："
    print_info "  1. 查看详细日志: docker logs openclaw-production --tail=100"
    print_info "  2. 重启服务: docker compose -f docker-compose.prod.yml restart"
    print_info "  3. 查看文档: ../docs/06-故障排查.md"
elif [ $test_warnings -gt 0 ]; then
    echo -e "${YELLOW}⚠️  服务运行中，但有警告项${NC}\n"
else
    echo -e "${GREEN}🎉 所有检查通过！服务运行正常！${NC}\n"
fi

echo ""
exit $exit_code
