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
# 要求：Node.js 22+, Docker（沙箱 agent 需要）
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
EDITOR="${EDITOR:-${VISUAL:-nano}}"
MIN_NODE_VERSION=22
SKIP_INSTALL=false
ADD_AGENT_ONLY=false
ADD_PROVIDER_ONLY=false
GATEWAY_TOKEN_SYNC_CHANGED=false

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

# ---------------------------------------------------------------------------
# 工具函数
# ---------------------------------------------------------------------------

# 检查命令是否存在
cmd_exists() { command -v "$1" &>/dev/null; }

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


sync_gateway_tokens() {
    # 对齐 gateway.auth.token 与 gateway.remote.token，避免 token mismatch
    local auth_token remote_token desired_token
    GATEWAY_TOKEN_SYNC_CHANGED=false

    auth_token=$(_read_token_from_config_file "auth")
    remote_token=$(_read_token_from_config_file "remote")
    desired_token="$auth_token"

    if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
        desired_token="$OPENCLAW_GATEWAY_TOKEN"
        if [[ "$auth_token" != "$desired_token" ]]; then
            config_set "gateway.auth.token" "$desired_token"
            auth_token="$desired_token"
            GATEWAY_TOKEN_SYNC_CHANGED=true
            step "已将 gateway.auth.token 对齐到 OPENCLAW_GATEWAY_TOKEN"
        fi
    fi

    if [[ -z "$desired_token" ]]; then
        warn "未检测到 gateway.auth.token，无法自动对齐 remote.token"
        return 0
    fi

    if [[ "$remote_token" != "$desired_token" ]]; then
        config_set "gateway.remote.token" "$desired_token"
        GATEWAY_TOKEN_SYNC_CHANGED=true
        step "已将 gateway.remote.token 对齐到 gateway.auth.token"
    fi

    if [[ "$GATEWAY_TOKEN_SYNC_CHANGED" == "true" ]]; then
        success "Gateway token 已对齐（auth/remote）"
    else
        step "Gateway token 已对齐，无需调整"
    fi
}


_status_has_token_mismatch() {
    local text="$1"
    echo "$text" | grep -Eqi "config token differs from service token|gateway token mismatch|gateway auth token mismatch|service token is stale"
}


repair_gateway_service_token_if_needed() {
    # 如果 service token 与 config token 漂移，自动执行 gateway install --force 修复
    local status_output
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
    doctor_output="$(openclaw doctor 2>&1 || true)"
    if echo "$doctor_output" | grep -Eqi "service token is stale|gateway token mismatch|gateway auth token mismatch|config token differs from service token"; then
        error "检测到 token 漂移（openclaw doctor）"
        echo "$doctor_output"
        return 1
    fi
    success "OpenClaw doctor 未发现 token 漂移"
}


