#!/bin/bash
#==============================================================================
# 脚本名称: 01-upload.sh
# 功能描述: 从本地上传 OpenClaw 企业微信桥接网关项目文件到生产服务器
# 使用方法: ./bin/01-upload.sh
# 执行位置: 🏠 本地（项目根目录）
# 分支:     20260302_feat_wecom_bridging
# 版本: V1.0
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
# 定位项目根目录
#==============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 校验项目结构
if [ ! -f "$PROJECT_ROOT/src/gateway/wecom_gateway.py" ]; then
    print_error "未找到 src/gateway/wecom_gateway.py，请在项目根目录运行此脚本"
    exit 1
fi

#==============================================================================
# 默认服务器配置（请根据实际环境修改）
DEFAULT_SERVER_IP=""
DEFAULT_SERVER_USER=""
DEFAULT_REMOTE_DIR="/opt/openclaw"

#==============================================================================
# 主流程
#==============================================================================

echo -e "${GREEN}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║       OpenClaw 企业微信桥接网关 — 上传到生产服务器            ║
╚═══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

#------------------------------------------------------------------------------
# 步骤 1: 获取服务器信息
#------------------------------------------------------------------------------
print_step "步骤 1/6: 配置服务器信息"

if [ -n "$DEFAULT_SERVER_IP" ]; then
    read -p "服务器 IP 地址 [${DEFAULT_SERVER_IP}]: " SERVER_IP
    SERVER_IP=${SERVER_IP:-$DEFAULT_SERVER_IP}
else
    while [ -z "$SERVER_IP" ]; do
        read -p "服务器 IP 地址: " SERVER_IP
    done
fi

if [ -n "$DEFAULT_SERVER_USER" ]; then
    read -p "服务器用户名 [${DEFAULT_SERVER_USER}]: " SERVER_USER
    SERVER_USER=${SERVER_USER:-$DEFAULT_SERVER_USER}
else
    while [ -z "$SERVER_USER" ]; do
        read -p "服务器用户名: " SERVER_USER
    done
fi

read -p "远程部署目录 [${DEFAULT_REMOTE_DIR}]: " REMOTE_DIR
REMOTE_DIR=${REMOTE_DIR:-$DEFAULT_REMOTE_DIR}

print_info "目标服务器: ${SERVER_USER}@${SERVER_IP}"
print_info "部署目录:   ${REMOTE_DIR}"

#------------------------------------------------------------------------------
# 步骤 2: 测试 SSH 连接
#------------------------------------------------------------------------------
print_step "步骤 2/6: 测试 SSH 连接"

print_info "测试 SSH 连接..."
if ssh -o ConnectTimeout=10 "${SERVER_USER}@${SERVER_IP}" "echo 'SSH 连接成功'" 2>/dev/null; then
    print_success "SSH 连接正常"
else
    print_error "SSH 连接失败！"
    print_info "请检查："
    print_info "  1. 服务器 IP 是否正确"
    print_info "  2. SSH 密钥是否配置（运行 ssh-copy-id ${SERVER_USER}@${SERVER_IP}）"
    print_info "  3. 服务器防火墙是否允许 SSH（端口 22）"
    exit 1
fi

#------------------------------------------------------------------------------
# 步骤 3: 确认上传内容
#------------------------------------------------------------------------------
print_step "步骤 3/6: 确认上传内容"

print_info "将上传以下文件/目录："
echo ""
echo "  src/gateway/                  — Gateway 主程序 + 依赖"
echo "    ├── wecom_gateway.py"
echo "    └── requirements.txt"
echo "  bin/                          — 部署步骤脚本"
echo "    ├── 02-install-gateway.sh"
echo "    ├── 03-install-openclaw.sh"
echo "    ├── 04-manage-agent.sh"
echo "    └── 05-cleanup.sh"
echo "  scripts/                      — 工具脚本"
echo "    ├── manage-agent.py"
echo "    ├── gateway-ctl.sh"
echo "    └── openclaw-gateway.service"
echo "  .env.example                  — 环境变量模板"
echo "  docs/                         — 文档"
echo "  README.md                     — 项目说明"
echo "  USER-GUIDE.md                 — 用户指南"
echo "  AGENTS.md                     — AI 编码指南"
echo ""

