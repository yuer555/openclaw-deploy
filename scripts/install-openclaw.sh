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
#   bash scripts/install-openclaw.sh            # 完整安装流程
#   bash scripts/install-openclaw.sh --skip-install   # 跳过安装，只做配置
#   bash scripts/install-openclaw.sh --add-agent      # 只添加新 Agent
#   bash scripts/install-openclaw.sh --add-provider   # 只添加模型提供商
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
config_set() { openclaw config set "$1" "$2" 2>/dev/null; }

# 读取用户输入（带默认值）
read_input() {
    local prompt="$1"
    local default="${2:-}"
    local result

    if [[ -n "$default" ]]; then
        echo -en "${prompt} ${DIM}[${default}]${NC}: "
    else
        echo -en "${prompt}: "
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
    echo -en "${prompt}: "

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
        echo -en "${prompt} ${DIM}[Y/n]${NC}: "
    else
        echo -en "${prompt} ${DIM}[y/N]${NC}: "
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

        if confirm "是否更新到最新版?" "n"; then
            step "更新 OpenClaw..."
            # 尝试不用 sudo，如果失败再用 sudo
            if npm install -g openclaw@latest 2>/dev/null; then
                success "已更新到 $(openclaw --version)"
            elif sudo -n npm install -g openclaw@latest 2>/dev/null; then
                success "已更新到 $(openclaw --version)"
            else
                warn "更新失败，请手动运行: sudo npm install -g openclaw@latest"
            fi
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

    local api_key
    api_key=$(read_secret "请输入 ${provider_name} API Key")

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

    local provider_id
    provider_id=$(read_input "提供商 ID (英文, 如 gmn)")

    if [[ -z "$provider_id" ]]; then
        warn "未输入提供商 ID，跳过"
        return 1
    fi

    local base_url api_key api_format
    base_url=$(read_input "API Base URL (如 https://gmn.chuangzuoli.com/v1)")
    api_key=$(read_secret "API Key")
    api_format=$(read_input "API 格式" "openai-responses")

    if [[ -z "$base_url" || -z "$api_key" ]]; then
        warn "信息不完整，跳过"
        return 1
    fi

    # 写入配置
    step "写入提供商配置..."
    config_set "models.providers.${provider_id}.baseUrl" "$base_url"
    config_set "models.providers.${provider_id}.apiKey" "$api_key"
    config_set "models.providers.${provider_id}.auth" "api-key"
    config_set "models.providers.${provider_id}.api" "$api_format"

    # 配置模型
    echo ""
    step "添加模型..."
    while true; do
        local model_id model_name context_window max_tokens is_reasoning

        model_id=$(read_input "模型 ID (如 gpt-5.3-codex, 留空结束)")
        [[ -z "$model_id" ]] && break

        model_name=$(read_input "模型显示名称" "$model_id")
        context_window=$(read_input "上下文窗口大小" "200000")
        max_tokens=$(read_input "最大输出 Token" "128000")

        if confirm "是否支持推理 (reasoning)?" "y"; then
            is_reasoning="true"
        else
            is_reasoning="false"
        fi

        # 通过 python 生成 JSON 片段并追加到配置
        # 这里用 openclaw config set 逐项写入
        step "添加模型: ${provider_id}/${model_id}"

        # 模型需要以数组形式追加到 providers.<id>.models[]
        # 由于 openclaw config set 不支持数组操作，直接编辑 JSON
        _append_model_to_config "$provider_id" "$model_id" "$model_name" \
            "$context_window" "$max_tokens" "$is_reasoning"

        success "已添加模型: ${provider_id}/${model_id}"
        echo ""
    done

    # 询问是否设为默认
    if confirm "是否将此提供商的模型设为默认?" "n"; then
        local default_model
        default_model=$(read_input "默认模型 (如 ${provider_id}/${model_id})")
        if [[ -n "$default_model" ]]; then
            openclaw models set "$default_model" 2>/dev/null || \
                config_set "agents.defaults.model.primary" "$default_model"
            success "默认模型已设为: ${default_model}"
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
        "reasoning": ${reasoning},
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
    if ! confirm "是否需要添加或修改模型提供商?" "n"; then
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
        }
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

    success "Agent '${agent_id}' 创建成功"
    echo -e "  ${DIM}Workspace: ${workspace}${NC}"
    echo -e "  ${DIM}Agent Dir: ${agent_dir}${NC}"
    echo ""

    return 0
}

