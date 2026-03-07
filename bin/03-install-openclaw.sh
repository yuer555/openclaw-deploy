#!/usr/bin/env bash
# ============================================================================
# install-openclaw.sh — OpenClaw 一键安装配置脚本
#
# 功能：
#   1. 安装 OpenClaw（自动检测已安装 / npm / curl）
#   2. 配置模型提供商（官方 API Key + 第三方流量池如 GMN）
#   3. 创建多个 Agent（各自 workspace、沙箱配置）
#   4. 编辑 Agent 人格设定（用编辑器依次编辑 OpenClaw 初始化的文件）
#
# 用法：
#   bash bin/03-install-openclaw.sh            # 完整安装流程
#   bash bin/03-install-openclaw.sh --skip-install   # 跳过安装，只做配置
#   bash bin/03-install-openclaw.sh --add-agent      # 只添加新 Agent
#   bash bin/03-install-openclaw.sh --add-provider   # 只添加模型提供商
#
# 要求：Node.js 22+；Docker 仅在沙箱 agent 需要
# 注意：请使用普通用户运行，不要 sudo，不要 root
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 颜色和格式
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }
header()  { echo -e "\n${BOLD}${BLUE}═══ $* ═══${NC}\n"; }
step()    { echo -e "${CYAN}→${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }

# ---------------------------------------------------------------------------
# 全局变量
# ---------------------------------------------------------------------------
OPENCLAW_HOME="${HOME}/.openclaw"
OPENCLAW_CONFIG="${OPENCLAW_HOME}/openclaw.json"
OPENCLAW_ENV_FILE="${OPENCLAW_HOME}/.env"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENCLAW_SANDBOX_IMAGE="${OPENCLAW_SANDBOX_IMAGE:-openclaw-sandbox:gateway-devtools-bookworm}"
OPENCLAW_SANDBOX_DOCKERFILE="${OPENCLAW_SANDBOX_DOCKERFILE:-${REPO_ROOT}/bin/openclaw-sandbox-devtools.Dockerfile}"
OPENCLAW_SANDBOX_BASE_IMAGE="${OPENCLAW_SANDBOX_BASE_IMAGE:-debian:bookworm-slim}"
GATEWAY_SKILL_NAME="gateway-file-upload"
GATEWAY_SKILL_SOURCE_DIR="${REPO_ROOT}/openclaw-skills/${GATEWAY_SKILL_NAME}"
GATEWAY_SKILL_TARGET_DIR="${OPENCLAW_HOME}/skills/${GATEWAY_SKILL_NAME}"
OPENCLAW_GATEWAY_RUN_PID_FILE="${OPENCLAW_HOME}/gateway-run.pid"
OPENCLAW_GATEWAY_RUN_LOG_FILE="${OPENCLAW_HOME}/gateway-run.log"
OPENCLAW_ONBOARD_DAEMON_SKIP_FLAG=""
EDITOR="${EDITOR:-${VISUAL:-nano}}"
MIN_NODE_VERSION=22
HOST_SHARED_ROOT="/app/shared"
SKIP_INSTALL=false
ADD_AGENT_ONLY=false
ADD_PROVIDER_ONLY=false
GATEWAY_TOKEN_SYNC_CHANGED=false
GATEWAY_TOKEN_PREPARE_REQUIRED=false
UPLOAD_SKILL_SANDBOX_AGENT_COUNT=0
UPLOAD_SKILL_SANDBOX_AGENT_IDS=""

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-install)   SKIP_INSTALL=true; shift ;;
        --add-agent)      ADD_AGENT_ONLY=true; shift ;;
        --add-provider)   ADD_PROVIDER_ONLY=true; shift ;;
        --help|-h)
            echo "用法: bash $0 [选项]"
            echo ""
            echo "选项:"
            echo "  --skip-install    跳过 OpenClaw 安装，只做配置"
            echo "  --add-agent       只添加新 Agent"
            echo "  --add-provider    只添加模型提供商"
            echo "  -h, --help        显示帮助"
            exit 0
            ;;
        *) error "未知参数: $1"; exit 1 ;;
    esac
done

if [ "$(id -u)" -eq 0 ]; then
    echo "错误: 请不要使用 root 或 sudo 运行此脚本"
    echo "原因: OpenClaw 的 workspace/sandbox 目录必须位于普通用户家目录，root 会落到 /root/.openclaw 并触发沙箱安全限制"
    echo "正确方式:"
    echo "  普通用户执行: bash bin/03-install-openclaw.sh"
    echo "  仅 Gateway 安装脚本使用 sudo: sudo bash bin/02-install-gateway.sh"
    exit 1
fi

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

# 检查命令是否存在
cmd_exists() { command -v "$1" &>/dev/null; }

_ensure_openclaw_env_file() {
    local env_file_created=false

    mkdir -p "$OPENCLAW_HOME"
    if [[ ! -f "$OPENCLAW_ENV_FILE" ]]; then
        touch "$OPENCLAW_ENV_FILE"
        env_file_created=true
    fi
    chmod 600 "$OPENCLAW_ENV_FILE" 2>/dev/null || true

    if [[ "$env_file_created" == "true" ]]; then
        success "已创建 OpenClaw 环境文件: ${OPENCLAW_ENV_FILE}"
    fi
}


_append_gateway_token_to_env_file_if_missing() {
    local token="$1"

    _ensure_openclaw_env_file

    if grep -Eq '^[[:space:]]*OPENCLAW_GATEWAY_TOKEN=' "$OPENCLAW_ENV_FILE" 2>/dev/null; then
        return 1
    fi

    [[ -s "$OPENCLAW_ENV_FILE" ]] && echo "" >> "$OPENCLAW_ENV_FILE"
    echo "OPENCLAW_GATEWAY_TOKEN=${token}" >> "$OPENCLAW_ENV_FILE"
    success "已写入 Gateway Token 到 ${OPENCLAW_ENV_FILE}"
    return 0
}


_upsert_env_values_in_file() {
    local env_file="$1"
    shift

    if [[ -z "$env_file" ]]; then
        return 1
    fi

python3 - "$env_file" "$@" <<'PYEOF'
import os
import sys

env_file = os.path.expanduser(sys.argv[1])
args = sys.argv[2:]
updates = {}
for raw in args:
    if '=' not in raw:
        continue
    key, value = raw.split('=', 1)
    updates[key] = value

os.makedirs(os.path.dirname(env_file), exist_ok=True)
if not os.path.exists(env_file):
    open(env_file, 'a', encoding='utf-8').close()

with open(env_file, 'r', encoding='utf-8') as f:
    lines = f.readlines()

written = set()
result = []
pending_append = []
for raw in lines:
    stripped = raw.strip()
    if not stripped or stripped.startswith('#') or '=' not in raw:
        result.append(raw)
        continue

    key = raw.split('=', 1)[0].strip()
    if key not in updates:
        result.append(raw)
        continue

    if key in written:
        continue

    written.add(key)
    value = updates[key]
    if value == '':
        continue
    result.append(f"{key}={value}\n")

for key in updates:
    if key in written:
        continue
    value = updates[key]
    if value == '':
        continue
    pending_append.append(f"{key}={value}\n")

if pending_append and result and result[-1].strip():
    result.append('\n')

result.extend(pending_append)

with open(env_file, 'w', encoding='utf-8') as f:
    f.writelines(result)
PYEOF
}


_write_upload_skill_env_to_openclaw_env_file() {
    local gateway_url="$1"
    local upload_token="$2"
    local expires_seconds="$3"

    _ensure_openclaw_env_file

    _upsert_env_values_in_file \
        "$OPENCLAW_ENV_FILE" \
        "OPENCLAW_FILE_UPLOAD_GATEWAY_URL=${gateway_url}" \
        "OPENCLAW_FILE_UPLOAD_TOKEN=${upload_token}" \
        "OPENCLAW_FILE_UPLOAD_EXPIRES=${expires_seconds}"

    export OPENCLAW_FILE_UPLOAD_GATEWAY_URL="$gateway_url"
    if [[ -n "$upload_token" ]]; then
        export OPENCLAW_FILE_UPLOAD_TOKEN="$upload_token"
    else
        unset OPENCLAW_FILE_UPLOAD_TOKEN 2>/dev/null || true
    fi
    export OPENCLAW_FILE_UPLOAD_EXPIRES="$expires_seconds"
}

ensure_gateway_token() {
    local env_token config_token generated_token=""

    _ensure_openclaw_env_file

    env_token="$(_read_env_file_value "$OPENCLAW_ENV_FILE" "OPENCLAW_GATEWAY_TOKEN")"
    if [[ -n "$env_token" ]]; then
        if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" && "${OPENCLAW_GATEWAY_TOKEN}" != "$env_token" ]]; then
            warn "${OPENCLAW_ENV_FILE} 中已有 OPENCLAW_GATEWAY_TOKEN，当前 shell 中的同名变量将仅在本次进程内生效"
        fi
        OPENCLAW_GATEWAY_TOKEN="$env_token"
        export OPENCLAW_GATEWAY_TOKEN
        return 0
    fi

    if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
        _append_gateway_token_to_env_file_if_missing "$OPENCLAW_GATEWAY_TOKEN" || true
        export OPENCLAW_GATEWAY_TOKEN
        return 0
    fi

    config_token="$(_read_token_from_config_file "auth")"
    if [[ -n "$config_token" && "$config_token" != "\${OPENCLAW_GATEWAY_TOKEN}" ]]; then
        OPENCLAW_GATEWAY_TOKEN="$config_token"
        export OPENCLAW_GATEWAY_TOKEN
        _append_gateway_token_to_env_file_if_missing "$OPENCLAW_GATEWAY_TOKEN" || true
        step "检测到现有 gateway.auth.token，已同步到 ${OPENCLAW_ENV_FILE}"
        return 0
    fi

    generated_token="$(openssl rand -hex 32 2>/dev/null || head -c 32 /dev/urandom | xxd -p -c 32)"
    OPENCLAW_GATEWAY_TOKEN="$generated_token"
    export OPENCLAW_GATEWAY_TOKEN
    _append_gateway_token_to_env_file_if_missing "$OPENCLAW_GATEWAY_TOKEN" || true
    success "已生成新的 Gateway Token，并写入 ${OPENCLAW_ENV_FILE}"
}

_print_sandbox_runtime_instructions() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Docker 沙箱准备指南${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  仅当你要创建 Docker 沙箱 Agent 时才需要以下步骤。"
    echo "  不启用沙箱则无需安装 Docker。"
    echo ""
    echo -e "${CYAN}▸ 1. 安装 Docker${NC}"
    echo ""
    if cmd_exists apt-get; then
        echo "  当前系统: Ubuntu / Debian"
        echo ""
        echo "  sudo apt-get install -y ca-certificates curl"
        echo "  sudo install -m 0755 -d /etc/apt/keyrings"
        echo "  curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg \\"
        echo "    | sudo tee /etc/apt/keyrings/docker.asc > /dev/null"
        echo "  echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \\"
        echo "    https://mirrors.aliyun.com/docker-ce/linux/ubuntu \\"
        echo "    \$(. /etc/os-release && echo \$VERSION_CODENAME) stable\" \\"
        echo "    | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install -y docker-ce docker-ce-cli containerd.io"
    elif cmd_exists dnf; then
        echo "  当前系统: RHEL / Rocky / AlmaLinux（dnf）"
        echo ""
        echo "  sudo dnf install -y dnf-plugins-core"
        echo "  sudo dnf config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
        echo "  sudo dnf install -y docker-ce docker-ce-cli containerd.io"
    elif cmd_exists yum; then
        echo "  当前系统: CentOS / RHEL（yum）"
        echo ""
        echo "  sudo yum install -y yum-utils"
        echo "  sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
        echo "  sudo yum install -y docker-ce docker-ce-cli containerd.io"
    else
        echo "  未识别包管理器，请按你的发行版选择其一："
        echo ""
        echo "  # Ubuntu/Debian:"
        echo "  sudo apt-get update && sudo apt-get install -y docker.io"
        echo "  # RHEL/Rocky/CentOS:"
        echo "  sudo yum install -y docker"
    fi
    echo "  sudo systemctl enable --now docker"
    echo "  sudo usermod -aG docker \$USER"
    echo "  newgrp docker   # 或重新登录"
    echo "  # 如果仍报 permission denied while trying to connect to the docker API"
    echo "  sudo chmod 666 /var/run/docker.sock   # 临时兜底方案"
    echo ""
    echo -e "${CYAN}▸ 2. 配置镜像加速${NC}（腾讯云机器优先）"
    echo ""
    cat <<'EOF'
  sudo mkdir -p /etc/docker
  sudo tee /etc/docker/daemon.json > /dev/null <<'JSON'
  {
    "registry-mirrors": [
      "https://mirror.ccs.tencentyun.com",
      "https://hub-mirror.c.163.com",
      "https://mirror.baidubce.com"
    ]
  }
  JSON
  sudo systemctl daemon-reload
  sudo systemctl restart docker
  docker info | sed -n '/Registry Mirrors/,$p'
EOF
    echo ""
    echo -e "${CYAN}▸ 3. 构建专用沙箱镜像${NC}"
    echo -e "  当前基础镜像: ${BOLD}${OPENCLAW_SANDBOX_BASE_IMAGE}${NC}"
    echo ""
    echo "  # 如基础镜像拉取慢，可改成你自己的 SWR / 私有仓库地址"
    echo "  export OPENCLAW_SANDBOX_BASE_IMAGE=\"${OPENCLAW_SANDBOX_BASE_IMAGE}\""
    echo ""
    echo "  docker build \\"
    echo "    --build-arg OPENCLAW_SANDBOX_BASE_IMAGE=${OPENCLAW_SANDBOX_BASE_IMAGE} \\"
    echo "    -t ${OPENCLAW_SANDBOX_IMAGE} \\"
    echo "    -f ${OPENCLAW_SANDBOX_DOCKERFILE} \\"
    echo "    ${REPO_ROOT}"
    echo ""
    echo "  # 验证镜像是否存在"
    echo "  docker image inspect ${OPENCLAW_SANDBOX_IMAGE}"
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}


