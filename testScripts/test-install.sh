#!/usr/bin/env bash
# 自动化测试 install-openclaw.sh 脚本

set -euo pipefail

echo "=== OpenClaw 安装脚本自动化测试 ==="
echo ""

# 模拟用户输入
cat << 'EOF' | bash scripts/install-openclaw.sh
n
n
2
test-provider
https://test.example.com/v1
test-api-key-12345
openai-responses
test-model-1
Test Model 1
200000
128000
y

y
test-provider/test-model-1
3
n
n
EOF

echo ""
echo "=== 测试完成 ==="
