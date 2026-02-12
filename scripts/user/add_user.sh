#!/bin/bash
# scripts/add_user.sh - 添加用户绑定

DB_PATH="/opt/openclaw/data/user_roles.db"

echo "=== 添加企业微信用户绑定 ==="
read -p "企业微信 UserId: " user_id
read -p "用户姓名: " user_name
echo "选择绑定角色 (多个用逗号分隔):"
echo "1. operation-agent (运营)"
echo "2. product-agent (产品)"
echo "3. development-agent (研发)"
echo "4. testing-agent (测试)"
echo "5. service-agent (客服)"
read -p "输入角色编号 (如: 1,3): " roles_input

# 转换编号为角色名
agents=""
IFS=',' read -ra ROLES <<< "$roles_input"
for role in "${ROLES[@]}"; do
    case $role in
        1) agents="${agents}operation-agent," ;;
        2) agents="${agents}product-agent," ;;
        3) agents="${agents}development-agent," ;;
        4) agents="${agents}testing-agent," ;;
        5) agents="${agents}service-agent," ;;
    esac
done
agents=${agents%,}  # 删除末尾逗号

# 插入数据库
sqlite3 "$DB_PATH" <<EOF
INSERT OR REPLACE INTO user_roles (user_id, user_name, agents, updated_at)
VALUES ('$user_id', '$user_name', '$agents', datetime('now'));
EOF

echo "用户绑定成功！"
echo "UserId: $user_id"
echo "姓名: $user_name"
echo "绑定角色: $agents"
