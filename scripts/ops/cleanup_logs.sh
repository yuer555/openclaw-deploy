#!/bin/bash
# scripts/cleanup_logs.sh - 清理旧日志

LOG_DIR="/opt/openclaw/logs"
RETENTION_DAYS=30

echo "=== 日志清理 ==="
echo "保留最近 $RETENTION_DAYS 天的日志"

# 1. 清理 Nginx 日志
echo "清理 Nginx 日志..."
if [ -d "$LOG_DIR/nginx" ]; then
    find $LOG_DIR/nginx -name "*.log.*" -mtime +$RETENTION_DAYS -delete
    echo "✓ Nginx 日志清理完成"
else
    echo "⊘ Nginx 日志目录不存在"
fi

# 2. 清理企业微信网关日志
echo "清理网关日志..."
if [ -d "$LOG_DIR/wecom" ]; then
    find $LOG_DIR/wecom -name "*.log" -mtime +$RETENTION_DAYS -delete
    echo "✓ 网关日志清理完成"
else
    echo "⊘ 网关日志目录不存在"
fi

# 3. 清理任务日志（数据库）
echo "清理数据库中的旧任务日志..."
if [ -f "/opt/openclaw/data/user_roles.db" ]; then
    sqlite3 /opt/openclaw/data/user_roles.db <<EOF
DELETE FROM task_logs 
WHERE created_at < datetime('now', '-$RETENTION_DAYS days');
EOF
    echo "✓ 任务日志清理完成"
else
    echo "⊘ 数据库文件不存在"
fi

# 4. 清理审计日志
echo "清理审计日志..."
if [ -f "/opt/openclaw/data/user_roles.db" ]; then
    sqlite3 /opt/openclaw/data/user_roles.db <<EOF
DELETE FROM audit_logs 
WHERE created_at < datetime('now', '-90 days');
EOF
    echo "✓ 审计日志清理完成（保留90天）"
fi

# 5. 显示清理后的磁盘使用
echo ""
echo "清理后磁盘使用:"
if [ -d "/opt/openclaw" ]; then
    df -h /opt/openclaw | tail -1
else
    df -h ~/.openclaw/workspace | tail -1
fi

echo ""
echo "日志清理完成！"
