#!/bin/bash
# rtx4090: 启动 Qwen3.8-Flash-Next-Uncensored 服务 (llama.cpp b10679, 端口 8301)
# 用法: rtx4090/start-qwen38-flash.sh
# 说明: 125B 级 MoE (512 专家取 10) + SSM 混合, 架构 qwen4exp, 约 97.5GB, 3 分片
# 引擎: llama.cpp b10679 (首个支持 qwen4exp 的官方构建), CUDA 13.3
#
# 显存分配 (2x RTX 4090, 32K 上下文实测):
#   GPU0 ~17.5GB / GPU1 ~17.9GB (含桌面占用), 各余 ~6.5GB
#   第 28-37 层专家 -> CUDA0, 第 38-47 层专家 -> CUDA1, 其余专家 -> CPU (mmap)
#   生成 ~22 t/s, 短 prompt prefill ~41-48 t/s (CPU 承担 28 层专家, 属正常瓶颈)
# 提速备选: 把 -ot 规则改为 22 层上 GPU0 / 23-47 上 CUDA1 (26 层 GPU)
#   可到 ~24 t/s, 但 GPU1 余量仅 ~2.8GB, 桌面+视觉负载下有 OOM 风险

set -euo pipefail

DIR="/e/data/tools/llama-b10679-cuda13.3"
MODEL_DIR="/e/data/hf_models/orcarouter/Qwen3.8-Flash-Next-Uncensored-GGUF"
MODEL="$MODEL_DIR/Qwen3.8-Flash-Next-Uncensored-IQ4_XS-00001-of-00003.gguf"
MMPROJ="$MODEL_DIR/mmproj-Qwen3.8-Flash-Next-Uncensored-F16.gguf"
LOG="$(dirname -- "${BASH_SOURCE[0]}")/../logs/qwen38-flash-server.log"
mkdir -p "$(dirname "$LOG")"
PORT=8301

find_pid() {
    netstat -ano | grep -E ":${PORT}[[:space:]].*LISTENING" | awk '{print $NF}' | head -1
}

pid=$(find_pid || true)
if [ -n "$pid" ]; then
    echo "已在运行 (PID $pid, 端口 $PORT)"
    exit 0
fi
[ -d "$DIR" ]    || { echo "缺引擎: $DIR"; exit 1; }
[ -f "$MODEL" ]  || { echo "缺模型: $MODEL"; exit 1; }
[ -f "$MMPROJ" ] || { echo "缺视觉: $MMPROJ"; exit 1; }

nohup "$DIR/llama-server.exe" \
    -m "$MODEL" \
    --mmproj "$MMPROJ" \
    -ngl 99 \
    -sm layer \
    -fit off \
    -ot '^per_layer_token_embd\.weight$=CPU,blk\.([0-9]|1[01]|2[5-9]|3[0-4])\.ffn_(up|down|gate|gate_up)_(ch|)exps=CPU' \
    -c 32768 \
    --parallel 1 \
    -fa on \
    -b 2048 \
    -ub 1024 \
    --jinja \
    --alias qwen3.8-flash-next \
    --host 0.0.0.0 \
    --port "$PORT" \
    >> "$LOG" 2>&1 &

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
