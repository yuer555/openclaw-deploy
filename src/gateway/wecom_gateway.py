from flask import Flask, request, jsonify
import hashlib
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
from datetime import datetime
import threading
import queue
import mimetypes
import websocket

app = Flask(__name__)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# ============= 配置（从环境变量读取）=============

# 数据库配置
DB_PATH = os.getenv('DB_PATH', '/opt/openclaw/data/gateway/gateway.db')

# 通信协议（全局默认）
OPENCLAW_TIMEOUT = int(os.getenv('OPENCLAW_TIMEOUT', '2700'))
OPENCLAW_PROTOCOL = os.getenv('OPENCLAW_PROTOCOL', 'ws')

# Gateway 端口
GATEWAY_PORT = int(os.getenv('GATEWAY_PORT', '8000'))

# ============= Agent 绑定（从 SQLite 加载）=============


def _ensure_agents_table():
    """确保 agents 表存在"""
    conn = sqlite3.connect(DB_PATH)
    conn.execute('''CREATE TABLE IF NOT EXISTS agents (
        name              TEXT PRIMARY KEY,
        display_name      TEXT NOT NULL,
        wecom_token       TEXT NOT NULL,
        wecom_aes_key     TEXT NOT NULL,
        openclaw_url      TEXT NOT NULL,
        openclaw_token    TEXT NOT NULL,
        openclaw_agent_id TEXT DEFAULT '',
        created_at        TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at        TEXT DEFAULT CURRENT_TIMESTAMP
    )''')
    conn.commit()
    conn.close()


def load_agents_from_db():
    """从 SQLite 加载所有 agent 绑定"""
    _ensure_agents_table()
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        "SELECT name, display_name, wecom_token, wecom_aes_key, "
        "openclaw_url, openclaw_token, openclaw_agent_id FROM agents"
    ).fetchall()
    agents = {}
    for name, display, token, aes_key, url, oc_token, agent_id in rows:
        agents[name] = {
            'display_name': display,
            'wecom_token': token,
            'wecom_encoding_aes_key': aes_key,
            'openclaw_url': url,
            'openclaw_token': oc_token,
            'openclaw_agent_id': agent_id or 'main',
        }
    conn.close()
    return agents


# 确保数据库目录存在
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

AGENTS = load_agents_from_db()


# ============= OpenClaw API 通用调用 =============

def _extract_reply_text(data):
    """从 /v1/responses 返回数据中提取文本"""
    texts = []
    for item in data.get('output', []):
        if item.get('type') == 'message':
            for c in item.get('content', []):
                if c.get('type') == 'output_text' and c.get('text'):
                    texts.append(c['text'])
    return '\n'.join(texts).strip()


def _call_openclaw_sse(url, message, session_key, timeout=2700, token='', agent_id='main'):
    """单次 HTTP SSE 流式调用，返回回复文本。连接异常时抛出异常。"""
    resp = requests.post(
        f"{url}/v1/responses",
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
            'x-openclaw-agent-id': agent_id,
        },
        json={'model': 'openclaw', 'input': message, 'stream': True, 'user': session_key},
        timeout=(10, timeout),
        stream=True,
    )
    resp.raise_for_status()

    final_data = None
    for line in resp.iter_lines(decode_unicode=True):
        if not line or not line.startswith('data: '):
            continue
        payload = line[6:]
        if payload == '[DONE]':
            break
        try:
            evt = json.loads(payload)
            if evt.get('type') == 'response.completed':
                final_data = evt.get('response', {})
        except json.JSONDecodeError:
            continue

    if final_data:
        return _extract_reply_text(final_data)
    return ''


def _call_openclaw_http(url, message, session_key, timeout=2700, token='', agent_id='main'):
    """同步 HTTP POST 调用，不使用流式，直接拿完整 JSON 响应"""
    resp = requests.post(
        f"{url}/v1/responses",
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
            'x-openclaw-agent-id': agent_id,
        },
        json={'model': 'openclaw', 'input': message, 'user': session_key},
        timeout=(10, timeout),
    )
    resp.raise_for_status()
    return _extract_reply_text(resp.json())


