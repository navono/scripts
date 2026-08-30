#!/bin/bash
# thor: 启动 SGLang + DSpark 服务（端口 8301）
# 用法: ./start-sglang-qwen38.sh [dspark|base]
set -euo pipefail

MODE="${1:-dspark}"
MODEL=/home/supcon/models/RadixArk/Qwen3.8-27B-NVFP4-BF16-LMHead
DRAFT_MODEL=/home/supcon/models/RadixArk/Qwen3.8-27B-DSpark
PORT=8301
LOG="$(dirname -- "${BASH_SOURCE[0]}")/../logs/sglang-server.log"
PID_FILE=/tmp/sglang-server.pid

if [[ "$MODE" != "base" && "$MODE" != "dspark" ]]; then
    echo "用法: $0 [dspark|base]" >&2
    exit 2
fi
if [[ "$MODE" == "dspark" && ! -f "$DRAFT_MODEL/model.safetensors" ]]; then
    echo "缺少 DSpark 草稿模型: $DRAFT_MODEL/model.safetensors" >&2
    exit 1
fi

"$SCRIPT_DIR/stop-sglang-qwen38.sh"

AVAILABLE_GB=0
for _ in $(seq 1 30); do
    AVAILABLE_GB="$(free -g | awk 'NR == 2 {print $7}')"
    (( AVAILABLE_GB >= 100 )) && break
    sleep 2
done
echo "可用统一内存: ${AVAILABLE_GB}G（至少需要 100G）"
if (( AVAILABLE_GB < 100 )); then
    echo "内存未释放，中止启动" >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG")"
export PATH="$HOME/venvs/sglang/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda-13.2/targets/sbsa-linux/lib:${LD_LIBRARY_PATH:-}"
export CPATH="$HOME/tools/pyinc/python3.12:$HOME/tools/pydev/usr/include"

ARGS=(
    --model-path "$MODEL"
    --served-model-name qwen3.8-27b-nvfp4-bf16-lmhead
    --host 0.0.0.0
    --port "$PORT"
    --trust-remote-code
    --context-length 262144
    --mem-fraction-static 0.75
    --max-running-requests 2
    --chunked-prefill-size 8192
    --max-prefill-tokens 16384
    --attention-backend triton
    --linear-attn-backend triton
    --linear-attn-decode-backend triton
    --fp4-gemm-backend flashinfer_cutlass
    --kv-cache-dtype fp8_e4m3
    --mamba-ssm-dtype bfloat16
    --mamba-full-memory-ratio 4.21
    --mamba-radix-cache-strategy extra_buffer_lazy
    --max-mamba-cache-size 8
    --reasoning-parser qwen3
    --tool-call-parser qwen3_coder
)

if [[ "$MODE" == "dspark" ]]; then
    ARGS+=(
        --speculative-algorithm DSPARK
        --speculative-draft-model-path "$DRAFT_MODEL"
        --speculative-dspark-block-size 7
        --speculative-draft-model-quantization unquant
        --speculative-num-draft-tokens 8
        --disable-prefill-cuda-graph
        --cuda-graph-max-bs-decode 4
        --num-continuous-decode-steps 2
    )
else
    ARGS+=(--disable-cuda-graph)
fi

nohup "$HOME/venvs/sglang/bin/python" -m sglang.launch_server "${ARGS[@]}" >"$LOG" 2>&1 &
echo $! >"$PID_FILE"
echo "SGLang ($MODE) PID $(cat "$PID_FILE")，日志: $LOG"

code=000
for i in $(seq 1 90); do
    code="$(curl -s -o /dev/null -m 3 -w '%{http_code}' "http://127.0.0.1:$PORT/v1/models" 2>/dev/null || true)"
    [[ "$code" == 200 ]] && break
    sleep 10
done

if [[ "$code" == 200 ]]; then
    echo "接口就绪（用时约 $((i * 10)) 秒）: http://$(hostname -I | awk '{print $1}'):$PORT"
else
    echo "900 秒内未就绪，请检查: tail -100 $LOG" >&2
    exit 1
fi
