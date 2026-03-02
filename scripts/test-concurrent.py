#!/usr/bin/env python3
"""
模拟企业微信消息通知，测试 gateway 并发处理能力。
5 个用户同时发送多条消息，验证：
1. 每个用户的回复是否正确送达（不串 session）
2. 同一用户的消息是否串行处理（per-user 队列）
3. 不同用户之间是否并行

使用方法（在服务器上运行）：
  pip install pycryptodome requests
  python3 test-concurrent.py

或指定 gateway 地址：
  GATEWAY_URL=http://139.199.200.144:8000 python3 test-concurrent.py
"""

import hashlib
import json
import os
import sys
import uuid
import time
import struct
import base64
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime

import requests
from Crypto.Cipher import AES

# ============= 配置 =============

GATEWAY_URL = os.getenv('GATEWAY_URL', 'http://139.199.200.144:8000')
CALLBACK_HOST = os.getenv('CALLBACK_HOST', '0.0.0.0')
CALLBACK_PORT = int(os.getenv('CALLBACK_PORT', '9999'))
# response_url 中用的地址，需要 gateway 容器能访问到
# 如果在服务器本机运行，用宿主机 IP（Docker 容器通过 host network 或 bridge 访问）
CALLBACK_BASE = os.getenv('CALLBACK_BASE', f'http://172.17.0.1:{CALLBACK_PORT}')

WECOM_TOKEN = '32c4407bae780aeb92b0d7f504dc26c1'
WECOM_ENCODING_AES_KEY = 'f7cTZKs4PQ1E0cLHrHArKpSoHYUzxUNE8mKTIauIkZA'
AES_KEY = base64.b64decode(WECOM_ENCODING_AES_KEY + '=')

# 模拟用户
USERS = ['TestUser1', 'TestUser2', 'TestUser3', 'TestUser4', 'TestUser5']

# 每个用户发送的消息列表
USER_MESSAGES = {
    'TestUser1': ['你好', '帮我写个登录功能的测试用例', '需要覆盖哪些场景'],
    'TestUser2': ['最近用户增长数据怎么样', '环比上个月呢'],
    'TestUser3': ['接口返回500错误怎么排查', '日志里没有明显报错'],
    'TestUser4': ['我想新增一个分享功能', '需要支持微信和朋友圈'],
    'TestUser5': ['你好', '在吗', '谢谢'],
}

# ============= 回复收集 =============

replies = {}  # msg_id -> {'user': ..., 'content': ..., 'time': ...}
replies_lock = threading.Lock()
send_log = []  # [(timestamp, user, msg_id, content)]


# ============= 加密 & 签名（复刻 gateway 逻辑）=============

def encrypt_msg(plain_text):
    """AES-256-CBC 加密，PKCS#7 填充，receiveid 为空"""
    rand_str = os.urandom(16)
    msg_bytes = plain_text.encode('utf-8')
    msg_len = struct.pack('!I', len(msg_bytes))
    body = rand_str + msg_len + msg_bytes + b''  # receiveid 为空
    pad = 32 - len(body) % 32
    body += bytes([pad] * pad)
    cipher = AES.new(AES_KEY, AES.MODE_CBC, AES_KEY[:16])
    return base64.b64encode(cipher.encrypt(body)).decode('utf-8')


def make_signature(timestamp, nonce, encrypt_str):
    """SHA1 签名：sort([token, timestamp, nonce, encrypt]) 拼接后哈希"""
    items = [WECOM_TOKEN, str(timestamp), str(nonce), encrypt_str]
    items.sort()
    return hashlib.sha1(''.join(items).encode('utf-8')).hexdigest()


# ============= 回调接收服务器 =============

class CallbackHandler(BaseHTTPRequestHandler):
    """接收 gateway 异步回复的 mock 服务器"""

    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(length)) if length else {}
        # 从 path 提取 user_id 和 msg_id: /response/{user}/{msg_id}
        parts = self.path.strip('/').split('/')
        user_id = parts[1] if len(parts) > 1 else '?'
        msg_id = parts[2] if len(parts) > 2 else '?'
        content = body.get('markdown', {}).get('content', body.get('text', {}).get('content', ''))
        with replies_lock:
            replies[msg_id] = {
                'user': user_id,
                'content': content[:200],
                'time': datetime.now().strftime('%H:%M:%S.%f')[:-3],
            }
        ts = datetime.now().strftime('%H:%M:%S')
        print(f"  📨 [{ts}] 收到回复 -> {user_id}: {content[:80]}...")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'ok')

    def log_message(self, format, *args):
        pass  # 静默 HTTP 日志


# ============= 发送消息 =============

