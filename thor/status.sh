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

flag_value() {
    # 取 /proc/$1/cmdline (NUL 分隔参数) 里标志 $2 的值; 多值 (--served-model-name a b) 取第一个
    [ -r "/proc/$1/cmdline" ] || return 0
    local prev=""
    while IFS= read -r -d '' a; do
        if [ "$prev" = y ]; then echo "$a"; return 0; fi
        prev=""
        case "$a" in
            "$2") prev=y ;;
            "$2="*) echo "${a#"$2="}"; return 0 ;;
        esac
    done < "/proc/$1/cmdline"
}

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
    # 实际 alias: llama.cpp 系用 --alias, vllm/sglang 用 --served-model-name;
    # 都没有时 (如 ds4) 退回模型文件名
    ALIAS=""
    if [ -n "$PID" ]; then
        case "$CURRENT" in
            vllm|sglang) ALIAS=$(flag_value "$PID" --served-model-name) || true ;;
            *)           ALIAS=$(flag_value "$PID" --alias) || true ;;
        esac
        if [ -z "$ALIAS" ]; then
            for f in --model-path --model -m; do
                ALIAS=$(flag_value "$PID" "$f") || true
                if [ -n "$ALIAS" ]; then ALIAS="${ALIAS##*/}"; break; fi
            done
        fi
    fi
    echo "thor: 后端 $CURRENT, PID ${PID:-未知}, health $HEALTH, alias=${ALIAS:-未知} (端口 $PORT)"
fi
echo "thor: 统一内存可用 $(free -g | awk 'NR == 2 {print $7}')GB"
