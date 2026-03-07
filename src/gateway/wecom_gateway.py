from flask import Flask, request, jsonify
import hashlib
import sqlite3
import uuid
import time
import os
import logging
import json
import base64
import shutil
import tempfile
from Crypto.Cipher import AES
import struct
import ssl
import requests
from datetime import datetime, timedelta, timezone
import threading
import queue
from collections import deque
import mimetypes
import zipfile
import websocket

try:
    import boto3
    from botocore.config import Config as BotoConfig
    from botocore.exceptions import BotoCoreError, ClientError
except Exception:
    boto3 = None
    BotoConfig = None
    BotoCoreError = Exception
    ClientError = Exception

app = Flask(__name__)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

LOCAL_SHARED_ROOT = '/app/shared'


_REQUESTS_VERIFY_PATH = None
_REQUESTS_VERIFY_FAILED = False


def _is_valid_ca_path(path):
    return bool(path) and os.path.exists(path)


def _resolve_requests_verify():
    """解析 requests 使用的 CA 路径，优先返回显式有效路径，避免遗留 certifi 路径导致失败"""
    global _REQUESTS_VERIFY_PATH, _REQUESTS_VERIFY_FAILED

    if _is_valid_ca_path(_REQUESTS_VERIFY_PATH):
        return _REQUESTS_VERIFY_PATH

    candidates = []
    seen = set()

    def add_candidate(path):
        normalized = (path or '').strip()
        if not normalized or normalized in seen:
            return
        seen.add(normalized)
        candidates.append(normalized)

    for env_key in ('REQUESTS_CA_BUNDLE', 'SSL_CERT_FILE', 'CURL_CA_BUNDLE'):
        env_value = os.getenv(env_key, '').strip()
        if env_value and not _is_valid_ca_path(env_value):
            logger.warning(f"检测到无效 {env_key}={env_value}，已忽略并回退系统证书")
            os.environ.pop(env_key, None)
            continue
        add_candidate(env_value)

    try:
        import requests.adapters as req_adapters
        add_candidate(getattr(req_adapters, 'DEFAULT_CA_BUNDLE_PATH', ''))
    except Exception:
        req_adapters = None

    try:
        import requests.certs as req_certs
        add_candidate(req_certs.where())
    except Exception:
        pass

    try:
        import certifi
        add_candidate(certifi.where())
    except Exception:
        pass

    try:
        default_paths = ssl.get_default_verify_paths()
        add_candidate(default_paths.cafile)
        add_candidate(default_paths.capath)
        add_candidate(default_paths.openssl_cafile)
        add_candidate(default_paths.openssl_capath)
    except Exception as e:
        logger.warning(f"读取系统 TLS 默认路径失败: {e}")

    fallback_paths = [
        '/etc/ssl/certs/ca-certificates.crt',
        '/etc/pki/tls/certs/ca-bundle.crt',
        '/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem',
        '/etc/ssl/cert.pem',
        '/etc/ssl/certs',
    ]
    for path in fallback_paths:
        add_candidate(path)

    for path in candidates:
        if _is_valid_ca_path(path):
            _REQUESTS_VERIFY_PATH = path
            if req_adapters is not None:
                req_adapters.DEFAULT_CA_BUNDLE_PATH = path
            return path

    if not _REQUESTS_VERIFY_FAILED:
        logger.error("未找到可用系统 CA 证书文件或目录，HTTPS 请求可能失败")
        _REQUESTS_VERIFY_FAILED = True
    return True


def _sanitize_requests_tls_env():
    """启动时预热 TLS 证书路径解析，尽早清理遗留环境变量"""
    _resolve_requests_verify()


def _requests_request(method, url, **kwargs):
    """统一 requests 调用，显式指定 verify，避免被遗留环境变量覆盖"""
    kwargs.setdefault('verify', _resolve_requests_verify())
    return requests.request(method, url, **kwargs)


_sanitize_requests_tls_env()

# ============= 配置（从环境变量读取）=============

# 数据库配置
DB_PATH = os.getenv('DB_PATH', '/opt/openclaw/data/gateway/gateway.db')

# 通信协议（全局默认）
OPENCLAW_TIMEOUT = int(os.getenv('OPENCLAW_TIMEOUT', '180'))
OPENCLAW_PROTOCOL = os.getenv('OPENCLAW_PROTOCOL', 'ws')


def _read_positive_int_env(name, default_value):
    """读取正整数环境变量，非法值回退默认值"""
    raw_value = os.getenv(name, str(default_value)).strip()
    try:
        value = int(raw_value)
    except ValueError:
        logger.warning(f"环境变量 {name} 非法: {raw_value}，回退默认值 {default_value}")
        return default_value
    if value <= 0:
        logger.warning(f"环境变量 {name} 必须为正整数，回退默认值 {default_value}")
        return default_value
    return value


OPENCLAW_CONNECT_TIMEOUT = _read_positive_int_env('OPENCLAW_CONNECT_TIMEOUT', 10)
OPENCLAW_WS_IDLE_TIMEOUT = _read_positive_int_env('OPENCLAW_WS_IDLE_TIMEOUT', 30)
OPENCLAW_WS_TOTAL_TIMEOUT = _read_positive_int_env('OPENCLAW_WS_TOTAL_TIMEOUT', 180)
OPENCLAW_SSE_IDLE_TIMEOUT = _read_positive_int_env('OPENCLAW_SSE_IDLE_TIMEOUT', 30)
OPENCLAW_SSE_TOTAL_TIMEOUT = _read_positive_int_env('OPENCLAW_SSE_TOTAL_TIMEOUT', 180)
OPENCLAW_HTTP_TIMEOUT = _read_positive_int_env('OPENCLAW_HTTP_TIMEOUT', 180)

MAX_GATEWAY_WORKERS = _read_positive_int_env('MAX_GATEWAY_WORKERS', 8)
MAX_PER_USER_PENDING = _read_positive_int_env('MAX_PER_USER_PENDING', 1)
MAX_QUEUE_WAIT_SECONDS = _read_positive_int_env('MAX_QUEUE_WAIT_SECONDS', 60)

# Gateway 端口
GATEWAY_PORT = int(os.getenv('GATEWAY_PORT', '8000'))

# 文件存储模式（local | s3）
FILE_STORAGE_MODE = os.getenv('FILE_STORAGE_MODE', 'local').strip().lower()
VALID_FILE_STORAGE_MODES = {'local', 's3'}
if FILE_STORAGE_MODE not in VALID_FILE_STORAGE_MODES:
    logger.warning(f"未知 FILE_STORAGE_MODE={FILE_STORAGE_MODE}，回退 local")
    FILE_STORAGE_MODE = 'local'

# 预签名下载默认有效期（秒）
try:
    FILE_STORAGE_PRESIGN_EXPIRES = int(os.getenv('FILE_STORAGE_PRESIGN_EXPIRES', '86400'))
except ValueError:
    logger.warning("FILE_STORAGE_PRESIGN_EXPIRES 非法，使用默认 86400")
    FILE_STORAGE_PRESIGN_EXPIRES = 86400
FILE_STORAGE_PRESIGN_EXPIRES = max(1, FILE_STORAGE_PRESIGN_EXPIRES)

# Gateway 内部上传接口鉴权 Token（供 OpenClaw skill 调用）
FILE_UPLOAD_INTERNAL_TOKEN = os.getenv('FILE_UPLOAD_INTERNAL_TOKEN', '').strip()

# S3 配置（仅 FILE_STORAGE_MODE=s3 时生效）
S3_BUCKET = os.getenv('S3_BUCKET', '').strip()
S3_REGION = os.getenv('S3_REGION', 'us-east-1').strip()
S3_ENDPOINT_URL = os.getenv('S3_ENDPOINT_URL', '').strip()
S3_ACCESS_KEY_ID = os.getenv('S3_ACCESS_KEY_ID', '').strip()
S3_SECRET_ACCESS_KEY = os.getenv('S3_SECRET_ACCESS_KEY', '').strip()
S3_KEY_PREFIX = os.getenv('S3_KEY_PREFIX', 'openclaw-gateway').strip().strip('/')
FILE_STORAGE_KEY_PREFIX = os.getenv('FILE_STORAGE_KEY_PREFIX', S3_KEY_PREFIX or 'openclaw-gateway').strip().strip('/')
S3_SIGNATURE_VERSION = os.getenv('S3_SIGNATURE_VERSION', 's3').strip()
S3_ADDRESSING_STYLE = os.getenv('S3_ADDRESSING_STYLE', 'path').strip()
S3_SSE_MODE = os.getenv('S3_SSE_MODE', '').strip()
S3_SSE_KMS_KEY_ID = os.getenv('S3_SSE_KMS_KEY_ID', '').strip()

