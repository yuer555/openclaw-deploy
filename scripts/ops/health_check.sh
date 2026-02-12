#!/bin/bash
# scripts/health_check.sh - 系统健康检查

echo "=== OpenClaw 系统健康检查 ==="
echo ""

# 1. 检查容器状态
echo "【1】容器运行状态"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep openclaw || echo "未找到容器（请先部署）"

echo ""

# 2. 检查容器资源使用
echo "【2】容器资源使用"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "NAME|agent|gateway" || echo "容器未运行"

echo ""

# 3. 检查磁盘空间
echo "【3】磁盘空间"
if [ -d "/opt/openclaw" ]; then
    df -h /opt/openclaw | tail -1 | awk '{print "使用率: " $5 " | 剩余: " $4}'
else
    df -h ~/.openclaw/workspace | tail -1 | awk '{print "使用率: " $5 " | 剩余: " $4}'
fi

echo ""

# 4. 检查数据库大小
echo "【4】数据库大小"
if [ -f "/opt/openclaw/data/user_roles.db" ]; then
    du -h /opt/openclaw/data/*.db 2>/dev/null || echo "数据库未创建"
else
    echo "数据库路径未配置（本地测试环境）"
fi

echo ""

# 5. 检查最近错误日志
echo "【5】最近错误日志 (最近 10 条)"
if [ -d "/opt/openclaw/logs" ]; then
    tail -10 /opt/openclaw/logs/*.log 2>/dev/null | grep -i error || echo "✓ 无错误日志"
else
    echo "日志目录未配置"
fi

echo ""

# 6. 检查今日任务统计
echo "【6】今日任务统计"
if [ -f "/opt/openclaw/data/user_roles.db" ]; then
    sqlite3 /opt/openclaw/data/user_roles.db <<EOF
SELECT 
    agent AS "代理",
    COUNT(*) AS "总任务数",
    SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) AS "成功",
    SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) AS "失败",
    printf('%.1f%%', SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS "成功率"
FROM task_logs
WHERE date(created_at) = date('now')
GROUP BY agent;
EOF
else
    echo "数据库未创建"
fi

echo ""

# 7. 网络连接检查
echo "【7】网络连接检查"
curl -s -o /dev/null -w "企业微信 API: %{http_code}\n" https://qyapi.weixin.qq.com/cgi-bin/gettoken 2>/dev/null || echo "网络检查失败"

echo ""
echo "健康检查完成！"
