#!/bin/bash
# scripts/remove_user.sh - 删除用户绑定

DB_PATH="/opt/openclaw/data/user_roles.db"

read -p "企业微信 UserId: " user_id

# 确认删除
read -p "确认删除用户 $user_id 的绑定吗？(yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "已取消删除"
    exit 0
fi

# 删除数据库记录
sqlite3 "$DB_PATH" <<EOF
DELETE FROM user_roles WHERE user_id = '$user_id';
EOF

echo "✓ 用户 $user_id 已删除"
