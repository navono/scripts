#!/bin/bash
# thor: 查看推理后端运行状态 (哪个后端在跑, PID, 健康检查, 统一内存)
# 用法: make thor status (仅限 thor 主机执行, 或直接 ~/scripts/thor/status.sh)
set -euo pipefail

# 仅限 Linux 主机: 在 Windows 本机跑会因 /proc 缺失把 flash 进程误认成 thor 后端
if ! uname -s | grep -qi linux; then
    echo "thor status 需在 thor 主机执行: ssh thor -- make -C ~/scripts thor status"
    exit 1
fi

PORT=8301

backend() {
    pgrep -f 'bin/vllm serve|VLLM::EngineCore' >/dev/null 2>&1 && { echo vllm; return; }
    pgrep -f 'ds4-server'                      >/dev/null 2>&1 && { echo ds; return; }
    pgrep -f '/home/supcon/venvs/sglang/bin/python.*sglang\.launch_server' >/dev/null 2>&1 && { echo sglang; return; }
    pgrep -f 'llama.cpp-qwen4exp/build/bin/llama-server' >/dev/null 2>&1 && { echo flashnext; return; }
    for p in $(pgrep -f 'llama-server' || true); do
        grep -aq qwen4exp "/proc/$p/cmdline" 2>/dev/null || { echo llama; return; }
    done
}

CURRENT="$(backend || true)"
if [ -z "$CURRENT" ]; then
    echo "thor: 无运行中的后端 (端口 $PORT 空闲)"
else
    PID="$(ss -tlnp 2>/dev/null | grep ":${PORT} " | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2)"
    if curl -sf -m 3 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
        HEALTH=ok
    else
        HEALTH=无响应
    fi
    echo "thor: 后端 $CURRENT, PID ${PID:-未知}, health $HEALTH (端口 $PORT)"
fi
echo "thor: 统一内存可用 $(free -g | awk 'NR == 2 {print $7}')GB"
