#!/bin/bash
# scripts/backup.sh - 备份配置和数据

BACKUP_DIR="/opt/openclaw/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="openclaw_backup_$TIMESTAMP.tar.gz"

echo "=== OpenClaw 数据备份 ==="

# 1. 创建备份目录
mkdir -p $BACKUP_DIR

# 2. 打包备份
echo "正在打包备份文件..."
tar -czf $BACKUP_DIR/$BACKUP_FILE \
    /opt/openclaw/data/*.db \
    /opt/openclaw/config \
    /opt/openclaw/agents/*/config.yaml \
    .env \
    docker-compose.yml 2>/dev/null

# 3. 验证备份
if [ -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
    SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)
    echo "✓ 备份完成: $BACKUP_FILE ($SIZE)"
else
    echo "✗ 备份失败"
    exit 1
fi

# 4. 清理旧备份（保留最近 7 个）
echo "清理旧备份..."
cd $BACKUP_DIR
ls -t openclaw_backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm

echo ""
echo "备份完成！"
echo "备份文件: $BACKUP_DIR/$BACKUP_FILE"
