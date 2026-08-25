#!/bin/bash
# thor: 停止 vLLM 服务并释放统一内存
for p in $(ps aux | grep -a "bin/vllm serve" | grep -av grep | awk '{print $2}'); do
    echo "停止 APIServer: $p"; kill "$p" 2>/dev/null
done
sleep 3
for p in $(ps aux | grep -a "VLLM::EngineCore" | grep -av grep | awk '{print $2}'); do
    echo "清理 EngineCore: $p"; kill -9 "$p" 2>/dev/null
done
sleep 4
free -h | head -2 | tail -1