def _call_openclaw_ws(url, message, session_key, timeout=2700, token='', agent_id='main'):
    """WebSocket 协议调用：connect 握手 + chat.send，监听 chat state=final 获取回复"""
    ws_url = url.replace('http://', 'ws://').replace('https://', 'wss://') + '/ws'
    ws = websocket.create_connection(ws_url, timeout=timeout)
    try:
        # Step 1: 收 challenge
        ws.recv()

        # Step 2: connect 握手
        ws.send(json.dumps({
            "type": "req", "id": "connect-1", "method": "connect",
            "params": {
                "client": {"id": "cli", "mode": "cli", "platform": "linux", "version": "2026.2.28"},
                "auth": {"token": token},
                "role": "operator",
                "scopes": ["operator.read", "operator.write"],
                "minProtocol": 3, "maxProtocol": 3
            }
        }))
        hello = json.loads(ws.recv())
        if not hello.get('ok'):
            raise Exception(f"WS connect 失败: {hello.get('error')}")

        # Step 3: chat.send — sessionKey 包含 agent 路由信息
        req_id = str(uuid.uuid4())
        ws.send(json.dumps({
            "type": "req", "id": req_id, "method": "chat.send",
            "params": {
                "message": message,
                "sessionKey": f"agent:{agent_id}:{session_key}",
                "idempotencyKey": str(uuid.uuid4())
            }
        }))

        # 监听事件流，chat state=final 包含完整回复
        while True:
            raw = ws.recv()
            evt = json.loads(raw)
            if evt.get('type') == 'event' and evt.get('event') == 'chat':
                payload = evt.get('payload', {})
                # 校验 sessionKey，忽略其他用户的 broadcast 事件
                evt_sk = (payload.get('sessionKey') or '').lower()
                if evt_sk and session_key.lower() not in evt_sk:
                    continue
                if payload.get('state') == 'final':
                    msg = payload.get('message', {})
                    texts = []
                    for c in msg.get('content', []):
                        if c.get('type') == 'text' and c.get('text'):
                            texts.append(c['text'])
                    return '\n'.join(texts).strip()
            # RPC 错误
            if evt.get('type') == 'res' and evt.get('id') == req_id and not evt.get('ok'):
                raise Exception(f"WS RPC 错误: {evt.get('error')}")
    finally:
        ws.close()


def _call_openclaw(url, message, session_key, timeout=2700, token='', agent_id='main'):
    """统一调用入口，根据 OPENCLAW_PROTOCOL 选择协议"""
    protocol = OPENCLAW_PROTOCOL.lower()

    if protocol == 'http':
        return _call_openclaw_http(url, message, session_key, timeout,
                                   token=token, agent_id=agent_id)

    elif protocol == 'ws':
        try:
            return _call_openclaw_ws(url, message, session_key, timeout,
                                     token=token, agent_id=agent_id)
        except Exception as e:
            logger.warning(f"WS 调用失败: {e}，尝试重试")
            retry_msg = "请重复你刚才的回复，不要做任何修改，原样输出即可。"
            return _call_openclaw_ws(url, retry_msg, session_key, timeout,
                                     token=token, agent_id=agent_id)

    else:  # 默认 sse
        try:
            return _call_openclaw_sse(url, message, session_key, timeout,
                                      token=token, agent_id=agent_id)
        except (requests.exceptions.ConnectionError,
                requests.exceptions.ChunkedEncodingError,
                requests.exceptions.ReadTimeout) as e:
            logger.warning(f"SSE 连接断开: {e}，尝试重试")
            retry_msg = "请重复你刚才的回复，不要做任何修改，原样输出即可。"
            return _call_openclaw_sse(url, retry_msg, session_key, timeout,
                                      token=token, agent_id=agent_id)


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
        cursor.execute('''CREATE TABLE IF NOT EXISTS file_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT,
            file_path TEXT,
            file_name TEXT,
            file_type TEXT,
            content_type TEXT,
            file_size INTEGER,
            source_url TEXT,
            msg_type TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )''')
        conn.commit()
        conn.close()
        logger.info("数据库初始化完成")
    except Exception as e:
        logger.error(f"数据库初始化失败: {e}")