_sandbox_image_available() {
    if ! cmd_exists docker; then
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        return 1
    fi

    docker image inspect "$OPENCLAW_SANDBOX_IMAGE" >/dev/null 2>&1
}


maybe_offer_sandbox_runtime_instructions() {
    local show_help_yn="n"

    if [[ "${ADD_PROVIDER_ONLY}" == "true" ]]; then
        return 0
    fi

    if [[ ! -r /dev/tty ]]; then
        return 0
    fi

    echo ""
    printf "%s" "如果你准备稍后创建沙箱 Agent，现在要查看准备命令并先退出脚本吗？[y/N]: "
    read -r show_help_yn </dev/tty || show_help_yn="n"
    show_help_yn="${show_help_yn:-n}"

    if [[ "$show_help_yn" =~ ^[Yy] ]]; then
        _print_sandbox_runtime_instructions
        echo ""
        info "已为你展示 Docker / 沙箱镜像准备命令。"
        info "准备完成后，请重新运行本脚本继续安装。"
        exit 0
    fi
}

# 打印前置依赖安装指南
_print_prereq_instructions() {
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  前置依赖安装指南${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${CYAN}▸ cmake / 构建工具${NC}（必须，OpenClaw 原生模块编译依赖）"
    echo ""
    if cmd_exists apt-get; then
        echo "  sudo apt-get install -y cmake build-essential"
    elif cmd_exists dnf; then
        echo "  sudo dnf install -y cmake gcc-c++ make"
    elif cmd_exists yum; then
        echo "  sudo yum install -y cmake gcc-c++ make"
    else
        echo "  # Ubuntu/Debian:"
        echo "  sudo apt-get install -y cmake build-essential"
        echo "  # RHEL/Rocky/CentOS:"
        echo "  sudo dnf install -y cmake gcc-c++ make"
    fi
    echo ""
    echo -e "${CYAN}▸ Node.js ${MIN_NODE_VERSION}+${NC}（OpenClaw 运行时，必须）"
    echo ""
    echo "  # 方式一：nvm via Gitee 镜像（国内推荐）"
    echo "  git clone https://gitee.com/mirrors/nvm.git ~/.nvm"
    echo "  echo 'export NVM_DIR=\"\$HOME/.nvm\"' >> ~/.bashrc"
    echo "  echo '[ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\"' >> ~/.bashrc"
    echo "  source ~/.bashrc"
    echo "  NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node nvm install ${MIN_NODE_VERSION}"
    echo ""
    echo "  # 方式二：NodeSource 官方源"
    if cmd_exists apt-get; then
        echo "  curl -fsSL https://deb.nodesource.com/setup_${MIN_NODE_VERSION}.x | sudo bash -"
        echo "  sudo apt-get install -y nodejs"
    elif cmd_exists dnf || cmd_exists yum; then
        echo "  curl -fsSL https://rpm.nodesource.com/setup_${MIN_NODE_VERSION}.x | sudo bash -"
        echo "  sudo yum install -y nodejs"
    else
        echo "  # Ubuntu/Debian:"
        echo "  curl -fsSL https://deb.nodesource.com/setup_${MIN_NODE_VERSION}.x | sudo bash -"
        echo "  sudo apt-get install -y nodejs"
        echo "  # RHEL/Rocky/CentOS:"
        echo "  curl -fsSL https://rpm.nodesource.com/setup_${MIN_NODE_VERSION}.x | sudo bash -"
        echo "  sudo yum install -y nodejs"
    fi
    echo ""
    echo "  # 国内镜像（阿里云）："
    echo "  Node.js 二进制: https://mirrors.aliyun.com/nodejs-release/"
    echo "  安装后配置 npm 镜像: npm config set registry https://registry.npmmirror.com"
    echo ""
    echo -e "${CYAN}▸ OpenClaw${NC}（必须）"
    echo ""
    echo "  # 方式一：官方安装脚本"
    echo "  curl -fsSL https://openclaw.ai/install.sh | OPENCLAW_VERSION=2026.02.26 bash"
    echo ""
    echo "  # 方式二：npm 安装"
    echo "  npm install -g openclaw@2026.02.26"
    echo ""
    echo -e "${CYAN}▸ Docker${NC}（仅启用沙箱 Agent 时需要）"
    echo ""
    echo "  无需现在安装。只有在创建 Docker 沙箱 Agent 时，脚本才会继续提示："
    echo "  1) 安装 Docker"
    echo "  2) 配置镜像加速"
    echo "  3) 构建专用沙箱镜像"
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 检查前置依赖
check_prerequisites() {
    header "第一步：检查前置环境"
    GATEWAY_TOKEN_PREPARE_REQUIRED=false

    local missing=false

    # --- cmake / 构建工具 ---
    if cmd_exists cmake; then
        success "cmake $(cmake --version | head -1 | awk '{print $3}')"
    else
        error "未找到 cmake（OpenClaw 原生模块编译依赖）"
        missing=true
    fi

    # --- Node.js ---
    if cmd_exists node; then
        local node_ver
        node_ver=$(node -v | sed 's/v//' | cut -d. -f1)
        if (( node_ver >= MIN_NODE_VERSION )); then
            success "Node.js $(node -v)"
        else
            error "Node.js 版本 $(node -v) 过低，需要 v${MIN_NODE_VERSION}+"
            missing=true
        fi
    else
        error "未找到 Node.js（需要 v${MIN_NODE_VERSION}+）"
        missing=true
    fi

    # --- Docker（可选，仅沙箱 Agent 需要）---
    if cmd_exists docker; then
        if docker info &>/dev/null 2>&1; then
            success "Docker $(docker --version | sed -E 's/.*version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
            if docker image inspect "$OPENCLAW_SANDBOX_IMAGE" >/dev/null 2>&1; then
                success "已检测到沙箱镜像: ${OPENCLAW_SANDBOX_IMAGE}"
            else
                step "未检测到沙箱镜像（只有创建 Docker 沙箱 Agent 时才需要）"
                maybe_offer_sandbox_runtime_instructions
            fi
        elif sudo docker info &>/dev/null 2>&1; then
            echo ""
            warn "Docker 已安装并运行，但当前用户无 socket 访问权限"
            warn "若后续启用 Docker 沙箱 Agent，请先执行以下任一操作："
            echo ""
            echo "  方式一（推荐）：重新 SSH 登录后再运行脚本"
            echo "  方式二：在当前终端执行 'newgrp docker'，然后重新运行脚本"
            echo "  方式三（临时兜底）：执行 'sudo chmod 666 /var/run/docker.sock' 后再运行脚本"
            echo ""
        else
            warn "未检测到可用 Docker（若后续启用 Docker 沙箱 Agent，请先安装并启动 Docker）"
        fi
    else
        warn "未找到 Docker（仅在启用 Docker 沙箱 Agent 时必须安装）"
    fi

    # --- OpenClaw ---
    if cmd_exists openclaw; then
        success "OpenClaw v$(openclaw --version 2>/dev/null || echo 'unknown')"
    else
        error "未找到 openclaw 命令"
        missing=true
    fi

    if [[ "$missing" == "true" ]]; then
        _print_prereq_instructions
        error "请安装以上缺失依赖后重新运行本脚本"
        exit 1
    fi

    echo ""

    # --- OpenClaw 初始化（首次 or 重置）---
    if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        step "首次初始化 OpenClaw..."
        cleanup_openclaw_sandbox_containers || warn "历史沙箱容器未完全清理，请稍后手动执行: openclaw sandbox recreate --all --force"
        echo -e "${DIM}将启动 OpenClaw 交互式配置向导...${NC}"
        echo ""
        run_openclaw_onboard
        success "OpenClaw 初始化完成"
        GATEWAY_TOKEN_PREPARE_REQUIRED=true
    else
        success "OpenClaw 配置已存在: ${OPENCLAW_CONFIG}"
        echo ""
        printf "%s" "是否清理当前安装并重新配置? [y/N]: "
        read -r reinstall_yn </dev/tty
        if [[ "$reinstall_yn" =~ ^[Yy] ]]; then
            step "清理当前 OpenClaw 安装..."
            openclaw gateway stop 2>/dev/null || true
            cleanup_openclaw_sandbox_containers || warn "历史沙箱容器未完全清理，请稍后手动执行: openclaw sandbox recreate --all --force"
            rm -rf "$OPENCLAW_HOME"
            success "清理完成，启动 OpenClaw 初始化向导..."
            echo ""
            run_openclaw_onboard
            success "OpenClaw 初始化完成"
            GATEWAY_TOKEN_PREPARE_REQUIRED=true
        fi
    fi

    # --- 初始化完成后再准备 Gateway Token ---
    # 避免在“是否重装”确认之前生成 ~/.openclaw/.env，随后又被 rm -rf 清掉
    if [[ "$GATEWAY_TOKEN_PREPARE_REQUIRED" == "true" ]]; then
        ensure_gateway_token
    fi

    # --- 确保 Gateway 已启动 ---
    ensure_gateway_running

    # --- 对齐 Gateway token（auth/remote）---
    echo ""
    step "同步 Gateway token 配置..."
    sync_gateway_tokens
    if [[ "$GATEWAY_TOKEN_SYNC_CHANGED" == "true" ]]; then
        step "检测到 token 变更，重启 Gateway 使配置生效..."
        restart_gateway_after_token_change || true
    fi
}

# 检测 OpenClaw 托管 Gateway 服务能力（launchd / systemd --user / schtasks）
get_gateway_service_mode() {
    local os_name
    os_name="$(uname -s 2>/dev/null || echo unknown)"

    case "$os_name" in
        Darwin)
            echo "launchd"
            ;;
        Linux)
            if ! cmd_exists systemctl; then
                echo "none"
                return 0
            fi

            if systemctl --user show-environment >/dev/null 2>&1; then
                echo "systemd-user"
            else
                echo "none"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*)
            echo "schtasks"
            ;;
        *)
            echo "none"
            ;;
    esac
}


gateway_service_supported() {
    [[ "$(get_gateway_service_mode)" != "none" ]]
}


gateway_start_hint() {
    if gateway_service_supported; then
        echo "openclaw gateway start"
    else
        echo "openclaw gateway run"
    fi
}


resolve_onboard_daemon_skip_flag() {
    local help_text

    if [[ -n "$OPENCLAW_ONBOARD_DAEMON_SKIP_FLAG" ]]; then
        echo "$OPENCLAW_ONBOARD_DAEMON_SKIP_FLAG"
        return 0
    fi

    help_text="$(openclaw onboard --help 2>&1 || true)"
    if echo "$help_text" | grep -q -- "--no-install-daemon"; then
        OPENCLAW_ONBOARD_DAEMON_SKIP_FLAG="--no-install-daemon"
    elif echo "$help_text" | grep -q -- "--skip-daemon"; then
        OPENCLAW_ONBOARD_DAEMON_SKIP_FLAG="--skip-daemon"
    else
        OPENCLAW_ONBOARD_DAEMON_SKIP_FLAG="unsupported"
    fi

    echo "$OPENCLAW_ONBOARD_DAEMON_SKIP_FLAG"
}


run_openclaw_onboard() {
    local skip_flag

    if gateway_service_supported; then
        openclaw onboard --install-daemon
        return 0
    fi

    warn "当前环境没有可用的 OpenClaw 托管服务能力（常见于 systemctl --user 不可用），将跳过 daemon 安装"
    skip_flag="$(resolve_onboard_daemon_skip_flag)"

    case "$skip_flag" in
        --no-install-daemon|--skip-daemon)
            openclaw onboard "$skip_flag"
            ;;
        *)
            warn "当前 OpenClaw 版本不支持跳过 daemon 安装参数，请在向导中手动跳过服务安装"
            openclaw onboard
            ;;
    esac
}


