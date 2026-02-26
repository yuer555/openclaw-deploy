from flask import Flask, request, jsonify
import hashlib
import xml.etree.ElementTree as ET
import sqlite3
import uuid
import time
import os
import logging
import json
import base64
from Crypto.Cipher import AES
import struct
import requests
from datetime import datetime, timedelta
import threading

app = Flask(__name__)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ============= 配置（从环境变量读取）=============

# 数据库配置
DB_PATH = os.getenv('DB_PATH', '/data/user_roles.db')

# 企业微信智能机器人配置
WECOM_TOKEN = os.getenv('WECOM_TOKEN', '')
WECOM_ENCODING_AES_KEY = os.getenv('WECOM_ENCODING_AES_KEY', '')

# OpenClaw Gateway 配置
OPENCLAW_GATEWAY_URL = os.getenv('OPENCLAW_GATEWAY_URL', 'http://localhost:18789')
OPENCLAW_API_KEY = os.getenv('OPENCLAW_API_KEY', '')
OPENCLAW_TIMEOUT = int(os.getenv('OPENCLAW_TIMEOUT', '30'))

# OpenClaw 内部通信 Token
OPENCLAW_INTERNAL_TOKEN = os.getenv('OPENCLAW_INTERNAL_TOKEN', 'openclaw-internal-secret')

# Agent 注册表
from agent_registry import AGENT_REGISTRY, DISPATCHER_URL


# ============= AI 调度员 =============

class AIDispatcher:
    """通过 openclaw CLI 调用调度员分析意图，返回目标 agent"""

    def route(self, message: str) -> tuple:
        """分析消息意图，返回 (agent_id, agent_url)"""
        import subprocess

        agents_desc = '\n'.join(
            f"- {aid}: {info['name']}（{info['desc']}）"
            for aid, info in AGENT_REGISTRY.items()
        )
        prompt = (
            f"根据以下用户消息，从可用员工中选择最合适的一位，只返回 agent ID，不返回其他内容。\n\n"
            f"可用员工：\n{agents_desc}\n\n"
            f"用户消息：{message}"
        )

        try:
            result = subprocess.run(
                ['npx', 'openclaw', 'agent', '--agent', 'main', '--local', '-m', prompt, '--json', '--timeout', '15'],
                capture_output=True, text=True, timeout=20, cwd='/workspace'
            )
            if result.returncode == 0 and result.stdout.strip():
                data = json.loads(result.stdout)
                # --local --json 输出: {"payloads": [{"text": "..."}], ...}
                # gateway --json 输出: {"result": {"payloads": [{"text": "..."}]}, ...}
                payloads = data.get('payloads') or data.get('result', {}).get('payloads', [])
                reply = payloads[0].get('text', '') if payloads else ''
                agent_id = reply.strip().lower().split()[0] if reply.strip() else 'service'
                if agent_id in AGENT_REGISTRY:
                    logger.info(f"AI 路由结果: {agent_id}")
                    return agent_id, AGENT_REGISTRY[agent_id]['url']
            logger.warning(f"AI 路由失败（CLI 返回: {result.stderr[:100]}），fallback 到 service")
        except Exception as e:
            logger.warning(f"AI 路由异常: {e}，fallback 到 service")

        return 'service', AGENT_REGISTRY['service']['url']


_dispatcher = AIDispatcher()


# ============= 企业微信加解密工具类 =============

