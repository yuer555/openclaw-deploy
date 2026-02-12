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
import socket
import requests

app = Flask(__name__)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 配置（从环境变量读取）
DB_PATH = os.getenv('DB_PATH', '/data/user_roles.db')
WECOM_CORP_ID = os.getenv('WECOM_CORP_ID', '')
WECOM_SECRET = os.getenv('WECOM_SECRET', '')
WECOM_TOKEN = os.getenv('WECOM_TOKEN', '')
WECOM_ENCODING_AES_KEY = os.getenv('WECOM_ENCODING_AES_KEY', '')

# 路由关键词配置
ROUTING_KEYWORDS = {
    'service-agent': ['客服', '咨询', '投诉', '售后', '反馈', '帮助', '问题'],
    'development-agent': ['开发', '代码', '功能', '接口', '部署', 'bug', '修复'],
    'testing-agent': ['测试', '用例', '自动化', 'qa', '质量'],
    'operation-agent': ['文案', '活动', '推广', '内容', '社群', '运营'],
    'product-agent': ['需求', '原型', '竞品', '分析', '文档', 'prd'],
}


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
        cursor.execute("SELECT agents FROM user_roles WHERE user_id = ?", (user_id,))
        result = cursor.fetchone()
        conn.close()
        
        if result:
            return result[0].split(',')
        return []
    except Exception as e:
        logger.error(f"查询用户绑定失败: {e}")
        return []


