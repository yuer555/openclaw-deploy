# Design: Telegram Bot 技术设计

**Change ID**: `add-telegram-bot-support`
**Status**: 🟡 Proposed

---

## 🏗️ 系统架构

### 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                        Telegram 用户                             │
│                   (移动端 + PC 端 + Web)                         │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS
                             │ 发送消息/命令
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Telegram 服务器                              │
│                  (api.telegram.org)                             │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS Webhook
                             │ POST /telegram/webhook
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              OpenClaw Gateway (扩展 Telegram 支持)              │
│                   src/gateway/                                  │
│                      端口: 8000                                  │
├─────────────────────────────────────────────────────────────────┤
│ 现有模块:                                                        │
│ • 企业微信适配器 (wecom_gateway.py)                            │
│   └─ /wecom/callback                                           │
│                                                                 │
│ 新增模块:                                                        │
│ • Telegram 适配器 (telegram_adapter.py)                        │
│   ├─ /telegram/webhook - Webhook 接收                         │
│   ├─ 命令处理 (/start, /help, /agents, /dispatcher...)        │
│   ├─ 会话管理 (user_id -> agent_id)                           │
│   └─ 消息路由                                                   │
│                                                                 │
│ 共享模块:                                                        │
│ • 数据库 (SQLite/PostgreSQL)                                   │
│ • 日志系统                                                       │
│ • 配置管理                                                       │
└────────────────────────────┬────────────────────────────────────┘
                             │
                             │ 直接调用或 HTTP API
                             ▼