hard_check_sandbox_shared_contract() {
    # 硬校验：沙箱 agent 的共享目录契约必须成立（<workspace>/shared -> /app/shared）
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
    shared = os.path.join(workspace, 'shared')

    if not os.path.isdir(workspace):
        errors.append(f"{agent_id}: workspace 不存在: {workspace}")
        continue

    if not os.path.exists(shared):
        os.makedirs(shared, exist_ok=True)
        notes.append(f"{agent_id}: 已自动创建共享目录 {shared}")

    if os.path.realpath(shared) != os.path.realpath(os.path.join(workspace, 'shared')):
        errors.append(f"{agent_id}: 共享目录路径异常: {shared}")

    docker_cfg = sandbox.get('docker', {})
    expected_src = os.path.realpath(shared)
    expected_dst = '/app/shared'
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
        errors.append(f"{agent_id}: 缺少共享目录挂载（需要 {shared} -> /app/shared）")

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
        success "沙箱共享目录契约校验通过（容器内路径: /app/shared）"
        if echo "$check_output" | grep -q "^- "; then
            echo "$check_output" | grep "^- "
        fi

        if cmd_exists docker; then
            local containers probe_failed=0
            containers=$(openclaw sandbox list 2>/dev/null | grep -Eo 'openclaw-sbx-agent-[^[:space:]]+' | sort -u || true)
            if [[ -n "$containers" ]]; then
                while IFS= read -r c; do
                    [[ -z "$c" ]] && continue
                    if ! docker exec -w /workspace "$c" sh -lc 'mkdir -p /app/shared && touch /app/shared/.probe && rm -f /app/shared/.probe' >/dev/null 2>&1; then
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

# ============================================================================
# 第一步：检查环境 & 安装 OpenClaw
# ============================================================================

check_and_install_openclaw() {
    header "第一步：检查环境 & 安装 OpenClaw"

    # --- 检查 Node.js ---
    if cmd_exists node; then
        local node_version
        node_version=$(node -v | sed 's/v//' | cut -d. -f1)
        if (( node_version < MIN_NODE_VERSION )); then
            error "Node.js 版本 $(node -v) 过低，需要 v${MIN_NODE_VERSION}+"
            echo "  推荐: nvm install ${MIN_NODE_VERSION} && nvm use ${MIN_NODE_VERSION}"
            exit 1
        fi
        success "Node.js $(node -v)"
    else
        error "未找到 Node.js，需要 v${MIN_NODE_VERSION}+"
        echo "  推荐安装方法:"
        echo "    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
        echo "    nvm install ${MIN_NODE_VERSION}"
        exit 1
    fi

    # --- 检查 npm ---
    if cmd_exists npm; then
        success "npm $(npm -v)"
    else
        error "未找到 npm"
        exit 1
    fi

    # --- 检查 Docker（可选，沙箱 agent 需要）---
    if cmd_exists docker; then
        if docker info &>/dev/null; then
            success "Docker $(docker --version | sed -E 's/.*version ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
        else
            warn "Docker 已安装但未运行。沙箱 Agent 需要 Docker"
        fi
    else
        warn "未找到 Docker。沙箱 Agent 需要 Docker，主 Agent 不受影响"
    fi

    # --- 检查/安装 OpenClaw ---
    if cmd_exists openclaw; then
        local current_version
        current_version=$(openclaw --version 2>/dev/null || echo "unknown")
        success "OpenClaw 已安装 (v${current_version})"

        echo ""
        printf "%s" "是否清理当前安装并重新配置? [y/N]: "
        read -r reinstall_yn </dev/tty
        if [[ "$reinstall_yn" =~ ^[Yy] ]]; then
            step "清理当前 OpenClaw 安装..."
            openclaw gateway stop 2>/dev/null || true
            rm -rf "$OPENCLAW_HOME"
            success "清理完成，启动 OpenClaw 初始化向导..."
            echo ""
            openclaw onboard --install-daemon
            success "OpenClaw 初始化完成"
        fi
    else
        step "安装 OpenClaw..."
        echo ""
        echo "选择安装方式:"
        echo "  1) npm install -g openclaw@latest (推荐)"
        echo "  2) curl -fsSL https://openclaw.ai/install.sh | bash"
        echo ""

        local install_method
        read -p "请输入选项 [1-2, 默认 2]: " install_method
        install_method="${install_method:-2}"

        case "$install_method" in
            1)
                # 尝试不用 sudo，如果失败再提示
                if npm install -g openclaw@latest 2>/dev/null; then
                    success "OpenClaw 安装成功（用户级）"
                else
                    warn "用户级安装失败，需要 sudo 权限"
                    if sudo -n true 2>/dev/null; then
                        sudo npm install -g openclaw@latest
                    else
                        error "需要 sudo 权限但无法获取。请手动运行: sudo npm install -g openclaw@latest"
                        exit 1
                    fi
                fi
                ;;
            2)
                curl -fsSL https://openclaw.ai/install.sh | bash
                ;;
            *)
                warn "无效选项，使用默认方式（curl）"
                curl -fsSL https://openclaw.ai/install.sh | bash
                ;;
        esac

        if ! cmd_exists openclaw; then
            error "安装失败，请检查输出并重试"
            error "你可以手动安装："
            echo "  方式1: sudo npm install -g openclaw@latest"
            echo "  方式2: curl -fsSL https://openclaw.ai/install.sh | bash"
            exit 1
        fi
        success "OpenClaw $(openclaw --version) 安装成功"
    fi

    # --- 首次初始化（如果没有配置文件）---
    if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
        step "首次初始化 OpenClaw..."
        echo -e "${DIM}将启动 OpenClaw 交互式配置向导...${NC}"
        echo ""
        openclaw onboard --install-daemon
        success "OpenClaw 初始化完成"
    else
        success "OpenClaw 配置已存在: ${OPENCLAW_CONFIG}"
    fi

    # --- 确保 gateway 已启动 ---
    step "检查 Gateway 状态..."
    if openclaw health &>/dev/null; then
        success "Gateway 已在运行"
    else
        step "启动 Gateway..."
        openclaw gateway start &>/dev/null &
        sleep 3
        if openclaw health &>/dev/null; then
            success "Gateway 启动成功"
        else
            warn "Gateway 启动失败，Agent 创建可能受影响，请稍后手动运行: openclaw gateway start"
        fi
    fi

    # --- 对齐 Gateway token（auth/remote）---
    echo ""
    step "同步 Gateway token 配置..."
    sync_gateway_tokens
    if [[ "$GATEWAY_TOKEN_SYNC_CHANGED" == "true" ]]; then
        step "检测到 token 变更，重启 Gateway 使配置生效..."
        openclaw gateway restart >/dev/null 2>&1 || {
            warn "Gateway 重启失败，请稍后手动执行: openclaw gateway restart"
        }
        sleep 2
    fi
}

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
        "workspace": "${workspace}"
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

    # 配置沙箱（非 main agent）
    if [[ "$use_sandbox" == "true" && "$agent_id" != "main" ]]; then
        step "配置 Docker 沙箱..."
        _configure_sandbox "$agent_id"
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
    echo ""

    return 0
}

