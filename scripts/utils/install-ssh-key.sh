#!/bin/bash
# SSH 密钥安装脚本 - 使用密码认证
# 使用方法: ./install-ssh-key.sh root@139.199.200.144

SERVER="$1"
if [ -z "$SERVER" ]; then
    echo "用法: $0 root@139.199.200.144"
    exit 1
fi

echo "=========================================="
echo "  SSH 公钥安装工具"
echo "=========================================="
echo ""
echo "目标服务器: $SERVER"
echo "公钥文件: ~/.ssh/id_rsa.pub"
echo ""

if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "❌ 错误: 公钥文件不存在"
    exit 1
fi

echo "正在安装公钥到服务器..."
echo "（需要输入服务器的 root 密码）"
echo ""

# 使用 ssh-copy-id 安装公钥
ssh-copy-id -i ~/.ssh/id_rsa.pub "$SERVER"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ 公钥安装成功！"
    echo ""
    echo "现在可以测试连接："
    echo "  ssh $SERVER"
else
    echo ""
    echo "❌ 公钥安装失败"
    echo ""
    echo "请检查："
    echo "  1. 服务器 IP 地址是否正确"
    echo "  2. root 密码是否正确"
    echo "  3. 服务器是否允许密码登录"
    echo ""
    echo "如果密码登录被禁用，请使用 VNC 控制台手动添加公钥"
fi
