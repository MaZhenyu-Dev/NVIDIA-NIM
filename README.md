# NVIDIA NIM 多 Key 负载均衡代理服务

> 本地部署的 NVIDIA NIM API 代理网关，支持多 API Key 智能负载均衡、自动故障转移、**Anthropic / OpenAI 双协议兼容**、实时监控面板。

[![Python](https://img.shields.io/badge/Python-3.10+-blue.svg)](https://www.python.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.111+-green.svg)](https://fastapi.tiangolo.com/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## ✨ 核心特性

| 特性 | 说明 |
|------|------|
| 🔑 **多 Key 负载均衡** | 支持配置多个 NVIDIA API Key，自动分配请求，突破单 Key RPM 限制 |
| ⚖️ **三种均衡策略** | `most_remaining`（剩余最多优先）/ `round_robin`（轮询）/ `least_used`（最少使用） |
| 📊 **滑动窗口限流** | 精确追踪每个 Key 的 RPM 使用量，基于时间窗口动态计算剩余配额 |
| 🔄 **自动故障转移** | Key 被限流时自动切换，支持可配置的重试次数与超时等待 |
| 🩺 **健康检查** | 后台周期性检测 Key 状态，自动封禁异常 Key 并在恢复后解禁 |
| 🌐 **OpenAI 兼容** | 完全兼容 `/v1/chat/completions`、`/v1/models` 等 OpenAI 接口格式 |
| 🤖 **Anthropic 兼容** | 支持 Anthropic Messages API 格式（`/v1/messages`），含模型映射、上下文截断、Thinking 模式、Tool Use |
| 📡 **流式响应** | 完整支持 SSE 流式输出（Streaming），含 Anthropic SSE 事件流转换 |
| 🔄 **模型级故障转移** | 模型被 429 限流时自动切换到备选模型链，对客户端透明 |
| 🚦 **前置准入控制** | 原子性预扣配额防止 429 雪崩，支持 `reject_fast`（快速失败）与 `queue_wait`（排队等待）两种模式 |
| 📈 **可视化监控面板** | 内置 Web Dashboard，实时展示请求趋势、Token 统计、Key 健康状态、调用记录、性能指标（TTFT/Tokens/s P50/P95） |
| 💾 **SQLite 持久化** | 异步批量写入（WriteBuffer），统计数据不丢，重启后历史数据保留 |
| 🎛️ **模型管理 API** | 支持模型启用/禁用、分组展示、从 NVIDIA 自动拉取最新模型列表 |

---

## 🏗️ 架构概览

```
客户端 (curl / ChatBox / LobeChat / Claude Code / 自定义脚本)
        │
        │  HTTP POST (OpenAI 或 Anthropic 格式)
        ▼
┌───────────────────────────────────────────────┐
│           FastAPI 本地代理服务                  │
│           http://localhost:8082                │
│                                               │
│   ┌──────────────────┐  ┌──────────────────┐  │
│   │  OpenAI 兼容层    │  │ Anthropic 兼容层  │  │
│   │ /v1/chat/*       │  │ /v1/messages      │  │
│   │ /v1/models       │  │ /v1/models        │  │
│   └────────┬─────────┘  └────────┬─────────┘  │
│            │                     │             │
│            └──────────┬──────────┘             │
│                       ▼                        │
│   ┌──────────────────────────────┐            │
│   │       LoadBalancer           │            │
│   │  (准入控制 + 重试 + 故障转移) │            │
│   └──────────────┬───────────────┘            │
│                  ▼                            │
│   ┌──────────────────────────────┐            │
│   │         Key Pool             │            │
│   │  ┌──────┐ ┌──────┐ ┌──────┐ │            │
│   │  │ Key1 │ │ Key2 │ │ Key3 │ │ ...        │
│   │  │ 35/40│ │ 封禁 │ │ 38/40│ │            │
│   │  └──────┘ └──────┘ └──────┘ │            │
│   └──────────────────────────────┘            │
│                                               │
│   ┌─────────────────┐  ┌──────────────────┐   │
│   │  /dashboard     │  │ /api/stats/*     │   │
│   │  (Web 监控面板)  │  │ /api/models/*    │   │
│   └─────────────────┘  └──────────────────┘   │
└───────────────────────────────────────────────┘
                   │
                   │  真实 HTTPS 请求
                   ▼
        ┌─────────────────────┐
        │  NVIDIA NIM API     │
        │  integrate.api.     │
        │  nvidia.com/v1      │
        └─────────────────────┘
```

---

## 📁 项目结构

```
NVIDIA-NIM/
├── main.py                 # 启动入口 (v2.2)
├── requirements.txt        # Python 依赖
├── config.example.yaml     # 配置文件模板
│
├── core/                   # 核心逻辑层
│   ├── config.py           # 集中化配置管理（单例模式）
│   ├── key_pool.py         # Key 池管理（滑动窗口计数、状态机）
│   ├── balancer.py         # 负载均衡器（3 种策略）
│   ├── proxy.py            # 请求转发（重试、流式、Token 提取、准入控制）
│   ├── model_manager.py    # 模型列表管理与缓存（启用/禁用/分组）
│   ├── stats_manager.py    # 统计数据核心（时序/Token/记录/性能指标）
│   ├── database.py         # SQLite 初始化与 ORM
│   ├── write_buffer.py     # 异步批量写入缓冲区
│   └── anthropic_adapter.py # ★ Anthropic ↔ OpenAI 格式双向转换适配器
│
├── api/                    # HTTP 接口层
│   ├── router.py           # 路由定义（OpenAI + Anthropic + 统计 + 模型管理）
│   └── dashboard.py        # 监控面板 HTML（内嵌 ECharts）
│
├── static/
│   └── dashboard.html      # 静态资源
│
├── tests/                  # 测试
│   ├── test_core.py
│   └── test_prompt_token_leak.py
│
├── data/                   # 运行时数据（SQLite 数据库）
└── logs/                   # 运行日志
```

---

## 🚀 快速开始

### 环境要求

- **Python** >= 3.10
- **NVIDIA API Key**（一个或多个）

### 安装

```bash
# 克隆项目
git clone https://github.com/Xiaoma716/NVIDIA-NIM.git
cd NVIDIA-NIM

# 创建虚拟环境（推荐）
python -m venv venv
venv\Scripts\activate          # Windows
# source venv/bin/activate      # Linux/macOS

# 安装依赖
pip install -r requirements.txt
```

### 配置

复制 `config.example.yaml` 为 `config.yaml` 并填入你的 API Key：

```bash
cp config.example.yaml config.yaml
```

#### 配置文件说明 (`config.yaml`)

```yaml
# ── API Keys ──────────────────────────────────────────────
keys:
  - key: "nvapi-xxxxxxxxxxxx"    # 你的 NVIDIA API Key
  - key: "nvapi-yyyyyyyyyyyy"    # 可添加多个 Key 实现负载均衡

# ── NVIDIA API 配置 ──────────────────────────────────────
nvidia:
  base_url: "https://integrate.api.nvidia.com/v1"
  default_model: "deepseek-ai/deepseek-v4-flash"
  rpm_limit: 30                     # 每 Key 每分钟请求上限
  rpm_buffer: 3                     # 安全余量

# ── 负载均衡配置 ─────────────────────────────────────────
balancer:
  strategy: "most_remaining"        # 可选: most_remaining / round_robin / least_used
  wait_timeout: 65                  # 无可用 Key 时等待超时（秒）
  max_retries: 1                    # 失败重试次数

  # 前置准入控制 (Admission Control)
  # 防止并发请求超过所有 Key 的总配额，从源头避免 NVIDIA 返回 429 雪崩
  admission_mode: "queue_wait"     # reject_fast | queue_wait
  queue_wait_timeout: 30           # 单位：秒，推荐 10~60

  # ★ 模型级故障转移 (Model Fallback)
  # 当主模型被 NVIDIA 429 限流时，自动切换到备选模型重试
  # 仅在所有 Key 均返回 RateLimitError (429) 时触发
  # 非 429 错误不会触发降级，避免掩盖真实故障
  model_fallback:
    enabled: true                    # 是否启用
    models:                         # 按优先级排列的备选模型链
      - "deepseek-ai/deepseek-v4-flash"
      - "moonshotai/kimi-k2.6"
      - "minimaxai/minimax-m2.7"
      - "z-ai/glm-5.1"
      - "deepseek-ai/deepseek-v4-pro"

# ── 服务配置 ──────────────────────────────────────────────
server:
  port: 8082                        # 服务监听端口

# ── 日志配置 ──────────────────────────────────────────────
logging:
  level: "INFO"
  rotation: "50 MB"
  retention: "7 days"

# ── 模型管理 ──────────────────────────────────────────────
models:
  auto_fetch: true                  # 启动时自动从 NVIDIA 拉取模型列表
  fallback_list:                    # 拉取失败时的备用模型列表
    - "deepseek-ai/deepseek-v4-flash"
    - "moonshotai/kimi-k2.6"
    - "minimaxai/minimax-m2.7"
    - "z-ai/glm-5.1"
    - "deepseek-ai/deepseek-v4-pro"

# ── Anthropic 兼容配置 ───────────────────────────────────
anthropic:
  default_model: "deepseek-v4-flash"

  # 模型名称映射：简短别名 → NVIDIA 模型名
  model_mapping:
    "deepseek-v4-flash": "deepseek-ai/deepseek-v4-flash"
    "deepseek-v4-pro": "deepseek-ai/deepseek-v4-pro"
    "kimi": "moonshotai/kimi-k2.6"
    "minimax": "minimaxai/minimax-m2.7"
    "glm": "z-ai/glm-5.1"

  # 各模型的上下文窗口大小（用于消息截断）
  context_windows:
    "deepseek-v4-flash": 1000000
    "deepseek-v4-pro": 1000000
    "kimi": 262000
    "minimax": 200000
    "glm": 200000
  default_context_window: 200000

  # 消息截断策略（超出上下文窗口时）
  truncation_strategy: "recent"      # recent: 保留最近消息 | middle: 从中间截断
  truncation_buffer_ratio: 0.10      # 截断缓冲比例（预留 10% 给输出）

  # Thinking（扩展思考）模式支持
  enable_thinking: true
  default_thinking_budget: 1024      # 默认 thinking token 预算

  # Tool Choice 支持
  enable_tool_choice: true
```

### 启动服务

```bash
python main.py
```

启动成功后：
- **OpenAI API 地址：** `http://localhost:8082/v1`
- **Anthropic API 地址：** `http://localhost:8082/v1`（携带 `anthropic-version` header）
- **监控面板：** `http://localhost:8082/dashboard`
- **健康检查：** `http://localhost:8082/health`

---

## 📖 使用指南

### OpenAI 格式调用（完全兼容）

```bash
# Chat Completions
curl http://localhost:8082/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek-ai/deepseek-v4-flash",
    "messages": [{"role": "user", "content": "你好"}],
    "stream": true
  }'

# 获取模型列表
curl http://localhost:8082/v1/models

# 健康检查
curl http://localhost:8082/health
```

### Anthropic 格式调用（★ 新增）

> 通过 `anthropic-version` 请求头识别为 Anthropic 格式，自动进行格式转换。

```bash
# Messages API（完全兼容 Anthropic SDK）
curl http://localhost:8082/v1/messages \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -H "x-api-key: any-string" \
  -d '{
    "model": "deepseek-v4-flash",
    "max_tokens": 1024,
    "messages": [
      {"role": "user", "content": "你好"}
    ]
  }'

# 获取模型列表（Anthropic 格式）
curl http://localhost:8082/v1/models \
  -H "anthropic-version: 2023-06-01"

# Token 计数估算
curl http://localhost:8082/v1/messages/count_tokens \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{
    "model": "claude-sonnet-4-6",
    "messages": [
      {"role": "user", "content": "Hello, world!"}
    ]
  }'
```

#### Anthropic 特有功能支持

| 功能 | 状态 | 说明 |
|------|------|------|
| ✅ **Thinking 模式** | 支持 | `"thinking": {"type": "enabled", "budget_tokens": 1024}` |
| ✅ **Tool Use** | 支持 | 工具定义 + tool_choice 自动/强制/禁止 |
| ✅ **System Prompt** | 支持 | 字符串或内容块数组格式 |
| ✅ **流式输出** | 支持 | Anthropic SSE 事件流（`content_block_start/delta/stop`） |
| ✅ **消息截断** | 自动 | 超出上下文窗口时按策略自动截断 |
| ✅ **错误转换** | 自动 | NVIDIA 错误 → Anthropic 错误格式 |
| ✅ **模型映射** | 自动 | `claude-*` → 对应的 NVIDIA 模型 |

---

## 🔌 客户端接入

### OpenAI 兼容客户端

将 `http://localhost:8000/v1` 作为 **API Base URL** 配置到以下客户端：

- [ChatBox](https://github.com/Bin-Huang/chatbox)
- [LobeChat](https://github.com/lobehub/lobe-chat)
- [NextChat](https://github.com/Yidadaa/ChatGPT-Next-Web)
- 任何兼容 OpenAI SDK 的应用

### Anthropic 兼容客户端

将 `http://localhost:8000` 作为 **API Base URL**，并确保请求携带 `anthropic-version` header：

- **Claude Code** (CLI)
- **Claude Desktop**
- 任何使用 Anthropic Python/TypeScript SDK 的应用

#### Claude Code 配置示例

```bash
# 设置环境变量
export ANTHROPIC_BASE_URL="http://localhost:8082"
export ANTHROPIC_API_KEY="any-string"
export ANTHROPIC_AUTH_TOKEN="any-string"

# 或在 ~/.claude/settings.json 中配置
```

项目附带 `scripts/all_in_one.sh`，可一键切换 Claude Code 模型（deepseek-v4-flash / kimi / minimax / glm / deepseek-v4-pro）。

---

## 📡 API 接口清单

### 监控接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/health` | 健康检查 + Key 池摘要 |
| GET | `/stats` | Key 池详细统计 |
| GET | `/dashboard` | Web 监控面板 |

### 统计分析接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/stats/overview` | 总体统计概览 |
| GET | `/api/stats/timeline?minutes=60` | 时序数据（请求量/Token） |
| GET | `/api/stats/models` | 各模型调用量统计 |
| GET | `/api/stats/perf` | 性能指标（TTFT/Tokens/s P50/P95） |
| GET | `/api/stats/keys` | 各 Key Token 消耗统计 |
| GET | `/api/stats/records?limit=50` | 最近请求记录详情 |

### 模型管理接口

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/models` | 获取所有模型（分组展示） |
| POST | `/api/models/{id}/enable` | 启用模型 |
| POST | `/api/models/{id}/disable` | 禁用模型 |
| POST | `/api/models/{id}/toggle` | 切换启用状态 |
| POST | `/api/models/enable-all` | 启用所有模型 |
| POST | `/api/models/disable-all` | 禁用所有模型（保留默认） |
| POST | `/api/models/fetch` | 从 NVIDIA 重新拉取模型列表 |

### OpenAI 兼容接口

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/chat/completions` | Chat Completions（流式/非流式） |
| GET | `/v1/models` | 模型列表 |
| GET | `/v1/models/{model_id}` | 单个模型详情 |

### Anthropic 兼容接口（★ 新增）

| 方法 | 路径 | 说明 |
|------|------|------|
| POST | `/v1/messages` | Messages API（完整兼容） |
| POST | `/v1/messages/count_tokens` | Token 计数估算 |
| GET | `/v1/models` | 模型列表（Anthropic 格式） |
| GET | `/v1/models/{model_id}` | 单个模型详情（Anthropic 格式） |

---

## ⚙️ 高级配置

### 负载均衡策略详解

| 策略 | 适用场景 | 说明 |
|------|----------|------|
| `most_remaining` | **推荐默认** | 优先选择剩余配额最多的 Key，最大化利用率 |
| `round_robin` | 均匀分配场景 | 严格轮询，每个 Key 依次处理请求 |
| `least_used` | 冷启动场景 | 优先选择使用次数最少的 Key |

### 准入控制模式选择

| 模式 | 适用场景 | 行为 |
|------|----------|------|
| `reject_fast` | 高并发 / API 调用 | 配额不足立即返回 429，零资源浪费 |
| `queue_wait` | 交互式 / 聊天 | 智能等待配额释放，用户无感知 |

### 模型级故障转移（Model Fallback）

NVIDIA NIM 各模型的速率限制不同。例如 `deepseek-ai/deepseek-v4-flash` 免费额度消耗极快，而 `deepseek-ai/deepseek-v4-pro` 更稳定。Model Fallback 自动处理这种差异：

```text
客户端请求: deepseek-ai/deepseek-v4-flash
       ↓ 首次尝试
  flash 被 429 → kimi-k2.6 被 429 → minimax-m2.7 → ... → v4-pro 成功
       ↓
响应返回: deepseek-ai/deepseek-v4-flash (对客户端透明)
```

关键行为：
- **触发条件**：仅当所有 Key 都返回 `RateLimitError` (429) 时触发
- **非 429 不降级**：如 401/500/超时等不触发，避免掩盖真实错误
- **范围**：OpenAI 和 Anthropic 双协议均受益（在 proxy.py transport 层实现）
- **客户端透明**：响应中的 `model` 字段保持原始请求值，客户端无感知

配置位于 `balancer.model_fallback`：
| 字段 | 说明 |
|------|------|
| `enabled` | 启用/禁用故障转移 |
| `models` | 按优先级排列的备选模型链（按顺序尝试） |

### Anthropic 模型映射原理

```
客户端请求: claude-sonnet-4-6
       ↓ anthropic_adapter.map_model_to_nvidia()
实际调用: qwen/qwen3.5-397b-a17b  (NVIDIA NIM)
       ↓
响应转换: 模型名回映为 claude-sonnet-4-6
```

通过 `config.yaml` 中的 `anthropic.model_mapping` 自定义映射关系。

---

## �️ 技术栈

| 组件 | 技术 | 用途 |
|------|------|------|
| Web 框架 | FastAPI + Uvicorn | 高性能异步 HTTP 服务 |
| HTTP 客户端 | httpx (HTTP/2) | 异步请求转发 |
| AI SDK | OpenAI Python SDK | 统一接口调用 NVIDIA API |
| 数据库 | SQLite + SQLAlchemy | 统计数据持久化 |
| 日志 | Loguru | 结构化日志 + 自动轮转 |
| 配置 | PyYAML | YAML 配置解析 |
| 前端 | ECharts (内嵌) | 监控面板可视化 |

---

## � 性能指标说明

监控面板和 `/api/stats/perf` 接口提供以下性能指标：

| 指标 | 含义 | 越低/越高越好 |
|------|------|---------------|
| **TTFT P50/P50** | 首个 Token 延迟中位数 | 越低越好 |
| **TTFT P95** | 首个 Token 延迟 95 分位 | 越低越好 |
| **Tokens/s P50** | 生成速度中位数 | 越高越好 |
| **Tokens/s P95** | 生成速度 95 分位 | 越高越好 |

## 📄 License

[MIT](LICENSE)

---

## 🙏 致谢

- [NVIDIA NIM](https://build.nvidia.com/nim) - 提供 AI 推理 API
- [FastAPI](https://fastapi.tiangolo.com/) - 现代 Python Web 框架
- [ECharts](https://echarts.apache.org/) - 数据可视化库