class WXBizMsgCrypt:
    """企业微信智能机器人消息加解密（receiveid 为空字符串）"""

    def __init__(self, token, encoding_aes_key):
        self.token = token
        self.encoding_aes_key = base64.b64decode(encoding_aes_key + "=")

    def verify_signature(self, signature, timestamp, nonce, echo_str=""):
        """验证签名"""
        sha = hashlib.sha1()
        items = [self.token, timestamp, nonce, echo_str]
        items.sort()
        sha.update(''.join(items).encode('utf-8'))
        return sha.hexdigest() == signature

    def decrypt(self, encrypt_msg):
        """解密消息，返回明文字符串"""
        try:
            cipher = AES.new(self.encoding_aes_key, AES.MODE_CBC, self.encoding_aes_key[:16])
            plain_text = cipher.decrypt(base64.b64decode(encrypt_msg))
            pad = plain_text[-1]
            if isinstance(pad, str):
                pad = ord(pad)
            plain_text = plain_text[:-pad]
            content_length = struct.unpack('!I', plain_text[16:20])[0]
            content = plain_text[20:20+content_length].decode('utf-8')
            return content
        except Exception as e:
            logger.error(f"解密失败: {e}")
            return None

    def encrypt(self, msg_text):
        """加密消息"""
        try:
            rand_str = os.urandom(16)
            msg_len = struct.pack('!I', len(msg_text.encode('utf-8')))
            # receiveid 为空字符串
            plain_text = rand_str + msg_len + msg_text.encode('utf-8') + b''
            pad = 32 - len(plain_text) % 32
            plain_text += bytes([pad] * pad)
            cipher = AES.new(self.encoding_aes_key, AES.MODE_CBC, self.encoding_aes_key[:16])
            cipher_text = cipher.encrypt(plain_text)
            return base64.b64encode(cipher_text).decode('utf-8')
        except Exception as e:
            logger.error(f"加密失败: {e}")
            return None

    def build_reply(self, msg_text, timestamp, nonce):
        """构造加密回复包"""
        encrypt = self.encrypt(msg_text)
        if not encrypt:
            return None
        sha = hashlib.sha1()
        items = [self.token, str(timestamp), nonce, encrypt]
        items.sort()
        sha.update(''.join(items).encode('utf-8'))
        signature = sha.hexdigest()
        return {
            "encrypt": encrypt,
            "msgsignature": signature,
            "timestamp": timestamp,
            "nonce": nonce,
        }


# ============= 数据库操作 =============

def init_db():
    """初始化数据库表"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute('''CREATE TABLE IF NOT EXISTS user_roles (
            user_id TEXT PRIMARY KEY,
            roles TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )''')
        cursor.execute('''CREATE TABLE IF NOT EXISTS task_logs (
            task_id TEXT PRIMARY KEY,
            user_id TEXT,
            agent_id TEXT,
            task_content TEXT,
            status TEXT,
            result TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )''')
        conn.commit()
        conn.close()
        logger.info("✅ 数据库初始化完成")
    except Exception as e:
        logger.error(f"❌ 数据库初始化失败: {e}")

init_db()

def get_user_agents(user_id):
    """查询用户绑定的代理"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT roles FROM user_roles WHERE user_id = ?", (user_id,))
        result = cursor.fetchone()
        conn.close()
        
        if result:
            # roles 字段存储的是逗号分隔的角色列表
            return result[0].split(',')
        return []
    except Exception as e:
        logger.error(f"查询用户绑定失败: {e}")
        return []


def log_task(task_id, user_id, agent_id, content, status='pending', result=''):
    """记录任务日志"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO task_logs (task_id, user_id, agent_id, task_content, status, result) VALUES (?, ?, ?, ?, ?, ?)",
            (task_id, user_id, agent_id, content, status, result)
        )
        conn.commit()
        conn.close()
        logger.info(f"✅ 任务日志已记录: {task_id} -> {agent_id} ({status})")
    except Exception as e:
        logger.error(f"❌ 记录任务日志失败: {e}")


def update_task_status(task_id, status, result=''):
    """更新任务状态"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE task_logs SET status = ?, result = ?, updated_at = CURRENT_TIMESTAMP WHERE task_id = ?",
            (status, result, task_id)
        )
        conn.commit()
        conn.close()
        logger.info(f"✅ 任务状态已更新: {task_id} -> {status}")
    except Exception as e:
        logger.error(f"❌ 更新任务状态失败: {e}")


# ============= 消息路由 =============

def route_message(content):
    """AI 路由消息到合适的代理，返回 (agent_id, agent_url)"""
    return _dispatcher.route(content)


