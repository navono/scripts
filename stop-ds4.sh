#!/bin/bash
# thor: 停止 ds4 服务
for p in $(ps aux | grep -a "ds4-server" | grep -av grep | awk '{print $2}'); do
    echo "停止: $p"; kill "$p" 2>/dev/null
done
sleep 3
free -h | head -2 | tail -1
