#!/bin/bash
# thor: 启动 vLLM NVFP4 + MTP 服务 (端口 8301)
# 用法: ~/scripts/llm/start-vllm-qwen38.sh [--restart]
# 依赖: ~/venvs/vllm (源码可编辑安装), CUDA 13.2 工具链
set -e

MODEL=/home/supcon/models/sakamakismile/Huihui-Qwen3.8-27B-abliterated-NVFP4
PORT=8301
LOG=$HOME/scripts/logs/vllm-server.log
mkdir -p "$(dirname "$LOG")"

# --- 先清理旧实例(含 EngineCore 僵尸,否则统一内存不释放) ---
for p in $(ps aux | grep -a "bin/vllm serve" | grep -av grep | awk '{print $2}'); do
    echo "停止旧 APIServer: $p"; kill "$p" 2>/dev/null || true
done
sleep 3
for p in $(ps aux | grep -a "VLLM::EngineCore" | grep -av grep | awk '{print $2}'); do
    echo "清理 EngineCore: $p"; kill -9 "$p" 2>/dev/null || true
done
sleep 4
AVAIL=$(free -g | head -2 | tail -1 | awk '{print $7}')
echo "内存可用: ${AVAIL}G (需 >100G)"
[ "$AVAIL" -lt 100 ] && { echo "内存未释放,中止"; exit 1; }

# --- 关键环境(缺一不可,均为踩坑结论) ---
# PATH 带 venv/bin: torch.compile 需要调 ninja 可执行文件
# CPATH 指向解包的 python3.12 头文件: triton JIT 编译 cuda_utils.c 需要
export PATH="$HOME/venvs/vllm/bin:$PATH"
export CPATH="$HOME/tools/pyinc/python3.12:$HOME/tools/pydev/usr/include"

nohup "$HOME/venvs/vllm/bin/vllm" serve "$MODEL" \
    --served-model-name qwen3.8-27b-abliterated-nvfp4 huihui-nvfp4 \
    --port $PORT \
    --max-model-len 262144 \
    --gpu-memory-utilization 0.80 \
    --max-num-seqs 2 \
    --speculative-config '{"method": "mtp", "num_speculative_tokens": 3}' \
    --reasoning-parser qwen3 \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_xml \
    > "$LOG" 2>&1 &
echo $! > /tmp/vllm-server.pid
echo "server PID $(cat /tmp/vllm-server.pid), 日志: $LOG"

# --- 等就绪(看 HTTP 状态码;端口绑定比日志晚 ~20s,勿抢跑) ---
for i in $(seq 1 90); do
    code=$(curl -s -o /dev/null -m 3 -w "%{http_code}" http://127.0.0.1:$PORT/health 2>/dev/null || true)
    [ "$code" = "200" ] && break
    sleep 10
done
if [ "$code" = "200" ]; then
    echo "就绪(用时 $((i*10))s): http://$(hostname -I | awk '{print $1}'):$PORT"
    curl -s http://127.0.0.1:$PORT/v1/models | python3 -c 'import json,sys; [print("  模型:", m["id"]) for m in json.load(sys.stdin)["data"]]'
else
    echo "90x10s 未就绪,查看: tail -50 $LOG"; exit 1
fi
