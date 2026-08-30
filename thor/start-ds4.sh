#!/bin/bash
# thor: 启动 ds4 服务 (DeepSeek-V4-Flash Q2 + DSpark 投机解码, 端口 8000)
# 用法: ~/scripts/thor/start-ds4.sh
# 注意: 87GB 权重 demand-mapped,首问较慢属正常;--warm-weights 可预热(启动更慢)
set -e

SERVE=$HOME/.local/bin/ds4-serve
BASE=$HOME/gguf/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf
DRAFT=$HOME/gguf/DSpark-drafter-Q2K-Q8-0731.gguf
PORT=8301
LOG="$(dirname -- "${BASH_SOURCE[0]}")/../logs/ds4-server.log"
mkdir -p "$(dirname "$LOG")"

for p in $(ps aux | grep -a "ds4-server" | grep -av grep | awk '{print $2}'); do
    echo "停止旧实例: $p"; kill "$p" 2>/dev/null || true
done
sleep 2

[ -f "$BASE" ]   || { echo "缺基座: $BASE"; exit 1; }
[ -f "$DRAFT" ]  || { echo "缺 DSpark 草稿: $DRAFT (无草稿会以纯解码启动,慢)"; }

nohup "$SERVE" \
    -m "$BASE" \
    --dspark "$DRAFT" \
    -c 262144 \
    --host 0.0.0.0 --port $PORT \
    > "$LOG" 2>&1 &
echo $! > /tmp/ds4-server.pid
echo "ds4 PID $(cat /tmp/ds4-server.pid), 日志: $LOG"

# ds4 无 /health,轮询端口任意 HTTP 响应
for i in $(seq 1 120); do
    code=$(curl -s -o /dev/null -m 3 -w "%{http_code}" http://127.0.0.1:$PORT/version 2>/dev/null || true)
    [ "$code" != "000" ] && [ -n "$code" ] && break
    sleep 10
done
echo "HTTP $code (用时 $((i*10))s): http://$(hostname -I | awk '{print $1}'):$PORT"
if [ "$code" = "000" ]; then
    echo "未就绪,查看: tail -50 $LOG"
    exit 1
fi