start_gateway_run_fallback() {
    local pid=""

    mkdir -p "$OPENCLAW_HOME"

    if [[ -f "$OPENCLAW_GATEWAY_RUN_PID_FILE" ]]; then
        pid="$(cat "$OPENCLAW_GATEWAY_RUN_PID_FILE" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            step "检测到兼容模式 Gateway 已在运行（PID: ${pid}）"
            return 0
        fi
        rm -f "$OPENCLAW_GATEWAY_RUN_PID_FILE"
    fi

    nohup openclaw gateway run >"$OPENCLAW_GATEWAY_RUN_LOG_FILE" 2>&1 &
    pid=$!
    echo "$pid" > "$OPENCLAW_GATEWAY_RUN_PID_FILE"
    sleep 3

    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && openclaw health &>/dev/null; then
        success "已用兼容模式启动 Gateway（后台执行 openclaw gateway run）"
        echo -e "  ${DIM}日志: ${OPENCLAW_GATEWAY_RUN_LOG_FILE}${NC}"
        return 0
    fi

    warn "兼容模式 Gateway 启动后仍未通过健康检查，请查看日志: ${OPENCLAW_GATEWAY_RUN_LOG_FILE}"
    return 1
}


restart_gateway_run_fallback() {
    local pid=""

    if [[ -f "$OPENCLAW_GATEWAY_RUN_PID_FILE" ]]; then
        pid="$(cat "$OPENCLAW_GATEWAY_RUN_PID_FILE" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" >/dev/null 2>&1 || true
            sleep 1
        fi
        rm -f "$OPENCLAW_GATEWAY_RUN_PID_FILE"
        start_gateway_run_fallback
        return $?
    fi

    if openclaw health &>/dev/null; then
        warn "当前环境未使用托管服务，若 Gateway 已在运行，请手动重启当前进程使新 token 生效"
        return 0
    fi

    start_gateway_run_fallback
}


ensure_gateway_running() {
    local start_hint
    start_hint="$(gateway_start_hint)"

    step "检查 Gateway 状态..."
    if openclaw health &>/dev/null; then
        success "Gateway 已在运行"
        return 0
    fi

    if gateway_service_supported; then
        step "启动 Gateway 服务..."
        openclaw gateway start >/dev/null 2>&1 || true
    else
        warn "当前环境不可用托管服务，改为后台执行: ${start_hint}"
        start_gateway_run_fallback || {
            warn "Gateway 兼容启动失败，请稍后手动运行: ${start_hint}"
            return 0
        }
    fi

    sleep 3
    if openclaw health &>/dev/null; then
        success "Gateway 启动成功"
    else
        warn "Gateway 启动失败，Agent 创建可能受影响，请稍后手动运行: ${start_hint}"
    fi
}


restart_gateway_after_token_change() {
    if gateway_service_supported; then
        openclaw gateway restart >/dev/null 2>&1 || {
            warn "Gateway 重启失败，请稍后手动执行: openclaw gateway restart"
            return 1
        }
        sleep 2
        return 0
    fi

    restart_gateway_run_fallback || {
        warn "Gateway 兼容模式重启失败，请手动重启当前 openclaw gateway run 进程"
        return 1
    }
    sleep 2
    return 0
}

# JSON5 配置读取（通过 openclaw config get）
config_get() { openclaw config get "$1" 2>/dev/null || echo ""; }

# JSON5 配置设置（通过 openclaw config set）
config_set() { openclaw config set "$1" "$2" 2>/dev/null || true; }


_read_token_from_config_file() {
    # 直接读配置文件中的 token 原文，避免 openclaw config get 对敏感值做掩码
    local token_type="$1"  # auth | remote
    if ! cmd_exists python3 || [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        echo ""
        return 0
    fi

python3 - "$OPENCLAW_CONFIG" "$token_type" <<'PYEOF'
import json
import re
import sys

config_path = sys.argv[1]
token_type = sys.argv[2]

try:
    with open(config_path, 'r') as f:
        content = f.read()
    try:
        config = json.loads(content)
    except json.JSONDecodeError:
        content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        content = re.sub(r',\s*([}\]])', r'\1', content)
        config = json.loads(content)
except Exception:
    print('')
    sys.exit(0)

gateway = config.get('gateway', {})
if token_type == 'auth':
    print(gateway.get('auth', {}).get('token', '') or '')
elif token_type == 'remote':
    print(gateway.get('remote', {}).get('token', '') or '')
else:
    print('')
PYEOF
}


_read_sandbox_image_info_from_config_file() {
    if ! cmd_exists python3 || [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        return 0
    fi

python3 - "$OPENCLAW_CONFIG" <<'PYEOF'
import json
import re
import sys

config_path = sys.argv[1]

try:
    with open(config_path, 'r') as f:
        content = f.read()
    try:
        config = json.loads(content)
    except json.JSONDecodeError:
        content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
        content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
        content = re.sub(r',\s*([}\]])', r'\1', content)
        config = json.loads(content)
except Exception:
    sys.exit(0)

seen = set()

def emit(label, image):
    if not image:
        return
    key = (label, image)
    if key in seen:
        return
    seen.add(key)
    print(f"{label}|{image}")

agents_cfg = config.get('agents', {}) or {}
defaults = agents_cfg.get('defaults', {}) or {}
default_image = (((defaults.get('sandbox') or {}).get('docker') or {}).get('image') or '').strip()
emit('agents.defaults.sandbox.docker.image', default_image)

for agent in agents_cfg.get('list', []) or []:
    if not isinstance(agent, dict):
        continue
    agent_id = (agent.get('id') or '').strip() or 'unknown'
    image = ((((agent.get('sandbox') or {}).get('docker') or {}).get('image')) or '').strip()
    emit(f'agents.list[{agent_id}].sandbox.docker.image', image)
PYEOF
}


_read_openclaw_default_sandbox_image_from_source() {
    if ! cmd_exists python3 || ! cmd_exists openclaw; then
        echo ""
        return 0
    fi

python3 - "$(command -v openclaw)" <<'PYEOF'
import os
import re
import sys

bin_path = sys.argv[1]
if not bin_path:
    print('')
    sys.exit(0)

real_path = os.path.realpath(bin_path)
package_root = os.path.dirname(real_path)
dist_dir = os.path.join(package_root, 'dist')

pattern = re.compile(r'DEFAULT_SANDBOX_IMAGE\s*=\s*"([^"]+)"')

if not os.path.isdir(dist_dir):
    print('')
    sys.exit(0)

for root, _, files in os.walk(dist_dir):
    for name in files:
        if not name.endswith('.js'):
            continue
        path = os.path.join(root, name)
        try:
            with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                match = pattern.search(f.read())
            if match:
                print(match.group(1))
                sys.exit(0)
        except Exception:
            continue

print('')
PYEOF
}


show_current_sandbox_image_info() {
    echo ""
    step "识别当前 OpenClaw 沙箱镜像配置..."

    if [[ -f "$OPENCLAW_CONFIG" ]]; then
        local lines found_any="false"
        lines="$(_read_sandbox_image_info_from_config_file || true)"
        if [[ -n "$lines" ]]; then
            while IFS='|' read -r label image; do
                [[ -z "$label" || -z "$image" ]] && continue
                echo -e "  ${DIM}${label}${NC} = ${image}"
                found_any="true"
            done <<< "$lines"
        fi
        if [[ "$found_any" != "true" ]]; then
            warn "已检测到 ${OPENCLAW_CONFIG}，但未找到显式 sandbox.docker.image 配置"
        fi
        echo -e "  ${DIM}本脚本目标镜像${NC} = ${OPENCLAW_SANDBOX_IMAGE}"
        return 0
    fi

    local default_image
    default_image="$(_read_openclaw_default_sandbox_image_from_source)"
    if [[ -n "$default_image" ]]; then
        echo -e "  ${DIM}OpenClaw 源码默认镜像${NC} = ${default_image}"
    else
        warn "未检测到本地 OpenClaw 配置，且无法从源码解析默认沙箱镜像"
    fi
    echo -e "  ${DIM}本脚本目标镜像${NC} = ${OPENCLAW_SANDBOX_IMAGE}"
}


sync_gateway_tokens() {
    # 将 gateway.auth.token 与 gateway.remote.token 设置为环境变量引用
    local auth_token remote_token env_token
    GATEWAY_TOKEN_SYNC_CHANGED=false

    auth_token=$(_read_token_from_config_file "auth")
    remote_token=$(_read_token_from_config_file "remote")
    env_token="$(_read_env_file_value "$OPENCLAW_ENV_FILE" "OPENCLAW_GATEWAY_TOKEN")"

    if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" && -z "$env_token" && "$GATEWAY_TOKEN_PREPARE_REQUIRED" != "true" ]]; then
        if [[ "$auth_token" == "\${OPENCLAW_GATEWAY_TOKEN}" || "$remote_token" == "\${OPENCLAW_GATEWAY_TOKEN}" ]]; then
            warn "当前 Gateway 配置依赖 OPENCLAW_GATEWAY_TOKEN，但 ${OPENCLAW_ENV_FILE} 中未找到该变量"
            warn "请先补充 ${OPENCLAW_ENV_FILE}，再重新执行 token 同步"
        else
            step "检测到沿用现有安装，跳过 Gateway Token 初始化"
        fi
        return 0
    fi

    ensure_gateway_token

    # 检查是否已经是环境变量引用格式
    if [[ "$auth_token" != "\${OPENCLAW_GATEWAY_TOKEN}" ]]; then
        config_set "gateway.auth.token" "\${OPENCLAW_GATEWAY_TOKEN}"
        GATEWAY_TOKEN_SYNC_CHANGED=true
        step "已将 gateway.auth.token 设置为环境变量引用"
    fi

    if [[ "$remote_token" != "\${OPENCLAW_GATEWAY_TOKEN}" ]]; then
        config_set "gateway.remote.token" "\${OPENCLAW_GATEWAY_TOKEN}"
        GATEWAY_TOKEN_SYNC_CHANGED=true
        step "已将 gateway.remote.token 设置为环境变量引用"
    fi

    if [[ "$GATEWAY_TOKEN_SYNC_CHANGED" == "true" ]]; then
        success "Gateway token 已设置为环境变量引用"
    else
        step "Gateway token 已是环境变量引用，无需调整"
    fi
}


_status_has_token_mismatch() {
    local text="$1"
    echo "$text" | grep -Eqi "config token differs from service token|gateway token mismatch|gateway auth token mismatch|service token is stale"
}


repair_gateway_service_token_if_needed() {
    # 如果 service token 与 config token 漂移，自动执行 gateway install --force 修复
    local status_output

    if ! gateway_service_supported; then
        return 0
    fi

    status_output="$(openclaw gateway status 2>&1 || true)"

    if ! _status_has_token_mismatch "$status_output"; then
        return 0
    fi

    warn "检测到 Gateway 服务 token 与配置可能不一致，尝试自动修复..."
    if ! openclaw gateway install --force >/dev/null 2>&1; then
        error "自动修复失败: openclaw gateway install --force"
        echo "$status_output"
        return 1
    fi

    openclaw gateway restart >/dev/null 2>&1 || true
    sleep 2
    success "已执行 gateway install --force 并重启服务"
    return 0
}


hard_check_gateway_token_health() {
    # 硬校验：gateway status 必须 RPC ok，doctor 不得出现 token stale/mismatch
    local status_output doctor_output

    if ! gateway_service_supported; then
        step "当前环境未启用托管 Gateway 服务，跳过 service token / doctor 硬校验"
        if openclaw health >/dev/null 2>&1; then
            success "Gateway 直连健康检查通过"
        else
            warn "Gateway 当前未运行，已跳过服务级 token 校验"
        fi
        return 0
    fi

    # 先尝试自动修复 service token 漂移（不影响已健康场景）
    if ! repair_gateway_service_token_if_needed; then
        error "自动修复 service token 失败，请先处理后再重试"
        return 1
    fi

    step "Gateway RPC 探针校验..."
    status_output="$(openclaw gateway status 2>&1 || true)"

    if _status_has_token_mismatch "$status_output"; then
        error "检测到 Gateway token 不一致（gateway status）"
        echo "$status_output"
        return 1
    fi

    if ! echo "$status_output" | grep -q "RPC probe: ok"; then
        error "Gateway RPC probe 未通过，请先修复后再继续"
        echo "$status_output"
        return 1
    fi
    success "Gateway RPC probe: ok"

    step "OpenClaw doctor token 校验..."
    doctor_output="$(openclaw doctor --non-interactive 2>&1 || true)"
    if echo "$doctor_output" | grep -Eqi "service token is stale|gateway token mismatch|gateway auth token mismatch|config token differs from service token"; then
        error "检测到 token 漂移（openclaw doctor）"
        echo "$doctor_output"
        return 1
    fi
    success "OpenClaw doctor 未发现 token 漂移"
}


shared_dir_for_agent() {
    local agent_id="$1"
    printf "%s/%s\n" "$HOST_SHARED_ROOT" "$agent_id"
}


shared_source_dir_for_agent() {
    local agent_id="$1"
    if [[ "$agent_id" == "main" ]]; then
        printf "%s/shared\n" "${OPENCLAW_HOME}/workspace"
    else
        printf "%s/shared\n" "${OPENCLAW_HOME}/workspace-${agent_id}"
    fi
}


ensure_shared_root() {
    if [[ -d "$HOST_SHARED_ROOT" && -w "$HOST_SHARED_ROOT" ]]; then
        return 0
    fi

    if mkdir -p "$HOST_SHARED_ROOT" 2>/dev/null; then
        chmod 775 "$HOST_SHARED_ROOT" 2>/dev/null || true
        return 0
    fi

    warn "无法自动创建共享根目录: ${HOST_SHARED_ROOT}"
    echo -e "  ${DIM}请先执行: sudo mkdir -p ${HOST_SHARED_ROOT}${NC}"
    echo -e "  ${DIM}          sudo chown $(whoami):$(id -gn) ${HOST_SHARED_ROOT}${NC}"
    echo -e "  ${DIM}          sudo chmod 775 ${HOST_SHARED_ROOT}${NC}"
    return 1
}


ensure_shared_dir_for_agent() {
    local agent_id="$1"
    local shared_dir
    local shared_source_dir
    shared_dir="$(shared_dir_for_agent "$agent_id")"
    shared_source_dir="$(shared_source_dir_for_agent "$agent_id")"

    if ! ensure_shared_root; then
        return 1
    fi

    if ! mkdir -p "$shared_source_dir" 2>/dev/null; then
        warn "无法自动创建共享真实目录: ${shared_source_dir}"
        echo -e "  ${DIM}请先确认 $(dirname "$shared_source_dir") 对当前用户可写${NC}"
        return 1
    fi

    if cmd_exists python3; then
        local layout_output layout_status
        layout_output="$(python3 - "$shared_source_dir" "$shared_dir" <<'PYEOF'
import os
import shutil
import sys

source_dir = os.path.realpath(sys.argv[1])
exposed_dir = sys.argv[2]

os.makedirs(source_dir, exist_ok=True)
os.makedirs(os.path.dirname(exposed_dir), exist_ok=True)

if os.path.islink(exposed_dir):
    if os.path.realpath(exposed_dir) != source_dir:
        os.remove(exposed_dir)
        os.symlink(source_dir, exposed_dir)
        print(f"fixed:{exposed_dir}->{source_dir}")
    else:
        print(f"ok:{exposed_dir}->{source_dir}")
    raise SystemExit(0)

if os.path.isdir(exposed_dir):
    if os.path.realpath(exposed_dir) == source_dir:
        print(f"ok:{exposed_dir}->{source_dir}")
        raise SystemExit(0)

    conflicts = [name for name in os.listdir(exposed_dir) if os.path.exists(os.path.join(source_dir, name))]
    if conflicts:
        print("conflict:" + ",".join(conflicts))
        raise SystemExit(2)

    for name in os.listdir(exposed_dir):
        shutil.move(os.path.join(exposed_dir, name), os.path.join(source_dir, name))
    os.rmdir(exposed_dir)
    os.symlink(source_dir, exposed_dir)
    print(f"migrated:{exposed_dir}->{source_dir}")
    raise SystemExit(0)

if os.path.lexists(exposed_dir):
    print(f"unsupported:{exposed_dir}")
    raise SystemExit(3)

os.symlink(source_dir, exposed_dir)
print(f"created:{exposed_dir}->{source_dir}")
PYEOF
)"
        layout_status=$?

        case "$layout_status" in
            0)
                return 0
                ;;
            2)
                warn "共享路径已存在冲突文件，未自动迁移: ${shared_dir}"
                echo -e "  ${DIM}请手动整理后改为软链: ${shared_dir} -> ${shared_source_dir}${NC}"
                return 1
                ;;
            *)
                warn "无法自动创建共享目录软链: ${shared_dir}"
                echo -e "  ${DIM}${layout_output}${NC}"
                return 1
                ;;
        esac
    fi

    if [[ ! -e "$shared_dir" ]]; then
        ln -s "$shared_source_dir" "$shared_dir" 2>/dev/null && return 0
    fi

    warn "无法自动创建共享目录软链: ${shared_dir}"
    echo -e "  ${DIM}请手动确认软链: ${shared_dir} -> ${shared_source_dir}${NC}"
    return 1
}