┌─────────────────────────────────────────────────────────────────┐
│              OpenClaw Core (现有系统)                            │
│                   Agent 系统                                     │
├─────────────────────────────────────────────────────────────────┤
│ • Agent 管理和调度                                              │
│ • AI 模型调用 (GitHub Copilot / OpenAI)                        │
│ • 会话管理和上下文                                              │
└─────────────────────────────────────────────────────────────────┘
```

### 关键设计决策

1. **集成而非独立**：Telegram 适配器集成到现有的 gateway 中，而不是创建新服务
2. **复用基础设施**：使用现有的数据库、日志、配置系统
3. **简化部署**：不需要额外的 Nginx 或网关层
4. **本地测试友好**：使用 ngrok 即可测试 Webhook

---

## 📦 核心组件设计

### 1. Telegram 适配器 (telegram_adapter.py)

#### 文件位置
```
src/gateway/telegram_adapter.py  # 新增
src/gateway/wecom_gateway.py     # 已有
src/gateway/main.py              # 主入口（可能需要创建）
```

#### 职责
- 接收和验证 Telegram Webhook 请求
- 解析 Update 对象
- 处理命令和普通消息
- 管理用户会话
- 调用 OpenClaw Core 的 Agent
- 发送响应消息

#### 类设计

```python
class TelegramAdapter:
    """Telegram Bot 适配器"""

    def __init__(self, bot_token: str, db_path: str):
        """
        初始化适配器

        Args:
            bot_token: Telegram Bot Token
            db_path: 数据库路径
        """
        self.bot_token = bot_token
        self.api_base = f"https://api.telegram.org/bot{bot_token}"
        self.db_path = db_path

        # 虚拟员工配置
        self.agents = {
            'dispatcher': {'name': '调度员', 'desc': '智能任务分发和路由'},
            'operation': {'name': '运营专员', 'desc': '数据分析、报表生成'},
            'product': {'name': '产品经理', 'desc': '需求管理、功能设计'},
            'development': {'name': '开发工程师', 'desc': '技术支持、代码审查'},
            'testing': {'name': '测试工程师', 'desc': '质量保障、测试用例'},
            'service': {'name': '客服专员', 'desc': '客户服务、问题解答'},
        }

    def handle_webhook(self, update: dict) -> dict:
        """
        处理 Webhook 请求

        Args:
            update: Telegram Update 对象

        Returns:
            响应字典
        """
        try:
            message = update.get('message')
            if not message:
                return {'ok': True}

            user_id = message['from']['id']
            chat_id = message['chat']['id']
            text = message.get('text', '')

            # 判断是命令还是普通消息
            if text.startswith('/'):
                response = self._handle_command(user_id, chat_id, text)
            else:
                response = self._handle_message(user_id, chat_id, text)

            # 发送响应
            if response:
                self.send_message(chat_id, response)

            return {'ok': True}

        except Exception as e:
            logger.error(f"处理 Webhook 失败: {e}")
            return {'ok': False, 'error': str(e)}

    def _handle_command(self, user_id: int, chat_id: int, text: str) -> str:
        """处理命令"""
        command = text.split()[0].lower()

        if command == '/start':
            return self._cmd_start(user_id, chat_id)
        elif command == '/help':
            return self._cmd_help()
        elif command == '/agents':
            return self._cmd_agents()
        elif command == '/current':
            return self._cmd_current(user_id)
        elif command == '/reset':
            return self._cmd_reset(user_id)
        elif command in ['/dispatcher', '/operation', '/product',
                        '/development', '/testing', '/service']:
            agent_id = command[1:]
            return self._cmd_switch_agent(user_id, agent_id)
        else:
            return "❓ 未知命令，使用 /help 查看帮助"

    def _handle_message(self, user_id: int, chat_id: int, text: str) -> str:
        """处理普通消息"""
        # 获取当前 Agent
        agent_id = self._get_current_agent(user_id)

        # 发送"正在输入"状态
        self.send_chat_action(chat_id, 'typing')

        # 调用 OpenClaw Agent
        try:
            response = self._call_agent(agent_id, text, user_id)
            return response
        except Exception as e:
            logger.error(f"调用 Agent 失败: {e}")
            return "❌ 系统暂时无法处理您的请求，请稍后再试"

    def _call_agent(self, agent_id: str, message: str, user_id: int) -> str:
        """
        调用 OpenClaw Agent

        Args:
            agent_id: Agent ID
            message: 用户消息
            user_id: 用户 ID

        Returns:
            AI 响应
        """
        # 方式1: 如果 OpenClaw 是独立服务，通过 HTTP API 调用
        # url = f"{OPENCLAW_GATEWAY_URL}/api/v1/sessions/send"
        # response = requests.post(url, json={...})

        # 方式2: 如果 OpenClaw 是库/模块，直接导入使用
        from openclaw.agents import AgentManager
        agent_manager = AgentManager()
        response = agent_manager.process_message(
            agent_id=f"{agent_id}-agent",
            message=message,
            user_id=f"telegram-{user_id}"
        )
        return response

    def send_message(self, chat_id: int, text: str) -> dict:
        """发送消息"""
        url = f"{self.api_base}/sendMessage"
        payload = {
            'chat_id': chat_id,
            'text': text,
            'parse_mode': 'Markdown'
        }
        response = requests.post(url, json=payload, timeout=10)
        return response.json()

    def send_chat_action(self, chat_id: int, action: str = 'typing'):
        """发送聊天动作"""
        url = f"{self.api_base}/sendChatAction"
        payload = {'chat_id': chat_id, 'action': action}
        requests.post(url, json=payload, timeout=5)

    # 会话管理方法
    def _get_current_agent(self, user_id: int) -> str:
        """获取当前 Agent"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute(
            "SELECT current_agent FROM telegram_sessions WHERE user_id = ?",
            (user_id,)
        )
        row = cursor.fetchone()
        conn.close()

        if row:
            return row[0]
        else:
            # 创建新会话，默认调度员
            self._create_session(user_id, 'dispatcher')
            return 'dispatcher'

    def _create_session(self, user_id: int, agent_id: str):
        """创建会话"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute(
            """INSERT OR REPLACE INTO telegram_sessions
               (user_id, current_agent, last_active)
               VALUES (?, ?, ?)""",
            (user_id, agent_id, datetime.now())
        )
        conn.commit()
        conn.close()

    def _switch_agent(self, user_id: int, agent_id: str):
        """切换 Agent"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute(
            """UPDATE telegram_sessions
               SET current_agent = ?, last_active = ?
               WHERE user_id = ?""",
            (agent_id, datetime.now(), user_id)
        )
        conn.commit()
        conn.close()

    # 命令处理方法
    def _cmd_start(self, user_id: int, chat_id: int) -> str:
        """处理 /start 命令"""
        self._create_session(user_id, 'dispatcher')
        return """👋 欢迎使用 OpenClaw 虚拟员工！