# ============= OpenClaw Gateway API 调用 =============

def call_openclaw_agent(agent_id, message, user_id, task_id, gateway_url=None):
    """调用 OpenClaw Gateway API"""
    try:
        # 构造 API 请求
        base_url = gateway_url or OPENCLAW_GATEWAY_URL
        url = f"{base_url}/api/v1/sessions/send"
        
        headers = {
            'Content-Type': 'application/json'
        }
        
        # 如果配置了 API Key，添加认证头
        if OPENCLAW_API_KEY:
            headers['Authorization'] = f'Bearer {OPENCLAW_API_KEY}'
        
        payload = {
            "message": message,
            "agentId": agent_id,
            "label": f"wecom-{user_id}",  # 使用 label 标识会话
            "timeoutSeconds": OPENCLAW_TIMEOUT
        }
        
        logger.info(f"🚀 调用 OpenClaw Agent: {agent_id}")
        logger.debug(f"请求: {json.dumps(payload, ensure_ascii=False)}")
        
        # 发送请求
        response = requests.post(
            url, 
            json=payload, 
            headers=headers,
            timeout=OPENCLAW_TIMEOUT + 5  # 稍微多给5秒
        )
        
        # 检查响应
        if response.status_code == 200:
            result = response.json()
            logger.info(f"✅ OpenClaw Agent 响应成功: {agent_id}")
            logger.debug(f"响应: {json.dumps(result, ensure_ascii=False)}")
            
            # 提取回复内容
            reply = result.get('reply', result.get('message', ''))
            
            if not reply:
                reply = "抱歉，我暂时无法处理您的请求。"
            
            # 更新任务状态
            update_task_status(task_id, 'success', reply[:500])  # 只存储前500字符
            
            return {
                'success': True,
                'reply': reply,
                'agent_id': agent_id
            }
        else:
            error_msg = f"API 返回错误: {response.status_code}"
            logger.error(f"❌ {error_msg}")
            update_task_status(task_id, 'failed', error_msg)
            
            return {
                'success': False,
                'error': error_msg,
                'reply': "抱歉，系统处理出现问题，请稍后再试。"
            }
            
    except requests.exceptions.Timeout:
        error_msg = "OpenClaw Gateway 超时"
        logger.error(f"❌ {error_msg}")
        update_task_status(task_id, 'timeout', error_msg)
        
        return {
            'success': False,
            'error': error_msg,
            'reply': "处理超时，请稍后再试。"
        }
        
    except Exception as e:
        error_msg = f"调用 OpenClaw API 失败: {str(e)}"
        logger.error(f"❌ {error_msg}")
        update_task_status(task_id, 'error', str(e)[:500])
        
        return {
            'success': False,
            'error': error_msg,
            'reply': "系统异常，请联系管理员。"
        }


# ============= 异步处理 =============

def process_message_async(user_id, content, agent_id, agent_url, task_id, response_url, crypto, timestamp, nonce):
    """异步处理消息，用 response_url 主动回复"""
    def worker():
        try:
            result = call_openclaw_agent(agent_id, content, user_id, task_id, gateway_url=agent_url)
            reply = result.get('reply', '处理失败，请稍后再试。')
            # 用 response_url 主动回复（markdown 格式）
            payload = {
                "msgtype": "markdown",
                "markdown": {"content": reply}
            }
            resp = requests.post(response_url, json=payload, timeout=10)
            logger.info(f"✅ 主动回复结果: {resp.status_code}")
        except Exception as e:
            logger.error(f"❌ 异步处理消息失败: {e}")

    threading.Thread(target=worker, daemon=True).start()
    logger.info(f"✅ 已启动异步处理线程: task_id={task_id}")


# ============= Flask 路由 =============

