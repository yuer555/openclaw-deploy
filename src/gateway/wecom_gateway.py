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

# 企业微信配置
WECOM_CORP_ID = os.getenv('WECOM_CORP_ID', '')
WECOM_SECRET = os.getenv('WECOM_SECRET', '')
WECOM_TOKEN = os.getenv('WECOM_TOKEN', '')
WECOM_ENCODING_AES_KEY = os.getenv('WECOM_ENCODING_AES_KEY', '')
WECOM_AGENT_ID = os.getenv('WECOM_AGENT_ID', '')

# OpenClaw Gateway 配置
OPENCLAW_GATEWAY_URL = os.getenv('OPENCLAW_GATEWAY_URL', 'http://localhost:18789')
OPENCLAW_API_KEY = os.getenv('OPENCLAW_API_KEY', '')
OPENCLAW_TIMEOUT = int(os.getenv('OPENCLAW_TIMEOUT', '30'))

# 路由关键词配置
ROUTING_KEYWORDS = {
    'service-agent': ['客服', '咨询', '投诉', '售后', '反馈', '帮助', '问题', '咨询一下'],
    'development-agent': ['开发', '代码', '功能', '接口', '部署', 'bug', '修复', '技术'],
    'testing-agent': ['测试', '用例', '自动化', 'qa', '质量', '测试用例'],
    'operation-agent': ['文案', '活动', '推广', '内容', '社群', '运营', '推广方案'],
    'product-agent': ['需求', '原型', '竞品', '分析', '文档', 'prd', '产品需求'],
}

# ============= Access Token 管理器 =============

class AccessTokenManager:
    """企业微信 Access Token 管理器（单例模式）"""
    
    _instance = None
    _lock = threading.Lock()
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance.token = None
                    cls._instance.expire_time = 0
        return cls._instance
    
    def get_token(self):
        """获取有效的 access_token"""
        # 如果 token 有效且未过期，直接返回
        if self.token and time.time() < self.expire_time:
            logger.debug(f"使用缓存的 access_token，剩余有效时间: {int(self.expire_time - time.time())}秒")
            return self.token
        
        # 刷新 token
        logger.info("正在刷新 access_token...")
        try:
            url = f"https://qyapi.weixin.qq.com/cgi-bin/gettoken"
            params = {
                'corpid': WECOM_CORP_ID,
                'corpsecret': WECOM_SECRET
            }
            response = requests.get(url, params=params, timeout=10)
            data = response.json()
            
            if data.get('errcode') == 0:
                self.token = data['access_token']
                # 提前 5 分钟过期（7200秒 - 300秒 = 6900秒）
                self.expire_time = time.time() + data.get('expires_in', 7200) - 300
                logger.info(f"✅ access_token 刷新成功，有效期: {int(self.expire_time - time.time())}秒")
                return self.token
            else:
                logger.error(f"❌ 获取 access_token 失败: {data}")
                return None
        except Exception as e:
            logger.error(f"❌ 获取 access_token 异常: {e}")
            return None

# 全局 token 管理器实例
token_manager = AccessTokenManager()


# ============= 企业微信加解密工具类 =============

class WXBizMsgCrypt:
    """企业微信消息加解密"""
    
    def __init__(self, token, encoding_aes_key, corp_id):
        self.token = token
        self.encoding_aes_key = base64.b64decode(encoding_aes_key + "=")
        self.corp_id = corp_id
        
    def verify_signature(self, signature, timestamp, nonce, echo_str=""):
        """验证签名"""
        sha = hashlib.sha1()
        items = [self.token, timestamp, nonce, echo_str]
        items.sort()
        sha.update(''.join(items).encode('utf-8'))
        return sha.hexdigest() == signature
    
    def decrypt(self, encrypt_msg):
        """解密消息"""
        try:
            cipher = AES.new(self.encoding_aes_key, AES.MODE_CBC, self.encoding_aes_key[:16])
            plain_text = cipher.decrypt(base64.b64decode(encrypt_msg))
            
            # 去除补位字符
            pad = plain_text[-1]
            if isinstance(pad, str):
                pad = ord(pad)
            plain_text = plain_text[:-pad]
            
            # 提取消息内容
            content_length = struct.unpack('!I', plain_text[16:20])[0]
            content = plain_text[20:20+content_length].decode('utf-8')
            from_corpid = plain_text[20+content_length:].decode('utf-8')
            
            if from_corpid != self.corp_id:
                raise ValueError("corpid 不匹配")
            
            return content
        except Exception as e:
            logger.error(f"解密失败: {e}")
            return None
    
    def encrypt(self, msg_text):
        """加密消息"""
        try:
            # 16位随机字符串
            rand_str = os.urandom(16)
            
            # 消息长度（4字节网络字节序）
            msg_len = struct.pack('!I', len(msg_text.encode('utf-8')))
            
            # 拼接: 随机字符串 + 消息长度 + 消息内容 + corpid
            plain_text = rand_str + msg_len + msg_text.encode('utf-8') + self.corp_id.encode('utf-8')
            
            # PKCS#7 补位
            pad = 32 - len(plain_text) % 32
            plain_text += bytes([pad] * pad)
            
            # AES 加密
            cipher = AES.new(self.encoding_aes_key, AES.MODE_CBC, self.encoding_aes_key[:16])
            cipher_text = cipher.encrypt(plain_text)
            
            return base64.b64encode(cipher_text).decode('utf-8')
        except Exception as e:
            logger.error(f"加密失败: {e}")
            return None