我们有 6 位专业的 AI 虚拟员工为您服务：
• 调度员 - 智能任务分发
• 运营专员 - 数据分析
• 产品经理 - 需求管理
• 开发工程师 - 技术支持
• 测试工程师 - 质量保障
• 客服专员 - 客户服务

💡 使用 /agents 查看所有员工
💡 使用 /help 查看帮助信息
💡 直接发送消息开始对话

当前默认员工：调度员"""

    def _cmd_help(self) -> str:
        """处理 /help 命令"""
        return """📖 OpenClaw 使用指南

🤖 切换虚拟员工：
/dispatcher - 调度员
/operation - 运营专员
/product - 产品经理
/development - 开发工程师
/testing - 测试工程师
/service - 客服专员

📋 其他命令：
/agents - 查看所有虚拟员工
/current - 查看当前员工
/reset - 重置会话
/help - 显示此帮助

💬 使用方法：
1. 选择一个虚拟员工（使用命令切换）
2. 直接发送消息进行对话
3. 随时切换到其他员工"""

    def _cmd_agents(self) -> str:
        """处理 /agents 命令"""
        lines = ["🤖 可用的虚拟员工：\n"]
        emojis = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣']

        for i, (agent_id, info) in enumerate(self.agents.items()):
            lines.append(f"{emojis[i]} {info['name']} - {info['desc']}")
            lines.append(f"   命令：/{agent_id}\n")

        lines.append("💡 使用命令切换虚拟员工，或直接发送消息给当前员工")
        return '\n'.join(lines)

    def _cmd_current(self, user_id: int) -> str:
        """处理 /current 命令"""
        agent_id = self._get_current_agent(user_id)
        agent_info = self.agents.get(agent_id, {})

        return f"""📍 当前虚拟员工：{agent_info.get('name', '未知')}
职责：{agent_info.get('desc', '无描述')}

💬 直接发送消息即可与当前员工对话
🔄 使用 /agents 查看其他员工"""

    def _cmd_reset(self, user_id: int) -> str:
        """处理 /reset 命令"""
        self._switch_agent(user_id, 'dispatcher')
        return """🔄 会话已重置

• 当前员工：调度员

💡 使用 /agents 选择其他员工"""

    def _cmd_switch_agent(self, user_id: int, agent_id: str) -> str:
        """处理切换员工命令"""
        self._switch_agent(user_id, agent_id)
        agent_info = self.agents.get(agent_id, {})

        return f"""✅ 已切换到：{agent_info.get('name', '未知')}

我可以帮您：{agent_info.get('desc', '无描述')}

