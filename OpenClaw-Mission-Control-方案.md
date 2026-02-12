# OpenClaw Mission Control 实现方案

## 📋 概述

**目标：** 构建一个中央控制系统，统一管理和调度多个 OpenClaw AI 代理，实现任务分发、状态监控和结果汇总。

**核心价值：**
- 🎯 统一入口：一个消息接口，智能路由到合适的 AI 代理
- 📊 可视化监控：实时查看所有代理状态和任务执行情况
- 🔄 自动调度：根据负载和能力自动分配任务
- 📝 统一日志：集中管理所有代理的日志和审计

---

## 一、系统架构

```
┌─────────────────────────────────────────────────────────────┐
│                    用户层 (User Layer)                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │企业微信  │  │ Telegram │  │ Discord  │  │   Web    │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              Mission Control 中央控制层                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  API Gateway (统一消息接入)                           │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │  Router (智能路由引擎)                                 │  │
│  │    - 关键词匹配                                        │  │
│  │    - 能力匹配                                          │  │
│  │    - 负载均衡                                          │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │  Scheduler (任务调度器)                               │  │
│  │    - 任务队列                                          │  │
│  │    - 优先级管理                                        │  │
│  │    - 超时控制                                          │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │  Monitor (监控中心)                                    │  │
│  │    - 代理状态                                          │  │
│  │    - 任务追踪                                          │  │
│  │    - 性能指标                                          │  │
│  ├───────────────────────────────────────────────────────┤  │
│  │  Dashboard (可视化控制台)                             │  │
│  │    - 实时状态                                          │  │
│  │    - 任务列表                                          │  │
│  │    - 日志查看                                          │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│                   Agent 代理层                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ 客服代理 │  │ 开发代理 │  │ 运营代理 │  │ 测试代理 │    │
│  │ service  │  │   dev    │  │operation │  │ testing  │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐    │
│  │ 产品代理 │  │ 自定义1  │  │ 自定义2  │  │   ...    │    │
│  │ product  │  │ custom1  │  │ custom2  │  │          │    │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘    │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、核心功能

### 2.1 统一消息接入

**接口：** `/api/message`

**功能：**
- 接收来自多个平台的消息
- 消息格式标准化
- 用户身份验证
- 消息优先级标记

**消息格式：**
```json
{
  "message_id": "msg-12345",
  "user_id": "user-001",
  "platform": "wecom|telegram|discord|web",
  "content": "用户反馈登录问题",
  "priority": "normal|high|urgent",
  "metadata": {
    "channel_id": "xxx",
    "timestamp": 1770792000
  }
}
```

---

### 2.2 智能路由引擎

**路由策略：**

#### 方式1：关键词匹配
```python
ROUTE_KEYWORDS = {
    'service-agent': ['客服', '咨询', '投诉', '售后', '帮助', '问题'],
    'development-agent': ['bug', '开发', '代码', '部署', '接口', '错误'],
    'operation-agent': ['活动', '推广', '文案', '数据', '用户', '增长'],
    'testing-agent': ['测试', '用例', '验收', '回归', '自动化'],
    'product-agent': ['需求', '功能', '原型', '设计', '迭代', '竞品']
}
```

#### 方式2：意图识别（LLM）
```python
# 使用 LLM 分析消息意图
intent = llm.classify_intent(message)
# 返回: "customer_support", "bug_report", "feature_request", etc.
```

#### 方式3：用户绑定
```python
# 用户可以指定默认代理或多代理绑定
user_agents = get_user_agents(user_id)
# 返回: ["service-agent", "operation-agent"]
```

---

### 2.3 任务调度器

**功能：**
- 任务队列管理（Redis 或内存队列）
- 优先级调度（urgent > high > normal）
- 并发控制（每个代理最大并发数）
- 超时控制（任务执行超时自动失败）
- 重试机制（失败任务自动重试）

**任务状态流转：**
```
pending → assigned → running → completed
                                ↓
                              failed → retry → running
