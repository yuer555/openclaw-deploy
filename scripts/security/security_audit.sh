#!/bin/bash
# scripts/security_audit.sh - 安全审计脚本

echo "=== OpenClaw 安全审计 ==="
echo ""

# 1. 检查容器权限
echo "【1】检查容器权限配置"
if command -v docker &> /dev/null; then
    for agent in operation-agent product-agent development-agent testing-agent service-agent; do
        if docker ps --format '{{.Names}}' | grep -q "$agent"; then
            PRIVILEGED=$(docker inspect $agent 2>/dev/null | jq -r '.[0].HostConfig.Privileged')
            if [ "$PRIVILEGED" == "false" ]; then
                echo "✓ $agent: 非特权模式"
            else
                echo "✗ $agent: 特权模式 (安全风险)"
            fi
        fi
    done
else
    echo "⊘ Docker 未安装"
fi

echo ""

# 2. 检查文件权限
echo "【2】检查敏感文件权限"
if [ -d "/opt/openclaw/config" ]; then
    PERM=$(stat -f "%OLp" /opt/openclaw/config 2>/dev/null || stat -c "%a" /opt/openclaw/config 2>/dev/null)
    if [ "$PERM" == "700" ] || [ "$PERM" == "600" ]; then
        echo "✓ 配置目录权限正确: $PERM"
    else
        echo "✗ 配置目录权限过宽: $PERM (建议 700)"
    fi
    
    for file in /opt/openclaw/config/*.yaml /opt/openclaw/.env; do
        if [ -f "$file" ]; then
            FPERM=$(stat -f "%OLp" "$file" 2>/dev/null || stat -c "%a" "$file" 2>/dev/null)
            if [ "$FPERM" == "600" ]; then
                echo "✓ $(basename $file): $FPERM"
            else
                echo "⚠ $(basename $file): $FPERM (建议 600)"
            fi
        fi
    done
else
    echo "⊘ 配置目录不存在"
fi

echo ""

# 3. 检查开放端口
echo "【3】检查开放端口"
if command -v netstat &> /dev/null; then
    echo "监听端口:"
    netstat -tuln 2>/dev/null | grep LISTEN | awk '{print $4}' | sed 's/.*://' | sort -u | head -10
elif command -v ss &> /dev/null; then
    echo "监听端口:"
    ss -tuln | grep LISTEN | awk '{print $5}' | sed 's/.*://' | sort -u | head -10
else
    echo "⊘ 无法检查端口（netstat/ss 不可用）"
fi

echo ""

# 4. 检查防火墙规则
echo "【4】检查防火墙规则"
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    echo "$UFW_STATUS"
    if echo "$UFW_STATUS" | grep -q "active"; then
        echo "✓ 防火墙已启用"
    else
        echo "✗ 防火墙未启用 (安全风险)"
    fi
elif command -v firewall-cmd &> /dev/null; then
    firewall-cmd --state 2>/dev/null
else
    echo "⊘ 防火墙未配置"
fi

echo ""

# 5. 检查日志异常
echo "【5】检查日志异常 (最近 20 条)"
if [ -d "/opt/openclaw/logs" ]; then
    ERROR_COUNT=$(grep -ri "error\|warning\|unauthorized" /opt/openclaw/logs/*.log 2>/dev/null | wc -l)
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "⚠ 发现 $ERROR_COUNT 条异常日志"
        grep -ri "error\|warning\|unauthorized" /opt/openclaw/logs/*.log 2>/dev/null | tail -20
    else
        echo "✓ 未发现异常日志"
    fi
else
    echo "⊘ 日志目录不存在"
fi

echo ""

# 6. 检查 API 密钥安全
echo "【6】检查 API 密钥是否加密存储"
if [ -d "/opt/openclaw/config" ]; then
    FOUND=$(grep -r "ANTHROPIC_API_KEY\|sk-ant-" /opt/openclaw/config/*.yaml 2>/dev/null)
    if [ -z "$FOUND" ]; then
        echo "✓ 未发现明文密钥"
    else
        echo "✗ 发现明文密钥 (安全风险)"
        echo "$FOUND"
    fi
else
    echo "⊘ 配置目录不存在"
fi

echo ""

# 7. 检查容器网络隔离
echo "【7】检查容器网络隔离"
if command -v docker &> /dev/null; then
    NETWORK=$(docker network ls | grep openclaw)
    if [ -n "$NETWORK" ]; then
        echo "✓ OpenClaw 网络已配置"
        docker network inspect openclaw-network 2>/dev/null | jq -r '.[0].Containers | keys[]' 2>/dev/null || echo "容器列表获取失败"
    else
        echo "⊘ OpenClaw 网络未配置"
    fi
else
    echo "⊘ Docker 未安装"
fi

echo ""

# 8. 生成报告
echo "【8】生成审计报告"
REPORT_DIR="/opt/openclaw/logs"
REPORT_FILE="$REPORT_DIR/security_audit_$(date +%Y%m%d_%H%M%S).log"

if [ -d "$REPORT_DIR" ]; then
    {
        echo "=== OpenClaw 安全审计报告 ==="
        echo "时间: $(date)"
        echo ""
        echo "审计项目: 容器权限、文件权限、开放端口、防火墙、日志异常、密钥安全、网络隔离"
        echo ""
        echo "详细信息请查看上述输出"
    } > "$REPORT_FILE"
    echo "✓ 报告已保存: $REPORT_FILE"
else
    echo "⊘ 日志目录不存在，无法保存报告"
fi

echo ""
echo "=== 审计完成 ==="
