#!/usr/bin/env python3
"""
OpenClaw 企业微信桥接网关 — Agent 绑定管理工具

用法:
  python3 manage-agent.py add <name>       交互式添加 agent-企业微信绑定
  python3 manage-agent.py remove <name>    删除绑定（需确认）
  python3 manage-agent.py list             列出所有绑定
  python3 manage-agent.py update <name>    更新绑定（同名覆盖，需确认）
  python3 manage-agent.py sync-token       同步 openclaw token（批量更新）
"""

import sys
import os
import re
import json
import sqlite3
import unicodedata
import requests

# 数据库路径（与 Gateway 一致）
DB_PATH = os.getenv('DB_PATH', '/opt/openclaw/data/gateway/gateway.db')

# Gateway 地址（用于通知重载）
GATEWAY_URL = os.getenv('GATEWAY_URL', 'http://localhost:8000')

# 默认 OpenClaw 地址
DEFAULT_OPENCLAW_URL = 'http://localhost:18789'

# 默认共享目录基础路径（位于 agent workspace 内，容器内通过 /workspace/shared 访问）
# 如果以 sudo 运行，使用实际调用者的 home 目录（避免展开为 /root/.openclaw）
_openclaw_home_env = os.getenv('OPENCLAW_HOME', '')
if _openclaw_home_env:
    OPENCLAW_HOME = os.path.expanduser(_openclaw_home_env)
else:
    sudo_user = os.getenv('SUDO_USER', '')
    if sudo_user and os.getuid() == 0:
        OPENCLAW_HOME = os.path.expanduser(f'~{sudo_user}/.openclaw')
    else:
        OPENCLAW_HOME = os.path.expanduser('~/.openclaw')

NAME_PATTERN = re.compile(r'^[a-z0-9][a-z0-9\-]{1,28}[a-z0-9]$')
CONTAINER_SHARED_PATH = '/workspace/shared'


def _agent_workspace(agent_id):
    """根据 agent_id 计算 OpenClaw workspace 路径"""
    if agent_id and agent_id != 'main':
        return os.path.join(OPENCLAW_HOME, f'workspace-{agent_id}')
    return os.path.join(OPENCLAW_HOME, 'workspace')


def _default_shared_dir(agent_id):
    """共享目录固定使用 <workspace>/shared"""
    return os.path.join(_agent_workspace(agent_id), 'shared')


def _validate_shared_dir(shared_dir, agent_id):
    """校验共享目录必须是 <workspace>/shared，确保容器内路径稳定"""
    shared_abs = os.path.realpath(os.path.expanduser(shared_dir))
    expected_abs = os.path.realpath(os.path.expanduser(_default_shared_dir(agent_id)))
    if shared_abs != expected_abs:
        print("错误: 共享目录必须使用当前 Agent workspace 的 shared 目录")
        print(f"  当前: {shared_abs}")
        print(f"  建议: {expected_abs}")
        print(f"  原因: Gateway 会将路径转换为容器内固定路径 {CONTAINER_SHARED_PATH}")
        sys.exit(1)
    return shared_abs


def display_width(s):
    """计算字符串在终端的显示宽度（中文/全角字符占 2 列）"""
    w = 0
    for ch in s:
        eaw = unicodedata.east_asian_width(ch)
        w += 2 if eaw in ('F', 'W') else 1
    return w


def pad(s, width):
    """将字符串填充到指定终端显示宽度"""
    return s + ' ' * max(0, width - display_width(s))


def _try_read_local_token():
    """尝试从本地 OpenClaw 配置读取 gateway token（best-effort）
    
    适用于 Gateway 与 OpenClaw 同机部署的场景。
    跨机部署时返回 None，用户需手动输入。
    """
    config_path = os.path.join(OPENCLAW_HOME, 'openclaw.json')
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        token = config.get('gateway', {}).get('auth', {}).get('token', '')
        return token if token else None
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        return None