```

**任务数据结构：**
```python
{
    "task_id": "task-12345",
    "message_id": "msg-12345",
    "user_id": "user-001",
    "agent_id": "service-agent",
    "status": "pending|assigned|running|completed|failed",
    "priority": "normal|high|urgent",
    "created_at": 1770792000,
    "assigned_at": 1770792010,
    "started_at": 1770792020,
    "completed_at": 1770792050,
    "result": "...",
    "error": null,
    "retry_count": 0
}
```

---

### 2.4 监控中心

**实时监控指标：**

| 指标 | 说明 |
|-----|------|
| agent_status | 每个代理的在线/离线状态 |
| agent_load | 每个代理当前处理的任务数 |
| task_queue_length | 待处理任务队列长度 |
| task_success_rate | 任务成功率（按代理） |
| avg_response_time | 平均响应时间（按代理） |
| total_tasks_today | 今日总任务数 |
| active_users | 活跃用户数 |

**API 接口：**
```bash
GET /api/monitor/status        # 系统状态概览
GET /api/monitor/agents        # 所有代理状态
GET /api/monitor/tasks         # 任务列表（分页）
GET /api/monitor/metrics       # 性能指标
```

---

### 2.5 可视化控制台

**功能页面：**

#### Dashboard（仪表盘）
- 实时任务统计
- 代理状态卡片
- 性能趋势图表
- 告警信息

#### Tasks（任务管理）
- 任务列表（可筛选、搜索）
- 任务详情（消息、结果、日志）
- 手动重试/取消任务

#### Agents（代理管理）
- 代理列表
- 启用/禁用代理
- 配置代理参数
- 查看代理日志

#### Users（用户管理）
- 用户列表
- 用户-代理绑定
- 权限管理

#### Logs（日志中心）
- 统一日志查看
- 日志搜索/过滤
- 错误日志高亮

---

## 三、技术实现

### 3.1 技术栈

**后端：**
- **框架：** FastAPI（Python）
- **数据库：** PostgreSQL（生产）/ SQLite（开发）
- **队列：** Redis（任务队列、缓存）
- **ORM：** SQLAlchemy
- **异步：** asyncio + uvicorn

**前端：**
- **框架：** React + TypeScript
- **UI 库：** Ant Design / Material-UI
- **状态管理：** Redux / Zustand
- **图表：** ECharts / Chart.js

**部署：**
- **容器化：** Docker + Docker Compose
- **反向代理：** Nginx
- **进程管理：** Supervisor

---

### 3.2 核心代码结构

```
mission-control/
├── backend/
│   ├── app/
│   │   ├── main.py                   # FastAPI 主入口
│   │   ├── api/
│   │   │   ├── routes/
│   │   │   │   ├── message.py        # 消息接入接口
│   │   │   │   ├── monitor.py        # 监控接口
│   │   │   │   ├── tasks.py          # 任务管理接口
│   │   │   │   └── agents.py         # 代理管理接口
│   │   ├── core/
│   │   │   ├── router.py             # 智能路由引擎
│   │   │   ├── scheduler.py          # 任务调度器
│   │   │   ├── monitor.py            # 监控中心
│   │   │   └── agent_manager.py      # 代理管理器
│   │   ├── models/
│   │   │   ├── task.py               # 任务模型
│   │   │   ├── agent.py              # 代理模型
│   │   │   └── user.py               # 用户模型
│   │   ├── db/
│   │   │   ├── database.py           # 数据库连接
│   │   │   └── crud.py               # CRUD 操作
│   │   └── utils/
│   │       ├── logger.py             # 日志工具
│   │       └── helpers.py            # 辅助函数
│   ├── requirements.txt
│   └── Dockerfile
├── frontend/
│   ├── src/
│   │   ├── App.tsx
│   │   ├── pages/
│   │   │   ├── Dashboard.tsx
│   │   │   ├── Tasks.tsx
│   │   │   ├── Agents.tsx
│   │   │   ├── Users.tsx
│   │   │   └── Logs.tsx
│   │   ├── components/
│   │   │   ├── AgentCard.tsx
│   │   │   ├── TaskList.tsx
│   │   │   ├── MetricsChart.tsx
│   │   │   └── LogViewer.tsx
│   │   └── api/
│   │       └── client.ts             # API 客户端
│   ├── package.json
│   └── Dockerfile
├── nginx/
│   └── nginx.conf                    # Nginx 配置
├── docker-compose.yml                # Docker Compose 配置
└── README.md
```

---

### 3.3 核心代码示例

#### router.py - 智能路由引擎

```python
from typing import Optional

