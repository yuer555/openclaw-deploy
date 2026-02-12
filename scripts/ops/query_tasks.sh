#!/bin/bash
# scripts/query_tasks.sh - 查询任务日志

DB_PATH="/opt/openclaw/data/user_roles.db"

echo "=== 任务日志查询 ==="
echo "1. 查看今日任务"
echo "2. 查看某个用户的任务"
echo "3. 查看某个代理的任务"
echo "4. 查看失败任务"
read -p "请选择 (1-4): " choice

case $choice in
    1)
        sqlite3 -header -column "$DB_PATH" <<EOF
SELECT 
    task_id AS "任务ID",
    user_id AS "用户",
    agent AS "代理",
    status AS "状态",
    created_at AS "创建时间"
FROM task_logs
WHERE date(created_at) = date('now')
ORDER BY created_at DESC
LIMIT 50;
EOF
        ;;
    
    2)
        read -p "输入用户 ID: " user_id
        sqlite3 -header -column "$DB_PATH" <<EOF
SELECT 
    task_id AS "任务ID",
    agent AS "代理",
    task_content AS "任务内容",
    status AS "状态",
    created_at AS "创建时间"
FROM task_logs
WHERE user_id = '$user_id'
ORDER BY created_at DESC
LIMIT 20;
EOF
        ;;
    
    3)
        read -p "输入代理名称: " agent
        sqlite3 -header -column "$DB_PATH" <<EOF
SELECT 
    task_id AS "任务ID",
    user_id AS "用户",
    task_content AS "任务内容",
    status AS "状态",
    duration_seconds AS "耗时(秒)",
    created_at AS "创建时间"
FROM task_logs
WHERE agent = '$agent'
ORDER BY created_at DESC
LIMIT 20;
EOF
        ;;
    
    4)
        sqlite3 -header -column "$DB_PATH" <<EOF
SELECT 
    task_id AS "任务ID",
    user_id AS "用户",
    agent AS "代理",
    error_message AS "错误信息",
    created_at AS "创建时间"
FROM task_logs
WHERE status = 'failed'
ORDER BY created_at DESC
LIMIT 20;
EOF
        ;;
    
    *)
        echo "无效选择"
        ;;
esac
