#!/bin/bash
# rtx4090: 查看运行中推理服务的日志 (同一时间基本只跑一个, 显示识别到的那个)
# 用法: make 4090 logs [行数] [follow]   默认最近 50 行; follow = 持续跟踪 (Ctrl-C 退出)
#       行数和 follow 顺序随意; 直接调用时 follow 也可写成 -f
# 识别: 两服务可能共用 8301 端口, 光靠端口分不清是谁, 找到监听 PID 后
#       按进程命令行里的模型名关键字判断归属
set -euo pipefail

DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# 服务定义: 名称|端口|日志文件|进程命令行识别关键字
SERVICES=(
    "flash|8301|$DIR/../logs/qwen38-flash-server.log|flash-next"
    "coldfusion|8301|$DIR/../logs/qwen38-coldfusion-server.log|cold-fusion"
)

declare -A CMDLINE   # PID -> 进程命令行缓存
pid_cmdline() {
    local p="$1"
    if [ -z "${CMDLINE[$p]:-}" ]; then
        CMDLINE[$p]="$(powershell -NoProfile -Command \
            "(Get-CimInstance Win32_Process -Filter 'ProcessId=$p').CommandLine" 2>/dev/null || true)"
    fi
    echo "${CMDLINE[$p]}"
}

find_pid() {
    netstat -ano | grep -E ":$1[[:space:]].*LISTENING" | awk '{print $NF}' | head -1
}

follow=""
lines=50
for a in "$@"; do
    case "$a" in
        -f|--follow|follow) follow=1 ;;
        ''|*[!0-9]*) echo "无法识别的参数: $a (用法: logs [行数] [follow])" >&2; exit 1 ;;
        *) lines=$a ;;
    esac
done

name="" log="" pid="" listener="" listener_port=""
for svc in "${SERVICES[@]}"; do
    IFS='|' read -r name port log key <<< "$svc"
    pid=$(find_pid "$port" || true)
    [ -n "$pid" ] || { name=""; log=""; continue; }
    listener="$pid"; listener_port="$port"
    if grep -qi "$key" <<< "$(pid_cmdline "$pid")"; then
        break
    fi
    name="" log="" pid=""
done

if [ -z "$name" ]; then
    if [ -n "$listener" ]; then
        echo "端口 $listener_port 有进程在监听 (PID $listener), 但不是本仓库管理的推理服务"
    else
        echo "没有运行中的服务 (make 4090 status 查看状态)"
    fi
    exit 1
fi

[ -f "$log" ] || { echo "$name 在运行 (PID $pid) 但找不到日志: $log"; exit 1; }

if [ -n "$follow" ]; then
    echo "== $name 日志 (PID $pid, 跟踪中, Ctrl-C 退出): $log =="
    exec tail -n "$lines" -f "$log"
fi
echo "== $name 日志 (PID $pid, 最近 $lines 行): $log =="
tail -n "$lines" "$log"