hard_check_sandbox_shared_contract() {
    # 硬校验：沙箱 agent 的共享目录契约必须成立（workspace/shared -> /app/shared/<agent_id>）
    if ! cmd_exists python3; then
        warn "未找到 python3，跳过共享目录契约校验"
        return 0
    fi

    local check_output
check_output="$(python3 <<'PYEOF'
import json
import os
import re
import sys

config_path = os.path.expanduser('~/.openclaw/openclaw.json')
if not os.path.exists(config_path):
    print(f'ERROR: OpenClaw 配置不存在: {config_path}')
    sys.exit(1)

with open(config_path, 'r') as f:
    content = f.read()

try:
    config = json.loads(content)
except json.JSONDecodeError:
    content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    content = re.sub(r',\s*([}\]])', r'\1', content)
    config = json.loads(content)

agents = config.get('agents', {}).get('list', [])
errors = []
notes = []
checked = 0

for agent in agents:
    agent_id = agent.get('id', '')
    if not agent_id or agent_id == 'main':
        continue

    sandbox = agent.get('sandbox', {})
    if sandbox.get('mode') != 'all':
        continue

    checked += 1

    if sandbox.get('workspaceAccess') != 'rw':
        errors.append(f"{agent_id}: workspaceAccess 不是 rw（当前: {sandbox.get('workspaceAccess')}）")

    workspace = agent.get('workspace') or os.path.expanduser(f"~/.openclaw/workspace-{agent_id}")
    shared_src = os.path.join(workspace, 'shared')
    shared_dst = os.path.join('/app/shared', agent_id)

    if not os.path.exists(shared_src):
        os.makedirs(shared_src, exist_ok=True)
        notes.append(f"{agent_id}: 已自动创建共享目录 {shared_src}")

    if not os.path.lexists(shared_dst):
        errors.append(f"{agent_id}: 缺少宿主机暴露路径 {shared_dst}（应软链到 {shared_src}）")
        continue

    if os.path.realpath(shared_dst) != os.path.realpath(shared_src):
        errors.append(f"{agent_id}: 宿主机暴露路径异常（当前: {shared_dst} -> {os.path.realpath(shared_dst)}，期望: {shared_src}）")
        continue

    docker_cfg = sandbox.get('docker', {})
    expected_src = os.path.realpath(shared_src)
    expected_dst = shared_dst
    mount_ok = False

    for item in (docker_cfg.get('binds') or []):
        if not isinstance(item, str):
            continue
        parts = item.split(':')
        if len(parts) < 2:
            continue
        src = os.path.realpath(parts[0])
        dst = parts[1]
        if src == expected_src and dst == expected_dst:
            mount_ok = True
            break

    if not mount_ok:
        for item in (docker_cfg.get('mounts') or []):
            if not isinstance(item, dict):
                continue
            src = os.path.realpath(str(item.get('source', '')))
            dst = str(item.get('target', ''))
            if src == expected_src and dst == expected_dst:
                mount_ok = True
                break

    if not mount_ok:
        errors.append(f"{agent_id}: 缺少共享目录挂载（需要 {shared_src} -> {shared_dst}）")

if errors:
    print('SANDBOX_SHARED_CONTRACT_FAILED')
    for item in errors:
        print(f"- {item}")
    sys.exit(1)

if checked == 0:
    print('NO_SANDBOX_AGENT')
else:
    print('SANDBOX_SHARED_CONTRACT_OK')
    for item in notes:
        print(f"- {item}")
PYEOF
)" || {
        error "共享目录契约校验失败"
        echo "$check_output"
        return 1
    }

    if [[ "$check_output" == *"NO_SANDBOX_AGENT"* ]]; then
        step "未检测到启用沙箱的子 Agent，跳过共享目录契约校验"
        return 0
    fi

    if [[ "$check_output" == *"SANDBOX_SHARED_CONTRACT_OK"* ]]; then
        success "沙箱共享目录契约校验通过（workspace/shared 已挂到 /app/shared/<agent_id>）"
        if echo "$check_output" | grep -q "^- "; then
            echo "$check_output" | grep "^- "
        fi

        if cmd_exists docker; then
            local containers probe_failed=0
            containers=$(openclaw sandbox list 2>/dev/null | grep -Eo 'openclaw-sbx-agent-[^[:space:]]+' | sort -u || true)
            if [[ -n "$containers" ]]; then
                while IFS= read -r c; do
                    [[ -z "$c" ]] && continue
                    local agent_id
                    agent_id="${c#openclaw-sbx-agent-}"
                    if ! docker exec -w /workspace "$c" sh -lc "mkdir -p '/app/shared/${agent_id}' && touch '/app/shared/${agent_id}/.probe' && rm -f '/app/shared/${agent_id}/.probe'" >/dev/null 2>&1; then
                        warn "运行时共享目录探针失败: ${c}"
                        probe_failed=1
                    fi
                done <<< "$containers"
                if [[ "$probe_failed" -eq 1 ]]; then
                    error "沙箱运行时共享目录探针失败，请检查容器挂载状态"
                    return 1
                fi
                success "沙箱运行时共享目录探针通过"
            else
                step "未检测到运行中的沙箱容器，跳过运行时共享目录探针"
            fi
        fi

        return 0
    fi

    error "共享目录契约校验结果异常"
    echo "$check_output"
    return 1
}

# 读取用户输入（带默认值）
read_input() {
    local prompt="$1"
    local default="${2:-}"
    local result

    if [[ -n "$default" ]]; then
        printf "%s" "${prompt} [${default}]: "
    else
        printf "%s" "${prompt}: "
    fi

    # 确保从终端读取
    if [[ -t 0 ]]; then
        read -r result
    else
        read -r result </dev/tty 2>/dev/null || read -r result
    fi

    echo "${result:-$default}"
}

# 读取密码输入（不回显）
read_secret() {
    local prompt="$1"
    local result
    printf "%s" "${prompt}: "

    # 确保从终端读取
    if [[ -t 0 ]]; then
        read -rs result
    else
        read -rs result </dev/tty 2>/dev/null || read -rs result
    fi

    echo ""
    echo "$result"
}

# 确认提示
confirm() {
    local prompt="${1:-确认?}"
    local default="${2:-n}"
    local yn

    if [[ "$default" == "y" ]]; then
        printf "%s" "${prompt} [Y/n]: "
    else
        printf "%s" "${prompt} [y/N]: "
    fi

    # 确保从终端读取
    if [[ -t 0 ]]; then
        read -r yn
    else
        read -r yn </dev/tty 2>/dev/null || read -r yn
    fi

    yn="${yn:-$default}"
    [[ "$yn" =~ ^[Yy] ]]
}

# 用编辑器编辑文件（带提示）
edit_file() {
    local filepath="$1"
    local description="$2"
    local filename
    filename=$(basename "$filepath")

    echo ""
    echo -e "${BOLD}${CYAN}编辑 ${filename}${NC} — ${description}"
    echo -e "${DIM}文件路径: ${filepath}${NC}"
    echo ""

    if confirm "是否打开编辑器编辑此文件?" "y"; then
        $EDITOR "$filepath"
        success "${filename} 已保存"
    else
        step "跳过编辑 ${filename}"
    fi
}

# 选择菜单
select_option() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice

    echo -e "${prompt}"
    for i in "${!options[@]}"; do
        echo -e "  ${BOLD}$((i+1))${NC}) ${options[$i]}"
    done
    echo -en "\n请选择 [1-${#options[@]}]: "

    # 确保从终端读取
    if [[ -t 0 ]]; then
        read -r choice
    else
        read -r choice </dev/tty 2>/dev/null || {
            error "无法读取用户输入（非交互式环境）"
            echo "0"
            return 1
        }
    fi

    # 验证输入
    if [[ -z "$choice" ]]; then
        warn "输入为空，请重新输入"
        echo "0"
        return 1
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
        echo "$((choice-1))"
    else
        warn "无效输入: $choice"
        echo "0"
        return 1
    fi
}


cleanup_openclaw_sandbox_containers() {
    # 清理历史沙箱容器（重装时使用）
    if ! cmd_exists docker; then
        warn "未找到 Docker，跳过历史沙箱容器清理"
        return 0
    fi

    show_current_sandbox_image_info

    step "执行 openclaw sandbox recreate 清理历史容器..."
    if cmd_exists openclaw; then
        if openclaw sandbox recreate --all --force >/dev/null 2>&1; then
            success "已执行 openclaw sandbox recreate --all --force"
        else
            warn "openclaw sandbox recreate 执行失败，继续检查 Docker 残留容器"
        fi
    else
        warn "未找到 openclaw 命令，跳过官方清理命令，直接检查 Docker 残留容器"
    fi

    step "复查 Docker 残留沙箱容器..."
    local existing
    existing=$(docker ps -a --format '{{.Names}}' | grep -E '^openclaw-sbx-' || true)
    if [[ -z "$existing" ]]; then
        success "未检测到残留 OpenClaw 沙箱容器"
        return 0
    fi

    warn "仍检测到孤儿沙箱容器"
    local container removed=0 failed=0
    while IFS= read -r container; do
        [[ -z "$container" ]] && continue
        echo -e "  ${YELLOW}残留容器:${NC} ${container}"
    done <<< "$existing"

    step "使用 docker rm -f 强制清理残留容器..."
    while IFS= read -r container; do
        [[ -z "$container" ]] && continue
        if docker rm -f "$container" >/dev/null 2>&1; then
            success "已强制删除孤儿沙箱容器: ${container}"
            removed=$((removed + 1))
        else
            warn "删除沙箱容器失败: ${container}"
            failed=$((failed + 1))
        fi
    done <<< "$existing"

    if [[ "$failed" -gt 0 ]]; then
        warn "历史沙箱容器清理完成（成功 ${removed}，失败 ${failed}）"
        return 1
    fi

    success "历史沙箱容器清理完成（共 ${removed} 个）"
    return 0
}


