"""
Telegram Bot 适配器
负责处理 Telegram Webhook 请求，管理用户会话，路由消息到 OpenClaw
"""

import os
import json
import logging
import sqlite3
import threading
import time
import requests
from datetime import datetime
from typing import Optional, Dict, Any

# 配置日志
logger = logging.getLogger(__name__)


class TelegramAdapter:
    """Telegram Bot 适配器"""

    # 虚拟员工配置
    AGENTS = {
        'dispatcher': {'name': '调度员', 'desc': '智能任务分发和路由'},
        'operation': {'name': '运营专员', 'desc': '数据分析、报表生成'},
        'product': {'name': '产品经理', 'desc': '需求管理、功能设计'},
        'development': {'name': '开发工程师', 'desc': '技术支持、代码审查'},
        'testing': {'name': '测试工程师', 'desc': '质量保障、测试用例'},
        'service': {'name': '客服专员', 'desc': '客户服务、问题解答'},
    }

    def __init__(self, bot_token: str, db_path: str, openclaw_url: str):
        """
        初始化适配器

        Args:
            bot_token: Telegram Bot Token
            db_path: 数据库路径
            openclaw_url: OpenClaw Gateway URL
        """
        self.bot_token = bot_token
        self.api_base = f"https://api.telegram.org/bot{bot_token}"
        self.db_path = db_path
        self.openclaw_url = openclaw_url
        self.openclaw_token = self._load_openclaw_token()

        # 轮询状态
        self._polling_thread = None
        self._stop_event = threading.Event()
        self._poll_offset = 0
        self._poll_timeout = 30
        self._retry_delay = 5

        # 初始化数据库
        self._init_database()

    def _load_openclaw_token(self) -> str:
        """从 ~/.openclaw/openclaw.json 读取 gateway token"""
        try:
            config_path = os.path.expanduser('~/.openclaw/openclaw.json')
            with open(config_path) as f:
                cfg = json.load(f)
            token = cfg.get('gateway', {}).get('auth', {}).get('token', '')
            if token:
                logger.info("✅ OpenClaw gateway token 已加载")
            return token
        except Exception as e:
            logger.warning(f"⚠️  无法读取 OpenClaw token: {e}")
            return os.getenv('OPENCLAW_API_KEY', '')

    def _init_database(self):
        """初始化数据库表"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()

            # 创建 telegram_sessions 表
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS telegram_sessions (
                    user_id BIGINT PRIMARY KEY,
                    current_agent VARCHAR(50) DEFAULT 'dispatcher',
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            """)

            # 创建索引
            cursor.execute("""
                CREATE INDEX IF NOT EXISTS idx_last_active
                ON telegram_sessions(last_active)
            """)

            conn.commit()
            conn.close()
            logger.info("✅ Telegram 数据库表初始化成功")
        except Exception as e:
            logger.error(f"❌ 数据库初始化失败: {e}")

    def handle_webhook(self, update: dict) -> dict:
        """
        处理 Webhook 请求

        Args:
            update: Telegram Update 对象

        Returns:
            响应字典
        """
        try:
            message = update.get('message')
            if not message:
                return {'ok': True}

            user_id = message['from']['id']
            chat_id = message['chat']['id']
            text = message.get('text', '')

            # 记录日志
            logger.info(f"收到消息: user_id={user_id}, text={text[:50]}")

            # 判断是命令还是普通消息
            if text.startswith('/'):
                response = self._handle_command(user_id, chat_id, text)
            else:
                response = self._handle_message(user_id, chat_id, text)

            # 发送响应
            if response:
                self.send_message(chat_id, response)

            return {'ok': True}

        except Exception as e:
            logger.error(f"处理 Webhook 失败: {e}")
            return {'ok': False, 'error': str(e)}

    def _handle_command(self, user_id: int, chat_id: int, text: str) -> str:
        """处理命令"""
        command = text.split()[0].lower()

        if command == '/start':
            return self._cmd_start(user_id)
        elif command == '/help':
            return self._cmd_help()
        elif command == '/agents':
            return self._cmd_agents()
        elif command == '/current':
            return self._cmd_current(user_id)
        elif command == '/reset':
            return self._cmd_reset(user_id)
        elif command in ['/dispatcher', '/operation', '/product',
                        '/development', '/testing', '/service']:
            agent_id = command[1:]
            return self._cmd_switch_agent(user_id, agent_id)
        else:
            return "❓ 未知命令，使用 /help 查看帮助"

    def _handle_message(self, user_id: int, chat_id: int, text: str) -> str:
        """处理普通消息"""
        # 获取当前 Agent
        agent_id = self._get_current_agent(user_id)

        # 发送"正在输入"状态
        self.send_chat_action(chat_id, 'typing')

        # 调用 OpenClaw Agent
        try:
            response = self._call_agent(agent_id, text, user_id)
            return response
        except Exception as e:
            logger.error(f"调用 Agent 失败: {e}")
            return "❌ 系统暂时无法处理您的请求，请稍后再试"

    def _call_agent(self, agent_id: str, message: str, user_id: int) -> str:
        """
        调用 OpenClaw Agent（通过 WebSocket RPC 协议）

        Args:
            agent_id: Agent ID
            message: 用户消息
            user_id: 用户 ID

        Returns:
            AI 响应
        """
        import websocket
        import uuid as _uuid

        ws_url = self.openclaw_url.replace('http://', 'ws://').replace('https://', 'wss://')
        token = self.openclaw_token
        session_key = f"agent:{agent_id}-agent:telegram-{user_id}"
        idempotency_key = str(_uuid.uuid4())

        result_text = None
        error_msg = None
        connected = threading.Event()
        done = threading.Event()

        def on_message(ws, raw):
            nonlocal result_text, error_msg
            try:
                msg = json.loads(raw)
            except Exception:
                return

            if msg.get('type') == 'event' and msg.get('event') == 'connect.challenge':
                nonce = msg.get('payload', {}).get('nonce', '')
                req = {
                    'type': 'req',
                    'id': str(_uuid.uuid4()),
                    'method': 'connect',
                    'params': {
                        'minProtocol': 3,
                        'maxProtocol': 3,
                        'client': {
                            'id': 'openclaw-probe',
                            'version': 'dev',
                            'platform': 'python',
                            'mode': 'backend',
                        },
                        'auth': {'token': token} if token else None,
                    }
                }
                ws.send(json.dumps(req))

            elif msg.get('type') == 'res':
                if not connected.is_set():
                    if msg.get('ok'):
                        connected.set()
                        # send chat.send
                        req = {
                            'type': 'req',
                            'id': str(_uuid.uuid4()),
                            'method': 'chat.send',
                            'params': {
                                'sessionKey': session_key,
                                'message': message,
                                'deliver': False,
                                'idempotencyKey': idempotency_key,
                            }
                        }
                        ws.send(json.dumps(req))
                    else:
                        error_msg = msg.get('error', {}).get('message', 'connect failed')
                        done.set()

            elif msg.get('type') == 'event' and msg.get('event') == 'chat':
                payload = msg.get('payload', {})
                if payload.get('sessionKey') != session_key:
                    return
                state = payload.get('state')
                if state == 'final':
                    done.set()
                elif state == 'error':
                    error_msg = payload.get('errorMessage', 'chat error')
                    done.set()
                elif state == 'aborted':
                    error_msg = '请求被中止'
                    done.set()
                elif state == 'delta':
                    msg_obj = payload.get('message')
                    if isinstance(msg_obj, dict):
                        for block in msg_obj.get('content', []):
                            if isinstance(block, dict) and block.get('type') == 'text':
                                result_text = block.get('text', result_text)
                                break
                    elif isinstance(msg_obj, str):
                        result_text = msg_obj

        def on_error(ws, err):
            nonlocal error_msg
            error_msg = str(err)
            done.set()

        def on_close(ws, *args):
            done.set()

        try:
            ws = websocket.WebSocketApp(
                ws_url,
                on_message=on_message,
                on_error=on_error,
                on_close=on_close,
            )
            t = threading.Thread(target=ws.run_forever, daemon=True)
            t.start()

            done.wait(timeout=60)
            ws.close()

            if error_msg:
                logger.error(f"OpenClaw WebSocket 错误: {error_msg}")
                return f"❌ {error_msg}"
            if result_text:
                return result_text
            return "❌ 未收到响应，请稍后重试"

        except Exception as e:
            logger.error(f"调用 OpenClaw 失败: {e}")
            return "❌ 系统暂时无法处理您的请求，请稍后再试"

    def send_message(self, chat_id: int, text: str, retry_count: int = 3) -> dict:
        """
        发送消息（带重试机制）

        Args:
            chat_id: 聊天 ID
            text: 消息文本
            retry_count: 重试次数

        Returns:
            API 响应字典
        """
        url = f"{self.api_base}/sendMessage"
        payload = {
            'chat_id': chat_id,
            'text': text,
            'parse_mode': 'Markdown'
        }

        for attempt in range(retry_count):
            try:
                response = requests.post(url, json=payload, timeout=10)
                result = response.json()

                if result.get('ok'):
                    return result
                else:
                    logger.warning(f"发送消息失败 (尝试 {attempt + 1}/{retry_count}): {result}")

            except requests.exceptions.Timeout:
                logger.warning(f"发送消息超时 (尝试 {attempt + 1}/{retry_count})")
            except Exception as e:
                logger.error(f"发送消息异常 (尝试 {attempt + 1}/{retry_count}): {e}")

            # 如果不是最后一次尝试，等待后重试
            if attempt < retry_count - 1:
                import time
                time.sleep(1)

        # 所有重试都失败
        logger.error(f"发送消息失败，已重试 {retry_count} 次")
        return {'ok': False, 'error': 'Max retries exceeded'}

    def send_chat_action(self, chat_id: int, action: str = 'typing'):
        """发送聊天动作"""
        url = f"{self.api_base}/sendChatAction"
        payload = {'chat_id': chat_id, 'action': action}

        try:
            requests.post(url, json=payload, timeout=5)
        except Exception as e:
            logger.error(f"发送聊天动作失败: {e}")

    # ============= 会话管理方法 =============

    def _get_current_agent(self, user_id: int) -> str:
        """获取当前 Agent"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute(
                "SELECT current_agent FROM telegram_sessions WHERE user_id = ?",
                (user_id,)
            )
            row = cursor.fetchone()
            conn.close()

            if row:
                return row[0]
            else:
                # 创建新会话，默认调度员
                self._create_session(user_id, 'dispatcher')
                return 'dispatcher'
        except Exception as e:
            logger.error(f"获取当前 Agent 失败: {e}")
            return 'dispatcher'

    def _create_session(self, user_id: int, agent_id: str):
        """创建会话"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute(
                """INSERT OR REPLACE INTO telegram_sessions
                   (user_id, current_agent, last_active)
                   VALUES (?, ?, ?)""",
                (user_id, agent_id, datetime.now())
            )
            conn.commit()
            conn.close()
        except Exception as e:
            logger.error(f"创建会话失败: {e}")

    def _switch_agent(self, user_id: int, agent_id: str):
        """切换 Agent"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute(
                """UPDATE telegram_sessions
                   SET current_agent = ?, last_active = ?
                   WHERE user_id = ?""",
                (agent_id, datetime.now(), user_id)
            )
            conn.commit()
            conn.close()
        except Exception as e:
            logger.error(f"切换 Agent 失败: {e}")

    # ============= 命令处理方法 =============

    def _cmd_start(self, user_id: int) -> str:
        """处理 /start 命令"""
        self._create_session(user_id, 'dispatcher')
        return """👋 欢迎使用 OpenClaw 虚拟员工！