def log_task(task_id, user_id, agent, content, status='success'):
    """记录任务日志"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO task_logs (task_id, user_id, agent, task_content, status) VALUES (?, ?, ?, ?, ?)",
            (task_id, user_id, agent, content, status)
        )
        conn.commit()
        conn.close()
        logger.info(f"任务日志已记录: {task_id} -> {agent}")
    except Exception as e:
        logger.error(f"记录任务日志失败: {e}")


# ============= 消息路由 =============

def route_message(content, user_agents):
    """智能路由消息到合适的代理"""
    # 优先级路由
    priority_order = ['service-agent', 'development-agent', 'operation-agent', 'product-agent', 'testing-agent']
    
    # 关键词匹配
    for agent in priority_order:
        if agent in user_agents or not user_agents:  # 未绑定则可使用所有代理
            keywords = ROUTING_KEYWORDS.get(agent, [])
            for keyword in keywords:
                if keyword in content:
                    return agent
    
    # 默认路由到第一个可用代理
    if user_agents:
        return user_agents[0]
    return 'service-agent'  # 兜底默认


# ============= 企业微信 API =============

def get_access_token():
    """获取企业微信 access_token"""
    try:
        url = f"https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid={WECOM_CORP_ID}&corpsecret={WECOM_SECRET}"
        response = requests.get(url, timeout=10)
        data = response.json()
        
        if data.get('errcode') == 0:
            return data.get('access_token')
        else:
            logger.error(f"获取 access_token 失败: {data}")
            return None
    except Exception as e:
        logger.error(f"获取 access_token 异常: {e}")
        return None


def send_text_message(user_id, content, agent_id='1000002'):
    """发送文本消息给用户"""
    try:
        access_token = get_access_token()
        if not access_token:
            return False
        
        url = f"https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token={access_token}"
        data = {
            "touser": user_id,
            "msgtype": "text",
            "agentid": agent_id,
            "text": {
                "content": content
            },
            "safe": 0
        }
        
        response = requests.post(url, json=data, timeout=10)
        result = response.json()
        
        if result.get('errcode') == 0:
            logger.info(f"消息发送成功: {user_id}")
            return True
        else:
            logger.error(f"消息发送失败: {result}")
            return False
    except Exception as e:
        logger.error(f"发送消息异常: {e}")
        return False


# ============= 路由处理 =============

@app.route('/health', methods=['GET'])
def health_check():
    """健康检查"""
    return jsonify({"status": "healthy", "timestamp": int(time.time())})


@app.route('/stats', methods=['GET'])
def stats():
    """统计信息"""
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        
        # 今日任务数
        cursor.execute("SELECT COUNT(*) FROM task_logs WHERE date(created_at) = date('now')")
        today_tasks = cursor.fetchone()[0]
        
        # 总任务数
        cursor.execute("SELECT COUNT(*) FROM task_logs")
        total_tasks = cursor.fetchone()[0]
        
        # 用户数
        cursor.execute("SELECT COUNT(*) FROM user_roles")
        users = cursor.fetchone()[0]
        
        conn.close()
        
        return jsonify({
            "timestamp": int(time.time()),
            "today_tasks": today_tasks,
            "total_tasks": total_tasks,
            "users": users
        })
    except Exception as e:
        logger.error(f"获取统计信息失败: {e}")
        return jsonify({"error": str(e)}), 500


@app.route('/wecom/callback', methods=['GET', 'POST'])
def wecom_callback():
    """企业微信回调接口"""
    
    # GET 请求：URL 验证
    if request.method == 'GET':
        msg_signature = request.args.get('msg_signature', '')
        timestamp = request.args.get('timestamp', '')
        nonce = request.args.get('nonce', '')
        echostr = request.args.get('echostr', '')
        
        logger.info(f"收到验证请求: signature={msg_signature}, timestamp={timestamp}, nonce={nonce}")
        
        # 验证签名
        if WECOM_TOKEN and WECOM_ENCODING_AES_KEY:
            crypt = WXBizMsgCrypt(WECOM_TOKEN, WECOM_ENCODING_AES_KEY, WECOM_CORP_ID)
            
            if crypt.verify_signature(msg_signature, timestamp, nonce, echostr):
                # 解密 echostr
                decrypted = crypt.decrypt(echostr)
                if decrypted:
                    logger.info("URL 验证成功")
                    return decrypted
                else:
                    logger.error("解密 echostr 失败")
                    return "decrypt failed", 400
            else:
                logger.error("签名验证失败")
                return "signature verification failed", 403
        else:
            logger.warning("未配置 TOKEN 或 AES_KEY，跳过验证")
            return echostr  # 开发环境：直接返回
    
    # POST 请求：接收消息
    elif request.method == 'POST':
        try:
            # 获取参数
            msg_signature = request.args.get('msg_signature', '')
            timestamp = request.args.get('timestamp', '')
            nonce = request.args.get('nonce', '')
            
            # 获取加密消息
            xml_data = request.data
            logger.info(f"收到消息: {xml_data[:200]}")
            
            # 解析 XML
            root = ET.fromstring(xml_data)
            
            # 如果消息是加密的
            encrypt_elem = root.find('Encrypt')
            if encrypt_elem is not None and WECOM_ENCODING_AES_KEY:
                # 解密消息
                crypt = WXBizMsgCrypt(WECOM_TOKEN, WECOM_ENCODING_AES_KEY, WECOM_CORP_ID)
                
                if not crypt.verify_signature(msg_signature, timestamp, nonce, encrypt_elem.text):
                    logger.error("消息签名验证失败")
                    return "signature failed", 403
                
                decrypted_xml = crypt.decrypt(encrypt_elem.text)
                if not decrypted_xml:
                    logger.error("消息解密失败")
                    return "decrypt failed", 400
                
                # 重新解析解密后的 XML
                root = ET.fromstring(decrypted_xml)
            
            # 提取消息信息
            msg_type = root.find('MsgType').text if root.find('MsgType') is not None else 'text'
            from_user = root.find('FromUserName').text if root.find('FromUserName') is not None else 'unknown'
            
            # 只处理文本消息
            if msg_type != 'text':
                logger.info(f"忽略非文本消息: {msg_type}")
                return "success"
            
            content = root.find('Content').text if root.find('Content') is not None else ''
            
            # 查询用户绑定的代理
            user_agents = get_user_agents(from_user)
            
            # 路由消息
            agent = route_message(content, user_agents)
            
            # 生成任务 ID
            task_id = str(uuid.uuid4())
            
            # 记录任务日志
            log_task(task_id, from_user, agent, content)
            
            # TODO: 调用 OpenClaw Agent 处理消息
            # response_text = call_openclaw_agent(agent, content)
            
            # 暂时返回路由信息
            response_text = f"您的消息已转发给 {agent}\n任务ID: {task_id}\n\n（OpenClaw Agent 集成开发中...）"
            
            # 发送回复消息
            send_text_message(from_user, response_text)
            
            logger.info(f"消息处理完成: {from_user} -> {agent}")
            
            return jsonify({
                "status": "ok",
                "task_id": task_id,
                "agent": agent
            })
            
        except Exception as e:
            logger.error(f"处理消息失败: {e}", exc_info=True)
            return jsonify({"error": str(e)}), 500


if __name__ == '__main__':
    logger.info("企业微信网关启动中...")
    logger.info(f"数据库路径: {DB_PATH}")
    logger.info(f"企业ID: {WECOM_CORP_ID[:10] if WECOM_CORP_ID else '未配置'}...")
    
    app.run(host='0.0.0.0', port=8000, debug=False)