init_db()


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
    except Exception as e:
        logger.error(f"记录任务日志失败: {e}")


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
    except Exception as e:
        logger.error(f"更新任务状态失败: {e}")


def log_file_record(user_id, file_path, file_name, file_type, content_type, file_size, source_url, msg_type):
    """记录文件存档信息"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO file_records (user_id, file_path, file_name, file_type, content_type, file_size, source_url, msg_type) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (user_id, file_path, file_name, file_type, content_type, file_size, source_url, msg_type)
        )
        conn.commit()
        conn.close()
    except Exception as e:
        logger.error(f"记录文件存档失败: {e}")


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


# ============= 文件下载目录 =============

def _default_files_base():
    """文件存储基础目录"""
    prod_path = '/opt/openclaw/data/gateway/files'
    if os.path.isdir(prod_path):
        return prod_path
    return os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'data', 'files')

FILES_BASE = os.getenv('FILES_BASE', _default_files_base())


def _get_today_dir():
    """获取当日文件目录，自动创建"""
    today = datetime.now().strftime('%Y-%m-%d')
    path = os.path.join(FILES_BASE, today)
    os.makedirs(path, exist_ok=True)
    return path


# ============= 多类型消息处理 =============

TEXT_EXTENSIONS = {'.txt', '.md', '.csv', '.json', '.xml', '.yaml', '.yml', '.py', '.js', '.ts',
                   '.java', '.go', '.rs', '.rb', '.php', '.sh', '.bash', '.sql', '.html', '.css',
                   '.conf', '.cfg', '.ini', '.toml', '.log', '.env', '.properties'}
TEXT_CONTENT_TYPES = {'text/', 'application/json', 'application/xml', 'application/yaml',
                      'application/x-yaml', 'application/toml', 'application/sql'}
MAX_TEXT_EMBED_SIZE = 50 * 1024  # 50KB


def _detect_file_type(local_path, content_type):
    """当 Content-Type 为 octet-stream 时，通过文件头魔数和内容探测真实类型"""
    if content_type != 'application/octet-stream':
        return content_type, mimetypes.guess_extension(content_type) or ''

    MAGIC_SIGNATURES = [
        (b'\x89PNG\r\n\x1a\n', 'image/png', '.png'),
        (b'\xff\xd8\xff', 'image/jpeg', '.jpg'),
        (b'GIF87a', 'image/gif', '.gif'),
        (b'GIF89a', 'image/gif', '.gif'),
        (b'%PDF', 'application/pdf', '.pdf'),
        (b'PK\x03\x04', 'application/zip', '.zip'),
        (b'\x1f\x8b', 'application/gzip', '.gz'),
        (b'Rar!\x1a\x07', 'application/x-rar', '.rar'),
    ]
    try:
        with open(local_path, 'rb') as f:
            header = f.read(16)
        for magic, ct, ext in MAGIC_SIGNATURES:
            if header.startswith(magic):
                if magic == b'PK\x03\x04':
                    name_lower = local_path.lower()
                    if name_lower.endswith(('.docx', '.doc')):
                        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', '.docx'
                    if name_lower.endswith(('.xlsx', '.xls')):
                        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.xlsx'
                return ct, ext
    except Exception:
        pass

    try:
        with open(local_path, 'rb') as f:
            sample = f.read(4096)
        sample.decode('utf-8')
        return 'text/plain', '.txt'
    except (UnicodeDecodeError, Exception):
        pass

    try:
        with open(local_path, 'rb') as f:
            sample = f.read(4096)
        sample.decode('gbk')
        return 'text/plain', '.txt'
    except (UnicodeDecodeError, Exception):
        pass

    return content_type, ''


def _decrypt_file(encrypted_data, encoding_aes_key):
    """解密企业微信文件内容（AES-256-CBC，PKCS#7 填充）"""
    try:
        aes_key = base64.b64decode(encoding_aes_key + "=")
        iv = aes_key[:16]
        cipher = AES.new(aes_key, AES.MODE_CBC, iv)
        decrypted = cipher.decrypt(encrypted_data)
        pad = decrypted[-1]
        if pad < 1 or pad > 32:
            return decrypted
        return decrypted[:-pad]
    except Exception as e:
        logger.warning(f"文件解密失败: {e}")
        return None