我们有 6 位专业的 AI 虚拟员工为您服务：
• 调度员 - 智能任务分发
• 运营专员 - 数据分析
• 产品经理 - 需求管理
• 开发工程师 - 技术支持
• 测试工程师 - 质量保障
• 客服专员 - 客户服务

💡 使用 /agents 查看所有员工
💡 使用 /help 查看帮助信息
💡 直接发送消息开始对话

当前默认员工：调度员"""

    def _cmd_help(self) -> str:
        """处理 /help 命令"""
        return """📖 OpenClaw 使用指南

🤖 切换虚拟员工：
/dispatcher - 调度员
/operation - 运营专员
/product - 产品经理
/development - 开发工程师
/testing - 测试工程师
/service - 客服专员

📋 其他命令：
/agents - 查看所有虚拟员工
/current - 查看当前员工
/reset - 重置会话
/help - 显示此帮助

💬 使用方法：
1. 选择一个虚拟员工（使用命令切换）
2. 直接发送消息进行对话
3. 随时切换到其他员工"""

    def _cmd_agents(self) -> str:
        """处理 /agents 命令"""
        lines = ["🤖 可用的虚拟员工：\n"]
        emojis = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣']

        for i, (agent_id, info) in enumerate(self.AGENTS.items()):
            lines.append(f"{emojis[i]} {info['name']} - {info['desc']}")
            lines.append(f"   命令：/{agent_id}\n")

        lines.append("💡 使用命令切换虚拟员工，或直接发送消息给当前员工")
        return '\n'.join(lines)

    def _cmd_current(self, user_id: int) -> str:
        """处理 /current 命令"""
        agent_id = self._get_current_agent(user_id)
        agent_info = self.AGENTS.get(agent_id, {})

        return f"""📍 当前虚拟员工：{agent_info.get('name', '未知')}