# ============= 数据库操作 =============

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

def route_message(content, user_agents):
    """智能路由消息到合适的代理"""
    # 优先级路由：基于关键词匹配
    for agent_id, keywords in ROUTING_KEYWORDS.items():
        for keyword in keywords:
            if keyword in content:
                # 检查用户是否有权限访问该代理
                if user_agents and agent_id not in user_agents:
                    logger.warning(f"⚠️  用户无权限访问 {agent_id}，跳过")
                    continue
                logger.info(f"✅ 消息路由到: {agent_id} (关键词: {keyword})")
                return agent_id
    
    # 如果没有匹配到关键词，使用默认代理
    if user_agents and len(user_agents) > 0:
        default_agent = user_agents[0]
        logger.info(f"✅ 使用用户默认代理: {default_agent}")
        return default_agent
    
    # 全局默认代理
    default_agent = 'service-agent'
    logger.info(f"✅ 使用全局默认代理: {default_agent}")
    return default_agent


# ============= OpenClaw Gateway API 调用 =============

def call_openclaw_agent(agent_id, message, user_id, task_id):
    """调用 OpenClaw Gateway API"""
    try:
        # 构造 API 请求
        url = f"{OPENCLAW_GATEWAY_URL}/api/v1/sessions/send"
        
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


# ============= 企业微信消息发送 =============

def send_wecom_message(user_id, content, safe=0):
    """发送消息到企业微信用户"""
    try:
        # 获取 access_token
        access_token = token_manager.get_token()
        if not access_token:
            logger.error("❌ 无法获取 access_token，消息发送失败")
            return False
        
        # 构造消息发送请求
        url = f"https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token={access_token}"
        
        # 消息内容（限制长度，企业微信单条消息最大2048字节）
        if len(content.encode('utf-8')) > 2000:
            content = content[:600] + "\n\n...(内容过长，已截断)"
        
        payload = {
            "touser": user_id,
            "msgtype": "text",
            "agentid": WECOM_AGENT_ID,
            "text": {
                "content": content
            },
            "safe": safe  # 0=可转发分享 1=不可转发
        }
        
        logger.info(f"📤 发送消息到企业微信: {user_id}")
        logger.debug(f"消息内容: {content[:100]}...")
        
        # 发送请求
        response = requests.post(url, json=payload, timeout=10)
        result = response.json()
        
        if result.get('errcode') == 0:
            logger.info(f"✅ 消息发送成功: {user_id}")
            return True
        else:
            logger.error(f"❌ 消息发送失败: {result}")
            
            # 如果是 token 过期，清除缓存的 token
            if result.get('errcode') in [40014, 42001]:
                logger.warning("⚠️  access_token 可能已过期，清除缓存")
                token_manager.token = None
                token_manager.expire_time = 0
            
            return False
            
    except Exception as e:
        logger.error(f"❌ 发送消息异常: {e}")
        return False


# ============= 异步处理（简化版） =============

def process_message_async(user_id, content, agent_id, task_id):
    """异步处理消息（在后台线程中执行）"""
    def worker():
        try:
            # 调用 OpenClaw Agent
            result = call_openclaw_agent(agent_id, content, user_id, task_id)
            
            # 发送回复到企业微信
            reply = result.get('reply', '处理失败，请稍后再试。')
            send_wecom_message(user_id, reply)
            
        except Exception as e:
            logger.error(f"❌ 异步处理消息失败: {e}")
            # 发送错误提示
            send_wecom_message(user_id, "抱歉，处理您的请求时出现错误，请稍后再试。")
    
    # 在新线程中执行
    thread = threading.Thread(target=worker, daemon=True)
    thread.start()
    
    logger.info(f"✅ 已启动异步处理线程: task_id={task_id}")


# ============= Flask 路由 =============

