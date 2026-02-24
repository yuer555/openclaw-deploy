#!/bin/bash
#==============================================================================
# 脚本名称: security-audit.sh
# 功能描述: OpenClaw 安全审计工具
# 使用方法: ./security-audit.sh [--fix]
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

AUDIT_LOG="${PROJECT_ROOT}/logs/security-audit.log"

# 审计统计
TOTAL_CHECKS=0
PASSED_CHECKS=0
WARNING_CHECKS=0
FAILED_CHECKS=0

#==============================================================================
# 审计函数
#==============================================================================

log_audit() {
    local message="$1"
    mkdir -p "$(dirname $AUDIT_LOG)"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$AUDIT_LOG"
}

run_check() {
    local check_name="$1"
    local check_result="$2"
    
    ((TOTAL_CHECKS++))
    
    case $check_result in
        pass)
            print_success "$check_name"
            ((PASSED_CHECKS++))
            log_audit "[PASS] $check_name"
            ;;
        warning)
            print_warning "$check_name"
            ((WARNING_CHECKS++))
            log_audit "[WARN] $check_name"
            ;;
        fail)
            print_error "$check_name"
            ((FAILED_CHECKS++))
            log_audit "[FAIL] $check_name"
            ;;
    esac
}

#==============================================================================
# 审计项目
#==============================================================================

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║            OpenClaw 安全审计工具 V1.4                        ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

log_audit "开始安全审计"

