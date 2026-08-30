#!/bin/bash
# thor: 启动 llama.cpp DFlash2 服务 (端口 8301, Qwen3.8-27B Q4_K_M + DFlash2 草稿, ~17.5 t/s)
# 用法: ~/scripts/thor/start-llamacpp-qwen38.sh
set -e

BIN=$HOME/code/llama.cpp-dflash2/build/bin/llama-server
TARGET=$HOME/models/JonathanColetti/Qwen3.8-27B-Uncensored-GGUF/Qwen3.8-27B-Uncensored-Q4_K_M.gguf
DRAFT=$HOME/models/incoai/Qwen3.8-27B-DFlash2-GGUF/Qwen3.8-27B-DFlash2-Q8_0.gguf
MMPROJ=$HOME/models/JonathanColetti/Qwen3.8-27B-Uncensored-GGUF/Qwen3.8-27B-Uncensored-vision-f16.gguf  # 需要视觉时取消注释并加 --mmproj
PORT=8301
LOG="$(dirname -- "${BASH_SOURCE[0]}")/../logs/llamacpp-server.log"
mkdir -p "$(dirname "$LOG")"

for p in $(ps aux | grep -a "llama-server" | grep -av grep | awk '{print $2}'); do
    echo "停止旧实例: $p"; kill "$p" 2>/dev/null || true
done
sleep 2

# n_max=4 为实测最优(3~4 同档,再高接受率崩)
nohup "$BIN" \
    -m "$TARGET" \
    --mmproj "$MMPROJ" \
    -md "$DRAFT" \
    --split-mode layer \
    --spec-type draft-dflash \
    --spec-draft-n-max 3 \
    --alias qwen3.8-27b-uncensored \
    --parallel 2 \
    -ngl 99 \
    --fit off \
    -fa on \
    --flash-attn on \
    --agent \
    -t 16 \
    --threads-batch 16 \
    --host 0.0.0.0 \
    --port $PORT \
    -c 262144 \
    > "$LOG" 2>&1 &
echo $! > /tmp/llamacpp-server.pid
echo "llama-server PID $(cat /tmp/llamacpp-server.pid), 日志: $LOG"

for i in $(seq 1 60); do
    code=$(curl -s -o /dev/null -m 3 -w "%{http_code}" http://127.0.0.1:$PORT/health 2>/dev/null || true)
    [ "$code" = "200" ] && break
    sleep 5
done
if [ "$code" = "200" ]; then
    echo "就绪(用时 $((i*5))s): http://$(hostname -I | awk '{print $1}'):$PORT  (模型别名 qwen3.8-27b-uncensored)"
else
    echo "未就绪,查看: tail -50 $LOG"; exit 1
fi
