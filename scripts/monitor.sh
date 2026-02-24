#!/bin/bash
#==============================================================================
# 脚本名称: monitor.sh
# 功能描述: 监控 OpenClaw 服务状态和系统资源
# 使用方法: ./monitor.sh [--watch] [--alert]
# 作者: OpenClaw Team
# 版本: V1.4
#==============================================================================

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

#==============================================================================
# 配置
#==============================================================================

# 告警阈值
CPU_THRESHOLD=80
MEMORY_THRESHOLD=80
DISK_THRESHOLD=80

# 监控间隔（秒）
WATCH_INTERVAL=5

#==============================================================================
# 监控函数
#==============================================================================

check_system() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}   系统资源监控${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # CPU 使用率
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    CPU_USAGE_INT=${CPU_USAGE%.*}
    
    echo -n "   💻 CPU 使用率: "
    if [ "$CPU_USAGE_INT" -gt "$CPU_THRESHOLD" ]; then
        echo -e "${RED}${CPU_USAGE}%${NC} ⚠️  告警"
    elif [ "$CPU_USAGE_INT" -gt 50 ]; then
        echo -e "${YELLOW}${CPU_USAGE}%${NC}"
    else
        echo -e "${GREEN}${CPU_USAGE}%${NC}"
    fi
    
    # 内存使用率
    MEMORY_INFO=$(free | grep Mem)
    MEMORY_TOTAL=$(echo $MEMORY_INFO | awk '{print $2}')
    MEMORY_USED=$(echo $MEMORY_INFO | awk '{print $3}')
    MEMORY_USAGE=$((MEMORY_USED * 100 / MEMORY_TOTAL))
    
    echo -n "   🧠 内存使用率: "
    if [ "$MEMORY_USAGE" -gt "$MEMORY_THRESHOLD" ]; then
        echo -e "${RED}${MEMORY_USAGE}%${NC} ⚠️  告警"
    elif [ "$MEMORY_USAGE" -gt 60 ]; then
        echo -e "${YELLOW}${MEMORY_USAGE}%${NC}"
    else
        echo -e "${GREEN}${MEMORY_USAGE}%${NC}"
    fi
    echo -e "      已用: $(free -h | awk '/^Mem:/ {print $3}') / 总计: $(free -h | awk '/^Mem:/ {print $2}')"
    
    # 磁盘使用率
    DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    echo -n "   💾 磁盘使用率: "
    if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
        echo -e "${RED}${DISK_USAGE}%${NC} ⚠️  告警"
    elif [ "$DISK_USAGE" -gt 70 ]; then
        echo -e "${YELLOW}${DISK_USAGE}%${NC}"
    else
        echo -e "${GREEN}${DISK_USAGE}%${NC}"
    fi
    echo -e "      已用: $(df -h / | awk 'NR==2 {print $3}') / 总计: $(df -h / | awk 'NR==2 {print $2}')"
    
    echo ""
}

check_docker() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}   Docker 服务监控${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 检查 Docker 服务
    if systemctl is-active --quiet docker; then
        print_success "Docker 服务运行中"
    else
        print_error "Docker 服务未运行"
    fi
    
    # 检查容器状态
    if docker ps | grep -q "openclaw"; then
        print_success "OpenClaw 容器运行中"
        echo ""
        echo "   容器列表："
        docker ps --filter "name=openclaw" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | sed 's/^/   /'
    else
        print_warning "OpenClaw 容器未运行"
    fi
    
    echo ""
}

check_container_resources() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}   容器资源使用${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if docker ps | grep -q "openclaw"; then
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" \
            $(docker ps --filter "name=openclaw" -q) | sed 's/^/   /'
    else
        print_warning "没有运行中的容器"
    fi
    
    echo ""
}

check_services() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}   服务可用性检查${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 检查端口
    echo -n "   🌐 端口 80: "
    if netstat -tuln | grep -q ":80 "; then
        print_success "监听中"
    else
        print_warning "未监听"
    fi
    
    echo -n "   🔒 端口 443: "
    if netstat -tuln | grep -q ":443 "; then
        print_success "监听中"
    else
        print_warning "未监听"
    fi
    
    # 检查 HTTP 接口
    echo -n "   🔗 HTTP 接口: "
    if curl -f -s http://localhost/health > /dev/null 2>&1; then
        print_success "正常"
    else
        print_error "异常"
    fi
    
    echo ""
}

check_logs() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}   最近错误日志${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if docker ps | grep -q "openclaw-production"; then
        ERROR_COUNT=$(docker logs openclaw-production --tail=100 2>&1 | grep -i "error\|fatal\|exception" | wc -l)
        
        if [ "$ERROR_COUNT" -gt 0 ]; then
            print_warning "发现 ${ERROR_COUNT} 条错误日志"
            echo ""
            docker logs openclaw-production --tail=100 2>&1 | grep -i "error\|fatal" | tail -5 | sed 's/^/   /'
        else
            print_success "无错误日志"
        fi
    else
        print_warning "容器未运行，无法检查日志"
    fi
    
    echo ""
}

show_summary() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}   监控总结${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 计算健康评分
    HEALTH_SCORE=100
    
    # CPU 告警扣分
    if [ "$CPU_USAGE_INT" -gt "$CPU_THRESHOLD" ]; then
        HEALTH_SCORE=$((HEALTH_SCORE - 20))
    fi
    
    # 内存告警扣分
    if [ "$MEMORY_USAGE" -gt "$MEMORY_THRESHOLD" ]; then
        HEALTH_SCORE=$((HEALTH_SCORE - 20))
    fi
    
    # 磁盘告警扣分
    if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
        HEALTH_SCORE=$((HEALTH_SCORE - 20))
    fi
    
    # 容器未运行扣分
    if ! docker ps | grep -q "openclaw"; then
        HEALTH_SCORE=$((HEALTH_SCORE - 40))
    fi
    
    echo -n "   健康评分: "
    if [ "$HEALTH_SCORE" -ge 80 ]; then
        echo -e "${GREEN}${HEALTH_SCORE}/100 ✨ 优秀${NC}"
    elif [ "$HEALTH_SCORE" -ge 60 ]; then
        echo -e "${YELLOW}${HEALTH_SCORE}/100 👍 良好${NC}"
    elif [ "$HEALTH_SCORE" -ge 40 ]; then
        echo -e "${YELLOW}${HEALTH_SCORE}/100 ⚠️  需要关注${NC}"
    else
        echo -e "${RED}${HEALTH_SCORE}/100 ❗ 严重告警${NC}"
    fi
    
    echo -e "   监控时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

#==============================================================================
# 主流程
#==============================================================================

clear

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║              OpenClaw 服务监控工具 V1.4                      ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 解析参数
WATCH_MODE=false
ALERT_MODE=false

for arg in "$@"; do
    case $arg in
        --watch) WATCH_MODE=true ;;
        --alert) ALERT_MODE=true ;;
        *) ;;
    esac
done

# 监控循环
if [ "$WATCH_MODE" = true ]; then
    print_info "监控模式（每 ${WATCH_INTERVAL} 秒刷新，按 Ctrl+C 退出）"
    echo ""
    
    while true; do
        clear
        echo -e "${GREEN}OpenClaw 实时监控 - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
        echo ""
        check_system
        check_docker
        check_container_resources
        sleep $WATCH_INTERVAL
    done
else
    # 单次检查
    check_system
    check_docker
    check_container_resources
    check_services
    check_logs
    show_summary
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    print_info "提示: 使用 --watch 参数开启实时监控"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
fi
