"""
Telegram Adapter 单元测试
测试 TelegramAdapter 的核心功能
"""

import unittest
import os
import sys
import sqlite3
import tempfile
from unittest.mock import Mock, patch, MagicMock

# 添加 src/gateway 到路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../src/gateway'))

from telegram_adapter import TelegramAdapter


class TestTelegramAdapter(unittest.TestCase):
    """TelegramAdapter 测试类"""

    def setUp(self):
        """测试前准备"""
        # 创建临时数据库
        self.db_fd, self.db_path = tempfile.mkstemp()

        # 初始化适配器
        self.adapter = TelegramAdapter(
            bot_token="test_token_123",
            db_path=self.db_path,
            openclaw_url="http://localhost:18789"
        )

    def tearDown(self):
        """测试后清理"""
        os.close(self.db_fd)
        os.unlink(self.db_path)

    def test_init(self):
        """测试初始化"""
        self.assertEqual(self.adapter.bot_token, "test_token_123")
        self.assertEqual(self.adapter.db_path, self.db_path)
        self.assertEqual(self.adapter.openclaw_url, "http://localhost:18789")
        self.assertIn("dispatcher", self.adapter.AGENTS)

    def test_database_initialization(self):
        """测试数据库初始化"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # 检查表是否存在
        cursor.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='telegram_sessions'"
        )
        result = cursor.fetchone()
        self.assertIsNotNone(result)

        conn.close()

    def test_create_session(self):
        """测试创建会话"""
        user_id = 123456
        agent_id = "dispatcher"

        self.adapter._create_session(user_id, agent_id)

        # 验证会话已创建
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT current_agent FROM telegram_sessions WHERE user_id = ?", (user_id,))
        result = cursor.fetchone()
        conn.close()

        self.assertIsNotNone(result)
        self.assertEqual(result[0], agent_id)

    def test_get_current_agent(self):
        """测试获取当前 Agent"""
        user_id = 123456

        # 第一次获取，应该创建默认会话
        agent_id = self.adapter._get_current_agent(user_id)
        self.assertEqual(agent_id, "dispatcher")

        # 切换 Agent
        self.adapter._switch_agent(user_id, "development")

        # 再次获取
        agent_id = self.adapter._get_current_agent(user_id)
        self.assertEqual(agent_id, "development")

    def test_switch_agent(self):
        """测试切换 Agent"""
        user_id = 123456

        # 创建初始会话
        self.adapter._create_session(user_id, "dispatcher")

        # 切换到开发工程师
        self.adapter._switch_agent(user_id, "development")

        # 验证切换成功
        agent_id = self.adapter._get_current_agent(user_id)
        self.assertEqual(agent_id, "development")

    def test_cmd_start(self):
        """测试 /start 命令"""
        user_id = 123456
        response = self.adapter._cmd_start(user_id)

        self.assertIn("欢迎使用 OpenClaw", response)
        self.assertIn("调度员", response)

        # 验证会话已创建
        agent_id = self.adapter._get_current_agent(user_id)
        self.assertEqual(agent_id, "dispatcher")

    def test_cmd_help(self):
        """测试 /help 命令"""
        response = self.adapter._cmd_help()

        self.assertIn("使用指南", response)
        self.assertIn("/dispatcher", response)
        self.assertIn("/help", response)

    def test_cmd_agents(self):
        """测试 /agents 命令"""
        response = self.adapter._cmd_agents()

        self.assertIn("可用的虚拟员工", response)
        self.assertIn("调度员", response)
        self.assertIn("开发工程师", response)
        self.assertIn("/dispatcher", response)

    def test_cmd_current(self):
        """测试 /current 命令"""
        user_id = 123456

        # 创建会话
        self.adapter._create_session(user_id, "development")

        response = self.adapter._cmd_current(user_id)

        self.assertIn("当前虚拟员工", response)
        self.assertIn("开发工程师", response)

    def test_cmd_reset(self):
        """测试 /reset 命令"""
        user_id = 123456

        # 创建会话并切换到开发工程师
        self.adapter._create_session(user_id, "development")

        # 重置
        response = self.adapter._cmd_reset(user_id)

        self.assertIn("会话已重置", response)

        # 验证已重置为调度员
        agent_id = self.adapter._get_current_agent(user_id)
        self.assertEqual(agent_id, "dispatcher")

    def test_cmd_switch_agent(self):
        """测试切换 Agent 命令"""
        user_id = 123456

        response = self.adapter._cmd_switch_agent(user_id, "product")

        self.assertIn("已切换到", response)
        self.assertIn("产品经理", response)

        # 验证切换成功
        agent_id = self.adapter._get_current_agent(user_id)
        self.assertEqual(agent_id, "product")

    def test_handle_command(self):
        """测试命令处理"""
        user_id = 123456
        chat_id = 123456

        # 测试 /start
        response = self.adapter._handle_command(user_id, chat_id, "/start")
        self.assertIn("欢迎", response)

        # 测试 /help
        response = self.adapter._handle_command(user_id, chat_id, "/help")
        self.assertIn("使用指南", response)

        # 测试未知命令
        response = self.adapter._handle_command(user_id, chat_id, "/unknown")
        self.assertIn("未知命令", response)

    @patch('telegram_adapter.requests.post')
    def test_send_message(self, mock_post):
        """测试发送消息"""
        mock_response = Mock()
        mock_response.json.return_value = {'ok': True, 'result': {'message_id': 1}}
        mock_post.return_value = mock_response

        chat_id = 123456
        text = "测试消息"

        result = self.adapter.send_message(chat_id, text)

        self.assertTrue(result['ok'])
        mock_post.assert_called_once()

    @patch('telegram_adapter.requests.post')
    def test_send_message_retry(self, mock_post):
        """测试发送消息重试机制"""
        # 前两次失败，第三次成功
        mock_response_fail = Mock()
        mock_response_fail.json.return_value = {'ok': False, 'error': 'timeout'}

        mock_response_success = Mock()
        mock_response_success.json.return_value = {'ok': True, 'result': {'message_id': 1}}

        mock_post.side_effect = [mock_response_fail, mock_response_fail, mock_response_success]

        chat_id = 123456
        text = "测试消息"

        result = self.adapter.send_message(chat_id, text, retry_count=3)

        self.assertTrue(result['ok'])
        self.assertEqual(mock_post.call_count, 3)

    @patch('telegram_adapter.requests.post')
    def test_send_chat_action(self, mock_post):
        """测试发送聊天动作"""
        chat_id = 123456

        self.adapter.send_chat_action(chat_id, 'typing')

        mock_post.assert_called_once()
        call_args = mock_post.call_args
        self.assertIn('typing', str(call_args))

    @patch('telegram_adapter.requests.post')
    def test_call_agent_success(self, mock_post):
        """测试调用 Agent 成功"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {'reply': 'AI 回复内容'}
        mock_post.return_value = mock_response

        response = self.adapter._call_agent("dispatcher", "测试消息", 123456)

        self.assertEqual(response, "AI 回复内容")

    @patch('telegram_adapter.requests.post')
    def test_call_agent_timeout(self, mock_post):
        """测试调用 Agent 超时"""
        import requests
        mock_post.side_effect = requests.exceptions.Timeout()

        response = self.adapter._call_agent("dispatcher", "测试消息", 123456)

        self.assertIn("超时", response)

    def test_handle_webhook_message(self):
        """测试处理 Webhook 消息"""
        update = {
            'message': {
                'from': {'id': 123456},
                'chat': {'id': 123456},
                'text': '/start'
            }
        }

        with patch.object(self.adapter, 'send_message') as mock_send:
            result = self.adapter.handle_webhook(update)

            self.assertTrue(result['ok'])
            mock_send.assert_called_once()

    def test_handle_webhook_no_message(self):
        """测试处理空 Webhook"""
        update = {}

        result = self.adapter.handle_webhook(update)

        self.assertTrue(result['ok'])


if __name__ == '__main__':
    unittest.main()
