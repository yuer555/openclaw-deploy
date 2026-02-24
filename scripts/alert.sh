#!/bin/bash
#==============================================================================
# 脚本名称: alert.sh
# 功能描述: OpenClaw 告警通知系统
# 使用方法: ./alert.sh [--wecom|--email] "告警消息" [告警级别]
# 告警级别: info, warning, error, critical
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

# 项目根目录
PROJECT_ROOT="/opt/openclaw"
if [ -d "production" ]; then
    PROJECT_ROOT=$(pwd)
fi

# 加载环境变量
if [ -f "${PROJECT_ROOT}/production/.env.prod" ]; then
    source "${PROJECT_ROOT}/production/.env.prod"
fi

# 告警配置
ALERT_LOG="${PROJECT_ROOT}/logs/alerts.log"
HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

#==============================================================================
# 告警函数
#==============================================================================

# 企业微信告警
send_wecom_alert() {
    local message="$1"
    local level="$2"
    
    # 级别图标
    local icon
    case $level in
        critical) icon="🔴" ;;
        error) icon="❌" ;;
        warning) icon="⚠️" ;;
        info) icon="ℹ️" ;;
        *) icon="📢" ;;
    esac
    
    # 构造消息
    local alert_message="
**OpenClaw 系统告警** ${icon}

**级别**: ${level}
**时间**: ${TIMESTAMP}
**主机**: ${HOSTNAME}
**消息**: ${message}
"
    
    # 发送企业微信消息（需要配置企业微信 webhook）
    if [ ! -z "$WECOM_WEBHOOK" ]; then
        curl -s -X POST "$WECOM_WEBHOOK" \
            -H 'Content-Type: application/json' \
            -d "{
                \"msgtype\": \"markdown\",
                \"markdown\": {
                    \"content\": \"${alert_message}\"
                }
            }" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            print_success "企业微信告警已发送"
            return 0
        else
            print_error "企业微信告警发送失败"
            return 1
        fi
    else
        print_warning "未配置企业微信 Webhook，跳过企业微信告警"
        return 1
    fi
}

# 邮件告警
send_email_alert() {
    local message="$1"
    local level="$2"
    
    if [ ! -z "$ADMIN_EMAIL" ]; then
        local subject="[OpenClaw Alert] ${level} - ${HOSTNAME}"
        
        echo -e "时间: ${TIMESTAMP}\n主机: ${HOSTNAME}\n级别: ${level}\n\n${message}" | \
            mail -s "$subject" "$ADMIN_EMAIL" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            print_success "邮件告警已发送到 ${ADMIN_EMAIL}"
            return 0
        else
            print_error "邮件告警发送失败"
            return 1
        fi
    else
        print_warning "未配置管理员邮箱，跳过邮件告警"
        return 1
    fi
}

# 本地日志
log_alert() {
    local message="$1"
    local level="$2"
    
    # 确保日志目录存在
    mkdir -p "$(dirname $ALERT_LOG)"
    
    # 写入日志
    echo "[${TIMESTAMP}] [${level}] [${HOSTNAME}] ${message}" >> "$ALERT_LOG"
}

# 控制台输出
console_alert() {
    local message="$1"
    local level="$2"
    
    case $level in
        critical|error)
            print_error "${level}: ${message}"
            ;;
        warning)
            print_warning "${level}: ${message}"
            ;;
        info)
            print_info "${level}: ${message}"
            ;;
        *)
            echo "${level}: ${message}"
            ;;
    esac
}

#==============================================================================
# 主流程
#==============================================================================

# 解析参数
SEND_WECOM=false
SEND_EMAIL=false
MESSAGE=""
LEVEL="info"

while [[ $# -gt 0 ]]; do
    case $1 in
        --wecom)
            SEND_WECOM=true
            shift
            ;;
        --email)
            SEND_EMAIL=true
            shift
            ;;
        --all)
            SEND_WECOM=true
            SEND_EMAIL=true
            shift
            ;;
        *)
            if [ -z "$MESSAGE" ]; then
                MESSAGE="$1"
            else
                LEVEL="$1"
            fi
            shift
            ;;
    esac
done

# 检查消息
if [ -z "$MESSAGE" ]; then
    echo "使用方法: $0 [--wecom|--email|--all] \"告警消息\" [级别]"
    echo ""
    echo "告警级别:"
    echo "  info     - 信息（默认）"
    echo "  warning  - 警告"
    echo "  error    - 错误"
    echo "  critical - 严重"
    echo ""
    echo "示例:"
    echo "  $0 --wecom \"CPU 使用率超过 80%\" warning"
    echo "  $0 --all \"服务宕机\" critical"
    exit 1
fi

# 如果没有指定发送方式，默认全部发送
if [ "$SEND_WECOM" = false ] && [ "$SEND_EMAIL" = false ]; then
    SEND_WECOM=true
    SEND_EMAIL=true
fi

# 发送告警
print_info "发送告警: ${MESSAGE} (${LEVEL})"

# 记录到本地日志
log_alert "$MESSAGE" "$LEVEL"

# 控制台输出
console_alert "$MESSAGE" "$LEVEL"

# 企业微信告警
if [ "$SEND_WECOM" = true ]; then
    send_wecom_alert "$MESSAGE" "$LEVEL"
fi

# 邮件告警
if [ "$SEND_EMAIL" = true ]; then
    send_email_alert "$MESSAGE" "$LEVEL"
fi

print_success "告警处理完成"

#==============================================================================
# 预定义告警场景
#==============================================================================

# 可以直接调用预定义场景
case "$MESSAGE" in
    "test")
        send_wecom_alert "这是一条测试告警消息" "info"
        ;;
esac
