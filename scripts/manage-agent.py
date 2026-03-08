#!/usr/bin/env python3
"""
OpenClaw 企业微信桥接网关 — Agent 绑定管理工具

用法:
  python3 manage-agent.py add [agent_id]   交互式添加 agent-企业微信绑定
  python3 manage-agent.py remove <agent_id> 删除绑定（需确认）
  python3 manage-agent.py list             列出所有绑定
  python3 manage-agent.py update <agent_id> 更新绑定（可重命名，需确认）
  python3 manage-agent.py sync-token       同步 openclaw token（批量更新）
"""

import sys
import os
import re
import json
import shutil
import sqlite3
import unicodedata
import requests

# 必须使用普通用户运行，避免将 OpenClaw home 落到 /root/.openclaw
if os.getuid() == 0:
    print("错误: 请不要使用 root 或 sudo 运行 manage-agent.py")
    print("提示: 请使用 Gateway 运行用户执行 04-manage-agent.sh（不要 sudo）")
    sys.exit(1)

# 数据库路径（与 Gateway 一致）
DB_PATH = os.getenv('DB_PATH', '/opt/openclaw/data/gateway/gateway.db')

# Gateway 地址（用于通知重载）
GATEWAY_URL = os.getenv('GATEWAY_URL', 'http://localhost:8000')

# 默认 Gateway/OpenClaw 地址
DEFAULT_OPENCLAW_URL = 'http://localhost:18789'

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
CONTAINER_SHARED_PATH = '/app/shared'


def _agent_workspace(agent_id):
    """根据 agent_id 计算 OpenClaw workspace 路径"""
    if agent_id == 'main':
        return os.path.join(OPENCLAW_HOME, 'workspace')
    return os.path.join(OPENCLAW_HOME, f'workspace-{agent_id}')


def _default_shared_source_dir(agent_id):
    """共享目录真实存储位置：保持在 workspace 内，满足沙箱 allowed roots 约束"""
    return os.path.join(_agent_workspace(agent_id), 'shared')


def _default_shared_dir(agent_id):
    """共享目录对外暴露路径固定使用 /app/shared/<agent_id>"""
    return os.path.join(CONTAINER_SHARED_PATH, agent_id)


def _validate_agent_id(agent_id):
    """校验 agent_id / 路由名格式"""
    if not NAME_PATTERN.match(agent_id):
        print(f"错误: agent_id 格式不合法（英文小写+数字+连字符，3-30 字符）: {agent_id}")
        sys.exit(1)
    return agent_id


def _ensure_shared_dir(agent_id, shared_dir):
    """确保共享目录布局存在：workspace 内真实目录 + /app/shared 软链"""
    source_dir = _default_shared_source_dir(agent_id)
    try:
        os.makedirs(source_dir, exist_ok=True)
        os.makedirs(os.path.dirname(shared_dir), exist_ok=True)

        if os.path.islink(shared_dir):
            current_target = os.path.realpath(shared_dir)
            expected_target = os.path.realpath(source_dir)
            if current_target != expected_target:
                os.remove(shared_dir)
                os.symlink(source_dir, shared_dir)
                print(f"已修正共享目录软链: {shared_dir} -> {source_dir}")
            else:
                print(f"共享目录已就绪: {shared_dir} -> {source_dir}")
            return

        if os.path.isdir(shared_dir):
            if os.path.realpath(shared_dir) == os.path.realpath(source_dir):
                print(f"共享目录已就绪: {shared_dir} -> {source_dir}")
                return

            existing_entries = os.listdir(shared_dir)
            conflicting_entries = [name for name in existing_entries if os.path.exists(os.path.join(source_dir, name))]
            if conflicting_entries:
                print(f"注意: 共享目录 {shared_dir} 已存在且包含冲突文件，未自动迁移")
                print(f"  请手动整理后改为软链: {shared_dir} -> {source_dir}")
                return

            for name in existing_entries:
                shutil.move(os.path.join(shared_dir, name), os.path.join(source_dir, name))
            os.rmdir(shared_dir)
            os.symlink(source_dir, shared_dir)
            print(f"已迁移共享目录并创建软链: {shared_dir} -> {source_dir}")
            return

        if os.path.lexists(shared_dir):
            print(f"注意: 路径已存在且无法自动处理: {shared_dir}")
            print(f"  请手动改为软链: {shared_dir} -> {source_dir}")
            return

        os.symlink(source_dir, shared_dir)
        print(f"已创建共享目录软链: {shared_dir} -> {source_dir}")
        return
    except PermissionError:
        print(f"注意: 无权创建共享目录布局 {shared_dir}")
        print(f"  真实目录应位于: {source_dir}")
        print(f"  请确保 {CONTAINER_SHARED_PATH} 对当前用户可写")
        print(f"  例如: sudo mkdir -p {CONTAINER_SHARED_PATH} && sudo chown $(whoami):$(id -gn) {CONTAINER_SHARED_PATH} && sudo chmod 775 {CONTAINER_SHARED_PATH}")
    except OSError as e:
        print(f"注意: 创建共享目录布局失败: {e}")
        print(f"  请手动确认软链: {shared_dir} -> {source_dir}")