💬 直接发送消息开始对话"""
```

---

## 🗄️ 数据库设计

### 表结构

#### telegram_sessions 表

```sql
CREATE TABLE IF NOT EXISTS telegram_sessions (
    user_id BIGINT PRIMARY KEY,
    current_agent VARCHAR(50) DEFAULT 'dispatcher',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_last_active (last_active)
);
```

**说明**：
- 简化设计，只存储必要信息
- 复用现有数据库连接
- 与企业微信的表结构类似

---

## 🔌 Flask 路由集成

### 主入口文件 (src/gateway/main.py 或扩展 wecom_gateway.py)

```python
from flask import Flask, request, jsonify
from telegram_adapter import TelegramAdapter
import os

app = Flask(__name__)

# 初始化 Telegram 适配器
telegram_bot_token = os.getenv('TELEGRAM_BOT_TOKEN')
db_path = os.getenv('DB_PATH', '/data/openclaw.db')

if telegram_bot_token:
    telegram_adapter = TelegramAdapter(telegram_bot_token, db_path)

# Telegram Webhook 路由
@app.route('/telegram/webhook', methods=['POST'])
def telegram_webhook():
    """Telegram Webhook 端点"""
    # 验证 Secret Token
    secret_token = os.getenv('TELEGRAM_WEBHOOK_SECRET')
    request_token = request.headers.get('X-Telegram-Bot-Api-Secret-Token')

    if secret_token and request_token != secret_token:
        return jsonify({'error': 'Unauthorized'}), 403

    # 处理 Update
    update = request.json
    result = telegram_adapter.handle_webhook(update)

    return jsonify(result)

# 健康检查
@app.route('/telegram/health', methods=['GET'])
def telegram_health():
    """Telegram 健康检查"""
    return jsonify({
        'status': 'healthy',
        'service': 'telegram-adapter',
        'timestamp': int(time.time())
    })

# 企业微信路由（已有）
@app.route('/wecom/callback', methods=['GET', 'POST'])
def wecom_callback():
    # 现有的企业微信处理逻辑
    pass

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=False)
```

---

## 🚀 部署方案

### 本地测试

```bash
# 1. 配置环境变量
cd local/
vim .env.local
# 添加：
# TELEGRAM_BOT_TOKEN=your_bot_token
# TELEGRAM_WEBHOOK_SECRET=your_secret

# 2. 启动服务
./2-start-local.sh

# 3. 使用 ngrok 暴露端口
ngrok http 3000

# 4. 设置 Webhook
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=https://your-ngrok-url.ngrok.io/telegram/webhook" \
  -d "secret_token=your_secret"

# 5. 设置命令菜单
curl -X POST "https://api.telegram.org/bot<TOKEN>/setMyCommands" \
  -H "Content-Type: application/json" \
  -d @telegram-commands.json

# 6. 测试
# 在 Telegram 中搜索你的 Bot 并发送消息
```

### 生产部署

```bash
# 1. 配置域名和 SSL
./production/4-setup-ssl.sh your-domain.com

# 2. 配置环境变量
vim /opt/openclaw/.env
# 添加 Telegram 配置

# 3. 部署服务
./production/3-deploy-production.sh

# 4. 设置 Webhook（使用生产域名）
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook" \
  -d "url=https://your-domain.com/telegram/webhook" \
  -d "secret_token=your_secret"

# 5. 设置命令菜单
curl -X POST "https://api.telegram.org/bot<TOKEN>/setMyCommands" \
  -H "Content-Type: application/json" \
  -d @telegram-commands.json
```

---

## 🔒 安全设计

### Webhook 验证

```python
def verify_webhook(request):
    """验证 Webhook 请求"""
    secret_token = os.getenv('TELEGRAM_WEBHOOK_SECRET')
    request_token = request.headers.get('X-Telegram-Bot-Api-Secret-Token')

    if not secret_token or request_token != secret_token:
        logger.warning("Webhook 验证失败")
        return False

    return True
```

### 敏感信息保护

- Bot Token 存储在环境变量中
- 日志中脱敏用户消息
- HTTPS 强制使用（Telegram 要求）

---

## 📊 性能优化

### 简化设计

- 不需要额外的网关层
- 直接集成到现有服务
- 复用数据库连接
- 最小化网络跳转

### 响应时间

- Webhook 响应 < 5 秒（Telegram 要求）
- AI 处理可以异步（如果需要）

---

**设计文档版本**: V2.0 (简化版)
**创建时间**: 2026-02-24
**维护者**: OpenClaw Team


#### 职责
- 接收和验证 Telegram Webhook 请求
- 解析 Update 对象
- 分发到命令处理器或消息路由器
- 管理与 Telegram API 的交互

#### 类设计

```python
class TelegramGateway:
    """Telegram Bot 网关主类"""

    def __init__(self, bot_token: str, openclaw_url: str, db_url: str):
        """
        初始化网关

        Args:
            bot_token: Telegram Bot Token
            openclaw_url: OpenClaw Gateway URL
            db_url: 数据库连接 URL
        """
        self.bot_token = bot_token
        self.openclaw_url = openclaw_url
        self.api_base = f"https://api.telegram.org/bot{bot_token}"

        # 初始化子组件
        self.session_manager = SessionManager(db_url)
        self.command_handler = CommandHandler(self.session_manager)
        self.message_router = MessageRouter(openclaw_url, self.session_manager)

    def handle_webhook(self, update: dict) -> dict:
        """
        处理 Webhook 请求

        Args:
            update: Telegram Update 对象

        Returns:
            响应字典
        """
        try:
            # 提取消息
            message = update.get('message')
            if not message:
                return {'ok': True}

            user_id = message['from']['id']
            chat_id = message['chat']['id']
            text = message.get('text', '')

            # 记录日志
            logger.info(f"收到消息: user_id={user_id}, text={text[:50]}")

            # 判断是命令还是普通消息
            if text.startswith('/'):
                response = self.command_handler.handle(message)
            else:
                response = self.message_router.route(message)

            # 发送响应
            if response:
                self.send_message(chat_id, response)

            return {'ok': True}

        except Exception as e:
            logger.error(f"处理 Webhook 失败: {e}")
            return {'ok': False, 'error': str(e)}

    def send_message(self, chat_id: int, text: str,
                     parse_mode: str = 'Markdown') -> dict:
        """
        发送消息到 Telegram

        Args:
            chat_id: 聊天 ID
            text: 消息文本
            parse_mode: 解析模式 (Markdown/HTML)

        Returns:
            API 响应
        """
        url = f"{self.api_base}/sendMessage"
        payload = {
            'chat_id': chat_id,
            'text': text,
            'parse_mode': parse_mode
        }

        response = requests.post(url, json=payload, timeout=10)
        return response.json()

    def send_chat_action(self, chat_id: int, action: str = 'typing'):
        """
        发送聊天动作（如"正在输入..."）

        Args:
            chat_id: 聊天 ID
            action: 动作类型 (typing/upload_photo/etc)
        """
        url = f"{self.api_base}/sendChatAction"
        payload = {
            'chat_id': chat_id,
            'action': action
        }

        requests.post(url, json=payload, timeout=5)
```

---

### 2. Session Manager (telegram_session.py)

#### 职责
- 管理用户会话状态
- 存储和检索会话信息
- 处理会话超时

#### 类设计

```python
class SessionManager:
    """会话管理器"""

    def __init__(self, db_url: str):
        """
        初始化会话管理器

        Args:
            db_url: 数据库连接 URL
        """
        self.db_url = db_url
        self.cache = {}  # 内存缓存，减少数据库查询

    def get_or_create_session(self, user_id: int, chat_id: int) -> dict:
        """
        获取或创建会话

        Args:
            user_id: 用户 ID
            chat_id: 聊天 ID

        Returns:
            会话字典
        """
        # 先查缓存
        if user_id in self.cache:
            session = self.cache[user_id]
            # 更新最后活跃时间
            session['last_active'] = datetime.now()
            self.update_session(user_id, session)
            return session

        # 查数据库
        conn = sqlite3.connect(self.db_url)
        cursor = conn.cursor()

        cursor.execute(
            "SELECT * FROM telegram_sessions WHERE user_id = ?",
            (user_id,)
        )
        row = cursor.fetchone()

        if row:
            session = {
                'user_id': row[0],
                'chat_id': row[1],
                'current_agent': row[2],
                'created_at': row[3],
                'last_active': row[4],
                'message_count': row[5]
            }
        else:
            # 创建新会话
            session = {
                'user_id': user_id,
                'chat_id': chat_id,
                'current_agent': 'dispatcher',  # 默认调度员
                'created_at': datetime.now(),
                'last_active': datetime.now(),
                'message_count': 0
            }

            cursor.execute(
                """INSERT INTO telegram_sessions
                   (user_id, chat_id, current_agent, created_at, last_active, message_count)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (user_id, chat_id, session['current_agent'],
                 session['created_at'], session['last_active'], 0)
            )
            conn.commit()

        conn.close()

        # 更新缓存
        self.cache[user_id] = session
        return session

    def update_session(self, user_id: int, updates: dict):
        """
        更新会话信息

        Args:
            user_id: 用户 ID
            updates: 更新字典
        """
        conn = sqlite3.connect(self.db_url)
        cursor = conn.cursor()

        # 构建 UPDATE 语句
        set_clause = ', '.join([f"{k} = ?" for k in updates.keys()])
        values = list(updates.values()) + [user_id]

        cursor.execute(
            f"UPDATE telegram_sessions SET {set_clause} WHERE user_id = ?",
            values
        )
        conn.commit()
        conn.close()

        # 更新缓存
        if user_id in self.cache:
            self.cache[user_id].update(updates)

    def switch_agent(self, user_id: int, agent_id: str):
        """
        切换虚拟员工

        Args:
            user_id: 用户 ID
            agent_id: Agent ID
        """
        self.update_session(user_id, {
            'current_agent': agent_id,
            'last_active': datetime.now()
        })

    def reset_session(self, user_id: int):
        """
        重置会话

        Args:
            user_id: 用户 ID
        """
        self.update_session(user_id, {
            'current_agent': 'dispatcher',
            'message_count': 0,
            'last_active': datetime.now()
        })

    def increment_message_count(self, user_id: int):
        """
        增加消息计数

        Args:
            user_id: 用户 ID
        """
        if user_id in self.cache:
            self.cache[user_id]['message_count'] += 1

        conn = sqlite3.connect(self.db_url)
        cursor = conn.cursor()
        cursor.execute(
            "UPDATE telegram_sessions SET message_count = message_count + 1 WHERE user_id = ?",
            (user_id,)
        )
        conn.commit()
        conn.close()
