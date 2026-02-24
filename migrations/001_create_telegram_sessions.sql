-- 创建 Telegram 会话表
-- 用于存储用户会话状态和当前选择的虚拟员工

CREATE TABLE IF NOT EXISTS telegram_sessions (
    user_id BIGINT PRIMARY KEY,
    current_agent VARCHAR(50) DEFAULT 'dispatcher',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 创建索引以优化查询性能
CREATE INDEX IF NOT EXISTS idx_last_active ON telegram_sessions(last_active);

-- 创建索引以优化按 agent 查询
CREATE INDEX IF NOT EXISTS idx_current_agent ON telegram_sessions(current_agent);