def download_temp_file(url, prefix='file', user_id='', msg_type='', encoding_aes_key=''):
    """下载临时 COS URL 到文件目录（按日期分区），返回 (local_path, text_content_or_none)"""
    try:
        today_dir = _get_today_dir()
        resp = requests.get(url, timeout=30, stream=True)
        resp.raise_for_status()

        encrypted_data = resp.content

        decrypted = _decrypt_file(encrypted_data, encoding_aes_key) if encoding_aes_key else None
        if decrypted is None:
            if encoding_aes_key:
                logger.warning("文件解密失败，使用原始数据")
            decrypted = encrypted_data

        tmp_filename = f"{prefix}-{uuid.uuid4().hex[:8]}.tmp"
        tmp_path = os.path.join(today_dir, tmp_filename)
        with open(tmp_path, 'wb') as f:
            f.write(decrypted)

        raw_content_type = resp.headers.get('Content-Type', 'application/octet-stream').split(';')[0].strip()
        content_type, ext = _detect_file_type(tmp_path, raw_content_type)
        if ext == '.jpe':
            ext = '.jpg'

        filename = f"{prefix}-{uuid.uuid4().hex[:8]}{ext}"
        local_path = os.path.join(today_dir, filename)
        os.rename(tmp_path, local_path)

        file_size = os.path.getsize(local_path)

        is_text = any(content_type.startswith(ct) for ct in TEXT_CONTENT_TYPES) or ext in TEXT_EXTENSIONS
        text_content = None
        if is_text:
            try:
                if file_size <= MAX_TEXT_EMBED_SIZE:
                    with open(local_path, 'rb') as f:
                        raw = f.read()
                    try:
                        text_content = raw.decode('utf-8')
                    except UnicodeDecodeError:
                        try:
                            text_content = raw.decode('gbk')
                        except UnicodeDecodeError:
                            text_content = raw.decode('utf-8', errors='replace')
            except Exception as e:
                logger.warning(f"读取文本文件内容失败: {e}")

        file_type = 'text' if is_text else content_type.split('/')[0]
        log_file_record(user_id, local_path, filename, file_type, content_type, file_size, url, msg_type)

        logger.info(f"文件已下载: {local_path} (type={content_type}, text={text_content is not None})")
        return local_path, text_content
    except Exception as e:
        logger.error(f"下载文件失败: {e}")
        return None, None


def extract_single_content(item, user_id='', encoding_aes_key=''):
    """提取单条消息内容（主消息或 quote 内的消息），返回文本描述"""
    msg_type = item.get('msgtype', '')

    if msg_type == 'text':
        return item.get('text', {}).get('content', '')

    elif msg_type == 'voice':
        return item.get('voice', {}).get('content', '')

    elif msg_type == 'image':
        url = item.get('image', {}).get('url', '')
        if not url:
            return '[用户发送了一张图片，但无法获取]'
        path, _ = download_temp_file(url, prefix='img', user_id=user_id, msg_type='image', encoding_aes_key=encoding_aes_key)
        if path:
            return f'[用户发送了一张图片，已保存到 {path}]'
        return '[用户发送了一张图片，下载失败]'

    elif msg_type == 'file':
        url = item.get('file', {}).get('url', '')
        if not url:
            return '[用户发送了一个文件，但无法获取]'
        path, text_content = download_temp_file(url, prefix='file', user_id=user_id, msg_type='file', encoding_aes_key=encoding_aes_key)
        if not path:
            return '[用户发送了一个文件，下载失败]'
        if text_content is not None:
            return f'[用户发送了一个文本文件 {path}]\n文件内容：\n{text_content}'
        return f'[用户发送了一个文件，已保存到 {path}]'

    elif msg_type == 'mixed':
        parts = []
        for sub_item in item.get('mixed', {}).get('msg_item', []):
            parts.append(extract_single_content(sub_item, user_id=user_id, encoding_aes_key=encoding_aes_key))
        return '\n'.join(parts)

    return f'[不支持的消息类型: {msg_type}]'