def get_db():
    """获取数据库连接，确保表存在"""
    db_dir = os.path.dirname(DB_PATH)
    try:
        os.makedirs(db_dir, exist_ok=True)
    except PermissionError:
        print(f"错误: 无权创建目录 {db_dir}")
        print("提示: 请使用 Gateway 运行用户执行 04-manage-agent.sh（不要 sudo）")
        sys.exit(1)
    try:
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
    except sqlite3.OperationalError as e:
        if 'readonly' in str(e).lower():
            print(f"错误: 数据库只读 — {DB_PATH}")
            print("提示: 请使用 Gateway 运行用户执行 04-manage-agent.sh（不要 sudo）")
            sys.exit(1)
        raise


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
        # 尝试从本地 OpenClaw 配置自动获取（同机部署场景）
        local_token = _try_read_local_token()
        if local_token:
            openclaw_token = local_token
            print(f"  已从本地配置读取 token: {mask(openclaw_token)}")
        else:
            print("错误: openclaw Token 不能为空（跨机部署请手动输入）")
            sys.exit(1)

    openclaw_agent_id = input("openclaw Agent ID（回车跳过，默认 main）: ").strip()

    # 共享目录：Gateway 下载的文件保存到此目录，容器内通过 /workspace/shared 访问
    openclaw_agent = openclaw_agent_id or 'main'
    default_shared = _default_shared_dir(openclaw_agent)
    shared_dir = input(f"共享文件目录（回车使用默认 {default_shared}）: ").strip()
    if not shared_dir:
        shared_dir = default_shared
    shared_dir = _validate_shared_dir(shared_dir, openclaw_agent)

    # 确认
    print(f"\n确认添加？")
    print(f"  路由名:     {name}")
    print(f"  显示名:     {display_name}")
    print(f"  企业微信:   Token={mask(wecom_token)} AESKey={mask(wecom_aes_key)}")
    print(f"  openclaw:   {openclaw_url} (agent: {openclaw_agent_id or 'main'})")
    print(f"  共享目录:   {shared_dir}")
    print(f"  容器路径:   {CONTAINER_SHARED_PATH}")

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

    # 尝试创建共享目录（权限不足时给出提示，不阻塞绑定创建）
    try:
        os.makedirs(shared_dir, exist_ok=True)
        print(f"已创建共享目录: {shared_dir}")
    except PermissionError:
        print(f"注意: 无权创建共享目录 {shared_dir}")
        print(f"  请手动执行: mkdir -p {shared_dir}")
        print(f"  Gateway 启动时也会自动创建此目录")

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
    openclaw_token = input(f"openclaw Token [{mask(old_oc_token)}]: ").strip()
    if not openclaw_token:
        openclaw_token = old_oc_token
    elif openclaw_token == 'auto':
        local_token = _try_read_local_token()
        if local_token:
            openclaw_token = local_token
            print(f"  已从本地配置读取 token: {mask(openclaw_token)}")
        else:
            print("  无法读取本地配置，保持原值")
            openclaw_token = old_oc_token
    openclaw_agent_id = input(f"openclaw Agent ID [{old_agent_id or 'main'}]: ").strip()
    if not openclaw_agent_id:
        openclaw_agent_id = old_agent_id

    openclaw_agent = openclaw_agent_id or old_agent_id or 'main'
    default_shared = _default_shared_dir(openclaw_agent)
    if old_shared_dir:
        old_shared_norm = os.path.realpath(os.path.expanduser(old_shared_dir))
        default_shared_norm = os.path.realpath(os.path.expanduser(default_shared))
        if old_shared_norm != default_shared_norm:
            print("注意: 当前共享目录与推荐路径不一致，建议修正为默认路径")
            print(f"  当前: {old_shared_norm}")
            print(f"  建议: {default_shared_norm}")
    shared_dir = input(f"共享文件目录 [{default_shared}]: ").strip() or default_shared
    shared_dir = _validate_shared_dir(shared_dir, openclaw_agent)

    # 确认
    print(f"\n确认更新？")
    print(f"  路由名:     {name}")
    print(f"  显示名:     {display_name}")
    print(f"  企业微信:   Token={mask(wecom_token)} AESKey={mask(wecom_aes_key)}")
    print(f"  openclaw:   {openclaw_url} (agent: {openclaw_agent_id or 'main'})")
    print(f"  共享目录:   {shared_dir}")
    print(f"  容器路径:   {CONTAINER_SHARED_PATH}")

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
        try:
            os.makedirs(shared_dir, exist_ok=True)
        except PermissionError:
            print(f"注意: 无权创建共享目录 {shared_dir}")
            print(f"  请手动执行: mkdir -p {shared_dir}")

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
    print(f"{pad('名称', 12)} {pad('显示名', 16)} {pad('openclaw 地址', 28)} {pad('Agent ID', 10)} {pad('共享目录', 30)} 创建时间")
    print("-" * 100)
    for name, display, url, agent_id, shared_dir, created, updated in rows:
        print(f"{pad(name, 12)} {pad(display, 16)} {pad(url, 28)} {pad(agent_id or 'main', 10)} {pad(shared_dir or '-', 30)} {created}")
    print("-" * 100)
    print(f"\n回调地址格式: https://your-domain/<name>/wecom/callback")