require_custom_sandbox_image() {
    # 启用沙箱 Agent 时强制检查专用沙箱镜像是否已准备完成
    if ! cmd_exists docker; then
        error "未找到 Docker，无法启用 Docker 沙箱"
        _print_sandbox_runtime_instructions
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        if sudo docker info >/dev/null 2>&1; then
            echo ""
            error "Docker 已安装并运行，但当前用户无 socket 访问权限"
            warn "请执行以下任一操作后重新运行脚本："
            echo ""
            echo "  方式一（推荐）：重新 SSH 登录后再运行脚本"
            echo "  方式二：在当前终端执行 'newgrp docker'，然后重新运行脚本"
            echo "  方式三（临时兜底）：执行 'sudo chmod 666 /var/run/docker.sock' 后再运行脚本"
            echo ""
        else
            error "Docker 未运行，无法启用 Docker 沙箱"
        fi
        return 1
    fi

    if [[ ! -f "$OPENCLAW_SANDBOX_DOCKERFILE" ]]; then
        error "未找到专用沙箱镜像 Dockerfile: ${OPENCLAW_SANDBOX_DOCKERFILE}"
        return 1
    fi

    if _sandbox_image_available; then
        success "检测到专用沙箱镜像已存在: ${OPENCLAW_SANDBOX_IMAGE}"
        return 0
    fi

    error "未检测到专用沙箱镜像: ${OPENCLAW_SANDBOX_IMAGE}"
    warn "启用 Docker 沙箱 Agent 前，请先手动构建专用沙箱镜像"
    _print_sandbox_runtime_instructions
    return 1
}


_read_env_file_value() {
    local env_file="$1"
    local key="$2"
    if [[ -z "$env_file" || ! -f "$env_file" ]]; then
        echo ""
        return 0
    fi

python3 - "$env_file" "$key" <<'PYEOF'
import sys

env_file = sys.argv[1]
key = sys.argv[2]

try:
    with open(env_file, 'r', encoding='utf-8') as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            k, v = line.split('=', 1)
            if k.strip() != key:
                continue
            value = v.strip().strip('"').strip("'")
            print(value)
            break
except Exception:
    print('')
PYEOF
}


_detect_gateway_env_file() {
    local candidate
    if [[ -n "${OPENCLAW_GATEWAY_ENV_FILE:-}" && -f "${OPENCLAW_GATEWAY_ENV_FILE}" ]]; then
        echo "${OPENCLAW_GATEWAY_ENV_FILE}"
        return 0
    fi

    for candidate in "/opt/openclaw/gateway/.env" "/opt/openclaw/.env" "${REPO_ROOT}/.env" "$(pwd)/.env"; do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    done

    echo ""
}


_resolve_file_storage_mode() {
    local mode env_file
    mode="${FILE_STORAGE_MODE:-}"
    if [[ -z "$mode" ]]; then
        env_file="$(_detect_gateway_env_file)"
        mode="$(_read_env_file_value "$env_file" "FILE_STORAGE_MODE")"
    fi
    mode="${mode:-local}"
    mode="$(echo "$mode" | tr 'A-Z' 'a-z')"

    case "$mode" in
        local|s3)
            echo "$mode"
            ;;
        *)
            warn "检测到未知 FILE_STORAGE_MODE=${mode}，回退 local"
            echo "local"
            ;;
    esac
}


UPLOAD_SKILL_GATEWAY_URL=""
UPLOAD_SKILL_TOKEN=""
UPLOAD_SKILL_EXPIRES=""
UPLOAD_SKILL_SANDBOX_GATEWAY_URL=""


_resolve_sandbox_upload_skill_gateway_url() {
    local gateway_url="$1"

python3 - "$gateway_url" <<'PYEOF'
import sys
from urllib.parse import urlsplit, urlunsplit

gateway_url = (sys.argv[1] or '').strip()
if not gateway_url:
    print('')
    sys.exit(0)

try:
    parsed = urlsplit(gateway_url)
except Exception:
    print(gateway_url)
    sys.exit(0)

hostname = (parsed.hostname or '').strip().lower()
if hostname not in {'localhost', '127.0.0.1', '::1'}:
    print(gateway_url)
    sys.exit(0)

netloc = parsed.netloc
if '@' in netloc:
    userinfo, hostport = netloc.rsplit('@', 1)
    prefix = f'{userinfo}@'
else:
    prefix = ''
    hostport = netloc

if hostport.startswith('['):
    closing = hostport.find(']')
    remainder = hostport[closing + 1:] if closing >= 0 else ''
else:
    remainder = ''
    if ':' in hostport:
        remainder = hostport[hostport.find(':'):]

new_netloc = f'{prefix}host.docker.internal{remainder}'
print(urlunsplit((parsed.scheme, new_netloc, parsed.path, parsed.query, parsed.fragment)))
PYEOF
}


_resolve_gateway_skill_runtime_values() {
    local env_file
    env_file="$(_detect_gateway_env_file)"

    UPLOAD_SKILL_GATEWAY_URL="${OPENCLAW_FILE_UPLOAD_GATEWAY_URL:-}"
    UPLOAD_SKILL_TOKEN="${OPENCLAW_FILE_UPLOAD_TOKEN:-}"
    UPLOAD_SKILL_EXPIRES="${OPENCLAW_FILE_UPLOAD_EXPIRES:-}"

    if [[ -z "$UPLOAD_SKILL_GATEWAY_URL" ]]; then
        UPLOAD_SKILL_GATEWAY_URL="$(_read_env_file_value "$env_file" "GATEWAY_URL")"
    fi
    if [[ -z "$UPLOAD_SKILL_GATEWAY_URL" ]]; then
        UPLOAD_SKILL_GATEWAY_URL="$(_read_env_file_value "$OPENCLAW_ENV_FILE" "OPENCLAW_FILE_UPLOAD_GATEWAY_URL")"
    fi
    if [[ -z "$UPLOAD_SKILL_TOKEN" ]]; then
        UPLOAD_SKILL_TOKEN="$(_read_env_file_value "$env_file" "FILE_UPLOAD_INTERNAL_TOKEN")"
    fi
    if [[ -z "$UPLOAD_SKILL_TOKEN" ]]; then
        UPLOAD_SKILL_TOKEN="$(_read_env_file_value "$OPENCLAW_ENV_FILE" "OPENCLAW_FILE_UPLOAD_TOKEN")"
    fi
    if [[ -z "$UPLOAD_SKILL_EXPIRES" ]]; then
        UPLOAD_SKILL_EXPIRES="$(_read_env_file_value "$env_file" "FILE_STORAGE_PRESIGN_EXPIRES")"
    fi
    if [[ -z "$UPLOAD_SKILL_EXPIRES" ]]; then
        UPLOAD_SKILL_EXPIRES="$(_read_env_file_value "$OPENCLAW_ENV_FILE" "OPENCLAW_FILE_UPLOAD_EXPIRES")"
    fi

    UPLOAD_SKILL_GATEWAY_URL="${UPLOAD_SKILL_GATEWAY_URL:-http://localhost:8000}"
    UPLOAD_SKILL_EXPIRES="${UPLOAD_SKILL_EXPIRES:-86400}"
    UPLOAD_SKILL_SANDBOX_GATEWAY_URL="$(_resolve_sandbox_upload_skill_gateway_url "$UPLOAD_SKILL_GATEWAY_URL")"
}


