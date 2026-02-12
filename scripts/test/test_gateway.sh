#!/bin/bash

# ====================================================
# OpenClaw 企业微信网关功能测试脚本
# ====================================================

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

GATEWAY_URL="${GATEWAY_URL:-http://localhost:8000}"

echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}OpenClaw 企业微信网关功能测试${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

# 测试 1：健康检查
echo -e "\n${COLOR_YELLOW}[测试 1/4] 健康检查...${COLOR_RESET}"
response=$(curl -s "${GATEWAY_URL}/health")
if echo "$response" | grep -q "healthy"; then
    echo -e "  ${COLOR_GREEN}✅ 健康检查通过${COLOR_RESET}"
    echo "  响应: $response"
else
    echo -e "  ${COLOR_RED}❌ 健康检查失败${COLOR_RESET}"
    echo "  响应: $response"
    exit 1
fi

# 测试 2：统计信息
echo -e "\n${COLOR_YELLOW}[测试 2/4] 获取统计信息...${COLOR_RESET}"
response=$(curl -s "${GATEWAY_URL}/stats")
if echo "$response" | grep -q "total_tasks"; then
    echo -e "  ${COLOR_GREEN}✅ 统计信息获取成功${COLOR_RESET}"
    echo "  响应: $response"
else
    echo -e "  ${COLOR_RED}❌ 统计信息获取失败${COLOR_RESET}"
    echo "  响应: $response"
fi

# 测试 3：测试消息发送（需要配置企业微信）
echo -e "\n${COLOR_YELLOW}[测试 3/4] 测试消息发送...${COLOR_RESET}"
echo -e "${COLOR_YELLOW}  请输入测试用户ID（企业微信UserID，输入 skip 跳过）:${COLOR_RESET}"
read -r test_user_id

if [ "$test_user_id" != "skip" ] && [ -n "$test_user_id" ]; then
    response=$(curl -s -X POST "${GATEWAY_URL}/test/send" \
        -H "Content-Type: application/json" \
        -d "{\"user_id\":\"${test_user_id}\",\"content\":\"OpenClaw 网关测试消息 $(date)\"}")
    
    if echo "$response" | grep -q '"success":true'; then
        echo -e "  ${COLOR_GREEN}✅ 测试消息发送成功${COLOR_RESET}"
        echo "  响应: $response"
    else
        echo -e "  ${COLOR_RED}❌ 测试消息发送失败${COLOR_RESET}"
        echo "  响应: $response"
    fi
else
    echo -e "  ${COLOR_YELLOW}⏭  跳过消息发送测试${COLOR_RESET}"
fi

# 测试 4：Access Token 获取
echo -e "\n${COLOR_YELLOW}[测试 4/4] Access Token 检查...${COLOR_RESET}"
if [ -n "$WECOM_CORP_ID" ] && [ -n "$WECOM_SECRET" ]; then
    token_response=$(curl -s "https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid=${WECOM_CORP_ID}&corpsecret=${WECOM_SECRET}")
    
    if echo "$token_response" | grep -q "access_token"; then
        echo -e "  ${COLOR_GREEN}✅ Access Token 获取成功${COLOR_RESET}"
        echo "  Token: $(echo "$token_response" | grep -o '"access_token":"[^"]*"')"
    else
        echo -e "  ${COLOR_RED}❌ Access Token 获取失败${COLOR_RESET}"
        echo "  响应: $token_response"
    fi
else
    echo -e "  ${COLOR_YELLOW}⚠️  未配置企业微信环境变量，跳过 Token 测试${COLOR_RESET}"
    echo "  请设置: WECOM_CORP_ID 和 WECOM_SECRET"
fi

echo -e "\n${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}测试完成！${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

# 显示下一步操作
echo -e "\n${COLOR_YELLOW}📋 下一步操作：${COLOR_RESET}"
echo "1. 如果健康检查通过，网关基本功能正常"
echo "2. 配置企业微信凭证（.env 文件）"
echo "3. 配置企业微信回调 URL: ${GATEWAY_URL}/wecom/callback"
echo "4. 添加测试用户: bash scripts/user/add_user.sh"
echo "5. 在企业微信中发送消息测试"
echo ""
echo "详细文档: docs/04-企业微信配置.md"
