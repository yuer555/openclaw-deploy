#!/bin/bash
#==============================================================================
# 脚本名称: update.sh
# 功能描述: OpenClaw 自动化更新脚本
# 使用方法: ./update.sh [--check|--apply|--force]
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
if [ -d "production" ]; then
    PROJECT_ROOT=$(pwd)
fi

BACKUP_DIR="${PROJECT_ROOT}/backups"
UPDATE_LOG="${PROJECT_ROOT}/logs/update.log"
CURRENT_VERSION="V1.4"

#==============================================================================
# 功能函数
#==============================================================================

log_message() {
    local message="$1"
    mkdir -p "$(dirname $UPDATE_LOG)"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$UPDATE_LOG"
}

check_docker_running() {
    if ! docker ps | grep -q "openclaw"; then
        return 1
    fi
    return 0
}

get_container_version() {
    docker exec openclaw-production cat /VERSION 2>/dev/null || echo "unknown"
}

check_for_updates() {
    print_info "检查更新..."
    
    # 检查 Docker Hub 最新版本
    LATEST_VERSION=$(curl -s "https://registry.hub.docker.com/v2/repositories/openclaw/openclaw/tags" | \
        jq -r '.results[0].name' 2>/dev/null || echo "unknown")
    
    if [ "$LATEST_VERSION" = "unknown" ]; then
        print_warning "无法获取最新版本信息"
        return 1
    fi
    
    print_info "当前版本: ${CURRENT_VERSION}"
    print_info "最新版本: ${LATEST_VERSION}"
    
    if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
        print_success "已是最新版本"
        return 1
    else
        print_warning "发现新版本: ${LATEST_VERSION}"
        return 0
    fi
}

backup_before_update() {
    print_info "更新前备份..."
    
    local backup_name="before-update-$(date +%Y%m%d-%H%M%S)"
    
    if [ -f "${PROJECT_ROOT}/scripts/backup.sh" ]; then
        bash "${PROJECT_ROOT}/scripts/backup.sh" "$backup_name"
        print_success "备份完成: ${backup_name}"
        echo "$backup_name"
    else
        print_warning "备份脚本不存在，跳过备份"
        echo ""
    fi
}

pull_latest_image() {
    print_info "拉取最新镜像..."
    
    cd "${PROJECT_ROOT}/production"
    
    docker compose -f docker-compose.prod.yml pull openclaw-production
    
    if [ $? -eq 0 ]; then
        print_success "镜像拉取成功"
        return 0
    else
        print_error "镜像拉取失败"
        return 1
    fi
}

stop_services() {
    print_info "停止服务..."
    
    cd "${PROJECT_ROOT}/production"
    
    docker compose -f docker-compose.prod.yml down
    
    if [ $? -eq 0 ]; then
        print_success "服务已停止"
        return 0
    else
        print_error "服务停止失败"
        return 1
    fi
}

start_services() {
    print_info "启动服务..."
    
    cd "${PROJECT_ROOT}/production"
    
    docker compose -f docker-compose.prod.yml up -d
    
    if [ $? -eq 0 ]; then
        print_success "服务已启动"
        return 0
    else
        print_error "服务启动失败"
        return 1
    fi
}

verify_update() {
    print_info "验证更新..."
    
    # 等待服务启动
    sleep 10
    
    # 检查容器状态
    if ! check_docker_running; then
        print_error "容器未运行"
        return 1
    fi
    
    # 检查健康状态
    local health_status=$(docker inspect --format='{{.State.Health.Status}}' openclaw-production 2>/dev/null || echo "none")
    
    if [ "$health_status" = "healthy" ] || [ "$health_status" = "none" ]; then
        print_success "服务运行正常"
        return 0
    else
        print_warning "服务状态: ${health_status}"
        return 1
    fi
}