class MessageRouter:
    def __init__(self):
        self.route_keywords = {
            'service-agent': ['客服', '咨询', '投诉', '售后', '帮助'],
            'development-agent': ['bug', '开发', '代码', '部署', '接口'],
            'operation-agent': ['活动', '推广', '文案', '数据', '用户'],
            'testing-agent': ['测试', '用例', '验收', '回归', '自动化'],
            'product-agent': ['需求', '功能', '原型', '设计', '迭代']
        }
    
    def route(self, message: str, user_agents: list) -> Optional[str]:
        """
        路由消息到合适的代理
        
        Args:
            message: 消息内容
            user_agents: 用户绑定的代理列表
        
        Returns:
            代理 ID 或 None
        """
        # 优先级排序（按匹配度）
        agent_scores = {}
        
        for agent_id, keywords in self.route_keywords.items():
            if agent_id not in user_agents:
                continue
            
            score = sum(1 for kw in keywords if kw in message)
            if score > 0:
                agent_scores[agent_id] = score
        
        if agent_scores:
            # 返回得分最高的代理
            return max(agent_scores, key=agent_scores.get)
        
        # 如果没有匹配，返回第一个绑定的代理
        return user_agents[0] if user_agents else None
```

---

#### scheduler.py - 任务调度器

```python
import asyncio
from typing import Dict, List
from datetime import datetime

class TaskScheduler:
    def __init__(self, max_concurrent_per_agent: int = 3):
        self.task_queue = asyncio.Queue()
        self.running_tasks: Dict[str, List[str]] = {}  # agent_id -> [task_ids]
        self.max_concurrent = max_concurrent_per_agent
    
    async def submit_task(self, task: dict):
        """提交任务到队列"""
        await self.task_queue.put(task)
    
    async def assign_task(self) -> Optional[dict]:
        """从队列中获取任务并分配"""
        if self.task_queue.empty():
            return None
        
        task = await self.task_queue.get()
        agent_id = task['agent_id']
        
        # 检查代理负载
        if agent_id not in self.running_tasks:
            self.running_tasks[agent_id] = []
        
        if len(self.running_tasks[agent_id]) >= self.max_concurrent:
            # 代理已满，任务重新入队
            await self.task_queue.put(task)
            return None
        
        # 分配任务
        self.running_tasks[agent_id].append(task['task_id'])
        task['status'] = 'assigned'
        task['assigned_at'] = datetime.now().timestamp()
        
        return task
    
    async def complete_task(self, agent_id: str, task_id: str):
        """标记任务完成"""
        if agent_id in self.running_tasks:
            if task_id in self.running_tasks[agent_id]:
                self.running_tasks[agent_id].remove(task_id)
    
    def get_agent_load(self, agent_id: str) -> int:
        """获取代理当前负载"""
        return len(self.running_tasks.get(agent_id, []))
```

---

#### main.py - FastAPI 主入口

```python
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

app = FastAPI(title="OpenClaw Mission Control")

# CORS 配置
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 初始化核心组件
router = MessageRouter()
scheduler = TaskScheduler()
monitor = Monitor()

class MessageRequest(BaseModel):
    user_id: str
    platform: str
    content: str
    priority: str = "normal"