def extract_message_content(msg, user_id='', encoding_aes_key=''):
    """提取完整消息内容，返回文本内容"""
    content = extract_single_content(msg, user_id=user_id, encoding_aes_key=encoding_aes_key)

    quote = msg.get('quote')
    if quote:
        quote_content = extract_single_content(quote, user_id=user_id, encoding_aes_key=encoding_aes_key)
        content = f"{content}\n\n[引用消息] {quote_content}"

    return content


# ============= 异步处理（per-user per-agent 消息管道）=============

_user_queues = {}   # queue_key -> queue.Queue
_user_workers = {}  # queue_key -> Thread
_queue_lock = threading.Lock()


def _user_worker(queue_key):
    """单个用户+agent 的消息 worker，串行处理"""
    q = _user_queues[queue_key]
    while True:
        try:
            task = q.get(timeout=300)
        except queue.Empty:
            with _queue_lock:
                if q.empty():
                    del _user_queues[queue_key]
                    del _user_workers[queue_key]
                    logger.info(f"Worker {queue_key} 空闲退出")
                    return
                continue
        try:
            _process_single_message(**task)
        except Exception as e:
            logger.error(f"处理消息失败 ({queue_key}): {e}")
        finally:
            q.task_done()

def _process_single_message(user_id, content, task_id, response_url, agent_name):
    """处理单条消息：调用对应 agent -> 回复"""
    agent_cfg = AGENTS.get(agent_name)
    if not agent_cfg:
        logger.error(f"Agent {agent_name} 不存在（可能已被删除）")
        return

    session_key = f"wecom:{agent_name}:{user_id}"
    log_task(task_id, user_id, agent_name, content[:200], status='processing')

    try:
        reply = _call_openclaw(
            agent_cfg['openclaw_url'], content, session_key,
            timeout=OPENCLAW_TIMEOUT,
            token=agent_cfg['openclaw_token'],
            agent_id=agent_cfg['openclaw_agent_id'],
        )
        if not reply:
            reply = '处理失败，请稍后再试。'
            update_task_status(task_id, 'failed', '无响应')
        else:
            update_task_status(task_id, 'success', reply[:500])
    except Exception as e:
        logger.error(f"调用 agent {agent_name} 异常: {e}")
        reply = '系统异常，请联系管理员。'
        update_task_status(task_id, 'error', str(e)[:500])

    reply = truncate_message(reply)
    payload = {"msgtype": "markdown", "markdown": {"content": reply}}
    try:
        resp = requests.post(response_url, json=payload, timeout=10)
        logger.info(f"[{agent_name}] 主动回复: {resp.status_code}, 长度: {len(reply)}")
    except Exception as e:
        logger.error(f"[{agent_name}] 主动回复失败: {e}")


