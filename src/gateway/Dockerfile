FROM python:3.11-alpine

WORKDIR /app

# 安装系统依赖
RUN apk add --no-cache curl

# 复制依赖文件
COPY requirements.txt .

# 安装 Python 依赖
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用代码
COPY wecom_gateway.py .

# 创建数据和日志目录
RUN mkdir -p /data /logs

# 暴露端口
EXPOSE 8000

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# 启动应用
CMD ["python", "-u", "wecom_gateway.py"]
