#!/usr/bin/env python3
"""
OpenClaw 企业微信桥接网关 — Agent 绑定管理工具

用法:
  python3 manage-agent.py add <name>       交互式添加 agent-企业微信绑定
  python3 manage-agent.py remove <name>    删除绑定（需确认）
  python3 manage-agent.py list             列出所有绑定
  python3 manage-agent.py update <name>    更新绑定（同名覆盖，需确认）
"""

import sys
import os
import re
import sqlite3
import requests

# 数据库路径（与 Gateway 一致）
DB_PATH = os.getenv('DB_PATH', '/opt/openclaw/data/gateway/gateway.db')

# Gateway 地址（用于通知重载）
GATEWAY_URL = os.getenv('GATEWAY_URL', 'http://localhost:8000')

# 默认 OpenClaw 地址
DEFAULT_OPENCLAW_URL = 'http://localhost:18789'

# 默认共享目录基础路径（位于 agent workspace 内，确保 Docker sandbox 能挂载）
OPENCLAW_HOME = os.path.expanduser(os.getenv('OPENCLAW_HOME', '~/.openclaw'))

NAME_PATTERN = re.compile(r'^[a-z0-9][a-z0-9\-]{1,28}[a-z0-9]$')


def get_db():
    """获取数据库连接，确保表存在"""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''CREATE TABLE IF NOT EXISTS agents (
        name              TEXT PRIMARY KEY,
        display_name      TEXT NOT NULL,
        wecom_token       TEXT NOT NULL,
        wecom_aes_key     TEXT NOT NULL,
        openclaw_url      TEXT NOT NULL,
        openclaw_token    TEXT NOT NULL,
        openclaw_agent_id TEXT DEFAULT '',
        shared_dir        TEXT DEFAULT '',
        created_at        TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at        TEXT DEFAULT CURRENT_TIMESTAMP
    )''')
    # 兼容旧版数据库：如果 shared_dir 列不存在则添加
    try:
        conn.execute("SELECT shared_dir FROM agents LIMIT 0")
    except sqlite3.OperationalError:
        conn.execute("ALTER TABLE agents ADD COLUMN shared_dir TEXT DEFAULT ''")
    conn.commit()
    return conn


def notify_reload():
    """通知 Gateway 重载 agent 绑定"""
    try:
        resp = requests.post(f"{GATEWAY_URL}/admin/reload", timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            print(f"已通知 Gateway 重载（当前 {len(data.get('agents', []))} 个 agent）")
        else:
            print(f"通知 Gateway 重载失败: HTTP {resp.status_code}")
    except requests.exceptions.ConnectionError:
        print(f"无法连接 Gateway ({GATEWAY_URL})，请手动重启或稍后重载")
    except Exception as e:
        print(f"通知 Gateway 重载异常: {e}")


def mask(s, show=4):
    """遮掩敏感字符串"""
    if len(s) <= show:
        return s
    return s[:show] + '...'


def cmd_add(name):
    """添加 agent 绑定"""
    if not NAME_PATTERN.match(name):
        print(f"错误: name 格式不合法（英文小写+数字+连字符，3-30 字符）: {name}")
        sys.exit(1)

    conn = get_db()
    existing = conn.execute("SELECT name FROM agents WHERE name = ?", (name,)).fetchone()
    if existing:
        print(f"错误: agent '{name}' 已存在，请使用 update 命令修改")
        conn.close()
        sys.exit(1)

    print(f"\n添加 agent 绑定: {name}")
    print("-" * 40)

    display_name = input("显示名（如 '开发工程师小明'）: ").strip()
    if not display_name:
        print("错误: 显示名不能为空")
        sys.exit(1)

    wecom_token = input("企业微信 Token: ").strip()
    if not wecom_token:
        print("错误: Token 不能为空")
        sys.exit(1)

    wecom_aes_key = input("企业微信 EncodingAESKey: ").strip()
    if not wecom_aes_key:
        print("错误: AESKey 不能为空")
        sys.exit(1)

    openclaw_url = input(f"openclaw 地址（回车使用默认 {DEFAULT_OPENCLAW_URL}）: ").strip()
    if not openclaw_url:
        openclaw_url = DEFAULT_OPENCLAW_URL
    openclaw_url = openclaw_url.rstrip('/')

    openclaw_token = input("openclaw Token: ").strip()
    if not openclaw_token:
        print("错误: openclaw Token 不能为空")
        sys.exit(1)

    openclaw_agent_id = input("openclaw Agent ID（回车跳过，默认 main）: ").strip()

    # 共享目录：Gateway 下载的文件保存到此目录，同时挂载到 Docker 沙箱容器的 /shared
    # 共享目录位于 agent workspace 内，确保 Docker sandbox bind mount 安全检查通过
    openclaw_agent = openclaw_agent_id or 'main'
    default_shared = os.path.join(OPENCLAW_HOME, f'workspace-{openclaw_agent}', 'shared') if openclaw_agent != 'main' else os.path.join(OPENCLAW_HOME, 'workspace', 'shared')
    shared_dir = input(f"共享文件目录（回车使用默认 {default_shared}）: ").strip()
    if not shared_dir:
        shared_dir = default_shared

    # 确认
    print(f"\n确认添加？")
    print(f"  路由名:     {name}")
    print(f"  显示名:     {display_name}")
    print(f"  企业微信:   Token={mask(wecom_token)} AESKey={mask(wecom_aes_key)}")
    print(f"  openclaw:   {openclaw_url} (agent: {openclaw_agent_id or 'main'})")
    print(f"  共享目录:   {shared_dir}")

    confirm = input("\n[Y/n] ").strip().lower()
    if confirm and confirm != 'y':
        print("已取消")
        conn.close()
        return

    conn.execute(
        "INSERT INTO agents (name, display_name, wecom_token, wecom_aes_key, "
        "openclaw_url, openclaw_token, openclaw_agent_id, shared_dir) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (name, display_name, wecom_token, wecom_aes_key, openclaw_url, openclaw_token,
         openclaw_agent_id, shared_dir)
    )
    conn.commit()
    conn.close()

    # 自动创建共享目录
    os.makedirs(shared_dir, exist_ok=True)
    print(f"已创建共享目录: {shared_dir}")

    print(f"已添加 agent '{name}'")
    print(f"企业微信回调地址: https://your-domain/{name}/wecom/callback")
    notify_reload()


def cmd_remove(name):
    """删除 agent 绑定"""
    conn = get_db()
    row = conn.execute(
        "SELECT name, display_name, wecom_token, openclaw_url, openclaw_agent_id, shared_dir FROM agents WHERE name = ?",
        (name,)
    ).fetchone()
    if not row:
        print(f"错误: agent '{name}' 不存在")
        conn.close()
        sys.exit(1)

    _, display, token, url, agent_id, shared_dir = row
    print(f"\n即将删除:")
    print(f"  路由名: {name} ({display})")
    print(f"  企业微信: Token={mask(token)}")
    print(f"  openclaw: {url} (agent: {agent_id or 'main'})")
    print(f"  共享目录: {shared_dir or '(未设置)'}")

    confirm = input("\n确认删除？此操作不可恢复。[y/N] ").strip().lower()
    if confirm != 'y':
        print("已取消")
        conn.close()
        return

    conn.execute("DELETE FROM agents WHERE name = ?", (name,))
    conn.commit()
    conn.close()

    print(f"已删除 agent '{name}'")
    if shared_dir:
        print(f"注意: 共享目录 {shared_dir} 未删除，如需清理请手动删除")
    notify_reload()


def cmd_update(name):
    """更新 agent 绑定"""
    conn = get_db()
    row = conn.execute(
        "SELECT name, display_name, wecom_token, wecom_aes_key, openclaw_url, openclaw_token, openclaw_agent_id, shared_dir FROM agents WHERE name = ?",
        (name,)
    ).fetchone()
    if not row:
        print(f"错误: agent '{name}' 不存在")
        conn.close()
        sys.exit(1)

    _, old_display, old_token, old_aes, old_url, old_oc_token, old_agent_id, old_shared_dir = row

    print(f"\n更新 agent 绑定: {name}")
    print(f"当前配置:")
    print(f"  显示名:     {old_display}")
    print(f"  企业微信:   Token={mask(old_token)} AESKey={mask(old_aes)}")
    print(f"  openclaw:   {old_url} (agent: {old_agent_id or 'main'})")
    print(f"  共享目录:   {old_shared_dir or '(未设置)'}")

    print(f"\n输入新值（回车保持不变）:")

    display_name = input(f"显示名 [{old_display}]: ").strip() or old_display
    wecom_token = input(f"企业微信 Token [{mask(old_token)}]: ").strip() or old_token
    wecom_aes_key = input(f"企业微信 AES Key [{mask(old_aes)}]: ").strip() or old_aes
    openclaw_url = input(f"openclaw 地址 [{old_url}]: ").strip() or old_url
    openclaw_url = openclaw_url.rstrip('/')
    openclaw_token = input(f"openclaw Token [{mask(old_oc_token)}]: ").strip() or old_oc_token
    openclaw_agent_id = input(f"openclaw Agent ID [{old_agent_id or 'main'}]: ").strip()
    if not openclaw_agent_id:
        openclaw_agent_id = old_agent_id

    openclaw_agent = openclaw_agent_id or old_agent_id or 'main'
    if not old_shared_dir:
        default_shared = os.path.join(OPENCLAW_HOME, f'workspace-{openclaw_agent}', 'shared') if openclaw_agent != 'main' else os.path.join(OPENCLAW_HOME, 'workspace', 'shared')
    else:
        default_shared = old_shared_dir
    shared_dir = input(f"共享文件目录 [{default_shared}]: ").strip() or default_shared

    # 确认
    print(f"\n确认更新？")
    print(f"  路由名:     {name}")
    print(f"  显示名:     {display_name}")
    print(f"  企业微信:   Token={mask(wecom_token)} AESKey={mask(wecom_aes_key)}")
    print(f"  openclaw:   {openclaw_url} (agent: {openclaw_agent_id or 'main'})")
    print(f"  共享目录:   {shared_dir}")

    confirm = input("\n[Y/n] ").strip().lower()
    if confirm and confirm != 'y':
        print("已取消")
        conn.close()
        return

    conn.execute(
        "UPDATE agents SET display_name=?, wecom_token=?, wecom_aes_key=?, "
        "openclaw_url=?, openclaw_token=?, openclaw_agent_id=?, shared_dir=?, updated_at=CURRENT_TIMESTAMP "
        "WHERE name=?",
        (display_name, wecom_token, wecom_aes_key, openclaw_url, openclaw_token, openclaw_agent_id, shared_dir, name)
    )
    conn.commit()
    conn.close()

    # 确保共享目录存在
    if shared_dir:
        os.makedirs(shared_dir, exist_ok=True)

    print(f"已更新 agent '{name}'")
    notify_reload()


def cmd_list():
    """列出所有 agent 绑定"""
    conn = get_db()
    rows = conn.execute(
        "SELECT name, display_name, openclaw_url, openclaw_agent_id, shared_dir, created_at, updated_at FROM agents ORDER BY name"
    ).fetchall()
    conn.close()

    if not rows:
        print("当前无 agent 绑定")
        print("使用 python3 manage-agent.py add <name> 添加")
        return

    print(f"\n共 {len(rows)} 个 agent 绑定:")
    print("-" * 100)
    print(f"{'名称':<12} {'显示名':<16} {'openclaw 地址':<28} {'Agent ID':<10} {'共享目录':<30} {'创建时间'}")
    print("-" * 100)
    for name, display, url, agent_id, shared_dir, created, updated in rows:
        print(f"{name:<12} {display:<16} {url:<28} {(agent_id or 'main'):<10} {(shared_dir or '-'):<30} {created}")
    print("-" * 100)
    print(f"\n回调地址格式: https://your-domain/<name>/wecom/callback")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == 'list':
        cmd_list()
    elif command == 'add':
        if len(sys.argv) < 3:
            print("用法: python3 manage-agent.py add <name>")
            sys.exit(1)
        cmd_add(sys.argv[2])
    elif command == 'remove':
        if len(sys.argv) < 3:
            print("用法: python3 manage-agent.py remove <name>")
            sys.exit(1)
        cmd_remove(sys.argv[2])
    elif command == 'update':
        if len(sys.argv) < 3:
            print("用法: python3 manage-agent.py update <name>")
            sys.exit(1)
        cmd_update(sys.argv[2])
    else:
        print(f"未知命令: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == '__main__':
    main()
