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
import queue
import mimetypes
import subprocess
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

# OpenClaw 配置
OPENCLAW_TIMEOUT = int(os.getenv('OPENCLAW_TIMEOUT', '2700'))
OPENCLAW_INTERNAL_TOKEN = os.getenv('OPENCLAW_INTERNAL_TOKEN', 'openclaw-internal-secret')
OPENCLAW_PROTOCOL = os.getenv('OPENCLAW_PROTOCOL', 'ws')

# ============= 多 Agent 配置（从环境变量自动发现）=============

KNOWN_ROLES = ['operation', 'product', 'development', 'testing', 'service']
# 默认端口映射
DEFAULT_PORTS = {'operation': 18791, 'product': 18792, 'development': 18793, 'testing': 18794, 'service': 18795}


def load_agents_from_env():
    """从环境变量扫描 AGENT_{ROLE}_ENABLE 构建 AGENTS 字典"""
    agents = {}
    for role in KNOWN_ROLES:
        prefix = f'AGENT_{role.upper()}_'
        enable = os.getenv(f'{prefix}ENABLE', 'false').lower() == 'true'
        if not enable:
            continue
        port = int(os.getenv(f'{prefix}PORT', str(DEFAULT_PORTS[role])))
        agents[role] = {
            'wecom_token': os.getenv(f'{prefix}WECOM_TOKEN', ''),
            'wecom_encoding_aes_key': os.getenv(f'{prefix}WECOM_ENCODING_AES_KEY', ''),
            'port': port,
            'url': f'http://localhost:{port}',
            'container': f'openclaw-agent-{role}',
        }
    return agents


def validate_agents():
    """启动时校验 enabled agent 的配置"""
    if not AGENTS:
        logger.error("❌ 没有启用任何 Agent！请在 .env 中设置 AGENT_*_ENABLE=true")
        raise SystemExit(1)
    errors = []
    for name, cfg in AGENTS.items():
        if not cfg['wecom_token']:
            errors.append(f"Agent {name}: AGENT_{name.upper()}_WECOM_TOKEN 未配置")
        if not cfg['wecom_encoding_aes_key']:
            errors.append(f"Agent {name}: AGENT_{name.upper()}_WECOM_ENCODING_AES_KEY 未配置")
    if errors:
        for e in errors:
            logger.error(f"❌ {e}")
        raise SystemExit(1)


AGENTS = load_agents_from_env()


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


