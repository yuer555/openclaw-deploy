#!/bin/bash

# ====================================================
# Prometheus Alertmanager 告警通知配置
# 支持：企业微信、邮件、Webhook
# 服务器：139.199.200.144
# ====================================================

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}Alertmanager 告警通知配置${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

CONFIG_DIR="/opt/openclaw/config"

# 1. 创建 Alertmanager 配置目录
echo -e "\n${COLOR_YELLOW}[1/6] 创建配置目录...${COLOR_RESET}"
sudo mkdir -p "$CONFIG_DIR/alertmanager"

# 2. 配置企业微信告警（交互式输入）
echo -e "\n${COLOR_YELLOW}[2/6] 配置企业微信告警...${COLOR_RESET}"
echo "请输入企业微信机器人 Webhook URL（可选，按回车跳过）:"
read WECOM_WEBHOOK_URL

echo "请输入告警接收人企业微信 ID（多个用,分隔，可选）:"
read WECOM_MENTIONED_LIST

# 3. 配置邮件告警（可选）
echo -e "\n${COLOR_YELLOW}[3/6] 配置邮件告警...${COLOR_RESET}"
echo "是否配置邮件告警？(y/n)"
read ENABLE_EMAIL

if [ "$ENABLE_EMAIL" = "y" ]; then
    echo "SMTP 服务器地址（如: smtp.gmail.com:587）:"
    read SMTP_SERVER
    
    echo "发件人邮箱:"
    read SMTP_FROM
    
    echo "SMTP 认证用户名:"
    read SMTP_AUTH_USERNAME
    
    echo "SMTP 认证密码:"
    read -s SMTP_AUTH_PASSWORD
    
    echo -e "\n收件人邮箱（多个用,分隔）:"
    read EMAIL_TO
fi

# 4. 生成 Alertmanager 配置文件
echo -e "\n${COLOR_YELLOW}[4/6] 生成 Alertmanager 配置...${COLOR_RESET}"

cat > "$CONFIG_DIR/alertmanager/alertmanager.yml" << EOF
global:
  resolve_timeout: 5m
  # 企业微信 API 配置
  wechat_api_url: 'https://qyapi.weixin.qq.com/cgi-bin/'
  wechat_api_corp_id: '${WECOM_CORPID:-your_corpid}'

# 告警路由配置
route:
  # 根路由
  receiver: 'wecom-default'
  group_by: ['alertname', 'severity']
  group_wait: 10s          # 等待组内新告警的时间
  group_interval: 10s      # 组内告警再次发送间隔
  repeat_interval: 1h      # 重复告警间隔
  
  # 子路由（按严重级别分发）
  routes:
    # P0 级别：立即通知所有渠道
    - match:
        severity: critical
      receiver: 'wecom-critical'
      continue: true
      
    - match:
        severity: critical
      receiver: 'email-critical'
      group_wait: 0s
      repeat_interval: 5m
    
    # P1 级别：企业微信通知
    - match:
        severity: warning
      receiver: 'wecom-warning'
      repeat_interval: 2h
    
    # P2 级别：仅记录，每天汇总
    - match:
        severity: info
      receiver: 'wecom-info'
      group_wait: 30m
      repeat_interval: 24h

# 告警接收器配置
receivers:
  # 企业微信 - 默认
  - name: 'wecom-default'
    webhook_configs:
EOF

# 添加企业微信 Webhook 配置
if [ -n "$WECOM_WEBHOOK_URL" ]; then
cat >> "$CONFIG_DIR/alertmanager/alertmanager.yml" << EOF
      - url: '$WECOM_WEBHOOK_URL'
        send_resolved: true
        http_config:
          follow_redirects: true
EOF
else
cat >> "$CONFIG_DIR/alertmanager/alertmanager.yml" << EOF
      # 企业微信 Webhook 未配置，请后续添加
EOF
fi

# 添加企业微信应用消息配置
cat >> "$CONFIG_DIR/alertmanager/alertmanager.yml" << EOF
    wechat_configs:
      - agent_id: '${WECOM_AGENT_ID:-1000001}'
        api_secret: '${WECOM_CORPSECRET}'
        to_party: '${WECOM_PARTY_ID:-1}'
        message: |
          【OpenClaw 告警】
          告警名称: {{ .GroupLabels.alertname }}
          严重级别: {{ .CommonLabels.severity }}
          告警详情: {{ .CommonAnnotations.summary }}
          
          {{ range .Alerts }}
          实例: {{ .Labels.instance }}
          描述: {{ .Annotations.description }}
          时间: {{ .StartsAt.Format "2006-01-02 15:04:05" }}
          {{ end }}

  # 企业微信 - 严重告警
  - name: 'wecom-critical'
    webhook_configs:
EOF

if [ -n "$WECOM_WEBHOOK_URL" ]; then
cat >> "$CONFIG_DIR/alertmanager/alertmanager.yml" << EOF
      - url: '$WECOM_WEBHOOK_URL'
        send_resolved: true
EOF
fi

cat >> "$CONFIG_DIR/alertmanager/alertmanager.yml" << EOF
    wechat_configs:
      - agent_id: '${WECOM_AGENT_ID:-1000001}'
        api_secret: '${WECOM_CORPSECRET}'
        to_user: '${WECOM_MENTIONED_LIST:-@all}'
        message_type: 'markdown'
        message: |
          ## 🚨 严重告警
          **告警名称**: {{ .GroupLabels.alertname }}
          **严重级别**: <font color="warning">{{ .CommonLabels.severity }}</font>
          
          {{ range .Alerts }}
          > **实例**: {{ .Labels.instance }}
          > **描述**: {{ .Annotations.description }}
          > **时间**: {{ .StartsAt.Format "2006-01-02 15:04:05" }}
          {{ end }}

  # 企业微信 - 警告
  - name: 'wecom-warning'
    wechat_configs:
      - agent_id: '${WECOM_AGENT_ID:-1000001}'
        api_secret: '${WECOM_CORPSECRET}'
        to_party: '${WECOM_PARTY_ID:-1}'
        message: |
          【告警】{{ .GroupLabels.alertname }}
          级别: {{ .CommonLabels.severity }}
          详情: {{ .CommonAnnotations.summary }}

  # 企业微信 - 信息
  - name: 'wecom-info'
    wechat_configs:
      - agent_id: '${WECOM_AGENT_ID:-1000001}'
        api_secret: '${WECOM_CORPSECRET}'
        to_party: '${WECOM_PARTY_ID:-1}'
        message: |
          【信息】{{ .GroupLabels.alertname }}
          {{ .CommonAnnotations.summary }}
EOF

# 如果配置了邮件
if [ "$ENABLE_EMAIL" = "y" ]; then
cat >> "$CONFIG_DIR/alertmanager/alertmanager.yml" << EOF

  # 邮件 - 严重告警
  - name: 'email-critical'
    email_configs:
      - to: '$EMAIL_TO'
        from: '$SMTP_FROM'
        smarthost: '$SMTP_SERVER'
        auth_username: '$SMTP_AUTH_USERNAME'
        auth_password: '$SMTP_AUTH_PASSWORD'
        headers:
          Subject: '🚨 OpenClaw 严重告警: {{ .GroupLabels.alertname }}'
        html: |
          <!DOCTYPE html>
          <html>
          <head>
            <style>
              body { font-family: Arial, sans-serif; }
              .critical { color: #d93025; font-weight: bold; }
              .warning { color: #f9ab00; }
              table { border-collapse: collapse; width: 100%; }
              th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
              th { background-color: #f2f2f2; }
            </style>
          </head>
          <body>
            <h2 class="critical">🚨 严重告警</h2>
            <p><strong>告警名称:</strong> {{ .GroupLabels.alertname }}</p>
            <p><strong>严重级别:</strong> <span class="critical">{{ .CommonLabels.severity }}</span></p>
            <p><strong>摘要:</strong> {{ .CommonAnnotations.summary }}</p>
            
            <h3>告警详情</h3>
            <table>
              <tr>
                <th>实例</th>
                <th>描述</th>
                <th>开始时间</th>
              </tr>
              {{ range .Alerts }}
              <tr>
                <td>{{ .Labels.instance }}</td>
                <td>{{ .Annotations.description }}</td>
                <td>{{ .StartsAt.Format "2006-01-02 15:04:05" }}</td>
              </tr>
              {{ end }}
            </table>
          </body>
          </html>
EOF
fi

# 添加告警抑制规则
cat >> "$CONFIG_DIR/alertmanager/alertmanager.yml" << 'EOF'

# 告警抑制规则（避免重复告警）
inhibit_rules:
  # 主机宕机时，抑制该主机上的所有其他告警
  - source_match:
      severity: 'critical'
      alertname: 'HostDown'
    target_match:
      severity: 'warning'
    equal: ['instance']
  
  # CPU 严重告警时，抑制 CPU 警告
  - source_match:
      severity: 'critical'
      alertname: 'HighCPUUsage'
    target_match:
      severity: 'warning'
      alertname: 'HighCPUUsage'
    equal: ['instance']
EOF

# 5. 更新 Prometheus 配置（添加 Alertmanager）
echo -e "\n${COLOR_YELLOW}[5/6] 更新 Prometheus 配置...${COLOR_RESET}"

cat >> "$CONFIG_DIR/prometheus.yml" << 'EOF'

# Alertmanager 配置
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - 'alertmanager:9093'

# 告警规则文件
rule_files:
  - '/etc/prometheus/alert_rules.yml'
EOF

# 创建告警规则文件
cat > "$CONFIG_DIR/alert_rules.yml" << 'EOF'
groups:
  - name: openclaw_alerts
    interval: 30s
    rules:
      # 容器宕机告警
      - alert: ContainerDown
        expr: up{job="docker"} == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "容器 {{ $labels.instance }} 已宕机"
          description: "容器 {{ $labels.container_name }} 在 {{ $labels.instance }} 上已停止运行超过 1 分钟"

      # CPU 使用率过高（严重）
      - alert: HighCPUUsage
        expr: rate(process_cpu_seconds_total[5m]) > 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.instance }} CPU 使用率过高"
          description: "CPU 使用率已达到 {{ $value | humanizePercentage }}，持续 5 分钟"

      # CPU 使用率告警（警告）
      - alert: HighCPUUsage
        expr: rate(process_cpu_seconds_total[5m]) > 0.7
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.instance }} CPU 使用率较高"
          description: "CPU 使用率达到 {{ $value | humanizePercentage }}"

      # 内存使用率过高
      - alert: HighMemoryUsage
        expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) > 0.9
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.container_name }} 内存使用率过高"
          description: "内存使用率已达到 {{ $value | humanizePercentage }}"

      # 磁盘空间不足
      - alert: DiskSpaceLow
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "{{ $labels.instance }} 磁盘空间不足"
          description: "剩余磁盘空间仅 {{ $value | humanizePercentage }}"

      # 磁盘空间严重不足
      - alert: DiskSpaceCritical
        expr: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.05
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.instance }} 磁盘空间严重不足"
          description: "剩余磁盘空间仅 {{ $value | humanizePercentage }}，请立即清理"

      # 网关响应时间过长
      - alert: GatewaySlowResponse
        expr: http_request_duration_seconds{job="wecom-gateway"} > 5
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "企业微信网关响应缓慢"
          description: "请求响应时间达到 {{ $value }}秒"

      # 任务队列积压
      - alert: TaskQueueBacklog
        expr: task_queue_length > 100
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "任务队列积压严重"
          description: "当前积压 {{ $value }} 个任务"

      # Agent 连续失败
      - alert: AgentFailureRate
        expr: rate(agent_task_failures_total[5m]) > 0.5
        for: 3m
        labels:
          severity: critical
        annotations:
          summary: "{{ $labels.agent }} 失败率过高"
          description: "过去 5 分钟失败率达到 {{ $value | humanizePercentage }}"

      # SSL 证书即将过期
      - alert: SSLCertificateExpiringSoon
        expr: (ssl_certificate_expiry_seconds - time()) < (7 * 24 * 3600)
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "SSL 证书即将过期"
          description: "域名 {{ $labels.domain }} 的证书将在 {{ $value | humanizeDuration }} 后过期"
