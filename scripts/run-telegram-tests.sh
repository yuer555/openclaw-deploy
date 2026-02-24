#!/bin/bash

#==============================================================================
# Telegram Adapter 测试运行脚本
# 用途: 运行单元测试和集成测试
#==============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Telegram Adapter 测试"
echo "=========================================="
echo ""

# 检查 Python
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ 错误: Python 3 未安装${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Python 版本: $(python3 --version)${NC}"
echo ""

# 安装测试依赖
echo "安装测试依赖..."
pip3 install -q pytest pytest-cov requests 2>/dev/null || true
echo -e "${GREEN}✅ 依赖已安装${NC}"
echo ""

# 运行单元测试
echo "运行单元测试..."
echo "----------------------------------------"
cd "$(dirname "$0")/.."

if python3 -m pytest tests/test_telegram_adapter.py -v --cov=src/gateway/telegram_adapter --cov-report=term-missing; then
    echo ""
    echo -e "${GREEN}✅ 单元测试通过${NC}"
else
    echo ""
    echo -e "${RED}❌ 单元测试失败${NC}"
    exit 1
fi

echo ""
echo "=========================================="
echo -e "${GREEN}✅ 所有测试通过！${NC}"
echo "=========================================="