# OpenClaw skill 经 Gateway 上传时的文件大小限制（默认 50MB）
try:
    MAX_INTERNAL_UPLOAD_FILE_SIZE = int(os.getenv('MAX_INTERNAL_UPLOAD_FILE_SIZE', str(50 * 1024 * 1024)))
except ValueError:
    logger.warning("MAX_INTERNAL_UPLOAD_FILE_SIZE 非法，使用默认 50MB")
    MAX_INTERNAL_UPLOAD_FILE_SIZE = 50 * 1024 * 1024

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
    # 兼容旧版数据库：如果 shared_dir 列不存在则添加
    try:
        conn.execute("SELECT shared_dir FROM agents LIMIT 0")
    except sqlite3.OperationalError:
        conn.execute("ALTER TABLE agents ADD COLUMN shared_dir TEXT DEFAULT ''")
        conn.commit()
    rows = conn.execute(
        "SELECT name, display_name, wecom_token, wecom_aes_key, "
        "openclaw_url, openclaw_token, openclaw_agent_id, shared_dir FROM agents"
    ).fetchall()
    agents = {}
    for name, display, token, aes_key, url, oc_token, agent_id, shared_dir in rows:
        effective_agent_id = (agent_id or name or 'main').strip() or 'main'
        expected_shared_dir = os.path.join(LOCAL_SHARED_ROOT, name)
        configured_shared_dir = (shared_dir or '').strip()
        if agent_id and agent_id != name:
            logger.warning(f"[{name}] openclaw_agent_id 与路由名不一致，当前继续沿用 DB 中的 agent_id={agent_id}")
        if configured_shared_dir and os.path.normpath(configured_shared_dir) != os.path.normpath(expected_shared_dir):
            logger.warning(f"[{name}] shared_dir 与固定路径不一致，已改用 {expected_shared_dir}（原值: {configured_shared_dir}）")
        agents[name] = {
            'display_name': display,
            'wecom_token': token,
            'wecom_encoding_aes_key': aes_key,
            'openclaw_url': url,
            'openclaw_token': oc_token,
            'openclaw_agent_id': effective_agent_id,
            'shared_dir': expected_shared_dir,
        }
    conn.close()
    return agents


# 确保数据库目录存在
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

AGENTS = load_agents_from_db()


# ============= OpenClaw API 通用调用 =============


class OpenClawTimeoutError(Exception):
    """OpenClaw 调用超时"""

    def __init__(self, stage, message):
        super().__init__(message)
        self.stage = stage


def _timeout_message(stage, seconds):
    """格式化超时错误消息"""
    return f"openclaw {stage} 超时（{seconds}s）"

def _extract_reply_text(data):
    """从 /v1/responses 返回数据中提取文本"""
    texts = []
    for item in data.get('output', []):
        if item.get('type') == 'message':
            for c in item.get('content', []):
                if c.get('type') == 'output_text' and c.get('text'):
                    texts.append(c['text'])
    return '\n'.join(texts).strip()


def _call_openclaw_sse(url, message, session_key, timeout=None, token='', agent_id='main'):
    """单次 HTTP SSE 流式调用，返回回复文本。连接异常时抛出异常。"""
    start_time = time.monotonic()
    try:
        resp = _requests_request(
            'post',
            f"{url}/v1/responses",
            headers={
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json',
                'x-openclaw-agent-id': agent_id,
            },
            json={'model': 'openclaw', 'input': message, 'stream': True, 'user': session_key},
            timeout=(OPENCLAW_CONNECT_TIMEOUT, OPENCLAW_SSE_IDLE_TIMEOUT),
            stream=True,
        )
        resp.raise_for_status()
    except requests.exceptions.Timeout as e:
        raise OpenClawTimeoutError('sse_connect', _timeout_message('sse_connect', OPENCLAW_CONNECT_TIMEOUT)) from e

    final_data = None
    try:
        for line in resp.iter_lines(decode_unicode=True):
            if time.monotonic() - start_time > OPENCLAW_SSE_TOTAL_TIMEOUT:
                raise OpenClawTimeoutError('sse_total', _timeout_message('sse_total', OPENCLAW_SSE_TOTAL_TIMEOUT))
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
    except OpenClawTimeoutError:
        raise
    except requests.exceptions.Timeout as e:
        raise OpenClawTimeoutError('sse_idle', _timeout_message('sse_idle', OPENCLAW_SSE_IDLE_TIMEOUT)) from e

    if final_data:
        return _extract_reply_text(final_data)
    return ''


def _call_openclaw_http(url, message, session_key, timeout=None, token='', agent_id='main'):
    """同步 HTTP POST 调用，不使用流式，直接拿完整 JSON 响应"""
    try:
        resp = _requests_request(
            'post',
            f"{url}/v1/responses",
            headers={
                'Authorization': f'Bearer {token}',
                'Content-Type': 'application/json',
                'x-openclaw-agent-id': agent_id,
            },
            json={'model': 'openclaw', 'input': message, 'user': session_key},
            timeout=(OPENCLAW_CONNECT_TIMEOUT, OPENCLAW_HTTP_TIMEOUT),
        )
        resp.raise_for_status()
    except requests.exceptions.Timeout as e:
        raise OpenClawTimeoutError('http', _timeout_message('http', OPENCLAW_HTTP_TIMEOUT)) from e
    return _extract_reply_text(resp.json())


def _extract_ws_chat_text(message_obj):
    """从 WS chat message 中提取文本内容"""
    texts = []
    if not isinstance(message_obj, dict):
        return ''

    for item in message_obj.get('content', []):
        if not isinstance(item, dict):
            continue
        item_type = item.get('type')
        if item_type in ('text', 'output_text') and item.get('text'):
            texts.append(item['text'])
            continue
        if item_type == 'input_text' and item.get('text'):
            texts.append(item['text'])

    return '\n'.join(texts).strip()


def _merge_ws_stream_text(accumulated_text, last_piece, current_piece):
    """合并 WS 流式分段文本，兼容快照模式与增量模式"""
    current_piece = (current_piece or '').strip()
    if not current_piece:
        return accumulated_text

    if not accumulated_text:
        return current_piece

    # 快照模式：当前分段是此前内容的扩展
    if current_piece.startswith(accumulated_text):
        return current_piece

    # 回退/重复片段，忽略
    if accumulated_text.startswith(current_piece):
        return accumulated_text
    if current_piece == (last_piece or '').strip():
        return accumulated_text
    if accumulated_text.endswith(current_piece) or current_piece in accumulated_text:
        return accumulated_text

    # 增量模式：按顺序追加
    return accumulated_text + current_piece


def _call_openclaw_ws(url, message, session_key, timeout=None, token='', agent_id='main'):
    """WebSocket 协议调用：connect 握手 + chat.send，监听 chat state=final 获取回复"""
    ws_url = url.replace('http://', 'ws://').replace('https://', 'wss://') + '/ws'
    start_time = time.monotonic()
    try:
        ws = websocket.create_connection(ws_url, timeout=OPENCLAW_CONNECT_TIMEOUT)
    except Exception as e:
        err_msg = str(e).lower()
        if 'timed out' in err_msg or 'timeout' in err_msg:
            raise OpenClawTimeoutError('ws_connect', _timeout_message('ws_connect', OPENCLAW_CONNECT_TIMEOUT)) from e
        raise
    try:
        # 连接成功后切换到空闲超时（等待 Agent 处理）
        ws.settimeout(OPENCLAW_WS_IDLE_TIMEOUT)
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
        accumulated_text = ''
        last_piece = ''
        while True:
            if time.monotonic() - start_time > OPENCLAW_WS_TOTAL_TIMEOUT:
                raise OpenClawTimeoutError('ws_total', _timeout_message('ws_total', OPENCLAW_WS_TOTAL_TIMEOUT))
            try:
                raw = ws.recv()
            except websocket.WebSocketTimeoutException as e:
                raise OpenClawTimeoutError('ws_idle', _timeout_message('ws_idle', OPENCLAW_WS_IDLE_TIMEOUT)) from e
            evt = json.loads(raw)
            if evt.get('type') == 'event' and evt.get('event') == 'chat':
                payload = evt.get('payload', {})
                # 校验 sessionKey，忽略其他用户的 broadcast 事件
                evt_sk = (payload.get('sessionKey') or '').lower()
                if evt_sk and session_key.lower() not in evt_sk:
                    continue
                msg = payload.get('message', {})
                piece_text = _extract_ws_chat_text(msg)
                if piece_text:
                    accumulated_text = _merge_ws_stream_text(accumulated_text, last_piece, piece_text)
                    last_piece = piece_text
                if payload.get('state') == 'final':
                    final_text = piece_text.strip() if piece_text else ''
                    if final_text:
                        return final_text
                    if accumulated_text:
                        logger.warning("WS final 事件未携带完整文本，使用分段累计兜底")
                        return accumulated_text.strip()
                    return ''
            # RPC 错误
            if evt.get('type') == 'res' and evt.get('id') == req_id and not evt.get('ok'):
                raise Exception(f"WS RPC 错误: {evt.get('error')}")
    finally:
        ws.close()