def _read_gateway_token(prompt, current_token=''):
    """读取 Gateway token，支持自动读取本地 token 与一致性校验"""
    token_input = input(prompt).strip()
    if not token_input:
        if current_token:
            return current_token
        local_token = _try_read_local_token()
        if local_token:
            print(f"  已从本地配置读取 token: {mask(local_token)}")
            return local_token
        print("错误: Gateway Token 不能为空（跨机部署请手动输入）")
        sys.exit(1)

    if token_input == 'auto':
        local_token = _try_read_local_token()
        if local_token:
            print(f"  已从本地配置读取 token: {mask(local_token)}")
            return local_token
        if not current_token:
            print("错误: 无法读取本地配置中的 Gateway Token")
            sys.exit(1)
        print("  无法读取本地配置，保持原值")
        return current_token

    token = token_input
    system_token = _try_read_local_token()
    if system_token and token != system_token:
        print(f"\n⚠️  注意: 输入的 token 与系统配置不一致")
        print(f"  系统 token: {mask(system_token)}")
        print(f"  输入 token: {mask(token)}")
        confirm = input("  是否使用系统 token？[Y/n] ").strip().lower()
        if confirm != 'n':
            token = system_token
            print(f"  已使用系统 token: {mask(token)}")
    return token


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
    """尝试读取 OpenClaw gateway token（优先级：环境变量 → .env 文件 → openclaw.json）

    适用于 Gateway 与 OpenClaw 同机部署的场景。
    跨机部署时返回 None，用户需手动输入。
    """
    # 1. 优先从环境变量读取
    env_token = os.getenv('OPENCLAW_GATEWAY_TOKEN', '').strip()
    if env_token:
        return env_token

    # 2. 尝试从 .env 文件读取
    env_file = os.path.join(OPENCLAW_HOME, '.env')
    if os.path.isfile(env_file):
        try:
            with open(env_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('OPENCLAW_GATEWAY_TOKEN='):
                        token = line.split('=', 1)[1].strip().strip('"').strip("'")
                        if token:
                            return token
        except Exception:
            pass

    # 3. 回退到 openclaw.json（可能是变量引用或实际 token）
    config_path = os.path.join(OPENCLAW_HOME, 'openclaw.json')
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        token = config.get('gateway', {}).get('auth', {}).get('token', '')
        # 如果是变量引用格式，返回 None（需要用户手动输入）
        if token and not token.startswith('${'):
            return token
    except (FileNotFoundError, json.JSONDecodeError, KeyError):
        pass

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


def cmd_add(initial_agent_id=''):
    """添加 agent 绑定"""
    print("\n添加 agent 绑定")
    print("-" * 40)

    openclaw_url = input(f"Gateway 地址（回车使用默认 {DEFAULT_OPENCLAW_URL}）: ").strip()
    if not openclaw_url:
        openclaw_url = DEFAULT_OPENCLAW_URL
    openclaw_url = openclaw_url.rstrip('/')

    prompt_suffix = f"（回车使用 {initial_agent_id}）" if initial_agent_id else ''
    agent_id = input(f"Agent ID（路由名，同 OpenClaw agent_id）{prompt_suffix}: ").strip() or initial_agent_id
    if not agent_id:
        print("错误: Agent ID 不能为空")
        sys.exit(1)
    agent_id = _validate_agent_id(agent_id)

    conn = get_db()
    existing = conn.execute("SELECT name FROM agents WHERE name = ?", (agent_id,)).fetchone()
    if existing:
        print(f"错误: agent '{agent_id}' 已存在，请使用 update 命令修改")
        conn.close()
        sys.exit(1)

    shared_dir = _default_shared_dir(agent_id)
    print(f"共享文件目录（自动生成，不可修改）: {shared_dir}")

    openclaw_token = _read_gateway_token("Gateway Token: ")

    wecom_token = input("企业微信 Token: ").strip()
    if not wecom_token:
        print("错误: Token 不能为空")
        conn.close()
        sys.exit(1)

    wecom_aes_key = input("企业微信 EncodingAESKey: ").strip()
    if not wecom_aes_key:
        print("错误: AESKey 不能为空")
        conn.close()
        sys.exit(1)

    display_name = input(f"显示名（回车使用 {agent_id}）: ").strip() or agent_id

    # 确认
    print(f"\n确认添加？")
    print(f"  Agent ID:   {agent_id}")
    print(f"  显示名:     {display_name}")
    print(f"  Gateway:    {openclaw_url}")
    print(f"  共享目录:   {shared_dir}")
    print(f"  GatewayToken={mask(openclaw_token)}")
    print(f"  企业微信:   Token={mask(wecom_token)} AESKey={mask(wecom_aes_key)}")
    print(f"  回调地址:   https://your-domain/{agent_id}/wecom/callback")

    confirm = input("\n[Y/n] ").strip().lower()
    if confirm and confirm != 'y':
        print("已取消")
        conn.close()
        return

    conn.execute(
        "INSERT INTO agents (name, display_name, wecom_token, wecom_aes_key, "
        "openclaw_url, openclaw_token, openclaw_agent_id, shared_dir) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        (agent_id, display_name, wecom_token, wecom_aes_key, openclaw_url, openclaw_token,
         agent_id, shared_dir)
    )
    conn.commit()
    conn.close()

    _ensure_shared_dir(agent_id, shared_dir)

    print(f"已添加 agent '{agent_id}'")
    print(f"企业微信回调地址: https://your-domain/{agent_id}/wecom/callback")
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
    print(f"  Agent ID: {name} ({display})")
    print(f"  企业微信: Token={mask(token)}")
    print(f"  Gateway:  {url} (agent: {agent_id or name})")
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
    old_effective_agent_id = name

    print(f"\n更新 agent 绑定: {name}")
    print(f"当前配置:")
    print(f"  Agent ID:   {old_effective_agent_id}")
    print(f"  显示名:     {old_display}")
    print(f"  Gateway:    {old_url}")
    print(f"  共享目录:   {old_shared_dir or _default_shared_dir(old_effective_agent_id)}")
    print(f"  企业微信:   Token={mask(old_token)} AESKey={mask(old_aes)}")

    print(f"\n输入新值（回车保持不变）:")

    openclaw_url = input(f"Gateway 地址 [{old_url}]: ").strip() or old_url
    openclaw_url = openclaw_url.rstrip('/')
    agent_id = input(f"Agent ID（路由名，同 OpenClaw agent_id） [{old_effective_agent_id}]: ").strip() or old_effective_agent_id
    agent_id = _validate_agent_id(agent_id)
    if agent_id != name:
        existing = conn.execute("SELECT name FROM agents WHERE name = ?", (agent_id,)).fetchone()
        if existing:
            print(f"错误: agent '{agent_id}' 已存在，无法重命名")
            conn.close()
            sys.exit(1)

    shared_dir = _default_shared_dir(agent_id)
    print(f"共享文件目录（自动生成，不可修改）: {shared_dir}")

    openclaw_token = _read_gateway_token(f"Gateway Token [{mask(old_oc_token)}]: ", current_token=old_oc_token)
    wecom_token = input(f"企业微信 Token [{mask(old_token)}]: ").strip() or old_token
    wecom_aes_key = input(f"企业微信 AES Key [{mask(old_aes)}]: ").strip() or old_aes
    display_name = input(f"显示名 [{old_display or agent_id}]: ").strip() or old_display or agent_id

    # 确认
    print(f"\n确认更新？")
    print(f"  Agent ID:   {agent_id}")
    print(f"  显示名:     {display_name}")
    print(f"  Gateway:    {openclaw_url}")
    print(f"  共享目录:   {shared_dir}")
    print(f"  GatewayToken={mask(openclaw_token)}")
    print(f"  企业微信:   Token={mask(wecom_token)} AESKey={mask(wecom_aes_key)}")
    print(f"  回调地址:   https://your-domain/{agent_id}/wecom/callback")

    confirm = input("\n[Y/n] ").strip().lower()
    if confirm and confirm != 'y':
        print("已取消")
        conn.close()
        return

    conn.execute(
        "UPDATE agents SET name=?, display_name=?, wecom_token=?, wecom_aes_key=?, "
        "openclaw_url=?, openclaw_token=?, openclaw_agent_id=?, shared_dir=?, updated_at=CURRENT_TIMESTAMP "
        "WHERE name=?",
        (agent_id, display_name, wecom_token, wecom_aes_key, openclaw_url, openclaw_token, agent_id, shared_dir, name)
    )
    conn.commit()
    conn.close()

    _ensure_shared_dir(agent_id, shared_dir)

    if old_shared_dir and old_shared_dir != shared_dir:
        print(f"注意: 旧共享目录 {old_shared_dir} 未删除，如需清理请手动处理")

    if agent_id == name:
        print(f"已更新 agent '{agent_id}'")
    else:
        print(f"已更新 agent '{name}' -> '{agent_id}'")
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
        print("使用 python3 manage-agent.py add [agent_id] 添加")
        return

    print(f"\n共 {len(rows)} 个 agent 绑定:")
    print("-" * 100)
    print(f"{pad('路由名', 12)} {pad('显示名', 16)} {pad('Gateway 地址', 28)} {pad('OpenClaw', 10)} {pad('共享目录', 30)} 创建时间")
    print("-" * 100)
    for name, display, url, agent_id, shared_dir, created, updated in rows:
        print(f"{pad(name, 12)} {pad(display, 16)} {pad(url, 28)} {pad(agent_id or 'main', 10)} {pad(shared_dir or '-', 30)} {created}")
    print("-" * 100)
    print(f"\n回调地址格式: https://your-domain/<agent_id>/wecom/callback")


def cmd_sync_token():
    """同步 Gateway token — 批量更新 DB 中 agent 的 token
    
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

    print(f"\n将更新以下 agent 的 Gateway token:")
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
    print(f"\n已更新 {updated} 个 agent 的 Gateway token: {mask(new_token)}")
    notify_reload()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    command = sys.argv[1].lower()

    if command == 'list':
        cmd_list()
    elif command == 'add':
        cmd_add(sys.argv[2] if len(sys.argv) >= 3 else '')
    elif command == 'remove':
        if len(sys.argv) < 3:
            print("用法: python3 manage-agent.py remove <agent_id>")
            sys.exit(1)
        cmd_remove(sys.argv[2])
    elif command == 'update':
        if len(sys.argv) < 3:
            print("用法: python3 manage-agent.py update <agent_id>")
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