def cmd_sync_token():
    """同步 openclaw token — 批量更新 DB 中 agent 的 token
    
    支持两种方式：
    - 自动从本地 OpenClaw 配置读取（同机部署）
    - 手动输入新 token（跨机部署）
    
    可选 --url 参数：只更新指向特定 openclaw 实例的 agent
    """
    # 解析 --url 参数
    target_url = None
    for i, arg in enumerate(sys.argv):
        if arg == '--url' and i + 1 < len(sys.argv):
            target_url = sys.argv[i + 1].rstrip('/')
            break

    conn = get_db()

    # 查询受影响的 agent
    if target_url:
        rows = conn.execute(
            "SELECT name, openclaw_url, openclaw_token FROM agents WHERE openclaw_url = ? ORDER BY name",
            (target_url,)
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT name, openclaw_url, openclaw_token FROM agents ORDER BY name"
        ).fetchall()

    if not rows:
        msg = f"没有找到指向 {target_url} 的 agent" if target_url else "当前无 agent 绑定"
        print(msg)
        conn.close()
        return

    # 按 openclaw_url 分组显示
    by_url = {}
    for name, url, token in rows:
        by_url.setdefault(url, []).append((name, token))

    print(f"\n将更新以下 agent 的 openclaw token:")
    for url, agents in by_url.items():
        print(f"\n  openclaw: {url}")
        for name, token in agents:
            print(f"    - {name} (当前 token: {mask(token)})")

    # 获取新 token
    local_token = _try_read_local_token()
    if local_token:
        print(f"\n检测到本地 OpenClaw 配置，token: {mask(local_token)}")
        new_token = input(f"新 token（回车使用本地配置值，或手动输入）: ").strip()
        if not new_token:
            new_token = local_token
    else:
        new_token = input("新 token: ").strip()

    if not new_token:
        print("错误: token 不能为空")
        conn.close()
        sys.exit(1)

    # 检查是否有变化
    all_same = all(token == new_token for _, _, token in rows)
    if all_same:
        print("\n所有 agent 的 token 已经是最新值，无需更新")
        conn.close()
        return

    confirm = input(f"\n确认更新 {len(rows)} 个 agent 的 token？[Y/n] ").strip().lower()
    if confirm and confirm != 'y':
        print("已取消")
        conn.close()
        return

    # 执行更新
    if target_url:
        conn.execute(
            "UPDATE agents SET openclaw_token = ?, updated_at = CURRENT_TIMESTAMP WHERE openclaw_url = ?",
            (new_token, target_url)
        )
    else:
        conn.execute(
            "UPDATE agents SET openclaw_token = ?, updated_at = CURRENT_TIMESTAMP",
            (new_token,)
        )
    conn.commit()
    conn.close()

    updated = len(rows)
    print(f"\n已更新 {updated} 个 agent 的 token: {mask(new_token)}")
    notify_reload()


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
    elif command == 'sync-token':
        cmd_sync_token()
    else:
        print(f"未知命令: {command}")
        print(__doc__)
        sys.exit(1)


if __name__ == '__main__':
    main()
