#!/bin/bash
# scripts/init_database.sh - 数据库初始化脚本

set -e

echo "=== OpenClaw 数据库初始化 ==="
echo ""

DB_PATH="/opt/openclaw/data/user_roles.db"
DB_DIR=$(dirname "$DB_PATH")

# 1. 创建数据目录
echo "【1】创建数据目录..."
mkdir -p "$DB_DIR"
echo "✓ 数据目录: $DB_DIR"

# 2. 检查数据库是否已存在
if [ -f "$DB_PATH" ]; then
    echo ""
    echo "⚠ 数据库文件已存在: $DB_PATH"
    read -p "是否备份并重新初始化？(yes/no): " confirm
    
    if [ "$confirm" == "yes" ]; then
        BACKUP_FILE="${DB_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
        mv "$DB_PATH" "$BACKUP_FILE"
        echo "✓ 原数据库已备份到: $BACKUP_FILE"
    else
        echo "已取消初始化"
        exit 0
    fi
fi

# 3. 创建数据库和表结构
echo ""
echo "【2】创建数据库表结构..."

sqlite3 "$DB_PATH" <<'EOF'
-- 用户角色绑定表
CREATE TABLE IF NOT EXISTS user_roles (
    user_id TEXT PRIMARY KEY,               -- 企业微信 UserId
    user_name TEXT NOT NULL,                -- 用户姓名
    agents TEXT NOT NULL,                   -- 绑定的代理列表（逗号分隔）
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 任务日志表
CREATE TABLE IF NOT EXISTS task_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT UNIQUE NOT NULL,           -- 任务 ID
    user_id TEXT NOT NULL,                  -- 用户 ID
    agent TEXT NOT NULL,                    -- 执行代理
    task_content TEXT NOT NULL,             -- 任务内容
    status TEXT NOT NULL,                   -- 状态: pending/running/success/failed
    result TEXT,                            -- 执行结果
    error_message TEXT,                     -- 错误信息
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    duration_seconds INTEGER,               -- 执行时长 (秒)
    
    FOREIGN KEY (user_id) REFERENCES user_roles(user_id)
);

-- 审计日志表
CREATE TABLE IF NOT EXISTS audit_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    event_type TEXT NOT NULL,               -- 事件类型: login/task/security
    user_id TEXT,
    agent TEXT,
    action TEXT NOT NULL,                   -- 操作: create/read/update/delete
    resource TEXT,                          -- 资源: task/file/config
    status TEXT NOT NULL,                   -- 状态: success/failed
    ip_address TEXT,
    user_agent TEXT,
    details TEXT,                           -- JSON 格式详情
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_user_id ON user_roles(user_id);
CREATE INDEX IF NOT EXISTS idx_task_status ON task_logs(status);
CREATE INDEX IF NOT EXISTS idx_task_user ON task_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_event ON audit_logs(event_type);
CREATE INDEX IF NOT EXISTS idx_audit_time ON audit_logs(created_at);

-- 插入测试数据（可选）
-- INSERT INTO user_roles (user_id, user_name, agents) 
-- VALUES ('admin', '管理员', 'operation-agent,product-agent,development-agent,testing-agent,service-agent');
EOF

echo "✓ 数据库表结构创建完成"

# 4. 验证表结构
echo ""
echo "【3】验证表结构..."
sqlite3 "$DB_PATH" <<'EOF'
.tables
EOF

echo ""
sqlite3 "$DB_PATH" <<'EOF'
SELECT name, sql FROM sqlite_master WHERE type='table';
EOF

# 5. 设置文件权限
echo ""
echo "【4】设置文件权限..."
chmod 600 "$DB_PATH"
chown $(logname):$(logname) "$DB_PATH" 2>/dev/null || echo "⚠ 无法设置所有者，跳过"
echo "✓ 数据库权限: 600 (仅所有者可读写)"

# 6. 创建示例用户（可选）
echo ""
read -p "是否创建示例管理员用户？(y/n): " create_admin

if [ "$create_admin" == "y" ]; then
    read -p "企业微信 UserId: " admin_id
    read -p "姓名: " admin_name
    
    sqlite3 "$DB_PATH" <<EOF
INSERT INTO user_roles (user_id, user_name, agents) 
VALUES ('$admin_id', '$admin_name', 'operation-agent,product-agent,development-agent,testing-agent,service-agent');
EOF
    
    echo "✓ 管理员用户已创建"
fi

# 7. 显示统计信息
echo ""
echo "【5】数据库统计..."
echo "用户数量: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM user_roles;")"
echo "任务数量: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM task_logs;")"
echo "审计日志: $(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM audit_logs;")"

# 8. 输出摘要
echo ""
echo "=== 数据库初始化完成 ==="
echo ""
echo "✓ 数据库文件: $DB_PATH"
echo "✓ 表: user_roles, task_logs, audit_logs"
echo "✓ 索引: 5 个"
echo ""
echo "管理命令:"
echo "  查看用户: sqlite3 $DB_PATH 'SELECT * FROM user_roles;'"
echo "  查看任务: sqlite3 $DB_PATH 'SELECT * FROM task_logs;'"
echo "  备份数据: cp $DB_PATH ${DB_PATH}.backup"
echo ""
echo "下一步: 运行 ./scripts/add_user.sh 添加用户绑定"