@app.route('/wecom/callback', methods=['GET', 'POST'])
def wecom_callback():
    """企业微信回调接口"""
    
    # 获取参数
    msg_signature = request.args.get('msg_signature', '')
    timestamp = request.args.get('timestamp', '')
    nonce = request.args.get('nonce', '')
    
    # 初始化加解密工具
    crypto = WXBizMsgCrypt(WECOM_TOKEN, WECOM_ENCODING_AES_KEY, WECOM_CORP_ID)
    
    # GET 请求：验证回调 URL
    if request.method == 'GET':
        echo_str = request.args.get('echostr', '')
        
        logger.info("收到企业微信回调验证请求")
        
        # 验证签名
        if not crypto.verify_signature(msg_signature, timestamp, nonce, echo_str):
            logger.error("❌ 签名验证失败")
            return "signature verification failed", 403
        
        # 解密 echostr
        decrypted = crypto.decrypt(echo_str)
        if not decrypted:
            logger.error("❌ 解密失败")
            return "decryption failed", 500
        
        logger.info("✅ 回调验证成功")
        return decrypted
    
    # POST 请求：接收消息
    if request.method == 'POST':
        try:
            # 解析 XML
            xml_data = request.data
            root = ET.fromstring(xml_data)
            
            # 提取加密消息
            encrypt_msg = root.find('Encrypt').text
            
            # 验证签名
            if not crypto.verify_signature(msg_signature, timestamp, nonce, encrypt_msg):
                logger.error("❌ 消息签名验证失败")
                return "signature verification failed", 403
            
            # 解密消息
            decrypted_xml = crypto.decrypt(encrypt_msg)
            if not decrypted_xml:
                logger.error("❌ 消息解密失败")
                return "decryption failed", 500
            
            # 解析解密后的 XML
            msg_root = ET.fromstring(decrypted_xml)
            
            msg_type = msg_root.find('MsgType').text
            from_user = msg_root.find('FromUserName').text
            
            logger.info(f"📩 收到企业微信消息: type={msg_type}, from={from_user}")
            
            # 只处理文本消息
            if msg_type == 'text':
                content = msg_root.find('Content').text
                
                logger.info(f"消息内容: {content}")
                
                # 生成任务 ID
                task_id = str(uuid.uuid4())
                
                # 查询用户绑定的代理
                user_agents = get_user_agents(from_user)
                
                # 路由消息
                agent_id = route_message(content, user_agents)
                
                # 记录任务日志
                log_task(task_id, from_user, agent_id, content, status='processing')
                
                # 异步处理消息（避免企业微信回调超时）
                process_message_async(from_user, content, agent_id, task_id)
                
                # 立即返回成功（企业微信要求5秒内响应）
                return "success", 200
            
            else:
                logger.info(f"⚠️  忽略非文本消息: {msg_type}")
                return "success", 200
                
        except Exception as e:
            logger.error(f"❌ 处理消息失败: {e}")
            return "error", 500


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


@app.route('/test/send', methods=['POST'])
def test_send():
    """测试消息发送接口（仅供调试）"""
    data = request.json
    user_id = data.get('user_id')
    content = data.get('content')
    
    if not user_id or not content:
        return jsonify({'error': 'user_id and content are required'}), 400
    
    success = send_wecom_message(user_id, content)
    
    return jsonify({
        'success': success,
        'user_id': user_id,
        'timestamp': int(time.time())
    })


if __name__ == '__main__':
    # 启动时检查配置
    logger.info("=" * 60)
    logger.info("OpenClaw 企业微信网关启动中...")
    logger.info("=" * 60)
    
    # 检查必需的环境变量
    required_env = {
        'WECOM_CORP_ID': WECOM_CORP_ID,
        'WECOM_SECRET': WECOM_SECRET,
        'WECOM_TOKEN': WECOM_TOKEN,
        'WECOM_ENCODING_AES_KEY': WECOM_ENCODING_AES_KEY,
        'WECOM_AGENT_ID': WECOM_AGENT_ID,
    }
    
    missing = [k for k, v in required_env.items() if not v]
    if missing:
        logger.warning(f"⚠️  以下环境变量未配置: {', '.join(missing)}")
    
    logger.info(f"✅ 数据库路径: {DB_PATH}")
    logger.info(f"✅ OpenClaw Gateway: {OPENCLAW_GATEWAY_URL}")
    logger.info(f"✅ 企业微信 Agent ID: {WECOM_AGENT_ID}")
    logger.info("=" * 60)
    
    # 预先获取一次 access_token
    token = token_manager.get_token()
    if token:
        logger.info("✅ Access Token 已就绪")
    else:
        logger.warning("⚠️  Access Token 获取失败，请检查企业微信配置")
    
    # 启动 Flask 应用
    app.run(host='0.0.0.0', port=8000, debug=False)