@app.post("/api/message")
async def receive_message(req: MessageRequest):
    """接收消息并路由"""
    
    # 获取用户绑定的代理
    user_agents = get_user_agents(req.user_id)
    if not user_agents:
        raise HTTPException(status_code=400, detail="用户未绑定代理")
    
    # 路由消息
    agent_id = router.route(req.content, user_agents)
    if not agent_id:
        raise HTTPException(status_code=404, detail="无法找到合适的代理")
    
    # 创建任务
    task = {
        "task_id": f"task-{uuid4()}",
        "user_id": req.user_id,
        "agent_id": agent_id,
        "content": req.content,
        "priority": req.priority,
        "status": "pending",
        "created_at": datetime.now().timestamp()
    }
    
    # 提交到调度器
    await scheduler.submit_task(task)
    
    # 保存到数据库
    save_task(task)
    
    return {
        "success": True,
        "task_id": task['task_id'],
        "agent_id": agent_id,
        "message": f"消息已转发给 {agent_id}"
    }

@app.get("/api/monitor/status")
async def get_status():
    """获取系统状态"""
    return {
        "agents": monitor.get_agent_status(),
        "tasks": {
            "pending": scheduler.task_queue.qsize(),
            "running": sum(len(tasks) for tasks in scheduler.running_tasks.values())
        },
        "timestamp": datetime.now().timestamp()
    }

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

---

## 四、数据库设计

### 4.1 表结构

#### users 表（用户）
```sql
CREATE TABLE users (
    id VARCHAR(50) PRIMARY KEY,
    username VARCHAR(100),
    platform VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### agents 表（代理）
```sql
CREATE TABLE agents (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100),
    type VARCHAR(50),
    status VARCHAR(20),  -- online, offline, busy
    max_concurrent INT DEFAULT 3,
    config JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

#### user_agents 表（用户-代理绑定）
```sql
CREATE TABLE user_agents (
    user_id VARCHAR(50),
    agent_id VARCHAR(50),
    priority INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, agent_id),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);
```

#### tasks 表（任务）
```sql
CREATE TABLE tasks (
    id VARCHAR(50) PRIMARY KEY,
    user_id VARCHAR(50),
    agent_id VARCHAR(50),
    content TEXT,
    status VARCHAR(20),  -- pending, assigned, running, completed, failed
    priority VARCHAR(20),  -- normal, high, urgent
    result TEXT,
    error TEXT,
    retry_count INT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    assigned_at TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);
```

#### logs 表（日志）
```sql
CREATE TABLE logs (
    id SERIAL PRIMARY KEY,
    task_id VARCHAR(50),
    agent_id VARCHAR(50),
    level VARCHAR(20),  -- INFO, WARNING, ERROR
    message TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (task_id) REFERENCES tasks(id),
    FOREIGN KEY (agent_id) REFERENCES agents(id)
);
```

---

## 五、部署方案

### 5.1 Docker Compose 部署

**docker-compose.yml:**
```yaml
version: '3.8'

services:
  # 后端 API
  backend:
    build: ./backend
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@postgres:5432/mission_control
      - REDIS_URL=redis://redis:6379/0
    depends_on:
      - postgres
      - redis
    volumes:
      - ./logs:/app/logs
    restart: unless-stopped
  
  # 前端
  frontend:
    build: ./frontend
    ports:
      - "3000:80"
    depends_on:
      - backend
    restart: unless-stopped
  
  # Nginx 反向代理
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - ./nginx/ssl:/etc/nginx/ssl
    depends_on:
      - backend
      - frontend
    restart: unless-stopped
  
  # PostgreSQL 数据库
  postgres:
    image: postgres:15
    environment:
      - POSTGRES_USER=user
      - POSTGRES_PASSWORD=pass
      - POSTGRES_DB=mission_control
    volumes:
      - postgres_data:/var/lib/postgresql/data
    restart: unless-stopped
  
  # Redis 缓存和队列
  redis:
    image: redis:7-alpine
    volumes:
      - redis_data:/data
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
```