print_warning "注意: .env、*.db、data/、logs/ 等敏感/运行时文件不会上传"
print_warning "远端部署时将仅保留 .env 和 data/，其余文件会清理后再解压"
echo ""
read -p "确认上传？[Y/n] " CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    print_info "已取消上传"
    exit 0
fi

#------------------------------------------------------------------------------
# 步骤 4: 打包项目文件
#------------------------------------------------------------------------------
print_step "步骤 4/6: 打包项目文件"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
PACKAGE_NAME="openclaw-gateway-${TIMESTAMP}.tar.gz"
TEMP_DIR="${PROJECT_ROOT}/.tmp_upload"

print_info "创建临时目录..."
rm -rf "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}/openclaw-gateway"

STAGING="${TEMP_DIR}/openclaw-gateway"

# 复制 Gateway 源码（仅核心文件）
print_info "复制 Gateway 源码..."
mkdir -p "${STAGING}/src/gateway"
cp "${PROJECT_ROOT}/src/gateway/wecom_gateway.py" "${STAGING}/src/gateway/"
cp "${PROJECT_ROOT}/src/gateway/requirements.txt" "${STAGING}/src/gateway/"

# 复制部署步骤脚本
print_info "复制部署步骤脚本..."
mkdir -p "${STAGING}/bin"
for f in "${PROJECT_ROOT}/bin/"*.sh; do
    [ -f "$f" ] && cp "$f" "${STAGING}/bin/"
done

# 复制工具脚本
print_info "复制工具脚本..."
mkdir -p "${STAGING}/scripts"
cp "${PROJECT_ROOT}/scripts/manage-agent.py" "${STAGING}/scripts/"
cp "${PROJECT_ROOT}/scripts/gateway-ctl.sh" "${STAGING}/scripts/" 2>/dev/null || true
cp "${PROJECT_ROOT}/scripts/openclaw-gateway.service" "${STAGING}/scripts/" 2>/dev/null || true

# 复制配置模板
print_info "复制配置文件..."
cp "${PROJECT_ROOT}/.env.example" "${STAGING}/" 2>/dev/null || true

# 复制文档
print_info "复制文档..."
mkdir -p "${STAGING}/docs"
for f in "${PROJECT_ROOT}/docs/"*.md; do
    [ -f "$f" ] && cp "$f" "${STAGING}/docs/"
done
cp "${PROJECT_ROOT}/README.md" "${STAGING}/" 2>/dev/null || true
cp "${PROJECT_ROOT}/USER-GUIDE.md" "${STAGING}/" 2>/dev/null || true
cp "${PROJECT_ROOT}/AGENTS.md" "${STAGING}/" 2>/dev/null || true
cp "${PROJECT_ROOT}/PROJECT-SUMMARY.md" "${STAGING}/" 2>/dev/null || true
cp "${PROJECT_ROOT}/PHASE2-PLAN.md" "${STAGING}/" 2>/dev/null || true

# 打包
print_info "打包文件..."
tar -czf "${TEMP_DIR}/${PACKAGE_NAME}" -C "${TEMP_DIR}" openclaw-gateway/

# 显示包大小
PACKAGE_SIZE=$(du -h "${TEMP_DIR}/${PACKAGE_NAME}" | cut -f1)
print_success "打包完成: ${PACKAGE_NAME} (${PACKAGE_SIZE})"

#------------------------------------------------------------------------------
# 步骤 5: 上传到服务器
#------------------------------------------------------------------------------
print_step "步骤 5/6: 上传文件到服务器"

print_info "创建远程目录..."
ssh "${SERVER_USER}@${SERVER_IP}" "sudo mkdir -p ${REMOTE_DIR} && sudo chown ${SERVER_USER}:${SERVER_USER} ${REMOTE_DIR}"

print_info "上传打包文件..."
scp "${TEMP_DIR}/${PACKAGE_NAME}" "${SERVER_USER}@${SERVER_IP}:${REMOTE_DIR}/"
print_success "文件上传完成"