@app.route('/wecom/callback', methods=['GET', 'POST'])
def wecom_callback():
    """企业微信智能机器人回调接口"""
    msg_signature = request.args.get('msg_signature', '')
    timestamp = request.args.get('timestamp', '')
    nonce = request.args.get('nonce', '')

    crypto = WXBizMsgCrypt(WECOM_TOKEN, WECOM_ENCODING_AES_KEY)

    # GET：验证回调 URL
    if request.method == 'GET':
        echo_str = request.args.get('echostr', '')
        logger.info("收到企业微信回调验证请求")
        if not crypto.verify_signature(msg_signature, timestamp, nonce, echo_str):
            logger.error("❌ 签名验证失败")
            return "signature verification failed", 403
        decrypted = crypto.decrypt(echo_str)
        if not decrypted:
            logger.error("❌ 解密失败")
            return "decryption failed", 500
        logger.info("✅ 回调验证成功")
        return decrypted

    # POST：接收消息（JSON 格式）
    if request.method == 'POST':
        try:
            body = request.get_json(force=True)
            logger.info(f"收到 POST body: {str(body)[:200]}")
            encrypt_msg = body.get('encrypt', '')

            if not crypto.verify_signature(msg_signature, timestamp, nonce, encrypt_msg):
                logger.error("❌ 消息签名验证失败")
                return jsonify({}), 403

            decrypted = crypto.decrypt(encrypt_msg)
            if not decrypted:
                logger.error("❌ 消息解密失败")
                return jsonify({}), 500

            msg = json.loads(decrypted)
            logger.info(f"📩 解密消息: {str(msg)[:200]}")

            msg_type = msg.get('msgtype', '')
            from_user = msg.get('from', {}).get('userid', '')
            response_url = msg.get('response_url', '')

            # 流式刷新事件：直接返回空包
            if msg_type == 'stream':
                return jsonify({}), 200

            # 只处理文本消息
            if msg_type == 'text':
                content = msg.get('text', {}).get('content', '')
                logger.info(f"消息内容: {content}, from: {from_user}")

                task_id = str(uuid.uuid4())
                agent_id, agent_url = route_message(content)
                log_task(task_id, from_user, agent_id, content, status='processing')

                # 先被动回复"处理中"，再异步用 response_url 主动回复
                processing_msg = json.dumps({"msgtype": "text", "text": {"content": "⏳ 正在处理，请稍候..."}})
                reply_pkg = crypto.build_reply(processing_msg, int(timestamp), nonce)

                process_message_async(from_user, content, agent_id, agent_url, task_id, response_url, crypto, timestamp, nonce)

                if reply_pkg:
                    return jsonify(reply_pkg), 200
                return jsonify({}), 200

            else:
                logger.info(f"⚠️  忽略消息类型: {msg_type}")
                return jsonify({}), 200

        except Exception as e:
            logger.error(f"❌ 处理消息失败: {e}")
            return jsonify({}), 500


@app.route('/health', methods=['GET'])
def health():
    """健康检查接口"""
    return jsonify({
        'status': 'healthy',
        'timestamp': int(time.time()),
        'service': 'openclaw-wecom-gateway'
    })