def _call_openclaw_sse(url, message, session_key, timeout=2700):
    """单次 HTTP SSE 流式调用，返回回复文本。连接异常时抛出异常。"""
    resp = requests.post(
        f"{url}/v1/responses",
        headers={
            'Authorization': f'Bearer {OPENCLAW_INTERNAL_TOKEN}',
            'Content-Type': 'application/json',
            'x-openclaw-agent-id': 'main',
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


def _call_openclaw_http(url, message, session_key, timeout=2700):
    """同步 HTTP POST 调用，不使用流式，直接拿完整 JSON 响应"""
    resp = requests.post(
        f"{url}/v1/responses",
        headers={
            'Authorization': f'Bearer {OPENCLAW_INTERNAL_TOKEN}',
            'Content-Type': 'application/json',
            'x-openclaw-agent-id': 'main',
        },
        json={'model': 'openclaw', 'input': message, 'user': session_key},
        timeout=(10, timeout),
    )
    resp.raise_for_status()
    return _extract_reply_text(resp.json())


def _extract_exec_reply(data):
    """从 docker exec --json 输出中提取文本（格式: {payloads: [{text: ...}]})"""
    texts = []
    for p in data.get('payloads', []):
        if p.get('text'):
            texts.append(p['text'])
    return '\n'.join(texts).strip()


def _call_openclaw_exec(url, message, session_key, timeout=2700, container=''):
    """通过 docker exec 调用容器内 openclaw CLI，解析 JSON 输出"""
    if not container:
        raise Exception("exec 协议需要指定容器名")

    cmd = [
        'docker', 'exec', container,
        'npx', 'openclaw', 'agent', '--agent', 'main', '--local',
        '--session-id', session_key,
        '-m', message, '--json', '--timeout', str(timeout),
    ]
    logger.info(f"exec 调用: docker exec {container} ...")
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout + 30)

    if result.returncode != 0:
        stderr = result.stderr.strip()
        logger.error(f"exec 调用失败 (rc={result.returncode}): {stderr[:500]}")
        raise Exception(f"docker exec 失败: {stderr[:200]}")

    stdout = result.stdout.strip()
    if not stdout:
        return ''
    try:
        data = json.loads(stdout)
        return _extract_exec_reply(data)
    except json.JSONDecodeError:
        reply_text = ''
        for line in stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                text = _extract_exec_reply(data)
                if text:
                    reply_text = text
            except json.JSONDecodeError:
                continue
        return reply_text


def _call_openclaw_ws(url, message, session_key, timeout=2700):
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
                "auth": {"token": OPENCLAW_INTERNAL_TOKEN},
                "role": "operator",
                "scopes": ["operator.read", "operator.write"],
                "minProtocol": 3, "maxProtocol": 3
            }
        }))
        hello = json.loads(ws.recv())
        if not hello.get('ok'):
            raise Exception(f"WS connect 失败: {hello.get('error')}")

        # Step 3: chat.send
        req_id = str(uuid.uuid4())
        ws.send(json.dumps({
            "type": "req", "id": req_id, "method": "chat.send",
            "params": {
                "message": message,
                "sessionKey": session_key,
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


def _call_openclaw(url, message, session_key, timeout=2700, container=''):
    """统一调用入口，根据 OPENCLAW_PROTOCOL 选择协议"""
    protocol = OPENCLAW_PROTOCOL.lower()

    if protocol == 'http':
        return _call_openclaw_http(url, message, session_key, timeout)

    elif protocol == 'exec':
        return _call_openclaw_exec(url, message, session_key, timeout, container=container)

    elif protocol == 'ws':
        try:
            return _call_openclaw_ws(url, message, session_key, timeout)
        except Exception as e:
            logger.warning(f"WS 调用失败: {e}，尝试重试")
            retry_msg = "请重复你刚才的回复，不要做任何修改，原样输出即可。"
            return _call_openclaw_ws(url, retry_msg, session_key, timeout)

    else:  # 默认 sse
        try:
            return _call_openclaw_sse(url, message, session_key, timeout)
        except (requests.exceptions.ConnectionError,
                requests.exceptions.ChunkedEncodingError,
                requests.exceptions.ReadTimeout) as e:
            logger.warning(f"SSE 连接断开: {e}，尝试重试")
            retry_msg = "请重复你刚才的回复，不要做任何修改，原样输出即可。"
            return _call_openclaw_sse(url, retry_msg, session_key, timeout)


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
        logger.info(f"✅ 文件存档已记录: {file_name} (user={user_id})")
    except Exception as e:
        logger.error(f"❌ 记录文件存档失败: {e}")


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


# ============= 共享文件目录配置 =============

def _default_shared_files_base():
    """本地开发时 /opt/openclaw/shared-files 不存在，自动 fallback 到 ./shared-files"""
    prod_path = '/opt/openclaw/shared-files'
    if os.path.isdir(prod_path):
        return prod_path
    return os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'shared-files')

SHARED_FILES_BASE = os.getenv('SHARED_FILES_BASE', _default_shared_files_base())
CONTAINER_FILES_BASE = os.getenv('CONTAINER_FILES_BASE', '/root/.openclaw/workspace/shared-files')


def _get_today_dir():
    """获取当日共享文件目录（宿主机路径），自动创建"""
    today = datetime.now().strftime('%Y-%m-%d')
    path = os.path.join(SHARED_FILES_BASE, today)
    os.makedirs(path, exist_ok=True)
    return path


def host_path_to_container_path(host_path):
    """将宿主机文件路径转换为容器内路径"""
    if host_path and host_path.startswith(SHARED_FILES_BASE):
        return CONTAINER_FILES_BASE + host_path[len(SHARED_FILES_BASE):]
    return host_path


# ============= 多类型消息处理 =============

TEMP_FILE_DIR = None
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
    """下载临时 COS URL 到共享文件目录（按日期分区），返回 (local_path, text_content_or_none)"""
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
            container_path = host_path_to_container_path(path)
            return f'[用户发送了一张图片，已保存到 {container_path}]'
        return '[用户发送了一张图片，下载失败]'

    elif msg_type == 'file':
        url = item.get('file', {}).get('url', '')
        if not url:
            return '[用户发送了一个文件，但无法获取]'
        path, text_content = download_temp_file(url, prefix='file', user_id=user_id, msg_type='file', encoding_aes_key=encoding_aes_key)
        if not path:
            return '[用户发送了一个文件，下载失败]'
        container_path = host_path_to_container_path(path)
        if text_content is not None:
            return f'[用户发送了一个文本文件 {container_path}]\n文件内容：\n{text_content}'
        return f'[用户发送了一个文件，已保存到 {container_path}]'

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
            logger.error(f"❌ 处理消息失败 ({queue_key}): {e}")
        finally:
            q.task_done()

def _process_single_message(user_id, content, task_id, response_url, agent_name):
    """处理单条消息：调用对应 agent → 回复"""
    agent_cfg = AGENTS[agent_name]
    session_key = f"{agent_name}-{user_id}"
    log_task(task_id, user_id, agent_name, content[:200], status='processing')

    try:
        reply = _call_openclaw(agent_cfg['url'], content, session_key,
                               timeout=OPENCLAW_TIMEOUT, container=agent_cfg['container'])
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
    resp = requests.post(response_url, json=payload, timeout=10)
    logger.info(f"✅ [{agent_name}] 主动回复: {resp.status_code}, 长度: {len(reply)}")


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
    logger.info(f"✅ 消息已入队: {queue_key}, task_id={task_id}, 队列长度={qsize}")


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
            logger.error(f"[{agent_name}] ❌ 签名验证失败")
            return "signature verification failed", 403
        decrypted = crypto.decrypt(echo_str)
        if not decrypted:
            logger.error(f"[{agent_name}] ❌ 解密失败")
            return "decryption failed", 500
        logger.info(f"[{agent_name}] ✅ 回调验证成功")
        return decrypted

    # POST：接收消息（JSON 格式）
    if request.method == 'POST':
        try:
            body = request.get_json(force=True)
            logger.info(f"[{agent_name}] 收到 POST body: {str(body)[:200]}")
            encrypt_msg = body.get('encrypt', '')

            if not crypto.verify_signature(msg_signature, timestamp, nonce, encrypt_msg):
                logger.error(f"[{agent_name}] ❌ 消息签名验证失败")
                return jsonify({}), 403

            decrypted = crypto.decrypt(encrypt_msg)
            if not decrypted:
                logger.error(f"[{agent_name}] ❌ 消息解密失败")
                return jsonify({}), 500

            msg = json.loads(decrypted)
            logger.info(f"[{agent_name}] 📩 解密消息: {json.dumps(msg, ensure_ascii=False)[:300]}")

            msg_type = msg.get('msgtype', '')
            msgid = msg.get('msgid', '')
            from_user = msg.get('from', {}).get('userid', '')
            response_url = msg.get('response_url', '')

            if msg_type == 'stream':
                return jsonify({}), 200

            if msgid and is_duplicate_msg(msgid):
                logger.info(f"[{agent_name}] ⚠️  重复消息已跳过: {msgid}")
                return jsonify({}), 200

            if msg_type in ('text', 'image', 'file', 'voice', 'mixed'):
                content = extract_message_content(msg, user_id=from_user,
                                                  encoding_aes_key=agent_cfg['wecom_encoding_aes_key'])
                logger.info(f"[{agent_name}] 消息内容: {content[:200]}, from: {from_user}")

                task_id = str(uuid.uuid4())

                processing_msg = json.dumps({"msgtype": "markdown", "markdown": {"content": "⏳ 正在处理，请稍候..."}})
                reply_pkg = crypto.build_reply(processing_msg, int(timestamp), nonce)

                process_message_async(from_user, content, task_id, response_url, agent_name)

                if reply_pkg:
                    return jsonify(reply_pkg), 200
                return jsonify({}), 200

            else:
                logger.info(f"[{agent_name}] ⚠️  忽略消息类型: {msg_type}")
                return jsonify({}), 200

        except Exception as e:
            logger.error(f"[{agent_name}] ❌ 处理消息失败: {e}")
            return jsonify({}), 500


@app.route('/wecom/callback', methods=['GET', 'POST'])
def wecom_callback_legacy():
    """
    兼容旧版路径的回调接口
    自动路由到第一个启用的 Agent（临时兼容方案）
    
    ⚠️  建议：修改企业微信回调 URL 为 /{agent_name}/wecom/callback
    """
    if not AGENTS:
        logger.error("没有启用任何 Agent")
        return jsonify({'error': 'no agents enabled'}), 500
    
    # 使用第一个启用的 Agent（或根据其他逻辑选择）
    default_agent = list(AGENTS.keys())[0]
    logger.warning(f"⚠️  使用旧版路径 /wecom/callback，自动路由到: {default_agent}")
    logger.warning(f"⚠️  建议修改企业微信回调 URL 为: /{default_agent}/wecom/callback")
    
    # 重定向到对应的 agent 路由处理
    return wecom_callback(default_agent)


@app.route('/health', methods=['GET'])
def health():
    """健康检查接口"""
    return jsonify({
        'status': 'healthy',
        'timestamp': int(time.time()),
        'service': 'openclaw-wecom-gateway',
        'agents': {name: {'url': cfg['url'], 'port': cfg['port']} for name, cfg in AGENTS.items()}
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


if __name__ == '__main__':
    logger.info("=" * 60)
    logger.info("OpenClaw 企业微信网关启动中...")
    logger.info("=" * 60)

    # 配置检查
    validate_agents()

    logger.info(f"✅ 数据库路径: {DB_PATH}")
    logger.info(f"✅ 通信协议: {OPENCLAW_PROTOCOL}")
    logger.info(f"✅ 已启用 {len(AGENTS)} 个 Agent:")
    for name, cfg in AGENTS.items():
        logger.info(f"   - {name}: {cfg['url']} (容器: {cfg['container']})")
    logger.info("=" * 60)

    app.run(host='0.0.0.0', port=8000, debug=False)
