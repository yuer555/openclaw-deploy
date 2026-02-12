#!/bin/bash
# scripts/network_isolation.sh - 配置容器网络隔离

echo "=== 配置容器网络隔离 ==="
echo ""

# 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "✗ Docker 未安装"
    exit 1
fi

# 1. 禁止容器间互访（可选）
echo "【1】配置容器网络隔离"
read -p "是否创建隔离网络？(y/n): " create_isolated

if [ "$create_isolated" == "y" ]; then
    docker network create --internal openclaw-isolated 2>/dev/null && echo "✓ 隔离网络已创建" || echo "⊘ 隔离网络已存在"
fi

# 2. 运营代理 - 仅允许访问社交平台
echo ""
echo "【2】配置运营代理网络规则"
if docker ps --format '{{.Names}}' | grep -q "operation-agent"; then
    docker exec operation-agent bash -c "
    iptables -F OUTPUT 2>/dev/null
    iptables -A OUTPUT -d weixin.qq.com -j ACCEPT
    iptables -A OUTPUT -d api.weibo.com -j ACCEPT
    iptables -A OUTPUT -d graph.facebook.com -j ACCEPT
    iptables -A OUTPUT -j REJECT
    " 2>/dev/null && echo "✓ 运营代理网络规则已配置" || echo "⊘ 运营代理未运行"
else
    echo "⊘ 运营代理未运行"
fi

# 3. 研发代理 - 仅允许访问代码仓库
echo ""
echo "【3】配置研发代理网络规则"
if docker ps --format '{{.Names}}' | grep -q "development-agent"; then
    docker exec development-agent bash -c "
    iptables -F OUTPUT 2>/dev/null
    iptables -A OUTPUT -d github.com -j ACCEPT
    iptables -A OUTPUT -d gitlab.com -j ACCEPT
    iptables -A OUTPUT -d npmjs.com -j ACCEPT
    iptables -A OUTPUT -d pypi.org -j ACCEPT
    iptables -A OUTPUT -j REJECT
    " 2>/dev/null && echo "✓ 研发代理网络规则已配置" || echo "⊘ 研发代理未运行"
else
    echo "⊘ 研发代理未运行"
fi

# 4. 测试代理 - 仅允许访问测试环境
echo ""
echo "【4】配置测试代理网络规则"
if docker ps --format '{{.Names}}' | grep -q "testing-agent"; then
    docker exec testing-agent bash -c "
    iptables -F OUTPUT 2>/dev/null
    iptables -A OUTPUT -d test-api.example.com -j ACCEPT
    iptables -A OUTPUT -d staging.example.com -j ACCEPT
    iptables -A OUTPUT -j REJECT
    " 2>/dev/null && echo "✓ 测试代理网络规则已配置" || echo "⊘ 测试代理未运行"
else
    echo "⊘ 测试代理未运行"
fi

# 5. 客服代理 - 仅允许访问客服系统
echo ""
echo "【5】配置客服代理网络规则"
if docker ps --format '{{.Names}}' | grep -q "service-agent"; then
    docker exec service-agent bash -c "
    iptables -F OUTPUT 2>/dev/null
    iptables -A OUTPUT -d crm.example.com -j ACCEPT
    iptables -A OUTPUT -d kb.example.com -j ACCEPT
    iptables -A OUTPUT -d ticket.example.com -j ACCEPT
    iptables -A OUTPUT -j REJECT
    " 2>/dev/null && echo "✓ 客服代理网络规则已配置" || echo "⊘ 客服代理未运行"
else
    echo "⊘ 客服代理未运行"
fi

echo ""
echo "网络隔离配置完成！"
echo ""
echo "注意事项:"
echo "1. 上述规则在容器重启后会失效，建议在 docker-compose.yml 中配置"
echo "2. 域名规则需要根据实际环境修改（如 example.com 替换为真实域名）"
echo "3. 可以通过 docker exec <agent> iptables -L -n 查看当前规则"
