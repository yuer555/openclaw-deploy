#!/bin/bash
set -e

# OpenClaw Gateway 自动化部署/更新脚本
# 用途: 在 Linux 服务器安装或更新 Gateway 运行目录
# 用法: sudo bash bin/02-install-gateway.sh

echo "=========================================="
echo "OpenClaw Gateway 自动化部署/更新"
echo "=========================================="
echo ""

# 检查是否以 root 运行
if [ "$EUID" -ne 0 ]; then 
    echo "❌ 请使用 sudo 运行此脚本"
    exit 1
fi

# 配置变量
INSTALL_DIR="/opt/openclaw/gateway"
DATA_DIR="/opt/openclaw/data"
LOG_DIR="/var/log/openclaw"
VENV_DIR="/opt/openclaw/gateway/venv"
FALLBACK_ENV_FILE="/opt/openclaw/.env"

sanitize_tls_env_file() {
    local env_file="$1"
    [ -f "$env_file" ] || return 0

    local removed
    removed=$(python3 - "$env_file" <<'PYEOF'
import os
import sys

env_file = sys.argv[1]
target_keys = {"REQUESTS_CA_BUNDLE", "SSL_CERT_FILE", "CURL_CA_BUNDLE"}

with open(env_file, 'r', encoding='utf-8') as f:
    lines = f.readlines()

new_lines = []
removed = []

for raw in lines:
    stripped = raw.strip()
    if not stripped or stripped.startswith('#') or '=' not in stripped:
        new_lines.append(raw)
        continue

    key, value = stripped.split('=', 1)
    key = key.strip()

    if key not in target_keys:
        new_lines.append(raw)
        continue

    value = value.strip().strip('"').strip("'")
    if value and os.path.isfile(value):
        new_lines.append(raw)
        continue

    removed.append(f"{key}={value}")

if removed:
    with open(env_file, 'w', encoding='utf-8') as f:
        f.writelines(new_lines)

for item in removed:
    print(item)
PYEOF
)

    if [ -n "$removed" ]; then
        while IFS= read -r item; do
            [ -n "$item" ] || continue
            echo "   ⚠️  清理无效 TLS 配置: $item ($env_file)"
        done <<< "$removed"
    fi
}

# 使用调用 sudo 的实际用户运行 Gateway（与 OpenClaw 共用同一用户，避免权限问题）
RUN_USER="${SUDO_USER:-$(whoami)}"
RUN_GROUP="$(id -gn "$RUN_USER" 2>/dev/null || echo "$RUN_USER")"
if [ "$RUN_USER" = "root" ]; then
    echo "错误: 请使用 sudo 运行（不要直接以 root 登录运行）"
    echo "用法: sudo bash $0"
    exit 1
fi
echo "Gateway 将以用户 $RUN_USER:$RUN_GROUP 运行"

# 步骤 1: 检测操作系统
echo "📋 步骤 1/8: 检测操作系统..."
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    echo "   检测到: $PRETTY_NAME"
else
    echo "❌ 无法检测操作系统"
    exit 1
fi

# 步骤 2: 安装系统依赖
echo ""
echo "📦 步骤 2/8: 安装系统依赖..."
case $OS in
    ubuntu|debian)
        apt-get update -qq
        apt-get install -y -qq python3 python3-pip python3-venv python3-full sqlite3 curl wget git
        ;;
    centos|rhel|rocky|almalinux)
        yum install -y -q python3 python3-pip sqlite curl wget git
        ;;
    *)
        echo "⚠️  未识别的系统: $OS，尝试继续..."
        ;;
esac
echo "   ✅ 系统依赖安装完成"

# 步骤 3: 确认运行用户
echo ""
echo "👤 步骤 3/8: 确认运行用户..."
echo "   Gateway 将以 $RUN_USER:$RUN_GROUP 运行（与 OpenClaw 共用同一用户）"

# 步骤 4: 创建目录结构
echo ""
echo "📁 步骤 4/8: 创建目录结构..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$DATA_DIR/gateway"
mkdir -p "$LOG_DIR"