```

---

### 3. Command Handler (telegram_commands.py)

#### 职责
- 解析和执行命令
- 生成命令响应文本
- 更新会话状态

#### 类设计

```python
class CommandHandler:
    """命令处理器"""

    # 虚拟员工配置
    AGENTS = {
        'dispatcher': {'name': '调度员', 'desc': '智能任务分发和路由'},
        'operation': {'name': '运营专员', 'desc': '数据分析、报表生成'},
        'product': {'name': '产品经理', 'desc': '需求管理、功能设计'},
        'development': {'name': '开发工程师', 'desc': '技术支持、代码审查'},
        'testing': {'name': '测试工程师', 'desc': '质量保障、测试用例'},
        'service': {'name': '客服专员', 'desc': '客户服务、问题解答'},
    }

    def __init__(self, session_manager: SessionManager):
        """
        初始化命令处理器

        Args:
            session_manager: 会话管理器实例
        """
        self.session_manager = session_manager

    def handle(self, message: dict) -> str:
        """
        处理命令

        Args:
            message: Telegram 消息对象

        Returns:
            响应文本
        """
        user_id = message['from']['id']
        chat_id = message['chat']['id']
        text = message['text']

        # 提取命令
        command = text.split()[0].lower()

        # 路由到具体命令处理方法
        if command == '/start':
            return self.cmd_start(user_id, chat_id)
        elif command == '/help':
            return self.cmd_help()
        elif command == '/agents':
            return self.cmd_agents()
        elif command == '/current':
            return self.cmd_current(user_id, chat_id)
        elif command == '/reset':
            return self.cmd_reset(user_id, chat_id)
        elif command in ['/dispatcher', '/operation', '/product',
                        '/development', '/testing', '/service']:
            agent_id = command[1:]  # 去掉 /
            return self.cmd_switch_agent(user_id, chat_id, agent_id)
        else:
            return "❓ 未知命令，使用 /help 查看帮助"

    def cmd_start(self, user_id: int, chat_id: int) -> str:
        """处理 /start 命令"""
        # 创建会话
        session = self.session_manager.get_or_create_session(user_id, chat_id)

        return """👋 欢迎使用 OpenClaw 虚拟员工！

我们有 6 位专业的 AI 虚拟员工为您服务：
• 调度员 - 智能任务分发
• 运营专员 - 数据分析
• 产品经理 - 需求管理
• 开发工程师 - 技术支持
• 测试工程师 - 质量保障
• 客服专员 - 客户服务

💡 使用 /agents 查看所有员工
💡 使用 /help 查看帮助信息
💡 直接发送消息开始对话

当前默认员工：调度员"""

    def cmd_help(self) -> str:
        """处理 /help 命令"""
        return """📖 OpenClaw 使用指南

🤖 切换虚拟员工：
/dispatcher - 调度员
/operation - 运营专员
/product - 产品经理
/development - 开发工程师
/testing - 测试工程师
/service - 客服专员

📋 其他命令：
/agents - 查看所有虚拟员工
/current - 查看当前员工
/reset - 重置会话
/help - 显示此帮助

💬 使用方法：
1. 选择一个虚拟员工（使用命令切换）
2. 直接发送消息进行对话
3. 随时切换到其他员工

❓ 问题反馈：https://github.com/your-org/openclaw-deploy/issues"""

    def cmd_agents(self) -> str:
        """处理 /agents 命令"""
        lines = ["🤖 可用的虚拟员工：\n"]

        emojis = ['1️⃣', '2️⃣', '3️⃣', '4️⃣', '5️⃣', '6️⃣']
        for i, (agent_id, info) in enumerate(self.AGENTS.items()):
            lines.append(f"{emojis[i]} {info['name']} - {info['desc']}")
            lines.append(f"   命令：/{agent_id}\n")

        lines.append("💡 使用命令切换虚拟员工，或直接发送消息给当前员工")

        return '\n'.join(lines)

    def cmd_current(self, user_id: int, chat_id: int) -> str:
        """处理 /current 命令"""
        session = self.session_manager.get_or_create_session(user_id, chat_id)
        agent_id = session['current_agent']
        agent_info = self.AGENTS.get(agent_id, {})

        return f"""📍 当前虚拟员工：{agent_info.get('name', '未知')}
职责：{agent_info.get('desc', '无描述')}

💬 直接发送消息即可与当前员工对话
🔄 使用 /agents 查看其他员工"""

    def cmd_reset(self, user_id: int, chat_id: int) -> str:
        """处理 /reset 命令"""
        self.session_manager.reset_session(user_id)

        return """🔄 会话已重置

• 当前员工：调度员
• 消息计数：0

💡 使用 /agents 选择其他员工"""

    def cmd_switch_agent(self, user_id: int, chat_id: int, agent_id: str) -> str:
        """处理切换员工命令"""
        # 确保会话存在
        self.session_manager.get_or_create_session(user_id, chat_id)

        # 切换 Agent
        self.session_manager.switch_agent(user_id, agent_id)

        agent_info = self.AGENTS.get(agent_id, {})

        return f"""✅ 已切换到：{agent_info.get('name', '未知')}

我可以帮您：{agent_info.get('desc', '无描述')}

💬 直接发送消息开始对话"""
```

---

### 4. Message Router (telegram_router.py)

#### 职责
- 路由普通消息到 OpenClaw
- 处理 AI 响应
- 错误处理和重试

#### 类设计

```python
class MessageRouter:
    """消息路由器"""

    def __init__(self, openclaw_url: str, session_manager: SessionManager):
        """
        初始化消息路由器

        Args:
            openclaw_url: OpenClaw Gateway URL
            session_manager: 会话管理器实例
        """
        self.openclaw_url = openclaw_url
        self.session_manager = session_manager

    def route(self, message: dict) -> str:
        """
        路由消息到 OpenClaw

        Args:
            message: Telegram 消息对象

        Returns:
            AI 响应文本
        """
        user_id = message['from']['id']
        chat_id = message['chat']['id']
        text = message.get('text', '')

        # 获取会话
        session = self.session_manager.get_or_create_session(user_id, chat_id)
        agent_id = session['current_agent']

        # 增加消息计数
        self.session_manager.increment_message_count(user_id)

        try:
            # 调用 OpenClaw API
            response = self.call_openclaw(agent_id, text, user_id)

            if response['success']:
                return response['reply']
            else:
                return f"❌ {response.get('error', '处理失败')}"

        except requests.exceptions.Timeout:
            return "⏱️ 处理超时，请稍后重试"
        except Exception as e:
            logger.error(f"路由消息失败: {e}")
            return "❌ 系统暂时无法处理您的请求，请稍后再试"

    def call_openclaw(self, agent_id: str, message: str, user_id: int) -> dict:
        """
        调用 OpenClaw Gateway API

        Args:
            agent_id: Agent ID
            message: 用户消息
            user_id: 用户 ID

        Returns:
            API 响应字典
        """
        url = f"{self.openclaw_url}/api/v1/sessions/send"

        payload = {
            'message': message,
            'agentId': f"{agent_id}-agent",
            'label': f"telegram-{user_id}",
            'timeoutSeconds': 30
        }

        headers = {
            'Content-Type': 'application/json'
        }

        response = requests.post(url, json=payload, headers=headers, timeout=35)

        if response.status_code == 200:
            data = response.json()
            return {
                'success': True,
                'reply': data.get('reply', data.get('message', '收到回复但内容为空'))
            }
        else:
            return {
                'success': False,
                'error': f'API 返回错误: {response.status_code}'
            }