@app.route('/stats', methods=['GET'])
def stats():
    """统计信息接口"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # 统计任务总数
        cursor.execute("SELECT COUNT(*) FROM task_logs")
        total_tasks = cursor.fetchone()[0]
        
        # 统计成功任务
        cursor.execute("SELECT COUNT(*) FROM task_logs WHERE status = 'success'")
        success_tasks = cursor.fetchone()[0]
        
        # 统计失败任务
        cursor.execute("SELECT COUNT(*) FROM task_logs WHERE status = 'failed'")
        failed_tasks = cursor.fetchone()[0]
        
        # 统计用户数
        cursor.execute("SELECT COUNT(*) FROM user_roles")
        total_users = cursor.fetchone()[0]
        
        conn.close()
        
        return jsonify({
            'total_tasks': total_tasks,
            'success_tasks': success_tasks,
            'failed_tasks': failed_tasks,
            'total_users': total_users,
            'success_rate': f"{success_tasks / total_tasks * 100:.2f}%" if total_tasks > 0 else "0%",
            'timestamp': int(time.time())
        })
    except Exception as e:
        logger.error(f"获取统计信息失败: {e}")
        return jsonify({'error': str(e)}), 500


@app.route('/test/route', methods=['POST'])
def test_route():
    """测试 AI 路由接口（仅供调试）"""
    data = request.json
    content = data.get('content')
    if not content:
        return jsonify({'error': 'content is required'}), 400
    agent_id, agent_url = route_message(content)
    return jsonify({
        'agent_id': agent_id,
        'agent_url': agent_url,
        'timestamp': int(time.time())
    })


# ============= Telegram Bot 路由 =============

# 初始化 Telegram 适配器（如果配置了 Token）
telegram_adapter = None
TELEGRAM_BOT_TOKEN = os.getenv('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_WEBHOOK_SECRET = os.getenv('TELEGRAM_WEBHOOK_SECRET', '')
TELEGRAM_MODE = os.getenv('TELEGRAM_MODE', 'webhook').lower()

if TELEGRAM_BOT_TOKEN:
    try:
        import atexit
        from telegram_adapter import TelegramAdapter
        telegram_adapter = TelegramAdapter(
            bot_token=TELEGRAM_BOT_TOKEN,
            db_path=DB_PATH,
            openclaw_url=OPENCLAW_GATEWAY_URL
        )
        logger.info("✅ Telegram 适配器初始化成功")
        if TELEGRAM_MODE == 'polling':
            telegram_adapter.start_polling()
            atexit.register(telegram_adapter.stop_polling)
    except Exception as e:
        logger.error(f"❌ Telegram 适配器初始化失败: {e}")


@app.route('/telegram/webhook', methods=['POST'])
def telegram_webhook():
    """Telegram Webhook 端点"""
    if not telegram_adapter:
        return jsonify({'error': 'Telegram adapter not initialized'}), 503

    if TELEGRAM_MODE == 'polling':
        return jsonify({'error': 'Webhook disabled, running in polling mode'}), 400

    # 验证 Secret Token
    if TELEGRAM_WEBHOOK_SECRET:
        request_token = request.headers.get('X-Telegram-Bot-Api-Secret-Token')
        if request_token != TELEGRAM_WEBHOOK_SECRET:
            logger.warning("Telegram Webhook 验证失败")
            return jsonify({'error': 'Unauthorized'}), 403

    # 处理 Update
    try:
        update = request.json
        result = telegram_adapter.handle_webhook(update)
        return jsonify(result)
    except Exception as e:
        logger.error(f"处理 Telegram Webhook 失败: {e}")
        return jsonify({'ok': False, 'error': str(e)}), 500


@app.route('/telegram/health', methods=['GET'])
def telegram_health():
    """Telegram 健康检查"""
    health_data = {
        'status': 'healthy' if telegram_adapter else 'disabled',
        'service': 'telegram-adapter',
        'mode': TELEGRAM_MODE,
        'timestamp': int(time.time()),
    }
    if telegram_adapter and TELEGRAM_MODE == 'polling':
        health_data['polling_active'] = (
            telegram_adapter._polling_thread is not None
            and telegram_adapter._polling_thread.is_alive()
        )
    return jsonify(health_data)


if __name__ == '__main__':
    logger.info("=" * 60)
    logger.info("OpenClaw 企业微信网关启动中...")
    logger.info("=" * 60)

    required_env = {
        'WECOM_TOKEN': WECOM_TOKEN,
        'WECOM_ENCODING_AES_KEY': WECOM_ENCODING_AES_KEY,
    }
    missing = [k for k, v in required_env.items() if not v]
    if missing:
        logger.warning(f"⚠️  以下环境变量未配置: {', '.join(missing)}")

    logger.info(f"✅ 数据库路径: {DB_PATH}")
    logger.info(f"✅ OpenClaw Gateway: {OPENCLAW_GATEWAY_URL}")
    logger.info("=" * 60)

    app.run(host='0.0.0.0', port=8000, debug=False)