# 配置沙箱（内部函数）
_configure_sandbox() {
    local agent_id="$1"
    local workspace="${OPENCLAW_HOME}/workspace-${agent_id}"
    local shared_dir="${workspace}/shared"

    # 确保共享目录存在。
    # 约定：容器内通过 /app/shared 访问（避免 /workspace 保留挂载前缀冲突）
    mkdir -p "$shared_dir"

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

shared_dir = "${shared_dir}"

agents_list = config.get("agents", {}).get("list", [])
for agent in agents_list:
    if agent.get("id") == "${agent_id}":
        agent["sandbox"] = {
            "mode": "all",
            "scope": "agent",
            "workspaceAccess": "rw",
            "docker": {
                "network": "bridge",
                "readOnlyRoot": False,
                "binds": [
                    f"{shared_dir}:/app/shared:rw"
                ]
            }
        }
        break

with open(config_path, "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF
        success "沙箱配置已写入（共享目录: ${shared_dir}，容器内路径: /app/shared）"
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
    gw_token=$(_read_token_from_config_file "auth")

    echo "OpenClaw Gateway 配置:"
    echo -e "  端口: ${BOLD}${gw_port}${NC}"
    echo -e "  Token: ${BOLD}${gw_token:0:12}...${NC}"
    echo ""

    # 检查 .env 文件
    local env_file
    env_file="$(dirname "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")")/.env"

    if [[ ! -f "$env_file" ]]; then
        env_file="$(pwd)/.env"
    fi

    if [[ -f "$env_file" ]]; then
        step "检测到 Gateway .env 文件: ${env_file}"

        # 显示当前 Gateway 需要的 OpenClaw 连接信息
        echo ""
        echo "企业微信 Gateway 连接 OpenClaw 所需信息:"
        echo -e "  ${BOLD}OPENCLAW_URL${NC}=http://localhost:${gw_port}"
        echo -e "  ${BOLD}OPENCLAW_TOKEN${NC}=${gw_token}"
        echo ""
        echo "在 04-manage-agent.sh add 时使用以上信息配置每个 Agent 的 openclaw_url 和 openclaw_token。"
        echo "不同 Agent 通过 openclaw_agent_id 区分（如 main, development, testing）。"
        echo ""
        echo "共享文件目录（Gateway 下载的文件保存于此，容器内通过 /app/shared 访问）:"
        echo -e "  默认: ${BOLD}~/.openclaw/workspace-<agent_id>/shared/${NC}"
    else
        echo "企业微信 Gateway 连接 OpenClaw 所需信息:"
        echo -e "  ${BOLD}OpenClaw URL${NC}: http://localhost:${gw_port}"
        echo -e "  ${BOLD}OpenClaw Token${NC}: ${gw_token}"
        echo ""
        echo "添加 Gateway Agent 绑定时使用:"
        echo -e "  ${DIM}/opt/openclaw/gateway/bin/04-manage-agent.sh add <name>${NC}"
        echo "  在交互式提示中填入以上 URL 和 Token，以及对应的 openclaw_agent_id。"
        echo ""
        echo "共享文件目录（Gateway 下载的文件保存于此，容器内通过 /app/shared 访问）:"
        echo -e "  默认: ${BOLD}~/.openclaw/workspace-<agent_id>/shared/${NC}"
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
        warn "OpenClaw Gateway 未运行。启动命令: openclaw gateway start"
    fi

    # 对于 --skip-install / --add-agent 模式，也要确保 token 配置对齐
    step "同步 Gateway token 配置..."
    sync_gateway_tokens
    if [[ "$GATEWAY_TOKEN_SYNC_CHANGED" == "true" ]]; then
        step "检测到 token 变更，重启 Gateway 使配置生效..."
        openclaw gateway restart >/dev/null 2>&1 || {
            warn "Gateway 重启失败，请稍后手动执行: openclaw gateway restart"
        }
        sleep 2
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
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║    OpenClaw 配置完成!                ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "后续操作:"
    echo -e "  ${CYAN}1.${NC} 启动 OpenClaw:       ${DIM}openclaw gateway start${NC}"
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
            error "OpenClaw 未安装，请先运行完整安装流程"
            exit 1
        fi
        configure_agents
        final_check
        return 0
    fi

    if [[ "$ADD_PROVIDER_ONLY" == "true" ]]; then
        if ! cmd_exists openclaw; then
            error "OpenClaw 未安装，请先运行完整安装流程"
            exit 1
        fi
        configure_models
        final_check
        return 0
    fi

    # 完整流程
    if [[ "$SKIP_INSTALL" != "true" ]]; then
        check_and_install_openclaw
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
