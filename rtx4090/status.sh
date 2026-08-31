#!/bin/bash
# rtx4090: 查看两个推理服务的运行状态与显存占用 (alias 取运行实例命令行里的实际值)
# 用法: make 4090 status (或直接 rtx4090/status.sh)
# 识别: 两服务可能共用 8301 端口 (coldfusion 旧版用 12234), 光靠端口分不清,
#       找到监听 PID 后按进程命令行里的模型名关键字判断归属
set -euo pipefail

find_pid() {
    netstat -ano | grep -E ":$1[[:space:]].*LISTENING" | awk '{print $NF}' | head -1
}

arg_value() {
    # 从命令行串 $1 里取标志 $2 的值 (--flag v 或 --flag=v)
    local rest="$1"
    case "$rest" in
        *"$2="*) rest="${rest#*"$2="}"; echo "${rest%% *}" ;;
        *"$2 "*) rest="${rest#*"$2 "}"; echo "${rest%% *}" ;;
    esac
}

pid_cmdline() {
    powershell -NoProfile -Command \
        "(Get-CimInstance Win32_Process -Filter 'ProcessId=$1').CommandLine" 2>/dev/null || true
}

alias_of() {
    # 运行实例的实际 alias: 命名标志的值, 没有时退回模型文件名
    local cmdline="$1" a m
    a=$(arg_value "$cmdline" --alias)
    if [ -n "$a" ]; then echo "$a"; return; fi
    m=$(arg_value "$cmdline" --model)
    [ -n "$m" ] || m=$(arg_value "$cmdline" -m)
    if [ -n "$m" ]; then echo "${m##*/}"; return; fi
    echo 未知
}

# 每个候选端口识别一次归属, 记录 端口/PID/alias
declare -A RUN_PORT RUN_PID RUN_ALIAS
for port in 8301 12234; do
    pid=$(find_pid "$port" || true)
    [ -n "$pid" ] || continue
    cmdline=$(pid_cmdline "$pid")
    if grep -qi 'flash-next' <<< "$cmdline"; then key=flash
    elif grep -qi 'cold-fusion' <<< "$cmdline"; then key=coldfusion
    else continue
    fi
    RUN_PORT[$key]=$port
    RUN_PID[$key]=$pid
    RUN_ALIAS[$key]=$(alias_of "$cmdline")
done

report() {
    local name="$1" health
    local port="${RUN_PORT[$name]:-}" pid="${RUN_PID[$name]:-}" alias="${RUN_ALIAS[$name]:-}"
    if [ -n "$pid" ]; then
        if curl -sf -m 3 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
            health=ok
        else
            health=无响应
        fi
        printf '%-11s (端口 %s): 运行中 PID %s, health %s, alias=%s\n' \
            "$name" "$port" "$pid" "$health" "$alias"
    else
        printf '%-11s: 未运行\n' "$name"
    fi
}

echo "== rtx4090 服务状态 =="
report flash
report coldfusion

nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader 2>/dev/null |
    awk -F, '{gsub(/ /, ""); printf "GPU%s 显存: %s / %s\n", $1, $2, $3}' || true
