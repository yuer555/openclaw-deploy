#!/bin/bash
#==============================================================================
# 脚本名称: restore.sh
# 功能描述: 恢复 OpenClaw 备份数据
# 使用方法: ./restore.sh [backup_file]
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

BACKUP_DIR="/opt/openclaw/backups"
PROJECT_ROOT="/opt/openclaw"

#==============================================================================
# 主流程
#==============================================================================

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║              OpenClaw 数据恢复工具 V1.4                      ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 确定项目根目录
if [ -d "production" ]; then
    PROJECT_ROOT=$(pwd)
    BACKUP_DIR="${PROJECT_ROOT}/backups"
fi

# 检查备份目录
if [ ! -d "$BACKUP_DIR" ]; then
    print_error "备份目录不存在: $BACKUP_DIR"
    exit 1
fi

# 选择备份文件
if [ -z "$1" ]; then
    print_info "可用的备份文件："
    echo ""
    ls -lht "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -10 | awk '{print "   " $9 " (" $5 ", " $6 " " $7 ")"}'
    echo ""
    read -p "$(echo -e ${YELLOW}请输入备份文件名: ${NC})" BACKUP_FILE
    BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
else
    BACKUP_FILE="$1"
    # 如果只提供了文件名，添加完整路径
    if [[ ! "$BACKUP_FILE" = /* ]]; then
        BACKUP_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
    fi
fi

# 检查备份文件
if [ ! -f "$BACKUP_FILE" ]; then
    print_error "备份文件不存在: $BACKUP_FILE"
    exit 1
fi

print_info "恢复配置："
echo -e "   备份文件: ${BLUE}${BACKUP_FILE}${NC}"
echo -e "   恢复到: ${BLUE}${PROJECT_ROOT}${NC}"
echo ""

# 警告提示
print_warning "⚠️  警告：恢复将覆盖现有数据！"
echo ""
read -p "$(echo -e ${RED}确认恢复？输入 'yes' 继续: ${NC})" -r
echo
if [[ ! $REPLY = "yes" ]]; then
    print_warning "已取消恢复"
    exit 0
fi

# 停止服务（如果运行中）
print_info "检查服务状态..."
if docker ps | grep -q "openclaw"; then
    print_warning "检测到服务运行中，需要先停止"
    read -p "$(echo -e ${YELLOW}是否停止服务？[y/N]: ${NC})" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cd "$PROJECT_ROOT/production"
        docker compose -f docker-compose.prod.yml down || true
        print_success "服务已停止"
    else
        print_error "请先停止服务后再恢复"
        exit 1
    fi
fi

# 备份当前数据（安全措施）
print_info "备份当前数据..."
SAFETY_BACKUP="${BACKUP_DIR}/before-restore-$(date +%Y%m%d-%H%M%S).tar.gz"
cd "$PROJECT_ROOT"
tar -czf "$SAFETY_BACKUP" data config 2>/dev/null || true
print_success "当前数据已备份到: $SAFETY_BACKUP"

# 执行恢复
print_info "正在恢复数据..."
cd "$PROJECT_ROOT"
tar -xzf "$BACKUP_FILE"

if [ $? -eq 0 ]; then
    print_success "数据恢复完成！"
else
    print_error "恢复失败！"
    print_info "可以从安全备份恢复: $SAFETY_BACKUP"
    exit 1
fi

# 询问是否重启服务
echo ""
read -p "$(echo -e ${YELLOW}是否重启服务？[y/N]: ${NC})" -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "正在启动服务..."
    cd "$PROJECT_ROOT/production"
    docker compose -f docker-compose.prod.yml up -d
    print_success "服务已启动"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_success "恢复完成！"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
print_info "安全备份保存在: $SAFETY_BACKUP"
echo ""