_list_openclaw_agent_workspaces() {
    if ! cmd_exists python3 || [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        return 0
    fi

python3 - "$OPENCLAW_CONFIG" "$OPENCLAW_HOME" <<'PYEOF'
import json
import os
import re
import sys

config_path, openclaw_home = sys.argv[1:3]

with open(config_path, 'r', encoding='utf-8') as f:
    content = f.read()

try:
    config = json.loads(content)
except json.JSONDecodeError:
    content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    content = re.sub(r',\s*([}\]])', r'\1', content)
    config = json.loads(content)

agents_cfg = config.get('agents', {})
defaults = agents_cfg.get('defaults', {})
default_workspace = defaults.get('workspace') or os.path.join(openclaw_home, 'workspace')

seen = set()
for agent in agents_cfg.get('list', []):
    agent_id = (agent.get('id') or '').strip()
    if not agent_id:
        continue
    workspace = (agent.get('workspace') or '').strip()
    if not workspace:
        if agent_id == 'main':
            workspace = default_workspace
        else:
            workspace = os.path.join(openclaw_home, f'workspace-{agent_id}')
    workspace = os.path.abspath(os.path.expanduser(workspace))
    print(f"{agent_id}\t{workspace}")
    seen.add(agent_id)

if 'main' not in seen:
    workspace = os.path.abspath(os.path.expanduser(default_workspace))
    print(f"main\t{workspace}")
PYEOF
}


_sync_gateway_skill_to_workspace() {
    local agent_id="$1"
    local workspace="$2"

    if [[ -z "$workspace" ]]; then
        return 0
    fi

    local target_dir="${workspace}/skills/${GATEWAY_SKILL_NAME}"

    if [[ ! -d "$GATEWAY_SKILL_SOURCE_DIR" ]]; then
        error "未找到 Skill 模板目录: $GATEWAY_SKILL_SOURCE_DIR"
        return 1
    fi

    mkdir -p "${workspace}/skills"
    rm -rf "$target_dir"
    cp -R "$GATEWAY_SKILL_SOURCE_DIR" "$target_dir"
    chmod +x "$target_dir/upload_to_gateway.py" 2>/dev/null || true
    step "已同步 Skill 到 agent=${agent_id} 的 workspace: ${workspace}/skills"
}


_sync_gateway_skill_to_all_workspaces() {
    local count=0
    local line agent_id workspace

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        agent_id="${line%%$'\t'*}"
        workspace="${line#*$'\t'}"
        if [[ "$workspace" == "$line" ]]; then
            continue
        fi
        _sync_gateway_skill_to_workspace "$agent_id" "$workspace"
        count=$((count + 1))
    done < <(_list_openclaw_agent_workspaces)

    success "已向 ${count} 个 workspace 安装上传 Skill"
}


_configure_gateway_skill_runtime_env() {
    local enabled="$1"
    local gateway_url="$2"
    local upload_token="$3"
    local expires_seconds="$4"
    local sandbox_gateway_url
    local runtime_summary

    if ! cmd_exists python3 || [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        warn "未找到 OpenClaw 配置文件或 python3，跳过 Skill 环境写入"
        return 0
    fi

    sandbox_gateway_url="$(_resolve_sandbox_upload_skill_gateway_url "$gateway_url")"
    _write_upload_skill_env_to_openclaw_env_file "$gateway_url" "$upload_token" "$expires_seconds"

    runtime_summary="$(python3 - "$OPENCLAW_CONFIG" "$GATEWAY_SKILL_NAME" "$enabled" "$gateway_url" "$sandbox_gateway_url" "$upload_token" "$expires_seconds" <<'PYEOF'
import json
import re
import sys
from urllib.parse import urlsplit

config_path, skill_key, enabled_raw, gateway_url, sandbox_gateway_url, upload_token, expires_seconds = sys.argv[1:8]
enabled = enabled_raw.lower() == 'true'
managed_keys = [
    'OPENCLAW_FILE_UPLOAD_GATEWAY_URL',
    'OPENCLAW_FILE_UPLOAD_TOKEN',
    'OPENCLAW_FILE_UPLOAD_EXPIRES',
]
managed_extra_host = 'host.docker.internal:host-gateway'

with open(config_path, 'r', encoding='utf-8') as f:
    content = f.read()

try:
    config = json.loads(content)
except json.JSONDecodeError:
    content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    content = re.sub(r',\s*([}\]])', r'\1', content)
    config = json.loads(content)

skills = config.setdefault('skills', {})
entries = skills.setdefault('entries', {})
entry = entries.setdefault(skill_key, {})
entry['enabled'] = bool(enabled)
entry_env = entry.get('env')
if isinstance(entry_env, dict):
    for key in managed_keys:
        entry_env.pop(key, None)
    if not entry_env:
        entry.pop('env', None)

updates = {
    'OPENCLAW_FILE_UPLOAD_GATEWAY_URL': gateway_url if enabled else '',
    'OPENCLAW_FILE_UPLOAD_TOKEN': upload_token if enabled else '',
    'OPENCLAW_FILE_UPLOAD_EXPIRES': expires_seconds if enabled else '',
}

sandbox_updates = {
    'OPENCLAW_FILE_UPLOAD_GATEWAY_URL': sandbox_gateway_url if enabled else '',
    'OPENCLAW_FILE_UPLOAD_TOKEN': upload_token if enabled else '',
    'OPENCLAW_FILE_UPLOAD_EXPIRES': expires_seconds if enabled else '',
}

agents = config.setdefault('agents', {})
defaults = agents.setdefault('defaults', {})
default_sandbox = defaults.setdefault('sandbox', {})
default_docker = default_sandbox.setdefault('docker', {})
default_env = default_docker.get('env')
if isinstance(default_env, dict):
    for key in managed_keys:
        default_env.pop(key, None)
    if not default_env:
        default_docker.pop('env', None)


def sandbox_enabled(agent):
    sandbox = agent.get('sandbox')
    if not isinstance(sandbox, dict):
        return False
    mode = str(sandbox.get('mode', '')).strip().lower()
    return mode not in ('', 'off', 'none', 'disabled', 'false')


def apply_updates_to_docker_env(docker_cfg, values):
    env = docker_cfg.get('env')
    if not isinstance(env, dict):
        env = {}
        docker_cfg['env'] = env

    for key, value in values.items():
        if value:
            env[key] = str(value)
        else:
            env.pop(key, None)

    if not env:
        docker_cfg.pop('env', None)


def ensure_managed_extra_host(docker_cfg, enabled_flag):
    extra_hosts = docker_cfg.get('extraHosts')
    if not isinstance(extra_hosts, list):
        extra_hosts = []

    normalized = [item for item in extra_hosts if isinstance(item, str) and item.strip()]
    normalized = [item for item in normalized if item != managed_extra_host]
    if enabled_flag:
        normalized.append(managed_extra_host)

    if normalized:
        docker_cfg['extraHosts'] = normalized
    else:
        docker_cfg.pop('extraHosts', None)


def needs_host_gateway_alias(url):
    try:
        hostname = (urlsplit(url).hostname or '').strip().lower()
    except Exception:
        return False
    return hostname == 'host.docker.internal'


sandbox_agent_ids = []
for agent in agents.get('list', []):
    sandbox = agent.get('sandbox')
    if not isinstance(sandbox, dict):
        continue

    docker = sandbox.setdefault('docker', {})
    if sandbox_enabled(agent):
        apply_updates_to_docker_env(docker, sandbox_updates)
        ensure_managed_extra_host(docker, bool(enabled and sandbox_gateway_url and needs_host_gateway_alias(sandbox_gateway_url)))
        sandbox_agent_ids.append((agent.get('id') or '').strip())
    else:
        apply_updates_to_docker_env(docker, {
            'OPENCLAW_FILE_UPLOAD_GATEWAY_URL': '',
            'OPENCLAW_FILE_UPLOAD_TOKEN': '',
            'OPENCLAW_FILE_UPLOAD_EXPIRES': '',
        })
        ensure_managed_extra_host(docker, False)

with open(config_path, 'w', encoding='utf-8') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print(f"{len([x for x in sandbox_agent_ids if x])}\t{','.join([x for x in sandbox_agent_ids if x])}")
PYEOF
)"

    UPLOAD_SKILL_SANDBOX_AGENT_COUNT="${runtime_summary%%$'\t'*}"
    if [[ "$UPLOAD_SKILL_SANDBOX_AGENT_COUNT" == "$runtime_summary" ]]; then
        UPLOAD_SKILL_SANDBOX_AGENT_IDS=""
    else
        UPLOAD_SKILL_SANDBOX_AGENT_IDS="${runtime_summary#*$'\t'}"
    fi
}


setup_gateway_file_upload_skill() {
    if [[ ! -d "$GATEWAY_SKILL_SOURCE_DIR" ]]; then
        error "未找到 Skill 模板目录: $GATEWAY_SKILL_SOURCE_DIR"
        return 1
    fi

    mkdir -p "${OPENCLAW_HOME}/skills"
    rm -rf "$GATEWAY_SKILL_TARGET_DIR"
    cp -R "$GATEWAY_SKILL_SOURCE_DIR" "$GATEWAY_SKILL_TARGET_DIR"
    chmod +x "$GATEWAY_SKILL_TARGET_DIR/upload_to_gateway.py" 2>/dev/null || true
    success "已安装全局 Skill: ${GATEWAY_SKILL_NAME}"

    _resolve_gateway_skill_runtime_values

    if [[ -z "$UPLOAD_SKILL_TOKEN" ]]; then
        warn "未配置 OPENCLAW_FILE_UPLOAD_TOKEN / FILE_UPLOAD_INTERNAL_TOKEN，Skill 调用会失败"
    fi

    _configure_gateway_skill_runtime_env "true" "$UPLOAD_SKILL_GATEWAY_URL" "$UPLOAD_SKILL_TOKEN" "$UPLOAD_SKILL_EXPIRES"
    _sync_gateway_skill_to_all_workspaces
    step "已写入 Skill 运行环境（Gateway: ${UPLOAD_SKILL_GATEWAY_URL}，Expires: ${UPLOAD_SKILL_EXPIRES}s）"
    echo -e "  ${DIM}非沙箱 Agent：变量已写入 ${OPENCLAW_ENV_FILE}${NC}"
    echo -e "  ${DIM}如果 OpenClaw 当前已在运行，必须重启 OpenClaw 进程后才会生效${NC}"
    if [[ "${UPLOAD_SKILL_SANDBOX_AGENT_COUNT:-0}" -gt 0 ]]; then
        echo -e "  ${DIM}沙箱 Agent：变量已写入 ${UPLOAD_SKILL_SANDBOX_AGENT_COUNT} 个 agent 的 sandbox.docker.env${NC}"
        if [[ "${UPLOAD_SKILL_SANDBOX_GATEWAY_URL:-}" != "${UPLOAD_SKILL_GATEWAY_URL}" ]]; then
            echo -e "  ${DIM}检测到上传地址使用 localhost，沙箱内已自动改为: ${UPLOAD_SKILL_SANDBOX_GATEWAY_URL}${NC}"
        fi
        if [[ -n "${UPLOAD_SKILL_SANDBOX_AGENT_IDS:-}" ]]; then
            echo -e "  ${DIM}涉及的沙箱 Agent: ${UPLOAD_SKILL_SANDBOX_AGENT_IDS}${NC}"
        fi
        echo -e "  ${DIM}若沙箱容器已存在，请执行: openclaw sandbox recreate --agent <agent_id>${NC}"
    else
        echo -e "  ${DIM}当前未检测到启用沙箱的 Agent，未写入 sandbox.docker.env${NC}"
    fi
}

# ============================================================================
# 第一步：检查环境 & 安装 OpenClaw
# ============================================================================

# ============================================================================
# 第二步：配置模型提供商
# ============================================================================

# --- 官方提供商列表（bash 3 兼容，用平行数组代替关联数组）---
PROVIDER_IDS=(  anthropic          openai       deepseek  groq  together       fireworks        openrouter  xai          minimax  moonshot)
PROVIDER_NAMES=("Anthropic (Claude)" "OpenAI (GPT)" "DeepSeek" "Groq" "Together AI" "Fireworks AI" "OpenRouter" "xAI (Grok)" "MiniMax" "Moonshot AI")

# 通过 ID 查找名称
_provider_name_by_id() {
    local target="$1"
    for i in "${!PROVIDER_IDS[@]}"; do
        if [[ "${PROVIDER_IDS[$i]}" == "$target" ]]; then
            echo "${PROVIDER_NAMES[$i]}"
            return 0
        fi
    done
    echo "$target"
}

# 官方提供商的模型认证命令
setup_official_provider() {
    local provider="$1"
    local provider_name
    provider_name=$(_provider_name_by_id "$provider")

    header "配置 ${provider_name}"

    printf "%s" "请输入 ${provider_name} API Key (输入时会显示): "
    read -r api_key </dev/tty
    echo ""

    if [[ -z "$api_key" ]]; then
        warn "未输入 API Key，跳过 ${provider_name}"
        return 1
    fi

    # 通过 openclaw models auth 配置
    step "配置 ${provider_name} 认证..."
    openclaw models auth set "$provider" --api-key "$api_key" 2>/dev/null || {
        # 回退：直接写入 config
        config_set "auth.profiles.${provider}.apiKey" "$api_key"
    }

    success "${provider_name} 已配置"
}

# 第三方流量池配置（如 GMN）
setup_custom_provider() {
    header "配置第三方模型提供商"

    echo ""
    printf "%s" "提供商 ID (英文, 如 gmn): "
    read -r provider_id </dev/tty

    if [[ -z "$provider_id" ]]; then
        warn "未输入提供商 ID，跳过"
        return 1
    fi

    printf "%s" "API Base URL (如 https://gmn.chuangzuoli.com/v1): "
    read -r base_url </dev/tty

    printf "%s" "API Key (输入时会显示): "
    read -r api_key </dev/tty

    echo ""
    echo "API 协议格式:"
    echo "  1) OpenAI 兼容 (openai-responses) — GPT、DeepSeek、国产大模型等"
    echo "  2) Anthropic 兼容 (anthropic-messages) — Claude 系列"
    echo "  3) 其他 (跳过自动配置，需手动编辑 openclaw.json)"
    echo ""
    printf "%s" "请选择 [1-3, 默认 1]: "
    read -r api_choice </dev/tty
    api_choice="${api_choice:-1}"

    local api_format=""
    local auto_configure=true
    case "$api_choice" in
        1) api_format="openai-responses" ;;
        2) api_format="anthropic-messages" ;;
        3) auto_configure=false ;;
        *) api_format="openai-responses" ;;
    esac

    if [[ -z "$base_url" || -z "$api_key" ]]; then
        warn "信息不完整，跳过"
        return 1
    fi

    if [[ "$auto_configure" == "false" ]]; then
        # 其他格式：只写入基础字段，提示用户手动配置
        step "写入基础提供商配置..."
        if cmd_exists python3; then
            python3 << PYEOF
import json, os, re

config_path = os.path.expanduser("~/.openclaw/openclaw.json")
with open(config_path, "r") as f:
    content = f.read()

try:
    config = json.loads(content)
except json.JSONDecodeError:
    content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    content = re.sub(r',\s*([}\]])', r'\1', content)
    config = json.loads(content)

providers = config.setdefault("models", {}).setdefault("providers", {})
provider = providers.setdefault("${provider_id}", {})
provider["baseUrl"] = "${base_url}"
provider["apiKey"] = "${api_key}"
provider.setdefault("models", [])

