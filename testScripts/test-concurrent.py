#!/usr/bin/env python3
"""
并发测试脚本 - 测试 Gateway 的 session 隔离功能

测试场景:
1. 多用户（3 个企业微信用户）
2. 多 Agent（2 个 agent: dev-main, dev-work）
3. 多消息（每用户每 agent 发 3 条消息）
4. 交叉并发调用

预期结果:
- 每个 user + agent 组合应该有独立的 session
- session_key 格式: wecom:{agent_name}:{user_id}
- 消息不应该串话
"""

import requests
import json
import time
import threading
import random
import os
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
import hashlib
import base64
from Crypto.Cipher import AES
import struct

# Gateway 配置
GATEWAY_URL = "http://localhost:8000"

# 企业微信配置（从你提供的信息）
WECOM_TOKEN = "32c4407bae780aeb92b0d7f504dc26c1"
WECOM_AES_KEY = "f7cTZKs4PQ1E0cLHrHArKpSoHYUzxUNE8mKTIauIkZA"

# 测试用户
TEST_USERS = [
    {"id": "user001", "name": "张三"},
    {"id": "user002", "name": "李四"},
    {"id": "user003", "name": "王五"},
]

# 测试 Agent
TEST_AGENTS = ["dev-main", "dev-work"]

# 每个用户每个 agent 发送的消息数
MESSAGES_PER_USER_AGENT = 3


class WXBizMsgCrypt:
    """企业微信消息加密解密（智能机器人模式，receiveid 为空字符串）"""
    
    def __init__(self, token, encoding_aes_key):
        self.token = token
        # Base64 解码 AES Key
        self.key = base64.b64decode(encoding_aes_key + "=")
        assert len(self.key) == 32
    
    def encrypt(self, msg_text):
        """加密消息（与 Gateway 的 encrypt 方法保持一致）"""
        # 16 字节随机字符串
        rand_str = os.urandom(16)
        # 消息长度（4字节网络字节序）
        msg_len = struct.pack("!I", len(msg_text.encode('utf-8')))
        # 拼接: random(16B) + msg_len(4B) + text + receiveid（空字符串）
        plain_text = rand_str + msg_len + msg_text.encode('utf-8') + b''
        
        # PKCS7 填充
        pad = 32 - len(plain_text) % 32
        plain_text += bytes([pad] * pad)
        
        # AES-CBC 加密
        cipher = AES.new(self.key, AES.MODE_CBC, self.key[:16])
        cipher_text = cipher.encrypt(plain_text)
        
        return base64.b64encode(cipher_text).decode('utf-8')
    
    def _signature(self, timestamp, nonce, encrypt_msg):
        """计算签名（与 Gateway 的 verify_signature 保持一致）"""
        sha = hashlib.sha1()
        items = [self.token, timestamp, nonce, encrypt_msg]
        items.sort()
        sha.update(''.join(items).encode('utf-8'))
        return sha.hexdigest()


def create_text_message(user_id, msg_id, content):
    """创建企业微信文本消息（JSON 格式，智能机器人格式）"""
    return json.dumps({
        "msgtype": "text",
        "msgid": msg_id,
        "from": {
            "userid": user_id
        },
        "text": {
            "content": content
        },
        "response_url": "https://example.com/wecom/response"
    }, ensure_ascii=False)


