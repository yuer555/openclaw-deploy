#!/bin/bash
#==============================================================================
# 脚本名称: 0-build-images.sh
# 功能描述: 构建 openclaw-base 和 agent 镜像
# 使用方法: ./0-build-images.sh
# 版本: V3.0
#==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_step()    { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n${BLUE}📍 $1${NC}\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

print_step "构建 Base 镜像（openclaw-base:latest）"
docker build \
    -f config/Dockerfile.base \
    -t openclaw-base:latest \
    .
print_success "openclaw-base:latest 构建完成"

print_step "构建 Agent 镜像（5 个角色）"

for ROLE in operation product development testing service; do
    print_info "构建 openclaw-agent-${ROLE}:local ..."
    docker build --no-cache \
        -f config/Dockerfile.agents \
        --build-arg ROLE=${ROLE} \
        -t openclaw-agent-${ROLE}:local \
        .
    print_success "openclaw-agent-${ROLE}:local 构建完成"
done

echo ""
print_success "所有镜像构建完成！"
echo ""
docker images | grep "openclaw-"
echo ""
print_info "下一步：./1-init-local.sh"
