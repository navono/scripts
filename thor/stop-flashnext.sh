#!/bin/bash
# thor: 停止 Qwen3.8-Flash-Next 服务并释放统一内存
# 进程特征: qwen4exp 引擎路径(区别于 dflash2 fork 的 llama-server)
for p in $(pgrep -f "llama.cpp-qwen4exp/build/bin/llama-server" || true); do
    echo "停止: $p"; kill "$p" 2>/dev/null || true
done
sleep 3
# 残留兜底
for p in $(pgrep -f "llama.cpp-qwen4exp/build/bin/llama-server" || true); do
    echo "强杀: $p"; kill -9 "$p" 2>/dev/null || true
done
rm -f /tmp/flashnext-server.pid
free -h | head -2 | tail -1