with open(config_path, "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF
            success "基础配置已写入"
            warn "请手动编辑 ${OPENCLAW_CONFIG} 补充 api、auth、headers 等字段"
        else
            error "未找到 python3，无法写入配置"
            return 1
        fi
        return 0
    fi

    # 写入配置（使用 Python 直接修改 JSON）
    step "写入提供商配置..."
    if cmd_exists python3; then
        python3 << PYEOF
import json, os, re

config_path = os.path.expanduser("~/.openclaw/openclaw.json")
with open(config_path, "r") as f:
    content = f.read()

try:
    config = json.loads(content)
except json.JSONDecodeError:
    content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    content = re.sub(r',\s*([}\]])', r'\1', content)
    config = json.loads(content)

# 确保路径存在
providers = config.setdefault("models", {}).setdefault("providers", {})
provider = providers.setdefault("${provider_id}", {})

api_format = "${api_format}"

# 写入提供商配置
provider["baseUrl"] = "${base_url}"
provider["apiKey"] = "${api_key}"
provider["auth"] = "api-key"
provider["api"] = api_format

if api_format == "openai-responses":
    # OpenAI 兼容：需要 authHeader + 标准 headers
    provider["authHeader"] = True
    provider["headers"] = {
        "User-Agent": "Mozilla/5.0 OpenClaw",
        "Accept": "application/json"
    }
elif api_format == "anthropic-messages":
    # Anthropic 兼容：openclaw 原生处理 x-api-key，无需额外配置
    provider.pop("authHeader", None)
    provider.pop("headers", None)

# 确保 models 数组存在
provider.setdefault("models", [])

with open(config_path, "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF
        success "提供商配置已写入"
    else
        error "未找到 python3，无法写入配置"
        return 1
    fi

    # 配置模型
    echo ""
    step "添加模型..."
    local last_model_id=""
    local model_count=0
    while true; do
        printf "%s" "模型 ID (留空结束添加): "
        read -r model_id </dev/tty
        [[ -z "$model_id" ]] && break

        printf "%s" "模型显示名称 (直接回车使用模型ID: ${model_id}): "
        read -r model_name </dev/tty
        model_name="${model_name:-$model_id}"

        printf "%s" "上下文窗口大小 (直接回车默认 200000 tokens): "
        read -r context_window </dev/tty
        context_window="${context_window:-200000}"

        printf "%s" "最大输出 Token (直接回车默认 128000 tokens): "
        read -r max_tokens </dev/tty
        max_tokens="${max_tokens:-128000}"

        printf "%s" "是否支持推理 (reasoning)? (直接回车默认 Yes) [Y/n]: "
        read -r reasoning_yn </dev/tty
        reasoning_yn="${reasoning_yn:-y}"
        if [[ "$reasoning_yn" =~ ^[Yy] ]]; then
            is_reasoning="true"
        else
            is_reasoning="false"
        fi

        step "添加模型: ${provider_id}/${model_id}"

        _append_model_to_config "$provider_id" "$model_id" "$model_name" \
            "$context_window" "$max_tokens" "$is_reasoning"

        success "已添加模型: ${provider_id}/${model_id}"
        last_model_id="$model_id"
        model_count=$((model_count + 1))
        echo ""
    done

    # 第一个模型自动设为默认，后续模型询问
    if [[ -n "$last_model_id" ]]; then
        if [[ $model_count -eq 1 ]]; then
            # 只添加了一个模型，自动设为默认
            local default_model="${provider_id}/${last_model_id}"
            step "将 ${default_model} 设为默认模型..."
            openclaw models set "$default_model" 2>/dev/null || \
                config_set "agents.defaults.model.primary" "$default_model"
            success "默认模型已设为: ${default_model}"
        else
            # 添加了多个模型，询问是否设为默认
            printf "%s" "是否修改默认模型? (直接回车保持当前默认) [y/N]: "
            read -r set_default </dev/tty
            if [[ "$set_default" =~ ^[Yy] ]]; then
                printf "%s" "默认模型 (直接回车使用 ${provider_id}/${last_model_id}): "
                read -r default_model </dev/tty
                default_model="${default_model:-${provider_id}/${last_model_id}}"
                openclaw models set "$default_model" 2>/dev/null || \
                    config_set "agents.defaults.model.primary" "$default_model"
                success "默认模型已设为: ${default_model}"
            fi
        fi
    fi

    success "${provider_id} 提供商配置完成"
}

# 向配置文件追加模型（内部函数）
_append_model_to_config() {
    local provider_id="$1"
    local model_id="$2"
    local model_name="$3"
    local ctx_window="$4"
    local max_tokens="$5"
    local reasoning="$6"

    # 转换 bash 布尔值为 Python 布尔值
    local py_reasoning="False"
    if [[ "$reasoning" == "true" ]]; then
        py_reasoning="True"
    fi

    # 使用 python3/node 来安全地修改 JSON
    if cmd_exists python3; then
        python3 << PYEOF
import json, os

config_path = os.path.expanduser("~/.openclaw/openclaw.json")
with open(config_path, "r") as f:
    # 简单处理 JSON5：去掉注释和尾逗号
    content = f.read()

# 尝试标准 JSON 解析
try:
    config = json.loads(content)
except json.JSONDecodeError:
    # 如果是 JSON5，尝试简单清理
    import re
    content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    content = re.sub(r',\s*([}\]])', r'\1', content)
    config = json.loads(content)

# 确保路径存在
providers = config.setdefault("models", {}).setdefault("providers", {})
provider = providers.setdefault("${provider_id}", {})
models = provider.setdefault("models", [])

# 检查是否已存在
existing_ids = [m.get("id") for m in models]
if "${model_id}" not in existing_ids:
    model_entry = {
        "id": "${model_id}",
        "name": "${model_name}",
        "reasoning": ${py_reasoning},
        "input": ["text", "image"],
        "contextWindow": ${ctx_window},
        "maxTokens": ${max_tokens}
    }
    models.append(model_entry)

with open(config_path, "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF
    else
        warn "未找到 python3，请手动编辑 ${OPENCLAW_CONFIG} 添加模型"
    fi
}

configure_models() {
    header "第二步：配置模型提供商"

    # 显示当前已配置的模型
    step "当前已配置的模型:"
    openclaw models list 2>/dev/null || echo "  (无)"
    echo ""

    # 简化为 y/n 确认方式
    if ! confirm "是否需要添加或修改模型提供商? (直接回车默认 No)" "n"; then
        success "跳过模型配置"
        return 0
    fi

    while true; do
        echo ""
        echo "请选择提供商类型:"
        echo "  1) 官方 API 提供商 (Anthropic, OpenAI, DeepSeek 等)"
        echo "  2) 第三方流量池 (如 GMN)"
        echo "  3) 完成，继续下一步"
        echo ""

        local choice
        read -p "请输入选项 [1-3]: " choice

        case "$choice" in
            1)
                # 官方提供商 - 简化为直接输入 ID
                echo ""
                echo "官方提供商列表:"
                for i in "${!PROVIDER_IDS[@]}"; do
                    echo "  $((i+1))) ${PROVIDER_NAMES[$i]} (${PROVIDER_IDS[$i]})"
                done
                echo ""

                local provider_choice
                read -p "请输入选项 [1-${#PROVIDER_IDS[@]}]: " provider_choice

                if [[ "$provider_choice" =~ ^[0-9]+$ ]] && (( provider_choice >= 1 && provider_choice <= ${#PROVIDER_IDS[@]} )); then
                    local idx=$((provider_choice - 1))
                    setup_official_provider "${PROVIDER_IDS[$idx]}"
                else
                    warn "无效选项"
                fi
                ;;
            2)
                setup_custom_provider
                ;;
            3|"")
                break
                ;;
            *)
                warn "无效选项，请输入 1-3"
                ;;
        esac
    done

    success "模型配置完成"
}

# ============================================================================
# 第三步：创建 Agent
# ============================================================================

create_agent() {
    local agent_id="$1"
    local agent_name="$2"
    local use_sandbox="$3"

    local workspace="${OPENCLAW_HOME}/workspace-${agent_id}"
    local agent_dir="${OPENCLAW_HOME}/agents/${agent_id}/agent"
    local shared_dir
    local shared_source_dir
    shared_dir="$(shared_dir_for_agent "$agent_id")"
    shared_source_dir="$(shared_source_dir_for_agent "$agent_id")"
    # 检查是否已存在
    if openclaw agents list 2>/dev/null | grep -q "^- ${agent_id}"; then
        warn "Agent '${agent_id}' 已存在"
        if ! confirm "是否重新配置?" "n"; then
            return 0
        fi
    fi

    # main agent 特殊处理
    if [[ "$agent_id" == "main" ]]; then
        workspace="${OPENCLAW_HOME}/workspace"
        step "配置主 Agent (main)..."
    else
        step "创建 Agent: ${agent_id} (${agent_name})..."
        openclaw agents add "$agent_id" \
            --workspace "$workspace" \
            --non-interactive 2>/dev/null || {
            warn "openclaw agents add 失败，尝试手动配置..."
            # 手动创建 workspace 目录和初始化文件
            mkdir -p "$workspace"
            touch "$workspace/IDENTITY.md" "$workspace/SOUL.md" \
                  "$workspace/USER.md" "$workspace/TOOLS.md" "$workspace/AGENTS.md"
            # 写入 agents.list
            python3 << PYEOF
import json, os, re

config_path = os.path.expanduser("~/.openclaw/openclaw.json")
with open(config_path, "r") as f:
    content = f.read()

try:
    config = json.loads(content)
except json.JSONDecodeError:
    content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    content = re.sub(r',\s*([}\]])', r'\1', content)
    config = json.loads(content)

            agents = config.setdefault("agents", {}).setdefault("list", [])
existing_ids = [a.get("id") for a in agents]
if "${agent_id}" not in existing_ids:
    agents.append({
        "id": "${agent_id}",
        "name": "${agent_name}",
        "workspace": "${workspace}",
        "agentDir": "${agent_dir}",
        "identity": {
            "name": "${agent_name}"
        }
    })

with open(config_path, "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF
        }
    fi

    # 确保 workspace 存在
    if [[ ! -d "$workspace" ]]; then
        mkdir -p "$workspace"
    fi

    if ensure_shared_dir_for_agent "$agent_id"; then
        step "共享目录已就绪: ${shared_dir} -> ${shared_source_dir}"
    else
        warn "共享目录未就绪，后续请手动确认: ${shared_dir} -> ${shared_source_dir}"
    fi

    _sync_gateway_skill_to_workspace "$agent_id" "$workspace"

    # 配置沙箱（非 main agent）
    if [[ "$use_sandbox" == "true" && "$agent_id" != "main" ]]; then
        if ! require_custom_sandbox_image; then
            error "专用沙箱镜像未就绪，无法为 Agent '${agent_id}' 配置沙箱"
            return 1
        fi
        step "配置 Docker 沙箱..."
        _configure_sandbox "$agent_id" "$agent_name" "$shared_source_dir" "$shared_dir"
    fi

    # 设置 agent 名称和身份
    if [[ -n "$agent_name" ]]; then
        openclaw agents set-identity --agent "$agent_id" --name "$agent_name" 2>/dev/null || true
    fi

    # 同步主 Agent 的模型配置（auth-profiles.json, models.json）
    if [[ "$agent_id" != "main" ]]; then
        local main_agent_dir="${OPENCLAW_HOME}/agents/main/agent"
        mkdir -p "$agent_dir"
        if [[ -f "${main_agent_dir}/auth-profiles.json" ]]; then
            cp "${main_agent_dir}/auth-profiles.json" "${agent_dir}/auth-profiles.json"
            step "已同步主 Agent 的认证配置到 ${agent_id}"
        fi
        if [[ -f "${main_agent_dir}/models.json" ]]; then
            cp "${main_agent_dir}/models.json" "${agent_dir}/models.json"
            step "已同步主 Agent 的模型配置到 ${agent_id}"
        fi
    fi

    success "Agent '${agent_id}' 创建成功"
    echo -e "  ${DIM}Workspace: ${workspace}${NC}"
    echo -e "  ${DIM}Agent Dir: ${agent_dir}${NC}"
    echo -e "  ${DIM}Shared Dir: ${shared_dir}${NC}"
    echo -e "  ${DIM}Shared Src: ${shared_source_dir}${NC}"
    echo ""

    return 0
}

# 配置沙箱（内部函数）
_configure_sandbox() {
    local agent_id="$1"
    local agent_name_input="${2:-$1}"
    local shared_source_dir="${3:-$(shared_source_dir_for_agent "$agent_id")}"
    local shared_dir="${4:-$(shared_dir_for_agent "$agent_id")}"
    local workspace="${OPENCLAW_HOME}/workspace-${agent_id}"
    local agent_dir="${OPENCLAW_HOME}/agents/${agent_id}/agent"
    local sandbox_image="$OPENCLAW_SANDBOX_IMAGE"
    local storage_mode
    storage_mode="$(_resolve_file_storage_mode)"
    _resolve_gateway_skill_runtime_values

    # 约定：workspace 内 shared 目录作为挂载源，对外统一暴露为 /app/shared/<agent_id>。
    ensure_shared_dir_for_agent "$agent_id" || true
    mkdir -p "$agent_dir"

    if cmd_exists python3; then
        python3 - "$OPENCLAW_CONFIG" "$agent_id" "$agent_name_input" "$workspace" "$agent_dir" "$shared_source_dir" "$shared_dir" "$sandbox_image" "$storage_mode" "$UPLOAD_SKILL_GATEWAY_URL" "$UPLOAD_SKILL_SANDBOX_GATEWAY_URL" "$UPLOAD_SKILL_TOKEN" "$UPLOAD_SKILL_EXPIRES" <<'PYEOF'
import json
import os
import re
import sys
from urllib.parse import urlsplit

config_path, agent_id, agent_name_raw, workspace, agent_dir, shared_source_dir, shared_dir, sandbox_image, storage_mode, gateway_url, sandbox_gateway_url, upload_token, upload_expires = sys.argv[1:14]
agent_name = (agent_name_raw or agent_id or '').strip() or agent_id

with open(config_path, "r") as f:
    content = f.read()

try:
    config = json.loads(content)
except json.JSONDecodeError:
    content = re.sub(r'//.*$', '', content, flags=re.MULTILINE)
    content = re.sub(r'/\*.*?\*/', '', content, flags=re.DOTALL)
    content = re.sub(r',\s*([}\]])', r'\1', content)
    config = json.loads(content)

agents_cfg = config.setdefault("agents", {})
agents_list = agents_cfg.setdefault("list", [])

target = None
for agent in agents_list:
    if agent.get("id") == agent_id:
        target = agent
        break

if target is None:
    target = {"id": agent_id}
    agents_list.append(target)

target["id"] = agent_id
target["name"] = agent_name
target["workspace"] = workspace
target["agentDir"] = agent_dir
target["identity"] = {"name": agent_name}

docker_cfg = {
    "readOnlyRoot": False,
    "network": "bridge",
    "image": sandbox_image,
    "binds": [
        f"{shared_source_dir}:{shared_dir}:rw"
    ],
    "env": {}
}

if gateway_url:
    docker_cfg["env"]["OPENCLAW_FILE_UPLOAD_GATEWAY_URL"] = sandbox_gateway_url or gateway_url
if upload_token:
    docker_cfg["env"]["OPENCLAW_FILE_UPLOAD_TOKEN"] = upload_token
if upload_expires:
    docker_cfg["env"]["OPENCLAW_FILE_UPLOAD_EXPIRES"] = str(upload_expires)
if not docker_cfg["env"]:
    docker_cfg.pop("env", None)

try:
    sandbox_gateway_host = (urlsplit(sandbox_gateway_url or '').hostname or '').strip().lower()
except Exception:
    sandbox_gateway_host = ''

if sandbox_gateway_host == 'host.docker.internal':
    docker_cfg["extraHosts"] = ["host.docker.internal:host-gateway"]

target["sandbox"] = {
    "mode": "all",
    "workspaceAccess": "rw",
    "scope": "agent",
    "docker": docker_cfg,
}

defaults = agents_cfg.setdefault("defaults", {})
default_sandbox = defaults.setdefault("sandbox", {})
default_docker = default_sandbox.setdefault("docker", {})
default_docker["image"] = sandbox_image
default_docker.pop("setupCommand", None)

target["tools"] = {
    "allow": [
        "group:fs",
        "group:runtime",
        "group:memory",
        "group:sessions",
    ],
    "deny": [
        "apply_patch"
    ],
}

with open(config_path, "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF
        success "沙箱模板配置已写入（挂载源: ${shared_source_dir}，容器路径: ${shared_dir}）"
    else
        warn "未找到 python3，请手动配置沙箱"
    fi
}

# 编辑 Agent 人格设定文件
edit_agent_persona() {
    local agent_id="$1"
    local workspace

    if [[ "$agent_id" == "main" ]]; then
        workspace="${OPENCLAW_HOME}/workspace"
    else
        workspace="${OPENCLAW_HOME}/workspace-${agent_id}"
    fi

    if [[ ! -d "$workspace" ]]; then
        error "Workspace 不存在: ${workspace}"
        return 1
    fi

    header "编辑 Agent '${agent_id}' 人格设定"
    echo -e "${DIM}Workspace: ${workspace}${NC}"
    echo -e "${DIM}编辑器: ${EDITOR}${NC}"
    echo ""
    echo "以下文件由 OpenClaw 初始化生成，你可以在原始内容基础上追加自定义内容。"
    echo "每个文件会依次打开编辑器，保存退出即可。"
    echo ""

    # 按推荐顺序依次编辑
    local files_to_edit=(
        "IDENTITY.md|身份定义 — 名字、物种、性格、Emoji"
        "SOUL.md|灵魂设定 — 核心人格、行为准则、角色定位"
        "USER.md|用户信息 — 关于你（用户）的基本信息"
        "TOOLS.md|工具配置 — 环境特定的工具和设备信息"
        "AGENTS.md|工作空间规则 — Session 流程、记忆管理、安全规则"
    )

    for entry in "${files_to_edit[@]}"; do
        local filename="${entry%%|*}"
        local description="${entry##*|}"
        local filepath="${workspace}/${filename}"

        if [[ -f "$filepath" ]]; then
            edit_file "$filepath" "$description"
        else
            warn "${filename} 不存在，跳过"
        fi
    done

    # 同步 IDENTITY.md 到 OpenClaw
    if [[ -f "${workspace}/IDENTITY.md" ]]; then
        step "同步身份信息到 OpenClaw..."
        openclaw agents set-identity --agent "$agent_id" --from-identity \
            --identity-file "${workspace}/IDENTITY.md" 2>/dev/null || true
    fi

    success "Agent '${agent_id}' 人格设定完成"
}

configure_agents() {
    header "第三步：创建和配置 Agent"

    # 显示当前 Agent
    step "当前已配置的 Agent:"
    openclaw agents list 2>/dev/null || echo "  (无)"
    echo ""

    # 配置 main agent 人格
    printf "%s" "是否编辑主 Agent (main) 的人格设定? (直接回车默认 Yes) [Y/n]: "
    read -r edit_main_yn </dev/tty
    edit_main_yn="${edit_main_yn:-y}"
    if [[ "$edit_main_yn" =~ ^[Yy] ]]; then
        edit_agent_persona "main"
    fi

    # 创建额外 Agent
    echo ""
    while true; do
        printf "%s" "是否创建新的 Agent? (直接回车默认 Yes) [Y/n]: "
        read -r create_agent_yn </dev/tty
        create_agent_yn="${create_agent_yn:-y}"
        if [[ ! "$create_agent_yn" =~ ^[Yy] ]]; then
            break
        fi

        echo ""
        printf "%s" "Agent ID (英文标识, 如 development, testing, service): "
        read -r agent_id </dev/tty
        if [[ -z "$agent_id" ]]; then
            warn "未输入 Agent ID，跳过"
            continue
        fi

        printf "%s" "显示名称 (直接回车使用 Agent ID: ${agent_id}): "
        read -r agent_name </dev/tty
        agent_name="${agent_name:-$agent_id}"

        echo "说明: 仅启用沙箱时才需要 Docker 和专用沙箱镜像；非沙箱 Agent 无需 Docker。"
        printf "%s" "是否启用 Docker 沙箱? (直接回车默认 Yes) [Y/n]: "
        read -r sandbox_yn </dev/tty
        sandbox_yn="${sandbox_yn:-y}"
        if [[ "$sandbox_yn" =~ ^[Yy] ]]; then
            use_sandbox="true"
        else
            use_sandbox="false"
        fi

        # 创建 Agent
        create_agent "$agent_id" "$agent_name" "$use_sandbox"

        # 编辑人格设定
        printf "%s" "是否立即编辑此 Agent 的人格设定? (直接回车默认 Yes) [Y/n]: "
        read -r edit_yn </dev/tty
        edit_yn="${edit_yn:-y}"
        if [[ "$edit_yn" =~ ^[Yy] ]]; then
            edit_agent_persona "$agent_id"
        fi

        echo ""
    done

    success "Agent 配置完成"
}

# ============================================================================
# 第四步：配置 Gateway 集成
# ============================================================================

configure_gateway_integration() {
    header "第四步：配置 Gateway 集成"

    # 读取 Gateway 配置
    local gw_port gw_token
    gw_port=$(config_get "gateway.port" 2>/dev/null || echo "18789")
    gw_token="${OPENCLAW_GATEWAY_TOKEN:-}"
    if [[ -z "$gw_token" ]]; then
        gw_token="$(_read_env_file_value "$OPENCLAW_ENV_FILE" "OPENCLAW_GATEWAY_TOKEN")"
    fi
    if [[ -z "$gw_token" ]]; then
        gw_token="$(_read_token_from_config_file "auth")"
    fi

    echo "OpenClaw Gateway 配置:"
    echo -e "  端口: ${BOLD}${gw_port}${NC}"
    echo -e "  Token: ${BOLD}${gw_token:0:12}...${NC}"
    echo ""

    # 检查 .env 文件
    local env_file
    env_file="$(_detect_gateway_env_file)"

    if [[ -f "$env_file" ]]; then
        step "检测到 Gateway .env 文件: ${env_file}"

        # 显示当前 Gateway 需要的 OpenClaw 连接信息
        echo ""
        echo "企业微信 Gateway 连接 OpenClaw 所需信息:"
        echo -e "  ${BOLD}Gateway URL${NC}: http://localhost:${gw_port}"
        echo -e "  ${BOLD}Gateway Token${NC}: ${gw_token}"
        echo ""
        echo "在 04-manage-agent.sh add 时使用以上信息配置每个 Agent 的 Gateway 地址和 Gateway Token。"
        echo "Agent ID 同时作为 OpenClaw agent_id 与 SQLite 路由名。"
        echo ""
        echo "共享文件目录（Gateway 向 Agent 下发的固定路径）:"
        echo -e "  对外路径: ${BOLD}/app/shared/<agent_id>${NC}"
        echo -e "  实际来源: ${BOLD}~/.openclaw/workspace-<agent_id>/shared${NC}（通过软链 + bind 暴露）"
    else
        echo "企业微信 Gateway 连接 OpenClaw 所需信息:"
        echo -e "  ${BOLD}Gateway URL${NC}: http://localhost:${gw_port}"
        echo -e "  ${BOLD}Gateway Token${NC}: ${gw_token}"
        echo ""
        echo "添加 Gateway Agent 绑定时使用:"
        echo -e "  ${DIM}/opt/openclaw/gateway/bin/04-manage-agent.sh add [agent_id]${NC}"
        echo "  在交互式提示中填入以上 URL 和 Token，并保持 Agent ID 与路由名一致。"
        echo ""
        echo "共享文件目录（Gateway 向 Agent 下发的固定路径）:"
        echo -e "  对外路径: ${BOLD}/app/shared/<agent_id>${NC}"
        echo -e "  实际来源: ${BOLD}~/.openclaw/workspace-<agent_id>/shared${NC}（通过软链 + bind 暴露）"
    fi

    echo ""
    success "Gateway 集成信息已输出"
}

# ============================================================================
# 第五步：最终检查
# ============================================================================

final_check() {
    header "第五步：最终检查"

    # 列出所有 Agent
    step "已配置的 Agent:"
    openclaw agents list 2>/dev/null || echo "  (无)"
    echo ""

    # 列出所有模型
    step "已配置的模型:"
    openclaw models list 2>/dev/null || echo "  (无)"
    echo ""

    # 健康检查
    step "OpenClaw 健康检查..."
    if openclaw health 2>/dev/null; then
        success "OpenClaw Gateway 运行正常"
    else
        warn "OpenClaw Gateway 未运行。启动命令: $(gateway_start_hint)"
    fi

    # 对于 --skip-install / --add-agent 模式，也要确保 token 配置对齐
    step "同步 Gateway token 配置..."
    sync_gateway_tokens
    if [[ "$GATEWAY_TOKEN_SYNC_CHANGED" == "true" ]]; then
        step "检测到 token 变更，重启 Gateway 使配置生效..."
        restart_gateway_after_token_change || true
    fi

    step "安装/刷新每个 Agent workspace 下的文件上传 Skill..."
    if ! setup_gateway_file_upload_skill; then
        error "文件上传 Skill 配置失败"
        exit 1
    fi

    # 硬校验：沙箱共享目录契约
    if ! hard_check_sandbox_shared_contract; then
        error "最终校验未通过，请先修复沙箱共享目录配置后重试"
        error "建议检查: ~/.openclaw/openclaw.json 的 agents.list[].workspace 与 sandbox.workspaceAccess"
        exit 1
    fi

    # 硬校验：token 一致性和 RPC 探针必须通过
    if ! hard_check_gateway_token_health; then
        error "最终校验未通过，请先修复 token 配置后重试"
        error "建议执行: openclaw gateway restart && openclaw doctor"
        exit 1
    fi

    echo ""
    local gateway_start_cmd
    gateway_start_cmd="$(gateway_start_hint)"
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║    OpenClaw 配置完成!                ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "后续操作:"
    echo -e "  ${CYAN}1.${NC} 启动 OpenClaw:       ${DIM}${gateway_start_cmd}${NC}"
    echo -e "  ${CYAN}2.${NC} 部署企微 Gateway:    ${DIM}sudo bash bin/02-install-gateway.sh${NC}"
    echo -e "  ${CYAN}3.${NC} 更新代码后同步部署: ${DIM}sudo bash bin/02-install-gateway.sh${NC}"
    echo -e "  ${CYAN}4.${NC} 添加企微 Agent 绑定: ${DIM}/opt/openclaw/gateway/bin/04-manage-agent.sh add <name>${NC}"
    echo -e "  ${CYAN}5.${NC} 查看 Agent 列表:     ${DIM}/opt/openclaw/gateway/bin/04-manage-agent.sh list${NC}"
    echo -e "  ${CYAN}6.${NC} 查看 OpenClaw 面板:  ${DIM}openclaw dashboard${NC}"
    echo ""
}

# ============================================================================
# 主流程
# ============================================================================

main() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║  OpenClaw 一键安装配置脚本 v1.0      ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""

    # 快捷模式
    if [[ "$ADD_AGENT_ONLY" == "true" ]]; then
        if ! cmd_exists openclaw; then
            error "OpenClaw 未安装，请先完成安装后重新运行"
            _print_prereq_instructions
            exit 1
        fi
        configure_agents
        final_check
        return 0
    fi

    if [[ "$ADD_PROVIDER_ONLY" == "true" ]]; then
        if ! cmd_exists openclaw; then
            error "OpenClaw 未安装，请先完成安装后重新运行"
            _print_prereq_instructions
            exit 1
        fi
        configure_models
        final_check
        return 0
    fi

    # 完整流程
    if [[ "$SKIP_INSTALL" != "true" ]]; then
        check_prerequisites
    else
        if ! cmd_exists openclaw; then
            error "OpenClaw 未安装，请去掉 --skip-install 运行"
            exit 1
        fi
        success "跳过安装，OpenClaw $(openclaw --version)"
    fi

    configure_models
    configure_agents
    configure_gateway_integration
    final_check
}

# 执行
main "$@"
