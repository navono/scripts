#!/bin/bash
# rtx4090: 查看两个推理服务的运行状态与显存占用
# 用法: make 4090 status (或直接 rtx4090/status.sh)
set -euo pipefail

find_pid() {
    netstat -ano | grep -E ":$1[[:space:]].*LISTENING" | awk '{print $NF}' | head -1
}

report() {
    local name="$1" port="$2" svc_alias="$3" pid health
    pid=$(find_pid "$port" || true)
    if [ -n "$pid" ]; then
        if curl -sf -m 3 "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
            health=ok
        else
            health=无响应
        fi
        printf '%-11s (端口 %s): 运行中 PID %s, health %s, alias=%s\n' \
            "$name" "$port" "$pid" "$health" "$svc_alias"
    else
        printf '%-11s (端口 %s): 未运行\n' "$name" "$port"
    fi
}

echo "== rtx4090 服务状态 =="
report flash 8301 qwen3.8-flash-next
report coldfusion 12234 Qwen3.8-27B-Cold-Fusion

nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv,noheader 2>/dev/null |
    awk -F, '{gsub(/ /, ""); printf "GPU%s 显存: %s / %s\n", $1, $2, $3}' || true