echo "   ✅ 目录创建完成"

# 步骤 5: 复制代码文件
echo ""
echo "📄 步骤 5/8: 复制代码文件..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$SCRIPT_DIR" != "$INSTALL_DIR" ]; then
    cp -r "$SCRIPT_DIR/src" "$INSTALL_DIR/"
    cp -r "$SCRIPT_DIR/scripts" "$INSTALL_DIR/"

    # 仅安装 Gateway 运行必需的 bin 脚本，避免双份脚本漂移
    rm -rf "$INSTALL_DIR/bin"
    mkdir -p "$INSTALL_DIR/bin"
    cp "$SCRIPT_DIR/bin/04-manage-agent.sh" "$INSTALL_DIR/bin/"
else
    echo "   检测到当前目录即安装目录，跳过代码复制"
fi

# 创建 .env 文件（如果不存在）
if [ ! -f "$INSTALL_DIR/.env" ]; then
    if [ -f "$FALLBACK_ENV_FILE" ]; then
        echo "   检测到回退配置文件: $FALLBACK_ENV_FILE"
        echo "   ℹ️  将优先使用 $FALLBACK_ENV_FILE（直到创建 $INSTALL_DIR/.env）"
    elif [ -f "$SCRIPT_DIR/.env.example" ]; then
        cp "$SCRIPT_DIR/.env.example" "$INSTALL_DIR/.env"
        echo "   ✅ 已创建 .env 配置文件"
        echo "   ⚠️  请编辑 $INSTALL_DIR/.env 修改配置"
    else
        # 创建默认配置
        cat > "$INSTALL_DIR/.env" <<EOF
DB_PATH=$DATA_DIR/gateway/gateway.db
GATEWAY_PORT=8000
OPENCLAW_PROTOCOL=ws
OPENCLAW_TIMEOUT=180
OPENCLAW_CONNECT_TIMEOUT=10
OPENCLAW_WS_IDLE_TIMEOUT=30
OPENCLAW_WS_TOTAL_TIMEOUT=180
OPENCLAW_SSE_IDLE_TIMEOUT=30
OPENCLAW_SSE_TOTAL_TIMEOUT=180
OPENCLAW_HTTP_TIMEOUT=180
MAX_GATEWAY_WORKERS=8
MAX_PER_USER_PENDING=1
MAX_QUEUE_WAIT_SECONDS=60
GATEWAY_URL=http://localhost:8000
FILE_STORAGE_MODE=local
FILE_STORAGE_PRESIGN_EXPIRES=86400
FILE_UPLOAD_INTERNAL_TOKEN=
MAX_INTERNAL_UPLOAD_FILE_SIZE=52428800
FILE_STORAGE_KEY_PREFIX=openclaw-gateway
S3_BUCKET=
S3_REGION=us-east-1
S3_ENDPOINT_URL=
S3_ACCESS_KEY_ID=
S3_SECRET_ACCESS_KEY=
S3_KEY_PREFIX=openclaw-gateway
S3_SIGNATURE_VERSION=s3
S3_ADDRESSING_STYLE=path
S3_SSE_MODE=
S3_SSE_KMS_KEY_ID=
EOF
        echo "   ✅ 已创建默认 .env 配置文件"
    fi
else
    echo "   .env 已存在，跳过"
fi

# 自动清理无效 TLS 证书路径（避免 requests 报 invalid certifi/cacert.pem）
sanitize_tls_env_file "$INSTALL_DIR/.env"
sanitize_tls_env_file "$FALLBACK_ENV_FILE"

echo "   ✅ 代码文件复制完成"

# 步骤 6: 创建 venv 并安装 Python 依赖
echo ""
echo "🐍 步骤 6/8: 创建 Python 虚拟环境并安装依赖..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
    echo "   ✅ 虚拟环境已创建: $VENV_DIR"
else
    echo "   虚拟环境已存在，跳过创建"
