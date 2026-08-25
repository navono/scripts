#!/bin/bash
# thor: 停止 llama.cpp 服务
for p in $(ps aux | grep -a "llama-server" | grep -av grep | awk '{print $2}'); do
    echo "停止: $p"; kill "$p" 2>/dev/null
done
sleep 2
echo "done"