def process_message_async(user_id, content, task_id, response_url, agent_name):
    """将消息放入 agent:user 队列，串行处理"""
    task = {
        'user_id': user_id,
        'content': content,
        'task_id': task_id,
        'response_url': response_url,
        'agent_name': agent_name,
    }
    queue_key = f"{agent_name}:{user_id}"
    with _queue_lock:
        if queue_key not in _user_queues:
            _user_queues[queue_key] = queue.Queue()
            t = threading.Thread(target=_user_worker, args=(queue_key,), daemon=True)
            _user_workers[queue_key] = t
            t.start()
            logger.info(f"创建 worker: {queue_key}")
        _user_queues[queue_key].put(task)
        qsize = _user_queues[queue_key].qsize()
    logger.info(f"消息已入队: {queue_key}, task_id={task_id}, 队列长度={qsize}")


# ============= 消息去重 =============

_processed_msgs = {}  # msgid -> timestamp
_MSG_DEDUP_TTL = 600


def is_duplicate_msg(msgid):
    """检查消息是否重复，返回 True 表示重复应跳过"""
    now = time.time()
    expired = [k for k, v in _processed_msgs.items() if now - v > _MSG_DEDUP_TTL]
    for k in expired:
        del _processed_msgs[k]
    if msgid in _processed_msgs:
        return True
    _processed_msgs[msgid] = now
    return False


# ============= Flask 路由 =============

@app.route('/<agent_name>/wecom/callback', methods=['GET', 'POST'])
def wecom_callback(agent_name):
    """企业微信智能机器人回调接口（按 agent 路由）"""
    if agent_name not in AGENTS:
        logger.warning(f"未知 agent: {agent_name}")
        return jsonify({'error': f'unknown agent: {agent_name}'}), 404

    agent_cfg = AGENTS[agent_name]
    msg_signature = request.args.get('msg_signature', '')
    timestamp = request.args.get('timestamp', '')
    nonce = request.args.get('nonce', '')

    crypto = WXBizMsgCrypt(agent_cfg['wecom_token'], agent_cfg['wecom_encoding_aes_key'])

    # GET：验证回调 URL
    if request.method == 'GET':
        echo_str = request.args.get('echostr', '')
        logger.info(f"[{agent_name}] 收到企业微信回调验证请求")
        if not crypto.verify_signature(msg_signature, timestamp, nonce, echo_str):
            logger.error(f"[{agent_name}] 签名验证失败")
            return "signature verification failed", 403
        decrypted = crypto.decrypt(echo_str)
        if not decrypted:
            logger.error(f"[{agent_name}] 解密失败")
            return "decryption failed", 500
        logger.info(f"[{agent_name}] 回调验证成功")
        return decrypted

    # POST：接收消息（JSON 格式）
    if request.method == 'POST':
        try:
            body = request.get_json(force=True)
            logger.info(f"[{agent_name}] 收到 POST body: {str(body)[:200]}")
            encrypt_msg = body.get('encrypt', '')

            if not crypto.verify_signature(msg_signature, timestamp, nonce, encrypt_msg):
                logger.error(f"[{agent_name}] 消息签名验证失败")
                return jsonify({}), 403

            decrypted = crypto.decrypt(encrypt_msg)
            if not decrypted:
                logger.error(f"[{agent_name}] 消息解密失败")
                return jsonify({}), 500

            msg = json.loads(decrypted)
            logger.info(f"[{agent_name}] 解密消息: {json.dumps(msg, ensure_ascii=False)[:300]}")

            msg_type = msg.get('msgtype', '')
            msgid = msg.get('msgid', '')
            from_user = msg.get('from', {}).get('userid', '')
            response_url = msg.get('response_url', '')

            if msg_type == 'stream':
                return jsonify({}), 200

            if msgid and is_duplicate_msg(msgid):
                logger.info(f"[{agent_name}] 重复消息已跳过: {msgid}")
                return jsonify({}), 200

            if msg_type in ('text', 'image', 'file', 'voice', 'mixed'):
                content = extract_message_content(msg, user_id=from_user,
                                                  encoding_aes_key=agent_cfg['wecom_encoding_aes_key'])
                logger.info(f"[{agent_name}] 消息内容: {content[:200]}, from: {from_user}")

                task_id = str(uuid.uuid4())

                processing_msg = json.dumps({"msgtype": "markdown", "markdown": {"content": "正在处理，请稍候..."}})
                reply_pkg = crypto.build_reply(processing_msg, int(timestamp), nonce)

                process_message_async(from_user, content, task_id, response_url, agent_name)

                if reply_pkg:
                    return jsonify(reply_pkg), 200
                return jsonify({}), 200

            else:
                logger.info(f"[{agent_name}] 忽略消息类型: {msg_type}")
                return jsonify({}), 200

        except Exception as e:
            logger.error(f"[{agent_name}] 处理消息失败: {e}")
            return jsonify({}), 500


