#!/usr/bin/env python3
"""
简化的并发测试脚本 - 直接测试 OpenClaw session 隔离

绕过企业微信加密，直接用 WebSocket 测试 Gateway 的 session 管理
"""

import websocket
import json
import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
import random

# OpenClaw WS 地址
OPENCLAW_WS = "ws://127.0.0.1:18789/ws"
OPENCLAW_TOKEN = "1e443bcba0ed1327699b31cdee8f6150e97226386c375f75"

# 测试用户
TEST_USERS = [
    {"id": "user001", "name": "张三"},
    {"id": "user002", "name": "李四"},
    {"id": "user003", "name": "王五"},
]

# 测试 Agent
TEST_AGENTS = ["main", "work"]

# 每个用户每个 agent 发送的消息数
MESSAGES_PER_USER_AGENT = 3

results = []
results_lock = threading.Lock()


def send_openclaw_message(agent_id, user_id, user_name, msg_num):
    """直接通过 WebSocket 发送消息到 OpenClaw"""
    try:
        # 构造 session_key: wecom:{agent}:{user_id}
        session_key = f"wecom:dev-{agent_id}:{user_id}"
        
        # 消息内容
        content = f"测试消息 #{msg_num} from {user_name} to {agent_id} agent"
        
        # 建立 WebSocket 连接
        ws = websocket.create_connection(
            OPENCLAW_WS,
            header=[f"Authorization: Bearer {OPENCLAW_TOKEN}"],
            timeout=60
        )
        
        # 构造 chat.send 消息（使用 agent:xxx:yyy 格式的 sessionKey）
        payload = {
            "id": f"test-{int(time.time()*1000)}-{random.randint(1000,9999)}",
            "method": "chat.send",
            "params": {
                "sessionKey": f"agent:{agent_id}:{session_key}",  # 使用 agent:xxx 格式
                "messages": [
                    {
                        "role": "user",
                        "content": content
                    }
                ]
            }
        }
        
        # 发送
        start_time = time.time()
        ws.send(json.dumps(payload))
        
        # 接收响应
        response_text = ""
        while True:
            try:
                resp = ws.recv()
                resp_json = json.loads(resp)
                
                # 检查是否是响应
                if resp_json.get("id") == payload["id"]:
                    if "error" in resp_json:
                        response_text = f"❌ Error: {resp_json['error']}"
                        break
                    elif "result" in resp_json:
                        response_text = "✅ Started"
                
                # 检查是否是消息事件
                if resp_json.get("method") == "chat.message":
                    params = resp_json.get("params", {})
                    if params.get("sessionKey") == f"agent:{agent_id}:{session_key}":
                        msg = params.get("message", {})
                        if msg.get("final"):
                            response_text = msg.get("content", "")[:100]
                            break
                        
            except websocket.WebSocketTimeoutException:
                response_text = "⏱️ Timeout"
                break
            except Exception as e:
                response_text = f"❌ {str(e)}"
                break
        
        end_time = time.time()
        ws.close()
        
        result = {
            "success": True,
            "agent": agent_id,
            "user_id": user_id,
            "user_name": user_name,
            "msg_num": msg_num,
            "content": content,
            "session_key": session_key,
            "response": response_text,
            "duration": round(end_time - start_time, 2),
            "timestamp": datetime.now().strftime("%H:%M:%S.%f")[:-3]
        }
        
        progress = f"[{result['timestamp']}] {user_name} → {agent_id} 消息#{msg_num}/3 ✅ ({result['duration']}s) - {response_text[:50]}"
        print(progress)
        
        with results_lock:
            results.append(result)
        
        return result
        
    except Exception as e:
        result = {
            "success": False,
            "agent": agent_id,
            "user_id": user_id,
            "user_name": user_name,
            "msg_num": msg_num,
            "error": str(e),
            "timestamp": datetime.now().strftime("%H:%M:%S.%f")[:-3]
        }
        
        with results_lock:
            results.append(result)
        
        print(f"[{result['timestamp']}] {user_name} → {agent_id} 消息#{msg_num}/3 ❌ - {str(e)}")
        return result


def run_test():
    """运行并发测试"""
    print("=" * 80)
    print("🚀 OpenClaw 并发 Session 隔离测试（直接 WS 调用）")
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
                    "agent_id": agent,
                    "user_id": user["id"],
                    "user_name": user["name"],
                    "msg_num": msg_num
                })
    
    # 随机打乱
    random.shuffle(tasks)
    
    print(f"📤 开始发送 {len(tasks)} 条消息（随机顺序，模拟并发）...\n")
    
    start_time = time.time()
    
    # 并发执行（使用较小的并发数，避免过载）
    with ThreadPoolExecutor(max_workers=6) as executor:
        futures = [
            executor.submit(
                send_openclaw_message,
                task["agent_id"],
                task["user_id"],
                task["user_name"],
                task["msg_num"]
            )
            for task in tasks
        ]
        
        for future in as_completed(futures):
            future.result()  # 等待完成
    
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
    
    # 按 session 分组统计
    print("\n" + "-" * 80)
    print("📋 Session 隔离验证")
    print("-" * 80)
    
    session_map = {}
    for r in results:
        if r.get("success"):
            key = f"{r['user_name']} × {r['agent']}"
            if key not in session_map:
                session_map[key] = []
            session_map[key].append(r)
    
    for key in sorted(session_map.keys()):
        messages = session_map[key]
        print(f"\n{key}:")
        print(f"  Session Key: {messages[0]['session_key']}")
        print(f"  消息数: {len(messages)}")
        for msg in sorted(messages, key=lambda x: x['msg_num']):
            print(f"    #{msg['msg_num']}: {msg['content']}")
            print(f"             回复: {msg.get('response', 'N/A')[:60]}")
    
    print("\n" + "=" * 80)
    print("✅ 测试完成！")
    print("=" * 80)


if __name__ == "__main__":
    run_test()