def send_message(user_id, content, msg_id=None):
    """构造加密消息并 POST 到 gateway，模拟企业微信回调"""
    msg_id = msg_id or uuid.uuid4().hex
    timestamp = str(int(time.time()))
    nonce = str(int(time.time() * 1000))

    # 构造企业微信消息体
    msg_json = json.dumps({
        'msgid': msg_id,
        'aibotid': 'aibTestBot',
        'chattype': 'single',
        'from': {'userid': user_id},
        'msgtype': 'text',
        'response_url': f'{CALLBACK_BASE}/response/{user_id}/{msg_id}',
        'text': {'content': content},
    }, ensure_ascii=False)

    # 加密
    encrypted = encrypt_msg(msg_json)
    signature = make_signature(timestamp, nonce, encrypted)

    # 发送
    url = f'{GATEWAY_URL}/wecom/callback?msg_signature={signature}&timestamp={timestamp}&nonce={nonce}'
    resp = requests.post(url, json={'encrypt': encrypted}, timeout=10)

    ts = datetime.now().strftime('%H:%M:%S')
    send_log.append((ts, user_id, msg_id, content))
    status = '✅' if resp.status_code == 200 else f'❌ {resp.status_code}'
    print(f"  📤 [{ts}] {status} {user_id}: {content}")
    return msg_id


# ============= 用户模拟线程 =============

def simulate_user(user_id, messages, delay=1.0):
    """模拟单个用户依次发送多条消息（间隔 delay 秒）"""
    msg_ids = []
    for content in messages:
        mid = send_message(user_id, content)
        msg_ids.append(mid)
        time.sleep(delay)
    return msg_ids


# ============= 主流程 =============

def main():
    total_msgs = sum(len(v) for v in USER_MESSAGES.values())
    print(f"{'='*60}")
    print(f"🧪 OpenClaw Gateway 并发测试")
    print(f"   Gateway:  {GATEWAY_URL}")
    print(f"   回调地址: {CALLBACK_BASE}")
    print(f"   用户数:   {len(USERS)}")
    print(f"   总消息数: {total_msgs}")
    print(f"{'='*60}\n")

    # 1. 启动回调接收服务器
    print(f"🔧 启动回调服务器 {CALLBACK_HOST}:{CALLBACK_PORT} ...")
    server = HTTPServer((CALLBACK_HOST, CALLBACK_PORT), CallbackHandler)
    server_thread = threading.Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    print(f"   回调服务器已启动\n")

    # 2. 健康检查
    print("🔍 Gateway 健康检查...")
    try:
        r = requests.get(f'{GATEWAY_URL}/health', timeout=5)
        print(f"   {r.json()}\n")
    except Exception as e:
        print(f"   ❌ 无法连接 gateway: {e}")
        sys.exit(1)

    # 3. 并发发送
    print(f"🚀 开始并发发送（{len(USERS)} 用户同时发消息）...\n")
    start_time = time.time()
    threads = []
    for user_id in USERS:
        messages = USER_MESSAGES[user_id]
        t = threading.Thread(target=simulate_user, args=(user_id, messages, 0.5))
        threads.append(t)
        t.start()

    # 等待所有发送完成
    for t in threads:
        t.join()

    send_elapsed = time.time() - start_time
    print(f"\n📤 全部消息发送完毕，耗时 {send_elapsed:.1f}s")

    # 4. 等待回复
    print(f"\n⏳ 等待异步回复（最多 120s）...")
    deadline = time.time() + 120
    while time.time() < deadline:
        with replies_lock:
            got = len(replies)
        if got >= total_msgs:
            break
        time.sleep(2)
        remaining = total_msgs - got
        print(f"   已收到 {got}/{total_msgs} 条回复，等待中...")

    total_elapsed = time.time() - start_time

    # 5. 结果汇总
    print(f"\n{'='*60}")
    print(f"📊 测试结果")
    print(f"{'='*60}\n")

    with replies_lock:
        got = len(replies)

    print(f"  发送: {total_msgs} 条")
    print(f"  收到: {got} 条")
    print(f"  耗时: {total_elapsed:.1f}s\n")

    # 按用户分组展示
    for user_id in USERS:
        user_msgs = USER_MESSAGES[user_id]
        print(f"  👤 {user_id} ({len(user_msgs)} 条消息):")
        for ts, uid, mid, content in send_log:
            if uid != user_id:
                continue
            reply_info = replies.get(mid)
            if reply_info:
                # 检查回复是否送达正确用户
                ok = '✅' if reply_info['user'] == user_id else f"❌ 串到 {reply_info['user']}"
                print(f"    [{ts}] \"{content}\"")
                print(f"      → {ok} [{reply_info['time']}] {reply_info['content'][:60]}")
            else:
                print(f"    [{ts}] \"{content}\"")
                print(f"      → ⏰ 未收到回复")
        print()

    # 判定
    if got == total_msgs:
        print("✅ 全部消息均收到回复")
    else:
        print(f"⚠️  有 {total_msgs - got} 条消息未收到回复")

    server.shutdown()


if __name__ == '__main__':
    main()