---

### 5.2 一键部署脚本

**deploy.sh:**
```bash
#!/bin/bash

echo "🚀 部署 OpenClaw Mission Control"

# 1. 检查 Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker 未安装"
    exit 1
fi

# 2. 创建目录
mkdir -p logs nginx/ssl

# 3. 构建镜像
echo "📦 构建 Docker 镜像..."
docker-compose build

# 4. 启动服务
echo "🎬 启动服务..."
docker-compose up -d

# 5. 等待服务就绪
echo "⏳ 等待服务启动..."
sleep 10

# 6. 健康检查
echo "🏥 健康检查..."
curl -s http://localhost:8000/health

# 7. 初始化数据库
echo "💾 初始化数据库..."
docker-compose exec backend python scripts/init_db.py

echo ""
echo "✅ 部署完成！"
echo ""
echo "📊 访问控制台: http://localhost"
echo "🔌 API 地址: http://localhost:8000"
echo ""
echo "查看日志: docker-compose logs -f"
echo "停止服务: docker-compose down"
```

---

## 六、使用示例

### 6.1 发送消息

```bash
curl -X POST http://localhost:8000/api/message \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "user-001",
    "platform": "wecom",
    "content": "客服，用户反馈登录问题",
    "priority": "high"
  }'
```

**响应：**
```json
{
  "success": true,
  "task_id": "task-12345",
  "agent_id": "service-agent",
  "message": "消息已转发给 service-agent"
}
```

---

### 6.2 查看系统状态

```bash
curl http://localhost:8000/api/monitor/status
```

**响应：**
```json
{
  "agents": {
    "service-agent": {
      "status": "online",
      "load": 2,
      "max_concurrent": 3
    },
    "development-agent": {
      "status": "online",
      "load": 1,
      "max_concurrent": 3
    }
  },
  "tasks": {
    "pending": 5,
    "running": 3
  },
  "timestamp": 1770792000
}
```

---

### 6.3 查看任务列表

```bash
curl http://localhost:8000/api/monitor/tasks?status=completed&limit=10
```

---

## 七、扩展功能

### 7.1 多租户支持
- 不同企业/组织独立的代理和任务空间
- 资源隔离和配额管理

### 7.2 插件系统
- 自定义路由策略
- 第三方代理集成
- 消息预处理和后处理

### 7.3 告警系统
- 代理离线告警
- 任务失败告警
- 性能异常告警

### 7.4 分析报表
- 任务统计报表
- 代理性能分析
- 用户行为分析

---

## 八、开发计划

### Phase 1：核心功能（2周）
- ✅ 消息接入 API
- ✅ 智能路由引擎
- ✅ 任务调度器
- ✅ 基础监控

### Phase 2：可视化（1周）
- ✅ Dashboard 仪表盘
- ✅ 任务管理页面
- ✅ 代理管理页面

### Phase 3：增强功能（1周）
- ✅ 日志中心
- ✅ 用户管理
- ✅ 告警系统

### Phase 4：生产优化（1周）
- ✅ 性能优化
- ✅ 安全加固
- ✅ 文档完善

---

## 九、总结

OpenClaw Mission Control 是一个**中央化的 AI 代理管理和调度系统**，核心价值在于：

1. **统一入口** - 一个消息接口，自动路由到合适的代理
2. **智能调度** - 负载均衡、优先级管理、超时控制
3. **可视化监控** - 实时查看代理状态和任务执行情况
4. **易于扩展** - 插件化架构，支持自定义代理和路由策略

**技术栈：** FastAPI + React + PostgreSQL + Redis + Docker

**部署时间：** < 10 分钟（一键部署脚本）

**适用场景：**
- 企业级 AI 客服系统
- 多角色协作系统
- 自动化运维平台
- 智能助手集群

---

**文档版本：** v1.0  
**更新时间：** 2026-02-11  
**作者：** OpenClaw Team
