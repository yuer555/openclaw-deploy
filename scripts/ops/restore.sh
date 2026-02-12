#!/bin/bash
# scripts/restore.sh - 恢复配置和数据

BACKUP_DIR="/opt/openclaw/backups"

echo "=== OpenClaw 数据恢复 ==="

# 1. 列出可用备份
if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A $BACKUP_DIR/openclaw_backup_*.tar.gz 2>/dev/null)" ]; then
    echo "未找到备份文件"
    echo "备份目录: $BACKUP_DIR"
    exit 1
fi

echo "可用备份文件:"
ls -lh $BACKUP_DIR/openclaw_backup_*.tar.gz | awk '{print NR". "$9" ("$5")"}'

# 2. 选择备份
read -p "请选择备份编号: " choice
BACKUP_FILE=$(ls $BACKUP_DIR/openclaw_backup_*.tar.gz | sed -n "${choice}p")

if [ -z "$BACKUP_FILE" ]; then
    echo "无效的备份编号"
    exit 1
fi

# 3. 确认恢复
echo ""
echo "将恢复备份: $(basename $BACKUP_FILE)"
read -p "确认恢复吗？这将覆盖现有数据！(yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "已取消恢复"
    exit 0
fi

# 4. 停止服务
echo "停止服务..."
if command -v docker-compose &> /dev/null; then
    docker-compose down
else
    echo "⊘ docker-compose 未安装，跳过停止服务"
fi

# 5. 解压备份
echo "恢复数据..."
tar -xzf $BACKUP_FILE -C /

# 6. 重启服务
echo "重启服务..."
if command -v docker-compose &> /dev/null; then
    docker-compose up -d
else
    echo "⊘ 请手动重启服务"
fi

echo ""
echo "恢复完成！"
