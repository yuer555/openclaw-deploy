#!/bin/bash
#==============================================================================
# 脚本名称: cleanup.sh
# 功能描述: 清理 OpenClaw 日志和临时文件
# 使用方法: ./cleanup.sh [--logs] [--docker] [--all]
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

#==============================================================================
# 配置
#==============================================================================

PROJECT_ROOT="/opt/openclaw"

# 确定项目根目录
if [ -d "production" ]; then
    PROJECT_ROOT=$(pwd)
fi

# 日志保留天数
LOG_RETENTION_DAYS=30

#==============================================================================
# 清理函数
#==============================================================================

cleanup_logs() {
    print_info "清理应用日志（保留 ${LOG_RETENTION_DAYS} 天）..."
    
    if [ -d "${PROJECT_ROOT}/logs" ]; then
        find "${PROJECT_ROOT}/logs" -name "*.log" -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true
        find "${PROJECT_ROOT}/logs" -name "*.log.*" -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true
        
        DELETED_COUNT=$(find "${PROJECT_ROOT}/logs" -type f -mtime +${LOG_RETENTION_DAYS} 2>/dev/null | wc -l)
        print_success "已清理 ${DELETED_COUNT} 个日志文件"
    else
        print_warning "日志目录不存在"
    fi
}

cleanup_docker_logs() {
    print_info "清理 Docker 日志..."
    
    # 清理停止的容器日志
    STOPPED_CONTAINERS=$(docker ps -a -q -f status=exited 2>/dev/null)
    if [ ! -z "$STOPPED_CONTAINERS" ]; then
        docker rm $STOPPED_CONTAINERS 2>/dev/null || true
        print_success "已清理停止的容器"
    fi
    
    # 清理未使用的镜像
    docker image prune -f > /dev/null 2>&1 || true
    print_success "已清理未使用的镜像"
    
    # 清理未使用的卷
    docker volume prune -f > /dev/null 2>&1 || true
    print_success "已清理未使用的卷"
}

cleanup_temp_files() {
    print_info "清理临时文件..."
    
    # 清理临时文件
    find "${PROJECT_ROOT}" -name "*.tmp" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}" -name "*.bak" -delete 2>/dev/null || true
    find "${PROJECT_ROOT}" -name "*~" -delete 2>/dev/null || true
    
    print_success "已清理临时文件"
}

cleanup_old_backups() {
    print_info "清理旧备份（保留最近 30 个）..."
    
    BACKUP_DIR="${PROJECT_ROOT}/backups"
    if [ -d "$BACKUP_DIR" ]; then
        cd "$BACKUP_DIR"
        ls -t backup-*.tar.gz 2>/dev/null | tail -n +31 | xargs -r rm -f
        print_success "已清理旧备份"
    else
        print_warning "备份目录不存在"
    fi
}

show_disk_usage() {
    print_info "磁盘使用情况："
    echo ""
    df -h "${PROJECT_ROOT}" | awk 'NR==1 || NR==2 {printf "   %-20s %-10s %-10s %-10s %-10s\n", $1, $2, $3, $4, $5}'
    echo ""
    
    print_info "目录大小："
    echo ""
    du -sh "${PROJECT_ROOT}/data" 2>/dev/null | awk '{printf "   数据目录:   %s\n", $1}'
    du -sh "${PROJECT_ROOT}/logs" 2>/dev/null | awk '{printf "   日志目录:   %s\n", $1}'
    du -sh "${PROJECT_ROOT}/backups" 2>/dev/null | awk '{printf "   备份目录:   %s\n", $1}'
    echo ""
}

#==============================================================================
# 主流程
#==============================================================================

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║              OpenClaw 清理工具 V1.4                          ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 显示当前状态
show_disk_usage

# 解析参数
CLEAN_LOGS=false
CLEAN_DOCKER=false
CLEAN_ALL=false

if [ $# -eq 0 ]; then
    # 无参数，显示菜单
    echo "请选择清理选项："
    echo ""
    echo "  1) 清理应用日志"
    echo "  2) 清理 Docker 资源"
    echo "  3) 清理临时文件"
    echo "  4) 清理旧备份"
    echo "  5) 全部清理"
    echo "  0) 退出"
    echo ""
    read -p "$(echo -e ${YELLOW}请输入选项 [0-5]: ${NC})" choice
    
    case $choice in
        1) CLEAN_LOGS=true ;;
        2) CLEAN_DOCKER=true ;;
        3) cleanup_temp_files ;;
        4) cleanup_old_backups ;;
        5) CLEAN_ALL=true ;;
        0) exit 0 ;;
        *) print_error "无效选项"; exit 1 ;;
    esac
else
    # 有参数，解析
    for arg in "$@"; do
        case $arg in
            --logs) CLEAN_LOGS=true ;;
            --docker) CLEAN_DOCKER=true ;;
            --all) CLEAN_ALL=true ;;
            *) print_error "未知参数: $arg"; exit 1 ;;
        esac
    done
fi

# 执行清理
if [ "$CLEAN_ALL" = true ]; then
    print_info "执行全部清理..."
    echo ""
    cleanup_logs
    cleanup_docker_logs
    cleanup_temp_files
    cleanup_old_backups
elif [ "$CLEAN_LOGS" = true ]; then
    cleanup_logs
elif [ "$CLEAN_DOCKER" = true ]; then
    cleanup_docker_logs
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_success "清理完成！"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 显示清理后的状态
show_disk_usage