职责：{agent_info.get('desc', '无描述')}

💬 直接发送消息即可与当前员工对话
🔄 使用 /agents 查看其他员工"""

    def _cmd_reset(self, user_id: int) -> str:
        """处理 /reset 命令"""
        self._switch_agent(user_id, 'dispatcher')
        return """🔄 会话已重置

• 当前员工：调度员

💡 使用 /agents 选择其他员工"""

    def _cmd_switch_agent(self, user_id: int, agent_id: str) -> str:
        """处理切换员工命令"""
        self._switch_agent(user_id, agent_id)
        agent_info = self.AGENTS.get(agent_id, {})

        return f"""✅ 已切换到：{agent_info.get('name', '未知')}

我可以帮您：{agent_info.get('desc', '无描述')}

💬 直接发送消息开始对话"""

    # ============= 长轮询方法 =============

    def delete_webhook(self):
        """清除已有 Webhook，切换到轮询模式前调用"""
        try:
            url = f"{self.api_base}/deleteWebhook"
            response = requests.post(url, timeout=10)
            result = response.json()
            if result.get('ok'):
                logger.info("✅ Telegram Webhook 已清除")
            else:
                logger.warning(f"清除 Webhook 返回: {result}")
        except Exception as e:
            logger.error(f"清除 Webhook 失败: {e}")

    def _poll_once(self) -> list:
        """单次 getUpdates 调用，返回 update 列表"""
        url = f"{self.api_base}/getUpdates"
        params = {
            'offset': self._poll_offset,
            'timeout': self._poll_timeout,
            'allowed_updates': ['message'],
        }
        response = requests.get(url, params=params, timeout=self._poll_timeout + 5)
        data = response.json()
        if not data.get('ok'):
            logger.warning(f"getUpdates 返回错误: {data}")
            return []
        updates = data.get('result', [])
        if updates:
            self._poll_offset = updates[-1]['update_id'] + 1
        return updates

    def _polling_loop(self):
        """轮询主循环，在独立线程中运行"""
        logger.info("✅ Telegram 长轮询已启动")
        while not self._stop_event.is_set():
            try:
                updates = self._poll_once()
                for update in updates:
                    try:
                        self.handle_webhook(update)
                    except Exception as e:
                        logger.error(f"处理 update 失败: {e}")
            except requests.exceptions.Timeout:
                continue
            except requests.exceptions.ConnectionError as e:
                logger.warning(f"轮询连接错误，{self._retry_delay}s 后重试: {e}")
                self._stop_event.wait(self._retry_delay)
            except Exception as e:
                logger.error(f"轮询异常，{self._retry_delay}s 后重试: {e}")
                self._stop_event.wait(self._retry_delay)
        logger.info("Telegram 长轮询已停止")

    def start_polling(self):
        """启动后台轮询线程"""
        self.delete_webhook()
        self._stop_event.clear()
        self._polling_thread = threading.Thread(
            target=self._polling_loop, daemon=True, name="telegram-polling"
        )
        self._polling_thread.start()

    def stop_polling(self):
        """停止轮询线程"""
        self._stop_event.set()
        if self._polling_thread and self._polling_thread.is_alive():
            self._polling_thread.join(timeout=self._poll_timeout + 10)
            logger.info("Telegram 轮询线程已退出")