#------------------------------------------------------------------------------
# 步骤 6: 在服务器上解压
#------------------------------------------------------------------------------
print_step "步骤 6/6: 在服务器上解压部署"

print_info "在服务器上解压文件..."
ssh "${SERVER_USER}@${SERVER_IP}" << ENDSSH
set -e
cd ${REMOTE_DIR}

# 备份现有 .env 配置
if [ -f .env ]; then
    cp .env /tmp/.env.gateway.bak
    echo "  已备份 .env"
fi

# 备份 SQLite 数据库（如果存在）
DB_PATH=\$(grep '^DB_PATH=' .env 2>/dev/null | cut -d= -f2 || echo "")
if [ -n "\$DB_PATH" ] && [ -f "\$DB_PATH" ]; then
    cp "\$DB_PATH" "\${DB_PATH}.bak.${TIMESTAMP}"
    echo "  已备份数据库: \$DB_PATH"
fi

# 全量清理旧文件（仅保留白名单：.env、data、当前上传包）
find . -mindepth 1 -maxdepth 1 \
    ! -name ".env" \
    ! -name "data" \
    ! -name "${PACKAGE_NAME}" \
    -exec rm -rf {} +

# 解压新文件
tar -xzf ${PACKAGE_NAME}
cp -a openclaw-gateway/. .
rmdir openclaw-gateway 2>/dev/null || true
rm -f ${PACKAGE_NAME}

# 恢复 .env 配置
if [ -f /tmp/.env.gateway.bak ]; then
    mv /tmp/.env.gateway.bak .env
    echo "  已恢复 .env"
fi

# 设置执行权限
chmod +x bin/*.sh 2>/dev/null || true
chmod +x scripts/*.sh 2>/dev/null || true
chmod +x scripts/*.py 2>/dev/null || true

echo ""
echo "部署目录内容:"
ls -la
ENDSSH

print_success "文件解压完成"

#------------------------------------------------------------------------------
# 清理临时文件
#------------------------------------------------------------------------------
print_info "清理本地临时文件..."
rm -rf "${TEMP_DIR}"

#==============================================================================
# 完成总结
#==============================================================================

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}🎉 文件上传成功！${NC}\n"

echo -e "${YELLOW}📋 下一步操作：${NC}\n"

echo -e "${YELLOW}1. 登录到服务器：${NC}"
echo -e "   ${BLUE}ssh ${SERVER_USER}@${SERVER_IP}${NC}\n"

echo -e "${YELLOW}2. 首次部署 — 运行安装脚本：${NC}"
echo -e "   ${BLUE}cd ${REMOTE_DIR} && sudo bash bin/02-install-gateway.sh${NC}\n"

echo -e "${YELLOW}3. 更新部署 — 同步代码并重启服务：${NC}"
echo -e "   ${BLUE}cd ${REMOTE_DIR} && sudo bash bin/02-install-gateway.sh${NC}\n"

echo -e "${YELLOW}   （仅修改 .env 时才只需重启服务）${NC}"
echo -e "   ${BLUE}sudo systemctl restart openclaw-gateway${NC}\n"

echo -e "${YELLOW}4. 安装配置 OpenClaw（如未安装）：${NC}"
echo -e "   ${BLUE}cd ${REMOTE_DIR} && bash bin/03-install-openclaw.sh${NC}\n"

echo -e "${YELLOW}5. 添加 Agent 绑定：${NC}"
echo -e "   ${BLUE}${REMOTE_DIR}/gateway/bin/04-manage-agent.sh add <name>${NC}\n"

echo -e "${YELLOW}6. 查看服务状态 / 日志：${NC}"
echo -e "   ${BLUE}sudo systemctl status openclaw-gateway${NC}"
echo -e "   ${BLUE}sudo journalctl -u openclaw-gateway -f${NC}\n"

echo -e "${YELLOW}7. 健康检查：${NC}"
echo -e "   ${BLUE}curl http://${SERVER_IP}:8000/health${NC}\n"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
