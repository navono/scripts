#!/bin/bash
# rtx4090: 停止 Qwen3.8-Flash-Next 服务 (按端口 8301 找 PID 后 taskkill)
# 用法: rtx4090/stop-qwen38-flash.sh
set -euo pipefail

PORT=8301

find_pid() {
    netstat -ano | grep -E ":${PORT}[[:space:]].*LISTENING" | awk '{print $NF}' | head -1
}

pid=$(find_pid || true)
if [ -z "$pid" ]; then
    echo "未在运行"
    exit 0
fi
taskkill //F //PID "$pid" >/dev/null
echo "已停止 (PID $pid)"

# 等待端口释放, 避免紧随的 start 误判仍在运行
for _ in $(seq 1 15); do
    [ -z "$(find_pid || true)" ] && exit 0
    sleep 1
done
echo "警告: 端口 $PORT 仍未释放, 请手动确认"
exit 1