# 配置沙箱（内部函数）
_configure_sandbox() {
    local agent_id="$1"

    if cmd_exists python3; then
        python3 << PYEOF
import json, os

config_path = os.path.expanduser("~/.openclaw/openclaw.json")
with open(config_path, "r") as f:
    config = json.loads(f.read())

agents_list = config.get("agents", {}).get("list", [])
for agent in agents_list:
    if agent.get("id") == "${agent_id}":
        agent["sandbox"] = {
            "mode": "all",
            "scope": "agent",
            "docker": {
                "setupCommand": "apt-get update && apt-get install -y git curl wget"
            }
        }
        break

with open(config_path, "w") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)
PYEOF
        success "沙箱配置已写入"
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
    if confirm "是否编辑主 Agent (main) 的人格设定?" "y"; then
        edit_agent_persona "main"
    fi

    # 创建额外 Agent
    echo ""
    while true; do
        if ! confirm "是否创建新的 Agent?" "y"; then
            break
        fi

        echo ""
        local agent_id agent_name use_sandbox

        agent_id=$(read_input "Agent ID (英文, 如 development, testing, service)")
        if [[ -z "$agent_id" ]]; then
            warn "未输入 Agent ID，跳过"
            continue
        fi

        agent_name=$(read_input "显示名称 (中文, 如 开发工程师)" "$agent_id")

        if confirm "是否启用 Docker 沙箱?" "y"; then
            use_sandbox="true"
        else
            use_sandbox="false"
        fi

        # 创建 Agent
        create_agent "$agent_id" "$agent_name" "$use_sandbox"

        # 编辑人格设定
        if confirm "是否立即编辑此 Agent 的人格设定?" "y"; then
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
    gw_token=$(config_get "gateway.auth.token" 2>/dev/null || echo "")

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
        echo -e "  ${BOLD}OPENCLAW_URL${NC}=ws://localhost:${gw_port}"
        echo -e "  ${BOLD}OPENCLAW_TOKEN${NC}=${gw_token}"
        echo ""
        echo "在 manage-agent.py add 时使用以上信息配置每个 Agent 的 openclaw_url 和 openclaw_token。"
        echo "不同 Agent 通过 openclaw_agent_id 区分（如 main, development, testing）。"
    else
        echo "企业微信 Gateway 连接 OpenClaw 所需信息:"
        echo -e "  ${BOLD}OpenClaw URL${NC}: ws://localhost:${gw_port}"
        echo -e "  ${BOLD}OpenClaw Token${NC}: ${gw_token}"
        echo ""
        echo "添加 Gateway Agent 绑定时使用:"
        echo -e "  ${DIM}python3 scripts/manage-agent.py add <name>${NC}"
        echo "  在交互式提示中填入以上 URL 和 Token，以及对应的 openclaw_agent_id。"
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

    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║    OpenClaw 配置完成!                ║${NC}"
    echo -e "${BOLD}${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "后续操作:"
    echo -e "  ${CYAN}1.${NC} 启动 OpenClaw:       ${DIM}openclaw gateway start${NC}"
    echo -e "  ${CYAN}2.${NC} 添加企微 Agent 绑定: ${DIM}python3 scripts/manage-agent.py add <name>${NC}"
    echo -e "  ${CYAN}3.${NC} 启动企微 Gateway:    ${DIM}python3 src/gateway/wecom_gateway.py${NC}"
    echo -e "  ${CYAN}4.${NC} 查看 Agent 列表:     ${DIM}openclaw agents list --bindings${NC}"
    echo -e "  ${CYAN}5.${NC} 查看控制面板:        ${DIM}openclaw dashboard${NC}"
    echo ""
}

# ============================================================================
# 主流程
# ============================================================================

main() {
    echo ""
    echo -e "${BOLD}${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${GREEN}║  OpenClaw 一键安装配置脚本 v1.0     ║${NC}"
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