send_update_alert() {
    local status="$1"
    local message="$2"
    
    if [ -f "${PROJECT_ROOT}/scripts/alert.sh" ]; then
        if [ "$status" = "success" ]; then
            bash "${PROJECT_ROOT}/scripts/alert.sh" --wecom "OpenClaw 更新成功: ${message}" "info"
        else
            bash "${PROJECT_ROOT}/scripts/alert.sh" --wecom "OpenClaw 更新失败: ${message}" "error"
        fi
    fi
}

#==============================================================================
# 主流程
#==============================================================================

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║            OpenClaw 自动化更新工具 V1.4                      ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 解析参数
ACTION="check"

case "${1:-check}" in
    --check)
        ACTION="check"
        ;;
    --apply)
        ACTION="apply"
        ;;
    --force)
        ACTION="force"
        ;;
    *)
        echo "使用方法: $0 [--check|--apply|--force]"
        echo ""
        echo "选项:"
        echo "  --check  检查更新（默认）"
        echo "  --apply  检查并应用更新"
        echo "  --force  强制更新（跳过版本检查）"
        exit 1
        ;;
esac

log_message "开始更新流程: ${ACTION}"

#------------------------------------------------------------------------------
# 检查更新
#------------------------------------------------------------------------------

if [ "$ACTION" = "check" ]; then
    check_for_updates
    exit $?
fi

#------------------------------------------------------------------------------
# 应用更新
#------------------------------------------------------------------------------

if [ "$ACTION" = "apply" ]; then
    # 检查是否有更新
    if ! check_for_updates; then
        print_info "无需更新"
        exit 0
    fi
    
    # 确认更新
    read -p "$(echo -e ${YELLOW}是否继续更新？[y/N]: ${NC})" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "已取消更新"
        exit 0
    fi
fi

#------------------------------------------------------------------------------
# 强制更新
#------------------------------------------------------------------------------

print_warning "开始更新流程..."

# 1. 备份
BACKUP_NAME=$(backup_before_update)
log_message "备份完成: ${BACKUP_NAME}"

# 2. 拉取镜像
if ! pull_latest_image; then
    print_error "镜像拉取失败，更新中止"
    send_update_alert "failure" "镜像拉取失败"
    exit 1
fi
log_message "镜像拉取成功"

# 3. 停止服务
if ! stop_services; then
    print_error "服务停止失败"
    send_update_alert "failure" "服务停止失败"
    exit 1
fi
log_message "服务已停止"

# 4. 启动服务
if ! start_services; then
    print_error "服务启动失败"
    log_message "服务启动失败，尝试回滚"
    
    # 尝试回滚
    print_warning "尝试回滚到之前版本..."
    if [ -f "${PROJECT_ROOT}/scripts/rollback.sh" ]; then
        bash "${PROJECT_ROOT}/scripts/rollback.sh" --auto "$BACKUP_NAME"
    fi
    
    send_update_alert "failure" "服务启动失败，已回滚"
    exit 1
fi
log_message "服务已启动"

# 5. 验证更新
if ! verify_update; then
    print_error "更新验证失败"
    log_message "更新验证失败，尝试回滚"
    
    # 尝试回滚
    print_warning "尝试回滚到之前版本..."
    if [ -f "${PROJECT_ROOT}/scripts/rollback.sh" ]; then
        bash "${PROJECT_ROOT}/scripts/rollback.sh" --auto "$BACKUP_NAME"
    fi
    
    send_update_alert "failure" "更新验证失败，已回滚"
    exit 1
fi
log_message "更新验证成功"

#------------------------------------------------------------------------------
# 更新完成
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_success "更新成功！"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

print_info "更新信息："
echo -e "   原版本: ${BLUE}${CURRENT_VERSION}${NC}"
echo -e "   新版本: ${BLUE}$(get_container_version)${NC}"
echo -e "   备份: ${BLUE}${BACKUP_NAME}${NC}"
echo -e "   时间: ${BLUE}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

log_message "更新成功"
send_update_alert "success" "从 ${CURRENT_VERSION} 更新到 $(get_container_version)"

print_info "如需回滚，请运行: ./scripts/rollback.sh"
echo ""
