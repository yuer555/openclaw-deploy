#!/bin/bash
#==============================================================================
# 脚本名称: backup.sh
# 功能描述: 备份 OpenClaw 数据和配置
# 使用方法: ./backup.sh [backup_name]
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

# 备份目录
BACKUP_DIR="/opt/openclaw/backups"
PROJECT_ROOT="/opt/openclaw"

# 生成备份名称
BACKUP_NAME=${1:-"backup-$(date +%Y%m%d-%H%M%S)"}
BACKUP_FILE="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

# 需要备份的目录和文件
BACKUP_ITEMS=(
    "data"
    "config"
    "production/.env.prod"
    "logs"
)

#==============================================================================
# 主流程
#==============================================================================

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║              OpenClaw 数据备份工具 V1.4                      ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 检查是否在正确目录
if [ ! -d "production" ] && [ ! -d "/opt/openclaw/production" ]; then
    print_error "请在项目根目录或 /opt/openclaw 运行此脚本"
    exit 1
fi

# 确定项目根目录
if [ -d "production" ]; then
    PROJECT_ROOT=$(pwd)
    BACKUP_DIR="${PROJECT_ROOT}/backups"
fi

# 创建备份目录
mkdir -p "$BACKUP_DIR"

print_info "备份配置："
echo -e "   项目目录: ${BLUE}${PROJECT_ROOT}${NC}"
echo -e "   备份目录: ${BLUE}${BACKUP_DIR}${NC}"
echo -e "   备份文件: ${BLUE}${BACKUP_FILE}${NC}"
echo ""

# 检查备份项
print_info "检查备份项..."
for item in "${BACKUP_ITEMS[@]}"; do
    if [ -e "${PROJECT_ROOT}/${item}" ]; then
        print_success "${item} - 存在"
    else
        print_warning "${item} - 不存在（跳过）"
    fi
done
echo ""

# 确认备份
read -p "$(echo -e ${YELLOW}是否继续备份？[y/N]: ${NC})" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "已取消备份"
    exit 0
fi

# 执行备份
print_info "正在备份..."

cd "$PROJECT_ROOT"
tar -czf "$BACKUP_FILE" \
    --exclude='*.log' \
    --exclude='node_modules' \
    --exclude='.git' \
    --exclude='OLD_VERSIONS' \
    $(printf "%s " "${BACKUP_ITEMS[@]}") \
    2>/dev/null || true

# 检查备份结果
if [ -f "$BACKUP_FILE" ]; then
    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    print_success "备份完成！"
    echo ""
    print_info "备份信息："
    echo -e "   文件: ${BLUE}${BACKUP_FILE}${NC}"
    echo -e "   大小: ${BLUE}${BACKUP_SIZE}${NC}"
    echo -e "   时间: ${BLUE}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
else
    print_error "备份失败！"
    exit 1
fi

# 清理旧备份（保留最近30个）
print_info "清理旧备份..."
cd "$BACKUP_DIR"
ls -t backup-*.tar.gz 2>/dev/null | tail -n +31 | xargs -r rm -f
print_success "清理完成"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_success "备份完成！可以使用 restore.sh 恢复数据"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
