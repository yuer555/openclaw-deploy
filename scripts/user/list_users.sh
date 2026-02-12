#!/bin/bash
# scripts/list_users.sh - 查看所有用户绑定

DB_PATH="/opt/openclaw/data/user_roles.db"

echo "=== 用户角色绑定列表 ==="
echo ""

sqlite3 -header -column "$DB_PATH" <<EOF
SELECT 
    user_id AS "企业微信ID",
    user_name AS "姓名",
    agents AS "绑定角色",
    created_at AS "创建时间"
FROM user_roles
ORDER BY created_at DESC;
EOF