def _call_openclaw(url, message, session_key, timeout=None, token='', agent_id='main'):
    """统一调用入口，根据 OPENCLAW_PROTOCOL 选择协议"""
    protocol = OPENCLAW_PROTOCOL.lower()

    if protocol == 'http':
        return _call_openclaw_http(url, message, session_key, timeout,
                                   token=token, agent_id=agent_id)

    elif protocol == 'ws':
        return _call_openclaw_ws(url, message, session_key, timeout,
                                 token=token, agent_id=agent_id)

    else:  # 默认 sse
        return _call_openclaw_sse(url, message, session_key, timeout,
                                  token=token, agent_id=agent_id)


_SANDBOX_MOUNT_ERROR_MARKERS = (
    'outside of container mount namespace root',
    'container breakout detected',
    'current working directory is outside',
    'mount namespace',
    '路径隔离问题',
    '挂载异常',
)


def _looks_like_sandbox_mount_error(reply_text):
    """判断回复文本是否包含沙箱路径挂载异常特征"""
    if not reply_text:
        return False
    text = reply_text.lower()
    for marker in _SANDBOX_MOUNT_ERROR_MARKERS:
        if marker.lower() in text:
            return True
    return False


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
            "INSERT OR IGNORE INTO task_logs (task_id, user_id, agent_id, task_content, status, result) VALUES (?, ?, ?, ?, ?, ?)",
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

WECOM_MSG_MAX_LEN = 20000  # 企业微信 markdown 消息限制 20480 字节，预留安全余量


def _utf8_len(text):
    """返回 UTF-8 字节长度"""
    return len((text or '').encode('utf-8'))


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


def _get_today_dir_for_agent(shared_dir):
    """获取当日文件目录（按 agent 共享目录），自动创建"""
    today = datetime.now().strftime('%Y-%m-%d')
    if shared_dir:
        path = os.path.join(shared_dir, today)
    else:
        path = os.path.join(FILES_BASE, today)
    os.makedirs(path, exist_ok=True)
    return path

# ============= 文件发布（local / s3） =============

_s3_client = None
_s3_client_lock = threading.Lock()


def _sanitize_storage_segment(value, fallback='unknown'):
    """规范化对象存储 key 片段"""
    if not value:
        return fallback
    cleaned = ''.join(ch if (ch.isalnum() or ch in ('-', '_', '.')) else '-' for ch in str(value))
    cleaned = cleaned.strip('-_.')
    return cleaned or fallback


def _resolve_presign_expires(expires_seconds=None):
    """解析预签名有效期，AWS S3 最大 7 天"""
    value = FILE_STORAGE_PRESIGN_EXPIRES if expires_seconds is None else expires_seconds
    try:
        value = int(value)
    except (TypeError, ValueError):
        value = FILE_STORAGE_PRESIGN_EXPIRES
    value = max(1, value)
    return min(value, 604800)


def _format_expires_at(expires_seconds):
    """将有效期秒数转换为 ISO8601 UTC 时间"""
    dt = datetime.now(timezone.utc) + timedelta(seconds=expires_seconds)
    return dt.isoformat()


def _build_storage_object_key(local_path, source='wecom', agent_name='default'):
    """构建对象存储 key"""
    ext = os.path.splitext(local_path)[1].lower() or '.bin'
    now = datetime.now().strftime('%Y/%m/%d')
    source_part = _sanitize_storage_segment(source, 'source')
    agent_part = _sanitize_storage_segment(agent_name, 'default')
    object_name = f"{uuid.uuid4().hex[:24]}{ext}"

    parts = []
    if FILE_STORAGE_KEY_PREFIX:
        parts.append(FILE_STORAGE_KEY_PREFIX)
    parts.extend([source_part, agent_part, now, object_name])
    return '/'.join(parts)


def _get_s3_client():
    """懒加载 S3 client"""
    global _s3_client

    if boto3 is None:
        raise RuntimeError('boto3 未安装，无法使用 S3 模式')

    with _s3_client_lock:
        if _s3_client is not None:
            return _s3_client

        if not S3_BUCKET:
            raise RuntimeError('S3_BUCKET 未配置')

        kwargs = {}
        if S3_REGION:
            kwargs['region_name'] = S3_REGION
        if S3_ENDPOINT_URL:
            kwargs['endpoint_url'] = S3_ENDPOINT_URL
        if S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY:
            kwargs['aws_access_key_id'] = S3_ACCESS_KEY_ID
            kwargs['aws_secret_access_key'] = S3_SECRET_ACCESS_KEY

        if BotoConfig is not None:
            kwargs['config'] = BotoConfig(
                signature_version=S3_SIGNATURE_VERSION or 's3v4',
                s3={'addressing_style': S3_ADDRESSING_STYLE or 'virtual'}
            )

        _s3_client = boto3.client('s3', **kwargs)
        return _s3_client


def _path_is_within(path, parent_dir):
    """判断 path 是否位于 parent_dir 内"""
    path_abs = os.path.abspath(path)
    parent_abs = os.path.abspath(parent_dir)
    return path_abs == parent_abs or path_abs.startswith(parent_abs + os.sep)


def _ensure_local_file_in_shared_dir(local_path, shared_dir):
    """local 模式下确保文件最终位于 agent 共享目录中"""
    host_path = os.path.abspath(local_path)
    if not shared_dir or _path_is_within(host_path, shared_dir):
        return host_path

    target_dir = _get_today_dir_for_agent(shared_dir)
    file_name = os.path.basename(host_path)
    base_name, ext = os.path.splitext(file_name)
    target_path = os.path.join(target_dir, file_name)
    counter = 1

    while os.path.exists(target_path):
        if os.path.abspath(target_path) == host_path:
            return host_path
        target_path = os.path.join(target_dir, f"{base_name}-{counter}{ext}")
        counter += 1

    shutil.move(host_path, target_path)
    logger.info(f"local 文件已移动到共享目录: {target_path}")
    return target_path


def _publish_file_local(local_path, shared_dir=''):
    """local 模式：返回 agent 可直接访问的绝对路径"""
    host_path = _ensure_local_file_in_shared_dir(local_path, shared_dir)
    return {
        'storage_mode': 'local',
        'storage_uri': f"file://{host_path}",
        'download_url': '',
        'expires_at': '',
        'display_value': host_path,
    }


NON_ACTIONABLE_MESSAGE_NOTICES = {
    '[用户发送了一张图片，但无法获取]',
    '[用户发送了一张图片，上传失败]',
    '[用户发送了一张图片，下载失败]',
    '[用户发送了一个文件，但无法获取]',
    '[用户发送了一个文件，文件有风险，已删除]',
    '[用户发送了一个文件，下载失败]',
    '[用户发送了一个文件，上传失败]',
}

USER_VISIBLE_NOTICE_MAP = {
    '[用户发送了一张图片，但无法获取]': '收到图片，但暂时无法获取图片内容，请稍后重试。',
    '[用户发送了一张图片，上传失败]': '收到图片，但保存失败，请稍后重试。',
    '[用户发送了一张图片，下载失败]': '收到图片，但下载失败，请稍后重试。',
    '[用户发送了一个文件，但无法获取]': '收到文件，但暂时无法获取文件内容，请稍后重试。',
    '[用户发送了一个文件，文件有风险，已删除]': '收到文件，但检测到安全风险，系统已拒绝处理。',
    '[用户发送了一个文件，下载失败]': '收到文件，但下载失败，请稍后重试。',
    '[用户发送了一个文件，上传失败]': '收到文件，但保存失败，请稍后重试。',
}


def _dedupe_keep_order(items):
    """按出现顺序去重"""
    seen = set()
    result = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def _is_non_actionable_notice_line(line):
    """判断一行提取文本是否只是系统提示，不应继续发送给 agent"""
    stripped = (line or '').strip()
    if not stripped:
        return False
    return stripped in NON_ACTIONABLE_MESSAGE_NOTICES or stripped.startswith('[不支持的消息类型:')