@app.route('/wecom/callback', methods=['GET', 'POST'])
def wecom_callback_legacy():
    """兼容旧版路径 — 提示用户使用新路径"""
    if not AGENTS:
        return jsonify({'error': '尚未添加任何 agent，请先通过 manage-agent.py 添加'}), 404

    # 使用第一个 agent（临时兼容）
    default_agent = list(AGENTS.keys())[0]
    logger.warning(f"旧版路径 /wecom/callback 请求，自动路由到: {default_agent}")
    return wecom_callback(default_agent)


# ============= 管理 API =============

@app.route('/admin/reload', methods=['POST'])
def admin_reload():
    """重新从 SQLite 加载绑定关系（管理脚本调用）"""
    global AGENTS
    AGENTS = load_agents_from_db()
    logger.info(f"Agent 绑定已重载，当前 {len(AGENTS)} 个: {list(AGENTS.keys())}")
    return jsonify({'status': 'ok', 'agents': list(AGENTS.keys())})


@app.route('/admin/agents', methods=['GET'])
def admin_list_agents():
    """列出所有绑定"""
    return jsonify({
        'agents': {
            name: {
                'display_name': cfg['display_name'],
                'openclaw_url': cfg['openclaw_url'],
                'openclaw_agent_id': cfg['openclaw_agent_id'],
            }
            for name, cfg in AGENTS.items()
        }
    })


@app.route('/health', methods=['GET'])
def health():
    """健康检查接口"""
    return jsonify({
        'status': 'ok',
        'timestamp': int(time.time()),
        'service': 'openclaw-wecom-gateway',
        'protocol': OPENCLAW_PROTOCOL,
        'agents': len(AGENTS),
        'agent_names': list(AGENTS.keys()),
    })


@app.route('/stats', methods=['GET'])
def stats():
    """统计信息接口"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()

        cursor.execute("SELECT COUNT(*) FROM task_logs")
        total_tasks = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM task_logs WHERE status = 'success'")
        success_tasks = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM task_logs WHERE status = 'failed'")
        failed_tasks = cursor.fetchone()[0]

        conn.close()

        return jsonify({
            'total_tasks': total_tasks,
            'success_tasks': success_tasks,
            'failed_tasks': failed_tasks,
            'success_rate': f"{success_tasks / total_tasks * 100:.2f}%" if total_tasks > 0 else "0%",
            'agents': len(AGENTS),
            'timestamp': int(time.time())
        })
    except Exception as e:
        logger.error(f"获取统计信息失败: {e}")
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    logger.info("=" * 60)
    logger.info("OpenClaw 企业微信桥接网关启动中...")
    logger.info(f"数据库路径: {DB_PATH}")
    logger.info(f"通信协议: {OPENCLAW_PROTOCOL}")
    logger.info(f"超时时间: {OPENCLAW_TIMEOUT}s")
    if AGENTS:
        logger.info(f"已加载 {len(AGENTS)} 个 Agent 绑定:")
        for name, cfg in AGENTS.items():
            logger.info(f"  - {name} ({cfg['display_name']}): {cfg['openclaw_url']} [agent: {cfg['openclaw_agent_id']}]")
    else:
        logger.info("当前无 Agent 绑定，请通过 manage-agent.py 添加")
    logger.info("=" * 60)

    app.run(host='0.0.0.0', port=GATEWAY_PORT, debug=False)