```

---

## 🗄️ 数据库设计

### 表结构

#### telegram_sessions 表

```sql
CREATE TABLE telegram_sessions (
    user_id BIGINT PRIMARY KEY,
    chat_id BIGINT NOT NULL,
    current_agent VARCHAR(50) DEFAULT 'dispatcher',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    message_count INTEGER DEFAULT 0,

    INDEX idx_last_active (last_active),
    INDEX idx_current_agent (current_agent)
);
```

#### telegram_messages 表

```sql
CREATE TABLE telegram_messages (
    id SERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    message_id BIGINT NOT NULL,
    message_text TEXT,
    agent_id VARCHAR(50),
    response_text TEXT,
    status VARCHAR(20),
    error_message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at),
    INDEX idx_status (status)
);
```

---

## 🔌 API 集成

### Telegram Bot API

#### 主要端点

1. **setWebhook** - 设置 Webhook
```http
POST https://api.telegram.org/bot<TOKEN>/setWebhook
Content-Type: application/json

{
  "url": "https://your-domain.com/telegram/webhook",
  "secret_token": "your-secret-token",
  "allowed_updates": ["message"]
}
```

2. **setMyCommands** - 设置命令菜单
```http
POST https://api.telegram.org/bot<TOKEN>/setMyCommands
Content-Type: application/json

