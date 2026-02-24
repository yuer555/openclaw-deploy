#!/bin/bash
#==============================================================================
# 脚本名称: rollback.sh
# 功能描述: OpenClaw 快速回滚工具
# 使用方法: ./rollback.sh [backup_name] [--auto]
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
ROLLBACK_LOG="${PROJECT_ROOT}/logs/rollback.log"

#==============================================================================
# 功能函数
#==============================================================================

log_message() {
    local message="$1"
    mkdir -p "$(dirname $ROLLBACK_LOG)"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$ROLLBACK_LOG"
}

list_backups() {
    print_info "可用的备份："
    echo ""
    
    if [ ! -d "$BACKUP_DIR" ]; then
        print_warning "备份目录不存在"
        return 1
    fi
    
    ls -lht "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -10 | \
        awk '{printf "   %s  %s %s %s  %s\n", NR, $6, $7, $8, $9}' | \
        sed 's|.*/||'
    
    echo ""
}

select_backup() {
    list_backups
    
    read -p "$(echo -e ${YELLOW}请输入备份文件名或编号: ${NC})" selection
    
    # 如果是数字，查找对应的备份
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        local backup_file=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | sed -n "${selection}p")
        echo "$backup_file"
    else
        # 否则作为文件名
        if [[ ! "$selection" = /* ]]; then
            selection="${BACKUP_DIR}/${selection}"
        fi
        echo "$selection"
    fi
}

stop_current_services() {
    print_info "停止当前服务..."
    
    cd "${PROJECT_ROOT}/production"
    
    docker compose -f docker-compose.prod.yml down 2>/dev/null || true
    
    print_success "服务已停止"
}

restore_backup() {
    local backup_file="$1"
    
    print_info "恢复备份: $(basename $backup_file)"
    
    # 验证备份文件
    if [ ! -f "$backup_file" ]; then
        print_error "备份文件不存在: $backup_file"
        return 1
    fi
    
    # 创建安全备份（万一回滚失败）
    print_info "创建安全备份..."
    local safety_backup="${BACKUP_DIR}/before-rollback-$(date +%Y%m%d-%H%M%S).tar.gz"
    cd "$PROJECT_ROOT"
    tar -czf "$safety_backup" data config 2>/dev/null || true
    
    # 恢复数据
    print_info "恢复数据..."
    cd "$PROJECT_ROOT"
    tar -xzf "$backup_file"
    
    if [ $? -eq 0 ]; then
        print_success "数据恢复成功"
        return 0
    else
        print_error "数据恢复失败"
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

verify_services() {
    print_info "验证服务..."
    
    # 等待服务启动
    sleep 10
    
    # 检查容器状态
    if docker ps | grep -q "openclaw-production"; then
        print_success "服务运行正常"
        
        # 运行健康检查
        if [ -f "${PROJECT_ROOT}/production/6-health-check.sh" ]; then
            bash "${PROJECT_ROOT}/production/6-health-check.sh" | tail -20
        fi
        
        return 0
    else
        print_error "服务未运行"
        return 1
    fi
}

send_rollback_alert() {
    local status="$1"
    local backup_name="$2"
    
    if [ -f "${PROJECT_ROOT}/scripts/alert.sh" ]; then
        if [ "$status" = "success" ]; then
            bash "${PROJECT_ROOT}/scripts/alert.sh" --wecom \
                "OpenClaw 回滚成功: ${backup_name}" "warning"
        else
            bash "${PROJECT_ROOT}/scripts/alert.sh" --wecom \
                "OpenClaw 回滚失败: ${backup_name}" "critical"
        fi
    fi
}

#==============================================================================
# 主流程
#==============================================================================

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║              OpenClaw 快速回滚工具 V1.4                      ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 解析参数
BACKUP_FILE=""
AUTO_MODE=false

for arg in "$@"; do
    case $arg in
        --auto)
            AUTO_MODE=true
            ;;
        *)
            BACKUP_FILE="$arg"
            ;;
    esac
done

log_message "开始回滚流程"

#------------------------------------------------------------------------------
# 选择备份
#------------------------------------------------------------------------------

if [ -z "$BACKUP_FILE" ]; then
    BACKUP_FILE=$(select_backup)
fi

# 验证备份文件
if [ ! -f "$BACKUP_FILE" ]; then
    print_error "备份文件不存在: $BACKUP_FILE"
    exit 1
fi

print_info "将回滚到: $(basename $BACKUP_FILE)"
log_message "选择备份: $BACKUP_FILE"

#------------------------------------------------------------------------------
# 确认回滚
#------------------------------------------------------------------------------

if [ "$AUTO_MODE" = false ]; then
    print_warning "⚠️  警告：回滚将覆盖当前数据和配置！"
    echo ""
    read -p "$(echo -e ${RED}确认回滚？输入 'yes' 继续: ${NC})" -r
    echo
    if [[ ! $REPLY = "yes" ]]; then
        print_warning "已取消回滚"
        exit 0
    fi
fi

#------------------------------------------------------------------------------
# 执行回滚
#------------------------------------------------------------------------------

print_warning "开始回滚..."

# 1. 停止服务
stop_current_services
log_message "服务已停止"

# 2. 恢复备份
if ! restore_backup "$BACKUP_FILE"; then
    print_error "备份恢复失败，回滚中止"
    send_rollback_alert "failure" "$(basename $BACKUP_FILE)"
    exit 1
fi
log_message "备份恢复成功"

# 3. 启动服务
if ! start_services; then
    print_error "服务启动失败"
    log_message "服务启动失败"
    send_rollback_alert "failure" "$(basename $BACKUP_FILE)"
    exit 1
fi
log_message "服务已启动"

# 4. 验证服务
if ! verify_services; then
    print_error "服务验证失败"
    log_message "服务验证失败"
    send_rollback_alert "failure" "$(basename $BACKUP_FILE)"
    exit 1
fi
log_message "服务验证成功"

#------------------------------------------------------------------------------
# 回滚完成
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_success "回滚成功！"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

print_info "回滚信息："
echo -e "   备份文件: ${BLUE}$(basename $BACKUP_FILE)${NC}"
echo -e "   回滚时间: ${BLUE}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

log_message "回滚成功"
send_rollback_alert "success" "$(basename $BACKUP_FILE)"

print_warning "建议："
print_info "  1. 检查服务日志: docker logs openclaw-production -f"
print_info "  2. 运行健康检查: ./production/6-health-check.sh"
print_info "  3. 验证核心功能是否正常"
echo ""
