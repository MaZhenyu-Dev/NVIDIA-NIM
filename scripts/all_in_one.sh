#!/bin/bash
# ./scripts/all_in_one.sh <model>  切换模型并启动代理
# 模型: dp_flash (默认), dp_pro, glm, kimi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="$PROJECT_DIR/.venv/bin/python"

case "${1:-dp_flash}" in
  -h|-help|--help)
    echo "用法: ./scripts/all_in_one.sh [模型]"
    echo ""
    echo "模型:"
    echo "  dp_flash   DeepSeek V4 Flash（默认）"
    echo "  dp_pro     DeepSeek V4 Pro"
    echo "  glm        GLM-5.1"
    echo "  kimi       Kimi K2.6"
    echo "  stop       关停代理"
    exit 0
    ;;
  stop)
    PID=$(lsof -ti :8082 -sTCP:LISTEN 2>/dev/null)
    if [ -n "$PID" ]; then
      kill "$PID"
      echo "✅ 代理已停止 (PID: $PID)"
    else
      echo "ℹ️  代理未运行"
    fi
    exit 0
    ;;
  dp_flash) MODEL="deepseek-v4-flash" ;;
  dp_pro)   MODEL="deepseek-v4-pro" ;;
  glm)      MODEL="glm-5.1" ;;
  kimi)     MODEL="kimi" ;;
  *)
    echo "未知模型: $1"
    echo "可用: dp_flash, dp_pro, glm, kimi"
    echo "查看帮助: ./scripts/all_in_one.sh -help"
    exit 1
    ;;
esac

# 生成 settings.json 并写入
MODELS_DIR="$PROJECT_DIR/scripts/models"
mkdir -p "$MODELS_DIR"

SETTINGS_FILE="$MODELS_DIR/settings-$MODEL.json"
if [ ! -f "$SETTINGS_FILE" ]; then
  cat > "$SETTINGS_FILE" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://localhost:8082",
    "ANTHROPIC_AUTH_TOKEN": "ccnim"
  },
  "model": "$MODEL"
}
EOF
fi

cp "$SETTINGS_FILE" ~/.claude/settings.json

# 启动代理
PROXY_PID=$(lsof -ti :8082 -sTCP:LISTEN 2>/dev/null)
if [ -z "$PROXY_PID" ]; then
  echo "🔄 启动代理服务..."
  nohup "$PYTHON" "$PROJECT_DIR/main.py" > "$PROJECT_DIR/logs/proxy.log" 2>&1 &
  sleep 3
  if lsof -ti :8082 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "✅ 代理已启动 (localhost:8082)"
    sleep 2
    curl -s -X POST http://localhost:8082/api/models/enable-all > /dev/null 2>&1 && echo "✅ 已启用所有可用模型"
  else
    echo "❌ 代理启动失败，查看 logs/proxy.log"
  fi
else
  echo "✅ 代理已在运行 (PID: $PROXY_PID)"
fi

echo "✅ Claude Code 模型已切换: $MODEL"
echo "📌 现在可以在任意终端直接运行: claude"