EOF

# 6. 更新 docker-compose.yml 添加 Alertmanager
echo -e "\n${COLOR_YELLOW}[6/6] 添加 Alertmanager 服务...${COLOR_RESET}"

cat > "$CONFIG_DIR/docker-compose-alertmanager.yml" << 'EOF'
version: '3.8'

services:
  alertmanager:
    image: prom/alertmanager:latest
    container_name: alertmanager
    restart: always
    ports:
      - "9093:9093"
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    volumes:
      - /opt/openclaw/config/alertmanager:/etc/alertmanager:ro
      - alertmanager-data:/alertmanager:rw
    networks:
      - openclaw-monitor
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true

volumes:
  alertmanager-data:

networks:
  openclaw-monitor:
    external: true
EOF

echo -e "\n${COLOR_GREEN}========================================${COLOR_RESET}"
echo -e "${COLOR_GREEN}✅ 告警通知配置完成！${COLOR_RESET}"
echo -e "${COLOR_GREEN}========================================${COLOR_RESET}"

echo -e "\n${COLOR_YELLOW}配置摘要：${COLOR_RESET}"
echo "- 企业微信 Webhook: ${WECOM_WEBHOOK_URL:-未配置}"
echo "- 企业微信提醒: ${WECOM_MENTIONED_LIST:-@all}"
if [ "$ENABLE_EMAIL" = "y" ]; then
    echo "- 邮件告警: 已启用 (发送至 $EMAIL_TO)"
else
    echo "- 邮件告警: 未启用"
fi

echo -e "\n${COLOR_YELLOW}下一步操作：${COLOR_RESET}"
echo "1. 启动 Alertmanager："
echo "   docker-compose -f docker-compose-alertmanager.yml up -d"
echo ""
echo "2. 重启 Prometheus 加载告警规则："
echo "   docker restart prometheus"
echo ""
echo "3. 访问 Alertmanager Web UI："
echo "   http://your-server:9093"
echo ""
echo "4. 测试告警："
echo "   curl -X POST http://localhost:9093/api/v1/alerts -d '[{\"labels\":{\"alertname\":\"Test\",\"severity\":\"warning\"},\"annotations\":{\"summary\":\"测试告警\"}}]'"
echo ""
echo "5. 查看告警规则状态："
echo "   http://your-server:9090/alerts"

echo -e "\n${COLOR_YELLOW}配置文件位置：${COLOR_RESET}"
echo "- Alertmanager: $CONFIG_DIR/alertmanager/alertmanager.yml"
echo "- 告警规则: $CONFIG_DIR/alert_rules.yml"