#------------------------------------------------------------------------------
# 1. 文件权限检查
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}1. 文件权限检查${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 检查 .env 文件权限
if [ -f "${PROJECT_ROOT}/production/.env.prod" ]; then
    perms=$(stat -c "%a" "${PROJECT_ROOT}/production/.env.prod" 2>/dev/null || stat -f "%A" "${PROJECT_ROOT}/production/.env.prod")
    if [ "$perms" = "600" ] || [ "$perms" = "400" ]; then
        run_check ".env.prod 权限正确 (${perms})" "pass"
    else
        run_check ".env.prod 权限不安全 (${perms})，应该是 600 或 400" "fail"
    fi
else
    run_check ".env.prod 文件不存在" "warning"
fi

# 检查脚本权限
for script in ${PROJECT_ROOT}/scripts/*.sh ${PROJECT_ROOT}/production/*.sh ${PROJECT_ROOT}/local/*.sh; do
    if [ -f "$script" ]; then
        if [ -x "$script" ]; then
            # 脚本可执行但不应该所有人可写
            perms=$(stat -c "%a" "$script" 2>/dev/null || stat -f "%A" "$script")
            if [[ "$perms" =~ ^[0-7][0-7][0-4]$ ]]; then
                run_check "$(basename $script) 权限正确" "pass"
            else
                run_check "$(basename $script) 权限过于宽松 (${perms})" "warning"
            fi
        fi
    fi
done

#------------------------------------------------------------------------------
# 2. 敏感信息检查
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}2. 敏感信息检查${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 检查是否有敏感信息暴露
SENSITIVE_PATTERNS=(
    "password"
    "secret"
    "api_key"
    "token"
    "private_key"
)

for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    # 排除已知安全的文件
    if grep -r -i "$pattern" "${PROJECT_ROOT}" \
        --exclude-dir=OLD_VERSIONS \
        --exclude-dir=.git \
        --exclude-dir=node_modules \
        --exclude="*.log" \
        --exclude="*.md" \
        --exclude="*example*" \
        --exclude="*.sh" 2>/dev/null | grep -v "^Binary" | head -1 > /dev/null; then
        run_check "发现 '$pattern' 关键词，请检查是否泄露" "warning"
    fi
done

# 检查 .env 文件是否在 .gitignore 中
if [ -f "${PROJECT_ROOT}/.gitignore" ]; then
    if grep -q "\.env" "${PROJECT_ROOT}/.gitignore"; then
        run_check ".env 文件已加入 .gitignore" "pass"
    else
        run_check ".env 文件未加入 .gitignore" "fail"
    fi
fi

#------------------------------------------------------------------------------
# 3. API Key 检查
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}3. API Key 安全检查${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [ -f "${PROJECT_ROOT}/production/.env.prod" ]; then
    source "${PROJECT_ROOT}/production/.env.prod"
    
    # 检查 API Key 是否为示例值
    if [ ! -z "$GITHUB_TOKEN" ]; then
        if [ "$GITHUB_TOKEN" = "your_github_token_here" ]; then
            run_check "GITHUB_TOKEN 未配置" "warning"
        else
            run_check "GITHUB_TOKEN 已配置" "pass"
        fi
    fi
    
    if [ ! -z "$OPENAI_API_KEY" ]; then
        if [ "$OPENAI_API_KEY" = "sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" ]; then
            run_check "OPENAI_API_KEY 未配置" "warning"
        else
            run_check "OPENAI_API_KEY 已配置" "pass"
        fi
    fi
    
    # 检查 SECRET_KEY 强度
    if [ ! -z "$SECRET_KEY" ]; then
        if [ "${#SECRET_KEY}" -ge 32 ]; then
            run_check "SECRET_KEY 长度充足 (${#SECRET_KEY} 字符)" "pass"
        else
            run_check "SECRET_KEY 太短 (${#SECRET_KEY} 字符)，建议至少 32 字符" "warning"
        fi
        
        # 检查是否包含大小写字母和数字
        if [[ "$SECRET_KEY" =~ [a-z] ]] && [[ "$SECRET_KEY" =~ [A-Z] ]] && [[ "$SECRET_KEY" =~ [0-9] ]]; then
            run_check "SECRET_KEY 复杂度良好" "pass"
        else
            run_check "SECRET_KEY 复杂度不足，建议包含大小写字母和数字" "warning"
        fi
    fi
fi

#------------------------------------------------------------------------------
# 4. Docker 安全检查
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}4. Docker 安全检查${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 检查容器是否以 root 运行
if docker ps | grep -q "openclaw-production"; then
    USER=$(docker exec openclaw-production whoami 2>/dev/null || echo "unknown")
    if [ "$USER" = "root" ]; then
        run_check "容器以 root 用户运行，建议使用非 root 用户" "warning"
    else
        run_check "容器使用非 root 用户 ($USER)" "pass"
    fi
    
    # 检查容器资源限制
    if docker inspect openclaw-production | grep -q "Memory"; then
        run_check "容器配置了资源限制" "pass"
    else
        run_check "容器未配置资源限制" "warning"
    fi
fi

# 检查镜像来源
if docker images | grep -q "openclaw/openclaw"; then
    run_check "使用官方镜像" "pass"
else
    run_check "未使用官方镜像" "warning"
fi

#------------------------------------------------------------------------------
# 5. 网络安全检查
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}5. 网络安全检查${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 检查防火墙
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        run_check "UFW 防火墙已启用" "pass"
    else
        run_check "UFW 防火墙未启用" "warning"
    fi
elif command -v firewalld &> /dev/null; then
    if systemctl is-active --quiet firewalld; then
        run_check "Firewalld 防火墙已启用" "pass"
    else
        run_check "Firewalld 防火墙未启用" "warning"
    fi
else
    run_check "未检测到防火墙" "warning"
fi

# 检查 SSL 证书
if [ -f "${PROJECT_ROOT}/config/ssl/fullchain.pem" ]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "${PROJECT_ROOT}/config/ssl/fullchain.pem" 2>/dev/null | cut -d= -f2)
    EXPIRY_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || echo "0")
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
    
    if [ $DAYS_LEFT -gt 30 ]; then
        run_check "SSL 证书有效 (剩余 $DAYS_LEFT 天)" "pass"
    elif [ $DAYS_LEFT -gt 0 ]; then
        run_check "SSL 证书即将过期 (剩余 $DAYS_LEFT 天)" "warning"
    else
        run_check "SSL 证书已过期" "fail"
    fi
else
    run_check "未配置 SSL 证书" "warning"
fi

#------------------------------------------------------------------------------
# 6. 访问日志检查
#------------------------------------------------------------------------------

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}6. 访问日志检查${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 检查最近的失败登录尝试
if [ -f "${PROJECT_ROOT}/logs/gateway/access.log" ]; then
    FAILED_ATTEMPTS=$(grep -c "401\|403" "${PROJECT_ROOT}/logs/gateway/access.log" 2>/dev/null || echo "0")
    if [ $FAILED_ATTEMPTS -gt 100 ]; then
        run_check "检测到大量失败请求 ($FAILED_ATTEMPTS 次)" "warning"
    else
        run_check "访问日志正常" "pass"
    fi
fi

#==============================================================================
# 审计总结
#==============================================================================

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}安全审计总结${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

print_info "审计统计："
echo -e "   总计: ${BLUE}${TOTAL_CHECKS}${NC}"
echo -e "   ✅ 通过: ${GREEN}${PASSED_CHECKS}${NC}"
echo -e "   ⚠️  警告: ${YELLOW}${WARNING_CHECKS}${NC}"
echo -e "   ❌ 失败: ${RED}${FAILED_CHECKS}${NC}"
echo ""

# 计算安全评分
SECURITY_SCORE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

print_info "安全评分："
if [ $SECURITY_SCORE -ge 90 ]; then
    echo -e "   ${GREEN}${SECURITY_SCORE}/100 - 优秀 ✨${NC}"
    EXIT_CODE=0
elif [ $SECURITY_SCORE -ge 70 ]; then
    echo -e "   ${YELLOW}${SECURITY_SCORE}/100 - 良好 👍${NC}"
    EXIT_CODE=0
elif [ $SECURITY_SCORE -ge 50 ]; then
    echo -e "   ${YELLOW}${SECURITY_SCORE}/100 - 需改进 ⚠️${NC}"
    EXIT_CODE=1
else
    echo -e "   ${RED}${SECURITY_SCORE}/100 - 存在风险 ❗${NC}"
    EXIT_CODE=1
fi

echo ""
log_audit "审计完成: 评分 ${SECURITY_SCORE}/100"

# 建议
if [ $FAILED_CHECKS -gt 0 ] || [ $WARNING_CHECKS -gt 0 ]; then
    echo -e "${YELLOW}📋 建议：${NC}"
    echo ""
    
    if [ $FAILED_CHECKS -gt 0 ]; then
        echo -e "   ${RED}严重问题需要立即处理！${NC}"
    fi
    
    if [ $WARNING_CHECKS -gt 0 ]; then
        echo -e "   ${YELLOW}建议处理警告项以提升安全性${NC}"
    fi
    
    echo ""
    print_info "常见修复方法："
    echo -e "   - 修改 .env 文件权限: ${BLUE}chmod 600 production/.env.prod${NC}"
    echo -e "   - 生成强密钥: ${BLUE}openssl rand -hex 32${NC}"
    echo -e "   - 启用防火墙: ${BLUE}sudo ufw enable${NC}"
    echo -e "   - 更新 SSL 证书: ${BLUE}./production/4-setup-ssl.sh${NC}"
    echo ""
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
print_info "详细审计日志: $AUDIT_LOG"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

exit $EXIT_CODE
