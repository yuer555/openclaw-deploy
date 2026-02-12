#!/bin/bash
# scripts/performance_test.sh - 性能测试脚本

WECOM_URL="https://your-domain.com/wecom/callback"
CONCURRENT=10
REQUESTS=100

echo "=== OpenClaw 性能测试 ==="
echo "目标地址: $WECOM_URL"
echo "并发数: $CONCURRENT"
echo "请求数: $REQUESTS"
echo ""

# 检查 ab 工具
if ! command -v ab &> /dev/null; then
    echo "✗ Apache Bench (ab) 未安装"
    echo "安装方法:"
    echo "  macOS: brew install httpd"
    echo "  Ubuntu: apt install apache2-utils"
    exit 1
fi

# 创建测试消息文件
cat > /tmp/test_message.xml <<EOF
<xml>
    <ToUserName><![CDATA[test]]></ToUserName>
    <FromUserName><![CDATA[test_user]]></FromUserName>
    <CreateTime>1234567890</CreateTime>
    <MsgType><![CDATA[text]]></MsgType>
    <Content><![CDATA[性能测试消息]]></Content>
    <MsgId>1234567890123456</MsgId>
</xml>
EOF

echo "开始测试..."
echo ""

# 执行测试
ab -n $REQUESTS -c $CONCURRENT -p /tmp/test_message.xml -T "text/xml" $WECOM_URL

# 清理
rm -f /tmp/test_message.xml

echo ""
echo "=== 测试完成 ==="
echo ""
echo "关键指标说明:"
echo "- Requests per second: 每秒处理请求数 (越高越好)"
echo "- Time per request: 平均响应时间 (越低越好)"
echo "- Failed requests: 失败请求数 (应该为 0)"
echo ""
echo "性能基准参考:"
echo "- 优秀: RPS > 100, 响应时间 < 100ms"
echo "- 良好: RPS > 50, 响应时间 < 200ms"
echo "- 一般: RPS > 20, 响应时间 < 500ms"