def _split_actionable_content_and_notices(content):
    """拆分可发送正文与系统提示"""
    if content is None:
        return '', []

    text = str(content)
    actionable_lines = []
    notices = []
    for line in text.splitlines():
        if _is_non_actionable_notice_line(line):
            notices.append(line.strip())
            continue
        actionable_lines.append(line)

    actionable_text = '\n'.join(actionable_lines).strip()
    return actionable_text, _dedupe_keep_order(notices)


def _render_user_visible_notices(notices):
    """将内部系统提示转换为用户可读回复"""
    rendered = []
    for notice in _dedupe_keep_order(notices):
        rendered.append(USER_VISIBLE_NOTICE_MAP.get(notice, notice))
    return '\n'.join(rendered)


def _publish_file_s3(local_path, object_key, content_type='', expires_seconds=None):
    """s3 模式：上传并返回预签名下载链接"""
    client = _get_s3_client()
    expires_seconds = _resolve_presign_expires(expires_seconds)
    extra_args = {}
    if content_type:
        extra_args['ContentType'] = content_type
    if S3_SSE_MODE:
        extra_args['ServerSideEncryption'] = S3_SSE_MODE
        if S3_SSE_MODE.lower() == 'aws:kms' and S3_SSE_KMS_KEY_ID:
            extra_args['SSEKMSKeyId'] = S3_SSE_KMS_KEY_ID

    if extra_args:
        client.upload_file(local_path, S3_BUCKET, object_key, ExtraArgs=extra_args)
    else:
        client.upload_file(local_path, S3_BUCKET, object_key)

    download_url = client.generate_presigned_url(
        ClientMethod='get_object',
        Params={'Bucket': S3_BUCKET, 'Key': object_key},
        ExpiresIn=expires_seconds,
        HttpMethod='GET',
    )

    return {
        'storage_mode': 's3',
        'storage_uri': f"s3://{S3_BUCKET}/{object_key}",
        'download_url': download_url,
        'expires_at': _format_expires_at(expires_seconds),
        'display_value': download_url,
    }


def publish_file(local_path, shared_dir='', user_id='', msg_type='', source_url='', agent_name='',
                 content_type='', source='wecom', expires_seconds=None):
    """统一文件发布入口：按模式发布并返回引用信息"""
    object_key = _build_storage_object_key(local_path, source=source, agent_name=agent_name or 'default')

    if FILE_STORAGE_MODE == 'local':
        return _publish_file_local(local_path, shared_dir=shared_dir)
    if FILE_STORAGE_MODE == 's3':
        return _publish_file_s3(local_path, object_key=object_key,
                                content_type=content_type, expires_seconds=expires_seconds)
    raise RuntimeError(f'不支持的 FILE_STORAGE_MODE: {FILE_STORAGE_MODE}')


def _format_link_with_expire(publish_result):
    """格式化带过期时间提示的下载链接"""
    download_url = publish_result.get('download_url', '')
    expires_at = publish_result.get('expires_at', '')
    if not download_url:
        return publish_result.get('display_value', '')
    if expires_at:
        return f"{download_url}（过期时间: {expires_at}）"
    return download_url


# ============= 多类型消息处理 =============

TEXT_EXTENSIONS = {'.txt', '.md', '.csv', '.json', '.xml', '.yaml', '.yml', '.py', '.js', '.ts',
                   '.java', '.go', '.rs', '.rb', '.php', '.sh', '.bash', '.sql', '.html', '.css',
                   '.conf', '.cfg', '.ini', '.toml', '.log', '.env', '.properties'}
TEXT_CONTENT_TYPES = {'text/', 'application/json', 'application/xml', 'application/yaml',
                      'application/x-yaml', 'application/toml', 'application/sql'}
MAX_TEXT_EMBED_SIZE = 50 * 1024  # 50KB
MAX_DOWNLOAD_FILE_SIZE = int(os.getenv('MAX_DOWNLOAD_FILE_SIZE', str(20 * 1024 * 1024)))  # 20MB
DOWNLOAD_CHUNK_SIZE = 64 * 1024

DEFAULT_RISKY_FILE_EXTENSIONS = {
    '.docm', '.dotx', '.dotm',
    '.xlsm', '.xltx', '.xltm', '.xlsb',
    '.pptm', '.potx', '.potm', '.ppsx', '.ppsm',
}


def _load_risky_file_extensions():
    """从环境变量加载高风险扩展名；为空时使用默认值"""
    raw = os.getenv('RISKY_FILE_EXTENSIONS', '').strip()
    if not raw:
        return set(DEFAULT_RISKY_FILE_EXTENSIONS)

    result = set()
    for item in raw.split(','):
        ext = item.strip().lower()
        if not ext:
            continue
        if not ext.startswith('.'):
            ext = '.' + ext
        result.add(ext)
    return result or set(DEFAULT_RISKY_FILE_EXTENSIONS)


RISKY_FILE_EXTENSIONS = _load_risky_file_extensions()


