#!/usr/bin/env python3
"""
直接调用 OpenClaw WebSocket API 测试会话隔离
绕过企业微信加密，专注测试 Gateway 的 session_key 机制
"""

import json
import time
import random
import uuid
import websocket

# OpenClaw WebSocket 配置
OPENCLAW_WS_URL = "ws://127.0.0.1:18789/ws"
OPENCLAW_TOKEN = "1e443bcba0ed1327699b31cdee8f6150e97226386c375f75"

# 测试数据
TEST_USERS = [
    {"name": "张三", "user_id": "user001"},
    {"name": "李四", "user_id": "user002"},
    {"name": "王五", "user_id": "user003"},
]

TEST_AGENTS = ["main", "work"]

def connect_openclaw(timeout=30):
    """连接 OpenClaw WebSocket 并完成握手"""
    ws = websocket.create_connection(OPENCLAW_WS_URL, timeout=timeout)
    
    # Step 1: 接收 challenge
    ws.recv()
    
    # Step 2: connect 握手（使用和 Gateway 完全一样的参数）
    ws.send(json.dumps({
        "type": "req",
        "id": "connect-1",
        "method": "connect",
        "params": {
            "client": {
                "id": "cli",
                "mode": "cli",
                "platform": "linux",
                "version": "2026.2.28"
            },
            "auth": {
                "token": OPENCLAW_TOKEN
            },
            "role": "operator",
            "scopes": ["operator.read", "operator.write"],
            "minProtocol": 3,
            "maxProtocol": 3
        }
    }))
    
    hello = json.loads(ws.recv())
    if not hello.get('ok'):
        raise Exception(f"WS connect 失败: {hello.get('error')}")
    
    return ws

def send_message(ws, agent_id, session_key, message, timeout=30):
    """发送消息到 OpenClaw 并等待回复"""
    # OpenClaw 期望的 sessionKey 格式: agent:{agent_id}:{custom_session_key}
    full_session_key = f"agent:{agent_id}:{session_key}"
    
    req_id = str(uuid.uuid4())
    
    ws.send(json.dumps({
        "type": "req",
        "id": req_id,
        "method": "chat.send",
        "params": {
            "message": message,
            "sessionKey": full_session_key,
            "idempotencyKey": str(uuid.uuid4())
        }
    }))
    
    # 监听事件流，等待 chat state=final
    start_time = time.time()
    while time.time() - start_time < timeout:
        raw = ws.recv()
        evt = json.loads(raw)
        
        # 检查是否是 chat 事件
        if evt.get('type') == 'event' and evt.get('event') == 'chat':
            payload = evt.get('payload', {})
            # 校验 sessionKey，忽略其他会话的 broadcast 事件
            evt_sk = (payload.get('sessionKey') or '').lower()
            if evt_sk and session_key.lower() not in evt_sk:
                continue
            # 等待 final 状态
            if payload.get('state') == 'final':
                msg = payload.get('message', {})
                texts = []
                for c in msg.get('content', []):
                    if c.get('type') == 'text' and c.get('text'):
                        texts.append(c['text'])
                return '\n'.join(texts).strip() or "无回复"
        
        # RPC 错误
        if evt.get('type') == 'res' and evt.get('id') == req_id and not evt.get('ok'):
            raise Exception(f"WS RPC 错误: {evt.get('error')}")
    
    raise Exception(f"等待回复超时 ({timeout}s)")

