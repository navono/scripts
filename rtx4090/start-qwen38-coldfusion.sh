#!/bin/bash
# rtx4090: 启动 Qwen3.8-27B-Cold-Fusion-GAIN 服务 (LM Studio 内置 llama.cpp, 端口 12234)
# 用法: rtx4090/start-qwen38-coldfusion.sh
# 说明: DavidAU 修改版 Qwen3.8-27B (GAIN 架构改动 + NEO-MTP 投机解码), Q6_K, 支持图片输入
# 引擎: LM Studio 内置 llama.cpp 2.30.0 (CUDA 12, avx2), 位于 ~/.lmstudio/extensions/backends/
# 服务: 端口 12234, API-Key 鉴权; 双 4090 张量并行 (tensor-split 1,1), 128K 上下文
# 模板: /e/data/qwen36-40b-claude-code-chat-template.jinja
#       enable_thinking + preserve_thinking (Claude Code 可直连, 思考过程保留)

set -euo pipefail

BIN="/c/Users/supcon/.lmstudio/extensions/backends/llama.cpp-win-x86_64-nvidia-cuda12-avx2-2.30.0/llama-server.exe"
MODEL_DIR="/e/data/hf_models/DavidAU/Qwen3.8-27B-Cold-Fusion-GAIN-V1.1-NM-DAU-NEO-MAX-MTP-GGUF"
MODEL="$MODEL_DIR/Qwen3.8-27B-Cold-Fusion-GAIN-V1.1-NM-DAU-NEO-MAX-NEO-MTP-Q6_K.gguf"
MMPROJ="$MODEL_DIR/mmproj-F16.gguf"
TPL="/e/data/qwen36-40b-claude-code-chat-template.jinja"
LOG="$(dirname -- "${BASH_SOURCE[0]}")/../logs/qwen38-coldfusion-server.log"
STAMP="$(dirname -- "${BASH_SOURCE[0]}")/../make/logstamp.sh"
mkdir -p "$(dirname "$LOG")"
PORT=8301
API_KEY="sk-pingqixing"

find_pid() {
    netstat -ano | grep -E ":${PORT}[[:space:]].*LISTENING" | awk '{print $NF}' | head -1
}

pid=$(find_pid || true)
if [ -n "$pid" ]; then
    echo "已在运行 (PID $pid, 端口 $PORT)"
    exit 0
fi
[ -x "$BIN" ]   || { echo "缺引擎: $BIN"; exit 1; }
[ -f "$MODEL" ] || { echo "缺模型: $MODEL"; exit 1; }
[ -f "$MMPROJ" ] || { echo "缺视觉: $MMPROJ"; exit 1; }
[ -f "$TPL" ]   || { echo "缺模板: $TPL"; exit 1; }

# 输出经 logstamp.sh 加本地时间前缀 (引擎自带的是运行时长戳); 整体包在 nohup bash 里脱离会话存活
nohup bash -c '
    stamp="$1" log="$2"; shift 2
    "$@" 2>&1 | bash "$stamp" "$log"
' _ "$STAMP" "$LOG" "$BIN" \
    --model "$MODEL" \
    --alias Qwen3.8-27B-ColdFusion \
    --host 0.0.0.0 \
    --port "$PORT" \
    --api-key "$API_KEY" \
    --verbosity 3 \
    --no-webui \
    --jinja \
    --chat-template-file "$TPL" \
    --chat-template-kwargs '{"enable_thinking":true,"preserve_thinking":true}' \
    --ctx-size 128000 \
    --parallel 2 \
    --n-gpu-layers all \
    --main-gpu 0 \
    --split-mode tensor \
    --tensor-split 1,1 \
    --fit off \
    --n-cpu-moe 0 \
    --batch-size 8192 \
    --ubatch-size 1024 \
    --threads 2 \
    --threads-batch 16 \
    --cache-type-k f16 \
    --cache-type-v f16 \
    --flash-attn on \
    --kv-offload \
    --kv-unified \
    --no-context-shift \
    --ctx-checkpoints 0 \
    --cache-ram 0 \
    --load-mode none \
    --spec-type draft-mtp \
    --spec-draft-n-max 2 \
    --spec-draft-n-min 0 \
    --spec-draft-p-min 0 \
    --mmproj "$MMPROJ" \
    >/dev/null 2>&1 &

echo "启动中... 日志: $LOG"
for _ in $(seq 1 60); do
    sleep 2
    if curl -sf -m 3 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
        echo "就绪: http://127.0.0.1:${PORT}"
        exit 0
    fi
    if ! kill -0 $! 2>/dev/null; then
        echo "启动失败, 最近日志:"; tail -5 "$LOG"; exit 1
    fi
done
echo "等待健康检查超时, 请查看日志"
exit 1