{
  "commands": [
    {"command": "start", "description": "开始使用"},
    {"command": "help", "description": "显示帮助"},
    ...
  ]
}
```

3. **sendMessage** - 发送消息
```http
POST https://api.telegram.org/bot<TOKEN>/sendMessage
Content-Type: application/json

{
  "chat_id": 123456,
  "text": "消息内容",
  "parse_mode": "Markdown"
}
```

4. **sendChatAction** - 发送聊天动作
```http
POST https://api.telegram.org/bot<TOKEN>/sendChatAction
Content-Type: application/json

{
  "chat_id": 123456,
  "action": "typing"
}
```

---

## 🔒 安全设计

### Webhook 验证

```python
def verify_webhook(request):
    """验证 Webhook 请求"""
    secret_token = os.getenv('TELEGRAM_WEBHOOK_SECRET')
    request_token = request.headers.get('X-Telegram-Bot-Api-Secret-Token')

    if not secret_token or request_token != secret_token:
        logger.warning("Webhook 验证失败")
        return False

    return True
```

### 敏感信息保护

- Bot Token 存储在环境变量中
- 日志中脱敏用户消息
- 数据库连接使用加密
- HTTPS 强制使用

---

## 📊 性能优化

### 缓存策略

- 会话信息内存缓存（减少数据库查询）
- 缓存过期时间：30 分钟
- LRU 缓存淘汰策略

### 异步处理

- Webhook 响应立即返回（< 5 秒）
- AI 处理在后台异步执行
- 使用消息队列处理高并发

### 数据库优化

- 添加索引优化查询
- 定期清理过期会话
- 使用连接池管理数据库连接

---

## 🔍 监控和日志

### 日志级别

- **DEBUG**: 详细的调试信息
- **INFO**: 正常操作日志
- **WARNING**: 警告信息
- **ERROR**: 错误信息

### 关键指标

- Webhook 接收数量
- 消息处理成功率
- 平均响应时间
- 错误率
- 活跃用户数

---

**设计文档版本**: V1.0
**创建时间**: 2026-02-24
**维护者**: OpenClaw Team
