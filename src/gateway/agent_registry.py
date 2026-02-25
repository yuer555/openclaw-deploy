"""
Agent 注册表 - 集中管理虚拟员工容器 URL
本地开发默认使用 localhost + 端口映射
生产环境通过环境变量注入 Docker 固定 IP
"""
import os

AGENT_REGISTRY = {
    "operation": {
        "url": os.getenv("AGENT_OPERATION_URL", "http://localhost:18791"),
        "name": "运营专员",
        "desc": "数据分析、运营策略、用户增长",
    },
    "product": {
        "url": os.getenv("AGENT_PRODUCT_URL", "http://localhost:18792"),
        "name": "产品经理",
        "desc": "需求管理、产品规划、用户故事",
    },
    "development": {
        "url": os.getenv("AGENT_DEVELOPMENT_URL", "http://localhost:18793"),
        "name": "开发工程师",
        "desc": "代码实现、技术架构、Bug修复",
    },
    "testing": {
        "url": os.getenv("AGENT_TESTING_URL", "http://localhost:18794"),
        "name": "测试工程师",
        "desc": "测试用例、质量保障、缺陷管理",
    },
    "service": {
        "url": os.getenv("AGENT_SERVICE_URL", "http://localhost:18795"),
        "name": "客服专员",
        "desc": "客户服务、问题解答、投诉处理",
    },
}

# 调度员 openclaw URL（Gateway 容器内部）
DISPATCHER_URL = os.getenv("DISPATCHER_URL", "http://localhost:18789")