def main():
    print("=" * 80)
    print("🚀 OpenClaw Session 隔离测试（直接 WS 调用）")
    print("=" * 80)
    
    # 计算测试规模
    num_users = len(TEST_USERS)
    num_agents = len(TEST_AGENTS)
    messages_per_session = 3
    total_sessions = num_users * num_agents
    total_messages = total_sessions * messages_per_session
    
    print(f"测试配置:")
    print(f"  - 用户数: {num_users}")
    print(f"  - Agent 数: {num_agents}")
    print(f"  - 每会话消息数: {messages_per_session}")
    print(f"  - 总会话数: {total_sessions}")
    print(f"  - 总消息数: {total_messages}")
    print("=" * 80)
    
    # 连接 OpenClaw WebSocket
    print(f"\n📡 连接 OpenClaw: {OPENCLAW_WS_URL}")
    try:
        ws = connect_openclaw()
        print("✅ WebSocket 握手成功\n")
    except Exception as e:
        print(f"❌ WebSocket 握手失败: {e}")
        return
    
    # 准备所有消息（模拟并发）
    messages = []
    for user in TEST_USERS:
        for agent_id in TEST_AGENTS:
            # Gateway 的 session_key 格式: wecom:{agent_name}:{user_id}
            # 这里为了测试方便，简化为: wecom:test-{agent_id}:{user_id}
            session_key = f"wecom:test-{agent_id}:{user['user_id']}"
            
            for i in range(1, messages_per_session + 1):
                message = f"测试消息 #{i} from {user['name']} to {agent_id} agent"
                messages.append({
                    "user_name": user["name"],
                    "user_id": user["user_id"],
                    "agent_id": agent_id,
                    "session_key": session_key,
                    "message": message,
                    "seq": i
                })
    
    # 随机打乱消息顺序（模拟并发）
    random.shuffle(messages)
    
    # 发送所有消息
    print(f"📤 开始发送 {total_messages} 条消息（随机顺序，模拟并发）...\n")
    
    results = []
    start_time = time.time()
    
    for msg in messages:
        msg_start = time.time()
        try:
            reply = send_message(
                ws,
                msg["agent_id"],
                msg["session_key"],
                msg["message"]
            )
            
            msg_duration = time.time() - msg_start
            
            results.append({
                "user_name": msg["user_name"],
                "user_id": msg["user_id"],
                "agent_id": msg["agent_id"],
                "session_key": msg["session_key"],
                "message": msg["message"],
                "seq": msg["seq"],
                "reply": reply,
                "duration": msg_duration,
                "success": True
            })
            
            print(f"[{time.strftime('%H:%M:%S')}] {msg['user_name']} → {msg['agent_id']} 消息#{msg['seq']}/{messages_per_session} ✅ ({msg_duration:.1f}s)")
            
        except Exception as e:
            results.append({
                "user_name": msg["user_name"],
                "user_id": msg["user_id"],
                "agent_id": msg["agent_id"],
                "session_key": msg["session_key"],
                "message": msg["message"],
                "seq": msg["seq"],
                "reply": f"❌ {str(e)}",
                "duration": 0,
                "success": False
            })
            print(f"[{time.strftime('%H:%M:%S')}] {msg['user_name']} → {msg['agent_id']} 消息#{msg['seq']}/{messages_per_session} ❌ - {e}")
    
    total_duration = time.time() - start_time
    
    # 关闭连接
    ws.close()
    print("\n🔌 WebSocket 连接已关闭\n")
    
    # 统计结果
    print("=" * 80)
    print("📊 测试结果统计")
    print("=" * 80)
    
    success_count = sum(1 for r in results if r["success"])
    fail_count = len(results) - success_count
    
    print(f"总消息数: {len(results)}")
    print(f"成功: {success_count} ✅")
    print(f"失败: {fail_count} ❌")
    print(f"成功率: {success_count / len(results) * 100:.1f}%")
    print(f"总耗时: {total_duration:.1f}s")
    print(f"平均耗时: {total_duration / len(results):.2f}s/消息")
    
    # 按会话分组展示
    print("\n" + "-" * 80)
    print("📋 Session 隔离验证")
    print("-" * 80)
    
    # 按 session_key 分组
    sessions = {}
    for r in results:
        key = (r["user_name"], r["agent_id"])
        if key not in sessions:
            sessions[key] = []
        sessions[key].append(r)
    
    for (user_name, agent_id), msgs in sorted(sessions.items()):
        print(f"\n{user_name} × {agent_id}:")
        print(f"  Session Key: {msgs[0]['session_key']}")
        print(f"  消息数: {len(msgs)}")
        
        # 按序号排序
        msgs_sorted = sorted(msgs, key=lambda x: x["seq"])
        for m in msgs_sorted:
            status = "✅" if m["success"] else "❌"
            print(f"    #{m['seq']}: {m['message']}")
            print(f"             回复: {m['reply'][:100]}{'...' if len(m['reply']) > 100 else ''}")
    
    print("\n" + "=" * 80)
    print("✅ 测试完成！")
    print("=" * 80)

if __name__ == "__main__":
    main()