def _detect_file_type(local_path, content_type):
    """当 Content-Type 不可靠（octet-stream/zip）时，通过内容探测真实类型"""
    if content_type not in {'application/octet-stream', 'application/zip'}:
        return content_type, mimetypes.guess_extension(content_type) or ''

    MAGIC_SIGNATURES = [
        (b'\x89PNG\r\n\x1a\n', 'image/png', '.png'),
        (b'\xff\xd8\xff', 'image/jpeg', '.jpg'),
        (b'GIF87a', 'image/gif', '.gif'),
        (b'GIF89a', 'image/gif', '.gif'),
        (b'BM', 'image/bmp', '.bmp'),
        (b'II*\x00', 'image/tiff', '.tiff'),
        (b'MM\x00*', 'image/tiff', '.tiff'),
        (b'%PDF', 'application/pdf', '.pdf'),
        (b'PK\x03\x04', 'application/zip', '.zip'),
        (b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1', 'application/x-ole-storage', '.doc'),
        (b'\x1f\x8b', 'application/gzip', '.gz'),
        (b'Rar!\x1a\x07', 'application/x-rar', '.rar'),
    ]
    try:
        with open(local_path, 'rb') as f:
            header = f.read(16)

        if len(header) >= 12 and header[:4] == b'RIFF' and header[8:12] == b'WEBP':
            return 'image/webp', '.webp'

        if len(header) >= 12 and header[4:8] == b'ftyp':
            brand = header[8:12].decode('ascii', errors='ignore').lower()
            if brand in {'avif', 'avis'}:
                return 'image/avif', '.avif'
            if brand in {'heif', 'mif3'}:
                return 'image/heif', '.heif'
            if brand in {'heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1'}:
                return 'image/heif', '.heic'

        for magic, ct, ext in MAGIC_SIGNATURES:
            if header.startswith(magic):
                if magic == b'PK\x03\x04':
                    package_type = _detect_zip_package_type(local_path)
                    if package_type is not None:
                        return package_type

                    name_lower = local_path.lower()
                    if name_lower.endswith('.docx'):
                        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', '.docx'
                    if name_lower.endswith('.xlsx'):
                        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.xlsx'
                    if name_lower.endswith('.pptx'):
                        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation', '.pptx'
                if magic == b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1':
                    ole_type = _detect_ole_document_type(local_path)
                    if ole_type is not None:
                        return ole_type
                    return 'application/x-ole-storage', '.ole'
                return ct, ext
    except Exception:
        pass

    try:
        with open(local_path, 'rb') as f:
            sample = f.read(8192)
        text = sample.decode('utf-8', errors='ignore').lower()
        if '<mxfile' in text:
            return 'application/vnd.jgraph.mxfile', '.drawio'
        if '<svg' in text:
            return 'image/svg+xml', '.svg'
        if text.lstrip().startswith('{\\rtf'):
            return 'application/rtf', '.rtf'
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


def _detect_zip_package_type(local_path):
    """从 zip 容器结构识别常见文档包类型（OOXML/Visio/iWork/OpenDocument）"""
    try:
        if not zipfile.is_zipfile(local_path):
            return None

        with zipfile.ZipFile(local_path, 'r') as zf:
            zip_names = zf.namelist()
            names = [name.lower() for name in zip_names]

            content_types_entry = None
            for original_name in zip_names:
                if original_name.lower() == '[content_types].xml':
                    content_types_entry = original_name
                    break

            if content_types_entry is not None:
                raw = zf.read(content_types_entry).decode('utf-8', errors='ignore').lower()

                if 'ms-word.template.macroenabled' in raw:
                    return 'application/vnd.ms-word.template.macroenabled.12', '.dotm'
                if 'ms-word.document.macroenabled' in raw:
                    return 'application/vnd.ms-word.document.macroenabled.12', '.docm'

                if 'ms-excel.sheet.binary.macroenabled' in raw:
                    return 'application/vnd.ms-excel.sheet.binary.macroenabled.12', '.xlsb'
                if 'ms-excel.template.macroenabled' in raw:
                    return 'application/vnd.ms-excel.template.macroenabled.12', '.xltm'
                if 'ms-excel.sheet.macroenabled' in raw:
                    return 'application/vnd.ms-excel.sheet.macroenabled.12', '.xlsm'

                if 'ms-powerpoint.slideshow.macroenabled' in raw:
                    return 'application/vnd.ms-powerpoint.slideshow.macroenabled.12', '.ppsm'
                if 'ms-powerpoint.template.macroenabled' in raw:
                    return 'application/vnd.ms-powerpoint.template.macroenabled.12', '.potm'
                if 'ms-powerpoint.presentation.macroenabled' in raw:
                    return 'application/vnd.ms-powerpoint.presentation.macroenabled.12', '.pptm'

                has_macro = 'macroenabled' in raw
                if 'wordprocessingml.template' in raw:
                    if has_macro:
                        return 'application/vnd.ms-word.template.macroenabled.12', '.dotm'
                    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.template', '.dotx'
                if 'wordprocessingml.document' in raw:
                    if has_macro:
                        return 'application/vnd.ms-word.document.macroenabled.12', '.docm'
                    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', '.docx'

                if 'sheet.binary' in raw and has_macro:
                    return 'application/vnd.ms-excel.sheet.binary.macroenabled.12', '.xlsb'
                if 'spreadsheetml.template' in raw:
                    if has_macro:
                        return 'application/vnd.ms-excel.template.macroenabled.12', '.xltm'
                    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.template', '.xltx'
                if 'spreadsheetml.sheet' in raw:
                    if has_macro:
                        return 'application/vnd.ms-excel.sheet.macroenabled.12', '.xlsm'
                    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.xlsx'

                if 'presentationml.slideshow' in raw:
                    if has_macro:
                        return 'application/vnd.ms-powerpoint.slideshow.macroenabled.12', '.ppsm'
                    return 'application/vnd.openxmlformats-officedocument.presentationml.slideshow', '.ppsx'
                if 'presentationml.template' in raw:
                    if has_macro:
                        return 'application/vnd.ms-powerpoint.template.macroenabled.12', '.potm'
                    return 'application/vnd.openxmlformats-officedocument.presentationml.template', '.potx'
                if 'presentationml.presentation' in raw:
                    if has_macro:
                        return 'application/vnd.ms-powerpoint.presentation.macroenabled.12', '.pptm'
                    return 'application/vnd.openxmlformats-officedocument.presentationml.presentation', '.pptx'

                if 'visio' in raw:
                    return 'application/vnd.visio', '.vsdx'

            if any(name.startswith('word/') for name in names):
                return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', '.docx'
            if any(name.startswith('xl/') for name in names):
                return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', '.xlsx'
            if any(name.startswith('ppt/') for name in names):
                return 'application/vnd.openxmlformats-officedocument.presentationml.presentation', '.pptx'
            if any(name.startswith('visio/') for name in names):
                return 'application/vnd.visio', '.vsdx'

            if 'mimetype' in names:
                try:
                    mimetype_raw = zf.read('mimetype').decode('utf-8', errors='ignore').strip().lower()
                    odf_map = {
                        'application/vnd.oasis.opendocument.text': ('application/vnd.oasis.opendocument.text', '.odt'),
                        'application/vnd.oasis.opendocument.spreadsheet': ('application/vnd.oasis.opendocument.spreadsheet', '.ods'),
                        'application/vnd.oasis.opendocument.presentation': ('application/vnd.oasis.opendocument.presentation', '.odp'),
                    }
                    if mimetype_raw in odf_map:
                        return odf_map[mimetype_raw]
                except Exception:
                    pass

            if any(name.startswith('index/tables/') for name in names):
                return 'application/vnd.apple.numbers', '.numbers'
            if any(name.startswith('index/templateslide') for name in names) or any(name.startswith('index/slide-') for name in names):
                return 'application/vnd.apple.keynote', '.key'
            if 'index/document.iwa' in names and any(name.startswith('metadata/') for name in names):
                return 'application/vnd.apple.pages', '.pages'
    except Exception:
        return None

    return None


def _get_ole_stream_names(raw):
    """最小化解析 OLE CFB 目录，提取流名称集合"""
    try:
        if len(raw) < 512 or raw[:8] != b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1':
            return set()

        FREESECT = 0xFFFFFFFF
        ENDOFCHAIN = 0xFFFFFFFE

        sector_shift = struct.unpack_from('<H', raw, 30)[0]
        sector_size = 1 << sector_shift
        if sector_size <= 0 or sector_size > 4096:
            return set()

        first_dir_sector = struct.unpack_from('<I', raw, 48)[0]
        difat = list(struct.unpack_from('<109I', raw, 76))
        fat_sectors = [x for x in difat if x not in (FREESECT, ENDOFCHAIN)]

        fat = []
        for sec in fat_sectors:
            off = (sec + 1) * sector_size
            if off < 0 or off + sector_size > len(raw):
                continue
            chunk = raw[off:off + sector_size]
            fat.extend(struct.unpack('<%dI' % (sector_size // 4), chunk))

        if not fat:
            return set()

        chain = []
        cur = first_dir_sector
        visited = set()
        while cur not in (ENDOFCHAIN, FREESECT) and cur < len(fat) and cur not in visited:
            visited.add(cur)
            chain.append(cur)
            cur = fat[cur]

        directory = bytearray()
        for sec in chain:
            off = (sec + 1) * sector_size
            if off < 0 or off + sector_size > len(raw):
                continue
            directory.extend(raw[off:off + sector_size])

        names = set()
        for i in range(0, len(directory), 128):
            entry = directory[i:i + 128]
            if len(entry) < 128:
                break
            name_len = struct.unpack_from('<H', entry, 64)[0]
            obj_type = entry[66]
            if obj_type == 0 or name_len < 2:
                continue
            name_raw = entry[:max(0, name_len - 2)]
            name = name_raw.decode('utf-16le', errors='ignore')
            if name:
                names.add(name)
        return names
    except Exception:
        return set()


def _detect_ole_document_type(local_path):
    """识别 OLE 复合文档（doc/xls/ppt）"""
    try:
        with open(local_path, 'rb') as f:
            raw = f.read()
    except Exception:
        return None

    stream_names = _get_ole_stream_names(raw)
    if 'VisioDocument' in stream_names:
        return 'application/vnd.visio', '.vsd'
    if 'WordDocument' in stream_names:
        return 'application/msword', '.doc'
    if 'Workbook' in stream_names or 'Book' in stream_names:
        return 'application/vnd.ms-excel', '.xls'
    if 'PowerPoint Document' in stream_names:
        return 'application/vnd.ms-powerpoint', '.ppt'
    if {'MatOST', 'MM', 'MN0'}.issubset(stream_names):
        return 'application/vnd.ms-works', '.wps'

    markers = [
        (b'WordDocument', b'W\x00o\x00r\x00d\x00D\x00o\x00c\x00u\x00m\x00e\x00n\x00t\x00',
         ('application/msword', '.doc')),
        (b'Workbook', b'W\x00o\x00r\x00k\x00b\x00o\x00o\x00k\x00',
         ('application/vnd.ms-excel', '.xls')),
        (b'Book', b'B\x00o\x00o\x00k\x00',
         ('application/vnd.ms-excel', '.xls')),
        (b'VisioDocument', b'V\x00i\x00s\x00i\x00o\x00D\x00o\x00c\x00u\x00m\x00e\x00n\x00t\x00',
         ('application/vnd.visio', '.vsd')),
        (b'PowerPoint Document', b'P\x00o\x00w\x00e\x00r\x00P\x00o\x00i\x00n\x00t\x00 \x00D\x00o\x00c\x00u\x00m\x00e\x00n\x00t\x00',
         ('application/vnd.ms-powerpoint', '.ppt')),
    ]

    for ascii_marker, utf16_marker, result in markers:
        if ascii_marker in raw or utf16_marker in raw:
            return result
    return None


def _is_risky_file_extension(ext):
    """判断文件扩展名是否属于高风险类型"""
    if not ext:
        return False
    return ext.lower() in RISKY_FILE_EXTENSIONS


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


def download_temp_file(url, prefix='file', user_id='', msg_type='', encoding_aes_key='', shared_dir=''):
    """下载临时 COS URL 到文件目录（按日期分区）
    返回 (local_path, text_content_or_none, status)
    
    如果 shared_dir 已设置，文件保存到该 agent 的固定绝对路径共享目录。
    返回的 local_path 为可直接下发给 agent 的绝对路径。
    status: ok | risky_deleted
    """
    tmp_path = None
    try:
        today_dir = _get_today_dir_for_agent(shared_dir)
        resp = _requests_request('get', url, timeout=30, stream=True)
        resp.raise_for_status()

        tmp_filename = f"{prefix}-{uuid.uuid4().hex[:8]}.tmp"
        tmp_path = os.path.join(today_dir, tmp_filename)

        total_size = 0
        with open(tmp_path, 'wb') as f:
            for chunk in resp.iter_content(chunk_size=DOWNLOAD_CHUNK_SIZE):
                if not chunk:
                    continue
                total_size += len(chunk)
                if total_size > MAX_DOWNLOAD_FILE_SIZE:
                    raise Exception(f"文件过大，超过限制 {MAX_DOWNLOAD_FILE_SIZE} bytes")
                f.write(chunk)

        if encoding_aes_key:
            with open(tmp_path, 'rb') as f:
                encrypted_data = f.read()

            decrypted = _decrypt_file(encrypted_data, encoding_aes_key)
            if decrypted is None:
                logger.warning("文件解密失败，使用原始数据")
                decrypted = encrypted_data

            with open(tmp_path, 'wb') as f:
                f.write(decrypted)

        raw_content_type = resp.headers.get('Content-Type', 'application/octet-stream').split(';')[0].strip()
        content_type, ext = _detect_file_type(tmp_path, raw_content_type)
        if ext == '.jpe':
            ext = '.jpg'

        if _is_risky_file_extension(ext):
            logger.warning(f"检测到高风险文件类型 {ext}，已删除: {tmp_path}")
            try:
                os.remove(tmp_path)
            except Exception:
                pass
            return None, None, 'risky_deleted'

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
        return local_path, text_content, 'ok'
    except Exception as e:
        logger.error(f"下载文件失败: {e}")
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass
        return None, None, 'error'

def extract_single_content(item, user_id='', encoding_aes_key='', shared_dir='', agent_name=''):
    """提取单条消息内容（主消息或 quote 内的消息），返回文本描述
    
    shared_dir: agent 的共享文件目录。设置后文件保存到此目录，并直接下发绝对路径。
    """
    msg_type = item.get('msgtype', '')

    if msg_type == 'text':
        return item.get('text', {}).get('content', '')

    elif msg_type == 'voice':
        return item.get('voice', {}).get('content', '')

    elif msg_type == 'image':
        url = item.get('image', {}).get('url', '')
        if not url:
            return '[用户发送了一张图片，但无法获取]'
        path, _, _ = download_temp_file(url, prefix='img', user_id=user_id, msg_type='image',
                                        encoding_aes_key=encoding_aes_key, shared_dir=shared_dir)
        if path:
            try:
                raw_content_type = mimetypes.guess_type(path)[0] or 'application/octet-stream'
                content_type, _ = _detect_file_type(path, raw_content_type)
                publish_result = publish_file(
                    path,
                    shared_dir=shared_dir,
                    user_id=user_id,
                    msg_type='image',
                    source_url=url,
                    agent_name=agent_name,
                    content_type=content_type,
                    source='wecom-image',
                )
            except Exception as e:
                logger.error(f"图片发布失败: {e}")
                return '[用户发送了一张图片，上传失败]'

            if FILE_STORAGE_MODE == 'local':
                return f"[用户发送了一张图片，已保存到 {publish_result.get('display_value', path)}]"

            link_text = _format_link_with_expire(publish_result)
            return f"[用户发送了一张图片，下载链接: {link_text}]"
        return '[用户发送了一张图片，下载失败]'

    elif msg_type == 'file':
        url = item.get('file', {}).get('url', '')
        if not url:
            return '[用户发送了一个文件，但无法获取]'
        path, text_content, status = download_temp_file(url, prefix='file', user_id=user_id, msg_type='file',
                                                        encoding_aes_key=encoding_aes_key, shared_dir=shared_dir)
        if status == 'risky_deleted':
            return '[用户发送了一个文件，文件有风险，已删除]'
        if not path:
            return '[用户发送了一个文件，下载失败]'

        try:
            raw_content_type = mimetypes.guess_type(path)[0] or 'application/octet-stream'
            content_type, _ = _detect_file_type(path, raw_content_type)
            publish_result = publish_file(
                path,
                shared_dir=shared_dir,
                user_id=user_id,
                msg_type='file',
                source_url=url,
                agent_name=agent_name,
                content_type=content_type,
                source='wecom-file',
            )
        except Exception as e:
            logger.error(f"文件发布失败: {e}")
            return '[用户发送了一个文件，上传失败]'

        if text_content is not None:
            if FILE_STORAGE_MODE == 'local':
                return f"[用户发送了一个文本文件 {publish_result.get('display_value', path)}]\n文件内容：\n{text_content}"
            link_text = _format_link_with_expire(publish_result)
            return f"[用户发送了一个文本文件，下载链接: {link_text}]\n文件内容：\n{text_content}"

        if FILE_STORAGE_MODE == 'local':
            return f"[用户发送了一个文件，已保存到 {publish_result.get('display_value', path)}]"

        link_text = _format_link_with_expire(publish_result)
        return f"[用户发送了一个文件，下载链接: {link_text}]"

    elif msg_type == 'mixed':
        parts = []
        for sub_item in item.get('mixed', {}).get('msg_item', []):
            parts.append(extract_single_content(sub_item, user_id=user_id,
                                                encoding_aes_key=encoding_aes_key,
                                                shared_dir=shared_dir,
                                                agent_name=agent_name))
        return '\n'.join(parts)

    return f'[不支持的消息类型: {msg_type}]'


def extract_message_content(msg, user_id='', encoding_aes_key='', shared_dir='', agent_name=''):
    """提取完整消息内容，返回 (正文, 系统提示列表)"""
    raw_content = extract_single_content(msg, user_id=user_id,
                                         encoding_aes_key=encoding_aes_key,
                                         shared_dir=shared_dir,
                                         agent_name=agent_name)
    content, notices = _split_actionable_content_and_notices(raw_content)

    quote = msg.get('quote')
    if quote:
        raw_quote_content = extract_single_content(quote, user_id=user_id,
                                                   encoding_aes_key=encoding_aes_key,
                                                   shared_dir=shared_dir,
                                                   agent_name=agent_name)
        quote_content, quote_notices = _split_actionable_content_and_notices(raw_quote_content)
        notices = _dedupe_keep_order(notices + quote_notices)
        if content and quote_content and quote_content != content:
            content = f"{content}\n\n[引用消息] {quote_content}"

    return content, notices


# ============= 异步处理（全局 worker 池 + 单用户串行）=============

PASSIVE_REPLY_PROCESSING = '已收到，处理中...'
PASSIVE_REPLY_QUEUED = '前序任务处理中，已进入等待队列，请稍候...'
PASSIVE_REPLY_BUSY = '当前已有任务处理中，请稍后再试'
ACTIVE_REPLY_TIMEOUT = '处理超时，请重试。'
ACTIVE_REPLY_QUEUE_EXPIRED = '前序任务处理时间较长，本次请求未执行，请重试。'
ACTIVE_REPLY_SYSTEM_ERROR = '系统异常，请稍后再试。'
ACTIVE_REPLY_NO_RESPONSE = '处理失败，请稍后再试。'

_dispatch_queue = queue.Queue()
_user_task_states = {}  # queue_key -> {'running': bool, 'pending': deque()}
_scheduler_workers = []
_scheduler_started = False
_queue_lock = threading.Lock()


def _send_wecom_response(response_url, agent_name, reply_text):
    """通过 response_url 主动回复企业微信消息"""
    if not response_url:
        logger.warning(f"[{agent_name}] response_url 为空，无法主动回复")
        return False

    wecom_reply = truncate_message(reply_text, max_len=WECOM_MSG_MAX_LEN)
    payload = {"msgtype": "markdown", "markdown": {"content": wecom_reply}}
    try:
        resp = _requests_request('post', response_url, json=payload, timeout=10)
        logger.info(f"[{agent_name}] 主动回复: {resp.status_code}, 长度: {_utf8_len(wecom_reply)} bytes")
        return True
    except Exception as e:
        logger.error(f"[{agent_name}] 主动回复失败: {e}")
        return False


def _build_wecom_markdown_reply(crypto, timestamp, nonce, reply_text):
    """构造企业微信 markdown 被动回复包"""
    wecom_reply = truncate_message(reply_text, max_len=WECOM_MSG_MAX_LEN)
    reply_msg = json.dumps({"msgtype": "markdown", "markdown": {"content": wecom_reply}})
    return crypto.build_reply(reply_msg, int(timestamp), nonce)


def _ensure_scheduler_workers():
    """懒加载固定数量的调度 worker"""
    global _scheduler_started
    with _queue_lock:
        if _scheduler_started:
            return
        for index in range(MAX_GATEWAY_WORKERS):
            worker = threading.Thread(
                target=_scheduler_worker,
                name=f'gateway-worker-{index + 1}',
                daemon=True,
            )
            _scheduler_workers.append(worker)
            worker.start()
        _scheduler_started = True
        logger.info(f"已启动 Gateway worker 池，数量={MAX_GATEWAY_WORKERS}")


def _build_task(queue_key, user_id, content, task_id, response_url, agent_name):
    """构造调度任务对象"""
    return {
        'queue_key': queue_key,
        'user_id': user_id,
        'content': content,
        'task_id': task_id,
        'response_url': response_url,
        'agent_name': agent_name,
        'enqueued_at': time.time(),
    }


def _schedule_next_task_locked(queue_key):
    """在持锁状态下调度同一用户的下一条任务"""
    state = _user_task_states.get(queue_key)
    if not state:
        return
    if state['pending']:
        next_task = state['pending'].popleft()
        state['running'] = True
        _dispatch_queue.put(next_task)
        logger.info(f"调度下一条任务: {queue_key}, 剩余等待={len(state['pending'])}")
        return
    del _user_task_states[queue_key]
    logger.info(f"队列空闲释放: {queue_key}")


def _scheduler_worker():
    """固定 worker 池，从全局队列获取任务执行"""
    while True:
        task = _dispatch_queue.get()
        queue_key = task['queue_key']
        try:
            queue_wait_seconds = max(0.0, time.time() - task['enqueued_at'])
            if queue_wait_seconds > MAX_QUEUE_WAIT_SECONDS:
                logger.warning(f"队列等待超时: {queue_key}, task_id={task['task_id']}, wait={queue_wait_seconds:.2f}s")
                update_task_status(task['task_id'], 'queue_expired', f'queue_wait_s={queue_wait_seconds:.2f}')
                _send_wecom_response(task['response_url'], task['agent_name'], ACTIVE_REPLY_QUEUE_EXPIRED)
            else:
                _process_single_message(
                    user_id=task['user_id'],
                    content=task['content'],
                    task_id=task['task_id'],
                    response_url=task['response_url'],
                    agent_name=task['agent_name'],
                    queue_wait_seconds=queue_wait_seconds,
                )
        except Exception as e:
            logger.error(f"处理消息失败 ({queue_key}): {e}")
        finally:
            with _queue_lock:
                _schedule_next_task_locked(queue_key)
            _dispatch_queue.task_done()


def _enqueue_message(user_id, content, task_id, response_url, agent_name):
    """按单用户串行策略入调度器，返回决策结果"""
    _ensure_scheduler_workers()
    queue_key = f"{agent_name}:{user_id}"
    task = _build_task(queue_key, user_id, content, task_id, response_url, agent_name)

    with _queue_lock:
        state = _user_task_states.get(queue_key)
        if state is None:
            _user_task_states[queue_key] = {
                'running': True,
                'pending': deque(),
            }
            log_task(task_id, user_id, agent_name, content[:200], status='pending', result='run_now')
            _dispatch_queue.put(task)
            logger.info(f"消息立即调度: {queue_key}, task_id={task_id}")
            return 'run_now'

        pending_count = len(state['pending'])
        if pending_count >= MAX_PER_USER_PENDING:
            log_task(task_id, user_id, agent_name, content[:200], status='busy_rejected',
                     result=f'running=1 pending={pending_count}')
            logger.warning(f"队列已满，拒绝新消息: {queue_key}, task_id={task_id}")
            return 'reject_busy'

        state['pending'].append(task)
        pending_position = len(state['pending'])
        log_task(task_id, user_id, agent_name, content[:200], status='queued',
                 result=f'pending_position={pending_position}')
        logger.info(f"消息进入等待队列: {queue_key}, task_id={task_id}, 等待数={pending_position}")
        return 'queued'


def _process_single_message(user_id, content, task_id, response_url, agent_name, queue_wait_seconds=0.0):
    """处理单条消息：调用对应 agent -> 回复"""
    agent_cfg = AGENTS.get(agent_name)
    if not agent_cfg:
        logger.error(f"Agent {agent_name} 不存在（可能已被删除）")
        update_task_status(task_id, 'error', 'agent_missing')
        _send_wecom_response(response_url, agent_name, ACTIVE_REPLY_SYSTEM_ERROR)
        return

    session_key = f"wecom:{agent_name}:{user_id}"
    update_task_status(task_id, 'processing', f'queue_wait_s={queue_wait_seconds:.2f}')

    try:
        reply = _call_openclaw(
            agent_cfg['openclaw_url'], content, session_key,
            token=agent_cfg['openclaw_token'],
            agent_id=agent_cfg['openclaw_agent_id'],
        )
        # 兜底恢复：如果回复提示“沙箱挂载异常”，自动切新会话重试一次
        if _looks_like_sandbox_mount_error(reply):
            logger.warning(f"[{agent_name}] 检测到沙箱路径异常，切换新会话重试一次")
            recovery_session_key = f"{session_key}:recovery:{uuid.uuid4().hex[:8]}"
            recovery_reply = _call_openclaw(
                agent_cfg['openclaw_url'], content, recovery_session_key,
                token=agent_cfg['openclaw_token'],
                agent_id=agent_cfg['openclaw_agent_id'],
            )
            if recovery_reply:
                reply = recovery_reply
        if not reply:
            reply = ACTIVE_REPLY_NO_RESPONSE
            update_task_status(task_id, 'failed', '无响应')
        else:
            update_task_status(task_id, 'success', reply[:500])
    except OpenClawTimeoutError as e:
        logger.warning(f"调用 agent {agent_name} 超时: {e}")
        reply = ACTIVE_REPLY_TIMEOUT
        update_task_status(task_id, 'timeout', e.stage)
    except Exception as e:
        logger.error(f"调用 agent {agent_name} 异常: {e}")
        reply = ACTIVE_REPLY_SYSTEM_ERROR
        update_task_status(task_id, 'error', str(e)[:500])

    _send_wecom_response(response_url, agent_name, reply)


def process_message_async(user_id, content, task_id, response_url, agent_name):
    """将消息放入调度器，返回决策结果"""
    return _enqueue_message(user_id, content, task_id, response_url, agent_name)


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


def _verify_internal_upload_auth(req):
    """校验内部上传接口鉴权"""
    if not FILE_UPLOAD_INTERNAL_TOKEN:
        return False, 'FILE_UPLOAD_INTERNAL_TOKEN 未配置，内部上传接口已禁用'

    auth = req.headers.get('Authorization', '').strip()
    if not auth.startswith('Bearer '):
        return False, '缺少 Bearer Token'

    token = auth[7:].strip()
    if token != FILE_UPLOAD_INTERNAL_TOKEN:
        return False, '鉴权失败'

    return True, ''


def _safe_ext_from_filename(filename):
    """从文件名提取安全扩展名"""
    ext = os.path.splitext(filename or '')[1].lower()
    if not ext:
        return ''
    ext = ''.join(ch for ch in ext if (ch.isalnum() or ch == '.'))
    if not ext.startswith('.'):
        return ''
    if len(ext) > 16:
        return ''
    return ext


def _save_internal_uploaded_file(file_storage):
    """保存 OpenClaw skill 上传文件到本地临时目录，返回 (local_path, content_type, file_size)"""
    tmp_path = None
    try:
        today_dir = _get_today_dir()
        with tempfile.NamedTemporaryFile(dir=today_dir, prefix='upload-', suffix='.tmp', delete=False) as tmp_file:
            tmp_path = tmp_file.name
            total_size = 0
            while True:
                chunk = file_storage.stream.read(DOWNLOAD_CHUNK_SIZE)
                if not chunk:
                    break
                total_size += len(chunk)
                if total_size > MAX_INTERNAL_UPLOAD_FILE_SIZE:
                    raise ValueError(f"文件过大，超过限制 {MAX_INTERNAL_UPLOAD_FILE_SIZE} bytes")
                tmp_file.write(chunk)

        raw_content_type = (file_storage.content_type or 'application/octet-stream').split(';')[0].strip()
        content_type, ext = _detect_file_type(tmp_path, raw_content_type)
        if ext == '.jpe':
            ext = '.jpg'
        if not ext:
            ext = _safe_ext_from_filename(file_storage.filename)
        if not ext:
            ext = '.bin'

        if _is_risky_file_extension(ext):
            raise ValueError(f"检测到高风险文件类型 {ext}，拒绝上传")

        local_path = os.path.join(today_dir, f"upload-{uuid.uuid4().hex[:8]}{ext}")
        os.rename(tmp_path, local_path)
        tmp_path = None

        file_size = os.path.getsize(local_path)
        return local_path, content_type, file_size
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass


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
                content, notices = extract_message_content(msg, user_id=from_user,
                                                           encoding_aes_key=agent_cfg['wecom_encoding_aes_key'],
                                                           shared_dir=agent_cfg.get('shared_dir', ''),
                                                           agent_name=agent_name)
                logger.info(f"[{agent_name}] 消息内容: {content[:200]}, from: {from_user}")
                if content and notices:
                    logger.info(f"[{agent_name}] 已过滤系统提示: {' | '.join(notices)}")

                if not content:
                    notice_text = _render_user_visible_notices(notices) or '收到消息，但暂无可处理内容，请重试。'
                    logger.info(f"[{agent_name}] 消息未进入 Agent，仅回复用户: {notice_text}")
                    reply_pkg = _build_wecom_markdown_reply(crypto, timestamp, nonce, notice_text)
                    if reply_pkg:
                        return jsonify(reply_pkg), 200
                    return jsonify({}), 200

                task_id = str(uuid.uuid4())

                decision = process_message_async(from_user, content, task_id, response_url, agent_name)
                if decision == 'run_now':
                    passive_text = PASSIVE_REPLY_PROCESSING
                elif decision == 'queued':
                    passive_text = PASSIVE_REPLY_QUEUED
                else:
                    passive_text = PASSIVE_REPLY_BUSY

                reply_pkg = _build_wecom_markdown_reply(crypto, timestamp, nonce, passive_text)

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


@app.route('/internal/files/upload', methods=['POST'])
def internal_upload_file():
    """内部文件上传接口（供 OpenClaw skill 调用）"""
    authorized, reason = _verify_internal_upload_auth(request)
    if not authorized:
        status_code = 503 if '未配置' in reason else 401
        return jsonify({'error': reason}), status_code

    upload = request.files.get('file')
    if upload is None:
        return jsonify({'error': '缺少文件字段 file'}), 400

    agent_name = request.form.get('agent_name', '').strip()
    user_id = request.form.get('user_id', '').strip()
    source = request.form.get('source', 'openclaw-skill').strip() or 'openclaw-skill'
    msg_type = request.form.get('msg_type', 'internal_upload').strip() or 'internal_upload'

    expires_seconds = None
    expires_raw = request.form.get('expires_seconds', '').strip()
    if expires_raw:
        try:
            expires_seconds = int(expires_raw)
        except ValueError:
            return jsonify({'error': 'expires_seconds 必须是整数'}), 400

    shared_dir = ''
    if agent_name:
        agent_cfg = AGENTS.get(agent_name)
        if not agent_cfg:
            return jsonify({'error': f'unknown agent: {agent_name}'}), 404
        shared_dir = agent_cfg.get('shared_dir', '')

    try:
        local_path, content_type, file_size = _save_internal_uploaded_file(upload)

        publish_result = publish_file(
            local_path,
            shared_dir=shared_dir,
            user_id=user_id,
            msg_type=msg_type,
            source_url='internal_upload',
            agent_name=agent_name,
            content_type=content_type,
            source=source,
            expires_seconds=expires_seconds,
        )

        file_type = content_type.split('/')[0] if '/' in content_type else content_type
        log_file_record(
            user_id,
            publish_result.get('storage_uri', local_path),
            os.path.basename(local_path),
            file_type,
            content_type,
            file_size,
            'internal_upload',
            msg_type,
        )

        return jsonify({
            'status': 'ok',
            'storage_mode': publish_result.get('storage_mode', FILE_STORAGE_MODE),
            'storage_uri': publish_result.get('storage_uri', ''),
            'download_url': publish_result.get('download_url', ''),
            'expires_at': publish_result.get('expires_at', ''),
            'display_value': publish_result.get('display_value', ''),
            'file_name': os.path.basename(local_path),
            'file_size': file_size,
            'agent_name': agent_name,
        })
    except ValueError as e:
        logger.warning(f"内部上传参数错误: {e}")
        return jsonify({'error': str(e)}), 400
    except (BotoCoreError, ClientError) as e:
        logger.error(f"内部上传 S3 失败: {e}")
        return jsonify({'error': '上传到 S3 失败'}), 500
    except Exception as e:
        logger.error(f"内部上传失败: {e}")
        return jsonify({'error': f'上传失败: {e}'}), 500


@app.route('/health', methods=['GET'])
def health():
    """健康检查接口"""
    return jsonify({
        'status': 'ok',
        'timestamp': int(time.time()),
        'service': 'openclaw-wecom-gateway',
        'protocol': OPENCLAW_PROTOCOL,
        'file_storage_mode': FILE_STORAGE_MODE,
        'active_user_queues': len(_user_task_states),
        'dispatch_queue_size': _dispatch_queue.qsize(),
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

        cursor.execute("SELECT COUNT(*) FROM task_logs WHERE status = 'timeout'")
        timeout_tasks = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM task_logs WHERE status = 'queue_expired'")
        queue_expired_tasks = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM task_logs WHERE status = 'busy_rejected'")
        busy_rejected_tasks = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM task_logs WHERE status = 'queued'")
        queued_tasks = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM task_logs WHERE status = 'processing'")
        processing_tasks = cursor.fetchone()[0]

        conn.close()

        return jsonify({
            'total_tasks': total_tasks,
            'success_tasks': success_tasks,
            'failed_tasks': failed_tasks,
            'timeout_tasks': timeout_tasks,
            'queue_expired_tasks': queue_expired_tasks,
            'busy_rejected_tasks': busy_rejected_tasks,
            'queued_tasks': queued_tasks,
            'processing_tasks': processing_tasks,
            'success_rate': f"{success_tasks / total_tasks * 100:.2f}%" if total_tasks > 0 else "0%",
            'agents': len(AGENTS),
            'active_user_queues': len(_user_task_states),
            'dispatch_queue_size': _dispatch_queue.qsize(),
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
    logger.info(f"旧版超时兼容值: {OPENCLAW_TIMEOUT}s")
    logger.info(
        "OpenClaw 超时配置: "
        f"connect={OPENCLAW_CONNECT_TIMEOUT}s, "
        f"ws_idle={OPENCLAW_WS_IDLE_TIMEOUT}s, ws_total={OPENCLAW_WS_TOTAL_TIMEOUT}s, "
        f"sse_idle={OPENCLAW_SSE_IDLE_TIMEOUT}s, sse_total={OPENCLAW_SSE_TOTAL_TIMEOUT}s, "
        f"http={OPENCLAW_HTTP_TIMEOUT}s"
    )
    logger.info(
        f"队列配置: workers={MAX_GATEWAY_WORKERS}, "
        f"per_user_pending={MAX_PER_USER_PENDING}, queue_wait={MAX_QUEUE_WAIT_SECONDS}s"
    )
    logger.info(f"文件存储模式: {FILE_STORAGE_MODE}")
    if FILE_STORAGE_MODE == 's3':
        logger.info(f"S3 Bucket: {S3_BUCKET or '(未配置)'}")
    if AGENTS:
        logger.info(f"已加载 {len(AGENTS)} 个 Agent 绑定:")
        for name, cfg in AGENTS.items():
            logger.info(f"  - {name} ({cfg['display_name']}): {cfg['openclaw_url']} [agent: {cfg['openclaw_agent_id']}]")
    else:
        logger.info("当前无 Agent 绑定，请通过 manage-agent.py 添加")
    logger.info("=" * 60)

    app.run(host='0.0.0.0', port=GATEWAY_PORT, debug=False)
