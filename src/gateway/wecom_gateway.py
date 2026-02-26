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
OPENCLAW_TIMEOUT = int(os.getenv('OPENCLAW_TIMEOUT', '2700'))

# OpenClaw 内部通信 Token
OPENCLAW_INTERNAL_TOKEN = os.getenv('OPENCLAW_INTERNAL_TOKEN', 'openclaw-internal-secret')

# Agent 注册表
from agent_registry import AGENT_REGISTRY


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
            route_session = f"route-{uuid.uuid4()}"
            result = subprocess.run(
                ['npx', 'openclaw', 'agent', '--agent', 'main', '--local',
                 '--session-id', route_session,
                 '-m', prompt, '--json', '--timeout', '30'],
                capture_output=True, text=True, timeout=40, cwd='/workspace'
            )
            if result.returncode == 0 and result.stdout.strip():
                # 解析 JSON（可能多行输出，取最后一个有效 JSON）
                data = None
                for line in reversed(result.stdout.strip().split('\n')):
                    if line.strip().startswith('{'):
                        try:
                            data = json.loads(line.strip())
                            break
                        except json.JSONDecodeError:
                            continue
                if not data:
                    try:
                        data = json.loads(result.stdout)
                    except json.JSONDecodeError:
                        data = None

                if data:
                    payloads = data.get('payloads') or data.get('result', {}).get('payloads', [])
                    parts = [p.get('text', '') for p in payloads if p.get('text')]
                    reply = '\n'.join(parts)
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


# ============= OpenClaw Agent 调用（docker exec + CLI）=============

def call_openclaw_agent(agent_id, message, user_id, task_id, gateway_url=None):
    """通过 docker exec 在远程 agent 容器内调用 openclaw CLI（与调度员相同模式）"""
    import subprocess

    container_name = AGENT_REGISTRY.get(agent_id, {}).get('container', f'openclaw-agent-{agent_id}')
    logger.info(f"调用 Agent {agent_id}: docker exec {container_name}")

    try:
        session_id = f"{agent_id}-{user_id}"
        result = subprocess.run(
            ['docker', 'exec', container_name,
             'npx', 'openclaw', 'agent', '--agent', 'main', '--local',
             '--session-id', session_id,
             '-m', message, '--json', '--timeout', str(OPENCLAW_TIMEOUT)],
            capture_output=True, text=True, timeout=OPENCLAW_TIMEOUT + 10,
            cwd='/workspace'
        )

        logger.info(f"Agent {agent_id} CLI 返回码: {result.returncode}, stdout长度: {len(result.stdout)}, stderr长度: {len(result.stderr)}")

        if result.returncode == 0 and result.stdout.strip():
            # stdout 可能包含多个 JSON 对象（每行一个），取最后一个完整的
            lines = result.stdout.strip().split('\n')
            logger.info(f"Agent {agent_id} stdout 行数: {len(lines)}")
            data = None
            for line in reversed(lines):
                line = line.strip()
                if line.startswith('{'):
                    try:
                        data = json.loads(line)
                        break
                    except json.JSONDecodeError:
                        continue
            if not data:
                try:
                    data = json.loads(result.stdout)
                except json.JSONDecodeError:
                    data = None

            if data:
                payloads = data.get('payloads') or data.get('result', {}).get('payloads', [])
                logger.info(f"Agent {agent_id} payloads 数量: {len(payloads)}")
                # 合并所有 payload 的 text
                parts = [p.get('text', '') for p in payloads if p.get('text')]
                reply = '\n'.join(parts)
                logger.info(f"Agent {agent_id} 回复长度: {len(reply)}, 前200字: {reply[:200]}")
                if reply:
                    update_task_status(task_id, 'success', reply[:500])
                    return {'success': True, 'reply': reply, 'agent_id': agent_id}
            else:
                logger.error(f"Agent {agent_id} JSON 解析失败, stdout前500字: {result.stdout[:500]}")

        error_msg = result.stderr[:200] if result.stderr else '无响应'
        logger.error(f"Agent {agent_id} CLI 调用失败: {error_msg}")
        update_task_status(task_id, 'failed', error_msg[:500])
        return {'success': False, 'error': error_msg, 'reply': '抱歉，系统处理出现问题，请稍后再试。'}

    except subprocess.TimeoutExpired:
        logger.error(f"Agent {agent_id} 调用超时")
        update_task_status(task_id, 'failed', 'timeout')
        return {'success': False, 'error': 'timeout', 'reply': '处理超时，请稍后再试。'}
    except Exception as e:
        error_msg = str(e)
        logger.error(f"Agent {agent_id} 调用异常: {error_msg}")
        update_task_status(task_id, 'error', error_msg[:500])
        return {'success': False, 'error': error_msg, 'reply': '系统异常，请联系管理员。'}


# ============= 长消息截断 =============

WECOM_MSG_MAX_LEN = 20000  # 企业微信 markdown 消息限制 20480 字节，留余量


def truncate_message(text, max_len=WECOM_MSG_MAX_LEN):
    """将长消息截断到 max_len 字节内，超长时按段落截断并加提示"""
    if len(text.encode('utf-8')) <= max_len:
        return text

    suffix = '\n\n...(回复过长已截断)'
    available = max_len - len(suffix.encode('utf-8'))

    # 按段落截断，保留完整段落
    result = ''
    for line in text.split('\n'):
        candidate = result + ('\n' if result else '') + line
        if len(candidate.encode('utf-8')) > available:
            break
        result = candidate

    # 如果一个段落都放不下，按字符强制截断
    if not result:
        result = text
        while len(result.encode('utf-8')) > available:
            result = result[:-1]

    return result + suffix


# ============= 异步处理 =============

def process_message_async(user_id, content, agent_id, agent_url, task_id, response_url, crypto, timestamp, nonce):
    """异步处理消息，用 response_url 主动回复"""
    def worker():
        try:
            result = call_openclaw_agent(agent_id, content, user_id, task_id, gateway_url=agent_url)
            reply = result.get('reply', '处理失败，请稍后再试。')
            reply = truncate_message(reply)
            payload = {
                "msgtype": "markdown",
                "markdown": {"content": reply}
            }
            resp = requests.post(response_url, json=payload, timeout=10)
            logger.info(f"✅ 主动回复: {resp.status_code}, 长度: {len(reply)}")
        except Exception as e:
            logger.error(f"❌ 异步处理消息失败: {e}")

    threading.Thread(target=worker, daemon=True).start()
    logger.info(f"✅ 已启动异步处理线程: task_id={task_id}")


# ============= 消息去重 =============

_processed_msgs = {}  # msgid -> timestamp
_MSG_DEDUP_TTL = 600  # 10分钟内同一 msgid 视为重复


def is_duplicate_msg(msgid):
    """检查消息是否重复，返回 True 表示重复应跳过"""
    now = time.time()
    # 清理过期记录
    expired = [k for k, v in _processed_msgs.items() if now - v > _MSG_DEDUP_TTL]
    for k in expired:
        del _processed_msgs[k]
    # 判断重复
    if msgid in _processed_msgs:
        return True
    _processed_msgs[msgid] = now
    return False


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
            msgid = msg.get('msgid', '')
            from_user = msg.get('from', {}).get('userid', '')
            response_url = msg.get('response_url', '')

            # 流式刷新事件：直接返回空包
            if msg_type == 'stream':
                return jsonify({}), 200

            # 消息去重（企业微信未收到及时响应会重试推送）
            if msgid and is_duplicate_msg(msgid):
                logger.info(f"⚠️  重复消息已跳过: {msgid}")
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
