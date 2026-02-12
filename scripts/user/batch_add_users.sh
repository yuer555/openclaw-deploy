#!/bin/bash
# scripts/batch_add_users.sh - 批量添加用户绑定

DB_PATH="/opt/openclaw/data/user_roles.db"
CSV_FILE=$1

if [ -z "$CSV_FILE" ]; then
    echo "用法: ./batch_add_users.sh <csv-file>"
    echo "CSV 格式: user_id,user_name,agents"
    echo "示例: zhangsan,张三,operation-agent,product-agent"
    exit 1
fi

echo "=== 批量添加用户绑定 ==="

# 读取 CSV 文件
while IFS=',' read -r user_id user_name agents_raw; do
    # 跳过标题行
    if [ "$user_id" == "user_id" ]; then
        continue
    fi
    
    # 转换代理列表格式
    agents=$(echo "$agents_raw" | tr ' ' ',')
    
    # 插入数据库
    sqlite3 "$DB_PATH" <<EOF
INSERT OR REPLACE INTO user_roles (user_id, user_name, agents, updated_at)
VALUES ('$user_id', '$user_name', '$agents', datetime('now'));
EOF
    
    echo "✓ 添加用户: $user_name ($user_id) - $agents"
done < "$CSV_FILE"

echo ""
echo "批量添加完成！"
