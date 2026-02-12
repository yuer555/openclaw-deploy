#!/bin/bash
# 诊断脚本 - 在远程服务器执行

echo "=========================================="
echo "  SSH 配置诊断"
echo "=========================================="
echo ""

echo "1. 检查 authorized_keys 文件..."
if [ -f ~/.ssh/authorized_keys ]; then
    echo "   ✓ 文件存在"
    echo "   文件大小: $(wc -c < ~/.ssh/authorized_keys) 字节"
    echo "   公钥数量: $(wc -l < ~/.ssh/authorized_keys) 行"
else
    echo "   ✗ 文件不存在"
fi
echo ""

echo "2. 检查文件权限..."
ls -la ~/.ssh/
echo ""

echo "3. 检查公钥内容（前50字符）..."
if [ -f ~/.ssh/authorized_keys ]; then
    head -c 50 ~/.ssh/authorized_keys
    echo "..."
fi
echo ""
echo ""

echo "4. 检查 SSH 配置..."
sudo grep -E "^(PubkeyAuthentication|AuthorizedKeysFile|PasswordAuthentication)" /etc/ssh/sshd_config
echo ""

echo "5. 检查 SSH 服务状态..."
sudo systemctl status sshd | head -5
echo ""

echo "=========================================="
echo "  请将以上输出发送给我"
echo "=========================================="