def send_message(agent_name, user_id, user_name, msg_num, total_messages):
    """发送一条消息到 Gateway"""
    try:
        # 生成消息内容
        content = f"测试消息 #{msg_num} from {user_name} to {agent_name}"
        msg_id = f"{int(time.time() * 1000)}{random.randint(1000, 9999)}"
        
        # 创建原始消息
        raw_msg = create_text_message(user_id, msg_id, content)
        
        # 加密
        crypt = WXBizMsgCrypt(WECOM_TOKEN, WECOM_AES_KEY)
        encrypt_msg = crypt.encrypt(raw_msg)  # 只要加密后的字符串
        timestamp = str(int(time.time()))
        nonce = str(random.randint(100000000, 999999999))
        signature = crypt._signature(timestamp, nonce, encrypt_msg)
        
        # 构造 JSON payload（Gateway 期望的格式）
        payload = {
            "encrypt": encrypt_msg  # 只传加密后的字符串，不要 XML 包装
        }
        
        # 构造回调 URL 参数
        params = {
            "msg_signature": signature,
            "timestamp": timestamp,
            "nonce": nonce
        }
        
        callback_url = f"{GATEWAY_URL}/{agent_name}/wecom/callback"
        
        # 发送请求
        start_time = time.time()
        response = requests.post(
            callback_url,
            params=params,
            json=payload,
            timeout=60
        )
        end_time = time.time()
        
        result = {
            "success": response.status_code == 200,
            "agent": agent_name,
            "user_id": user_id,
            "user_name": user_name,
            "msg_num": msg_num,
            "content": content,
            "status_code": response.status_code,
            "response_text": response.text[:200] if response.text else "",
            "duration": round(end_time - start_time, 2),
            "timestamp": datetime.now().strftime("%H:%M:%S.%f")[:-3]
        }
        
        # 打印进度
        progress = f"[{result['timestamp']}] {user_name} → {agent_name} 消息#{msg_num}/{total_messages} " \
                   f"{'✅' if result['success'] else '❌'} ({result['duration']}s)"
        print(progress)
        
        return result
        
    except Exception as e:
        return {
            "success": False,
            "agent": agent_name,
            "user_id": user_id,
            "user_name": user_name,
            "msg_num": msg_num,
            "error": str(e),
            "timestamp": datetime.now().strftime("%H:%M:%S.%f")[:-3]
        }


def run_concurrent_test():
    """运行并发测试"""
    print("=" * 80)
    print("🚀 Gateway 并发 Session 隔离测试")
    print("=" * 80)
    print(f"测试配置:")
    print(f"  - 用户数: {len(TEST_USERS)}")
    print(f"  - Agent 数: {len(TEST_AGENTS)}")
    print(f"  - 每用户每 Agent 消息数: {MESSAGES_PER_USER_AGENT}")
    print(f"  - 总消息数: {len(TEST_USERS) * len(TEST_AGENTS) * MESSAGES_PER_USER_AGENT}")
    print(f"  - 预期独立 Session 数: {len(TEST_USERS) * len(TEST_AGENTS)}")
    print("=" * 80)
    print()
    
    # 准备所有测试任务
    tasks = []
    for user in TEST_USERS:
        for agent in TEST_AGENTS:
            for msg_num in range(1, MESSAGES_PER_USER_AGENT + 1):
                tasks.append({
                    "agent_name": agent,
                    "user_id": user["id"],
                    "user_name": user["name"],
                    "msg_num": msg_num,
                    "total_messages": MESSAGES_PER_USER_AGENT
                })
    
    # 随机打乱任务顺序，模拟真实并发场景
    random.shuffle(tasks)
    
    print(f"📤 开始发送 {len(tasks)} 条消息（随机顺序，模拟并发）...\n")
    
    # 并发执行
    results = []
    start_time = time.time()
    
    with ThreadPoolExecutor(max_workers=10) as executor:
        future_to_task = {
            executor.submit(
                send_message,
                task["agent_name"],
                task["user_id"],
                task["user_name"],
                task["msg_num"],
                task["total_messages"]
            ): task
            for task in tasks
        }
        
        for future in as_completed(future_to_task):
            result = future.result()
            results.append(result)
    
    end_time = time.time()
    total_duration = round(end_time - start_time, 2)
    
    # 统计结果
    print("\n" + "=" * 80)
    print("📊 测试结果统计")
    print("=" * 80)
    
    success_count = sum(1 for r in results if r.get("success", False))
    fail_count = len(results) - success_count
    
    print(f"总消息数: {len(results)}")
    print(f"成功: {success_count} ✅")
    print(f"失败: {fail_count} ❌")
    print(f"成功率: {success_count / len(results) * 100:.1f}%")
    print(f"总耗时: {total_duration}s")
    print(f"平均耗时: {total_duration / len(results):.2f}s/消息")
    
    # 按用户和 Agent 分组统计
    print("\n" + "-" * 80)
    print("📋 Session 隔离验证（按用户和 Agent 分组）")
    print("-" * 80)
    
    session_stats = {}
    for result in results:
        if result.get("success"):
            key = f"{result['user_name']} × {result['agent']}"
            if key not in session_stats:
                session_stats[key] = []
            session_stats[key].append(result)
    
    for session_key in sorted(session_stats.keys()):
        messages = session_stats[session_key]
        print(f"\n{session_key}:")
        print(f"  Session Key: wecom:{messages[0]['agent']}:{messages[0]['user_id']}")
        print(f"  消息数: {len(messages)}")
        for msg in sorted(messages, key=lambda x: x["msg_num"]):
            print(f"    #{msg['msg_num']}: {msg['content']} ({msg['duration']}s)")
    
    # 失败消息
    if fail_count > 0:
        print("\n" + "-" * 80)
        print("❌ 失败消息详情")
        print("-" * 80)
        for result in results:
            if not result.get("success"):
                print(f"  {result['user_name']} → {result['agent']} 消息#{result['msg_num']}")
                print(f"    错误: {result.get('error', result.get('response_text', 'Unknown'))}")
    
    print("\n" + "=" * 80)
    return results


