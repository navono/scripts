#!/bin/bash
# thor: 停止 SGLang 服务并释放统一内存
set -u

PID_FILE=/tmp/sglang-server.pid
if [[ -f "$PID_FILE" ]]; then
    pid="$(cat "$PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
        echo "停止 SGLang: $pid"
        kill "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
fi

for pid in $(pgrep -f '/home/supcon/venvs/sglang/bin/python.*sglang\.launch_server' || true); do
    echo "清理 SGLang 进程: $pid"
    kill "$pid" 2>/dev/null || true
done

for _ in $(seq 1 20); do
    pgrep -f '/home/supcon/venvs/sglang/bin/python.*sglang\.launch_server' >/dev/null || break
    sleep 1
done
free -h | awk 'NR == 2'