fi
"$VENV_DIR/bin/pip" install -q --upgrade pip
"$VENV_DIR/bin/pip" install -q -r "$INSTALL_DIR/src/gateway/requirements.txt"

# certifi 偶发损坏会导致 requests 报 "invalid path .../certifi/cacert.pem"
if ! "$VENV_DIR/bin/python" - <<'PYEOF'
import os
import certifi
path = certifi.where()
if not path or not os.path.isfile(path):
    raise SystemExit(1)
print(path)
PYEOF
then
    echo "   ⚠️  检测到 certifi CA 路径异常，尝试修复..."
    "$VENV_DIR/bin/pip" install -q --force-reinstall certifi
fi

echo "   ✅ Python 依赖安装完成"

# 步骤 7: 设置权限
echo ""
echo "🔐 步骤 7/8: 设置文件权限..."
chown -R "$RUN_USER:$RUN_GROUP" "$INSTALL_DIR"
chown -R "$RUN_USER:$RUN_GROUP" "$DATA_DIR"
chown -R "$RUN_USER:$RUN_GROUP" "$LOG_DIR"
if [ -f "$INSTALL_DIR/.env" ]; then
    chmod 600 "$INSTALL_DIR/.env"
fi
if [ -f "$FALLBACK_ENV_FILE" ]; then
    chmod 600 "$FALLBACK_ENV_FILE" 2>/dev/null || true
fi
chmod +x "$INSTALL_DIR/scripts/manage-agent.py"
chmod +x "$INSTALL_DIR/scripts/"*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/bin/"*.sh 2>/dev/null || true
echo "   ✅ 权限设置完成"

# 步骤 8: 安装并启动 systemd 服务
echo ""
echo "⚙️  步骤 8/8: 配置 systemd 服务..."
# 用实际运行用户替换 service 模板中的占位符
sed -e "s/__RUN_USER__/$RUN_USER/g" -e "s/__RUN_GROUP__/$RUN_GROUP/g" \
    "$SCRIPT_DIR/scripts/openclaw-gateway.service" > /etc/systemd/system/openclaw-gateway.service
systemctl daemon-reload
systemctl enable openclaw-gateway.service
if systemctl is-active --quiet openclaw-gateway.service; then
    systemctl restart openclaw-gateway.service
    echo "   ✅ systemd 服务已重启（已加载最新代码）"
else
    systemctl start openclaw-gateway.service
    echo "   ✅ systemd 服务已启动"
fi

echo "   ✅ systemd 服务安装/更新完成"

# 等待服务启动
echo ""
echo "⏳ 等待服务启动..."
sleep 3

# 检查服务状态
if systemctl is-active --quiet openclaw-gateway.service; then
    echo ""
    echo "=========================================="
    echo "✅ 部署完成！"
    echo "=========================================="
    echo ""
    echo "服务状态: $(systemctl is-active openclaw-gateway.service)"
    echo "安装目录: $INSTALL_DIR"
    echo "数据目录: $DATA_DIR"
    echo "日志目录: $LOG_DIR"
    echo ""
    echo "说明: 本脚本会将当前仓库代码同步到 $INSTALL_DIR"
    echo "      更新代码后请重新执行本脚本；仅重启服务不会同步新代码"
    echo ""
    echo "下一步操作:"
    echo "  1. 编辑配置: sudo nano $INSTALL_DIR/.env"
    echo "  2. 仅配置变更时重启: sudo systemctl restart openclaw-gateway"
    echo "  3. 添加 Agent: $INSTALL_DIR/bin/04-manage-agent.sh add <name>"
    echo "  4. 查看日志: tail -f /var/log/openclaw/gateway.log"
    echo "  5. 查看状态: sudo systemctl status openclaw-gateway"
    echo ""
    echo "健康检查: curl http://localhost:8000/health"
    echo ""
else
    echo ""
    echo "❌ 服务启动失败，请查看日志:"
    echo "   sudo journalctl -u openclaw-gateway -n 50"
    exit 1
fi