def check_gateway_stats():
    """检查 Gateway 统计信息"""
    print("\n" + "=" * 80)
    print("📈 Gateway 统计信息")
    print("=" * 80)
    
    try:
        # 健康检查
        health = requests.get(f"{GATEWAY_URL}/health").json()
        print(f"\n健康状态: {health['status']}")
        print(f"Agent 数: {health['agents']}")
        print(f"Agent 列表: {', '.join(health['agent_names'])}")
        
        # 统计信息
        stats = requests.get(f"{GATEWAY_URL}/stats").json()
        print(f"\n任务统计:")
        print(f"  总任务数: {stats['total_tasks']}")
        print(f"  成功: {stats['success_tasks']}")
        print(f"  失败: {stats['failed_tasks']}")
        print(f"  成功率: {stats['success_rate']}")
        
    except Exception as e:
        print(f"❌ 获取统计信息失败: {e}")


def check_database():
    """检查数据库内容"""
    print("\n" + "=" * 80)
    print("🗄️  数据库内容检查")
    print("=" * 80)
    
    import sqlite3
    import os
    
    db_path = os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "../data/gateway.db"
    )
    
    if not os.path.exists(db_path):
        print(f"❌ 数据库文件不存在: {db_path}")
        return
    
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # 任务日志统计
        cursor.execute("""
            SELECT agent_id, status, COUNT(*) as count
            FROM task_logs
            GROUP BY agent_id, status
            ORDER BY agent_id, status
        """)
        
        print("\n任务日志统计（按 agent 和状态分组）:")
        print("-" * 60)
        for row in cursor.fetchall():
            agent_id, status, count = row
            print(f"  {agent_id or '(未知)'} - {status}: {count} 条")
        
        # 按用户统计
        cursor.execute("""
            SELECT user_id, agent_id, COUNT(*) as count
            FROM task_logs
            GROUP BY user_id, agent_id
            ORDER BY user_id, agent_id
        """)
        
        print("\n任务日志统计（按用户和 agent 分组）:")
        print("-" * 60)
        for row in cursor.fetchall():
            user_id, agent_id, count = row
            print(f"  {user_id} × {agent_id}: {count} 条")
        
        # 最近的任务
        cursor.execute("""
            SELECT user_id, agent_id, task_content, status, created_at
            FROM task_logs
            ORDER BY created_at DESC
            LIMIT 10
        """)
        
        print("\n最近 10 条任务:")
        print("-" * 60)
        for row in cursor.fetchall():
            user_id, agent_id, content, status, created_at = row
            content_preview = (content[:50] + "...") if len(content) > 50 else content
            print(f"  [{created_at}] {user_id} → {agent_id}")
            print(f"    内容: {content_preview}")
            print(f"    状态: {status}")
        
        conn.close()
        
    except Exception as e:
        print(f"❌ 数据库查询失败: {e}")


if __name__ == "__main__":
    # 运行并发测试
    results = run_concurrent_test()
    
    # 等待一下，让 Gateway 处理完所有消息
    print("\n⏳ 等待 5 秒，让 Gateway 处理完所有消息...")
    time.sleep(5)
    
    # 检查 Gateway 统计
    check_gateway_stats()
    
    # 检查数据库
    check_database()
    
    print("\n" + "=" * 80)
    print("✅ 测试完成！")
    print("=" * 80)
