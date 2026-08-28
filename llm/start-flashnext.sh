#!/bin/bash
# thor: 启动 Qwen3.8-Flash-Next 服务 (llama.cpp qwen4exp 分支, AtomicChat AD-4.27bpw, 端口 8301)
# 用法: ~/scripts/llm/start-flashnext.sh
# 说明: 176B MoE(激活 6B), 95GB 分片 mmap 按需加载,首次请求有 IO 高峰属正常
# 引擎: ~/code/llama.cpp-qwen4exp (unsloth PR #27742, sm_110, 见 docs/)
set -euo pipefail

BIN=$HOME/code/llama.cpp-qwen4exp/build/bin/llama-server
QDIR=$HOME/models/AtomicChat/Qwen3.8-Flash-Next-GGUF/Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64
MODEL=$QDIR/Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64-00001-of-00033.gguf
MMPROJ=$HOME/models/AtomicChat/Qwen3.8-Flash-Next-GGUF/mmproj-Qwen3.8-Flash-Next-F16.gguf
# 补丁模板: 原模板遇中途 system 消息直接 raise(Claude Code 必触发), 此版把 system 归拢到开头
TPL=$HOME/models/AtomicChat/Qwen3.8-Flash-Next-GGUF/chat-template-claude-code.jinja
PORT=8301
LOG=$HOME/scripts/logs/flashnext-server.log
mkdir -p "$(dirname "$LOG")"

# 视觉: 必须配 --no-mmproj-offload。mmproj 卸载 GPU 的路径在 PR #27742 会死锁
# (futex_wait, 2026-08-28 实测); 视觉编码器留 CPU 则正常, 已实测图片解析可用。
# 另: 音频/视频输入需要 ffprobe 在 PATH, 未装则仅图片可用。
# ngram-mod: 无草稿投机解码(参数来自 sxuff/qwen38-flash-next-dgx-spark)。
# 2026-08-28 配对实测: 复制代码 3.99x / JSON 2.0x / 聚合 1.96x, 输出无损;
# 自由生成无增益无副作用。
[ -x "$BIN" ]     || { echo "缺引擎: $BIN (见 docs/flashnext-install.md)"; exit 1; }
[ -f "$MODEL" ]   || { echo "缺模型: $MODEL"; exit 1; }
[ -f "$MMPROJ" ]  || { echo "缺视觉: $MMPROJ"; exit 1; }
[ -f "$TPL" ]     || { echo "缺模板: $TPL"; exit 1; }

# 停旧实例(仅本引擎, 不碰 dflash2 fork 的 llama-server)
for p in $(pgrep -f "llama.cpp-qwen4exp/build/bin/llama-server" || true); do
    echo "停止旧实例: $p"; kill "$p" 2>/dev/null || true
done
sleep 3

nohup "$BIN" \
    -m "$MODEL" \
    --mmproj "$MMPROJ" \
    --no-mmproj-offload \
    --chat-template-file "$TPL" \
    --alias qwen3.8-flash-next \
    -ngl 99 \
    -c 262144 \
    --parallel 1 \
    -fa on \
    -t 14 \
    --threads-batch 14 \
    --spec-type ngram-mod \
    --spec-ngram-mod-n-match 24 \
    --spec-ngram-mod-n-min 48 \
    --spec-ngram-mod-n-max 64 \
    --host 0.0.0.0 \
    --port $PORT \
    > "$LOG" 2>&1 &
echo $! > /tmp/flashnext-server.pid
echo "flashnext PID $(cat /tmp/flashnext-server.pid), 日志: $LOG"

# 等就绪(95GB mmap + CUDA 图初始化较慢, 上限 30 分钟)
# 每 3 分钟输出一次启动进度(health/RSS/最近日志), 不黑等
PID=$(cat /tmp/flashnext-server.pid)
code=000
report_at=0
for i in $(seq 1 180); do
    code=$(curl -s -o /dev/null -m 5 -w "%{http_code}" "http://127.0.0.1:$PORT/health" 2>/dev/null || true)
    [ "$code" = "200" ] && break
    now=$((i * 10))
    if [ $((now - report_at)) -ge 180 ]; then
        RSS_GB=$(ps -o rss= -p "$PID" 2>/dev/null | awk '{printf "%.1f", $1/1048576}' || echo "?")
        LAST_LOG=$(tail -1 "$LOG" 2>/dev/null | cut -c1-90)
        echo "[启动进度 ${now}s] health=$code RSS=${RSS_GB}GB 最近日志: ${LAST_LOG:-无}"
        report_at=$now
    fi
    sleep 10
done
if [ "$code" = "200" ]; then
    echo "就绪(用时 ${now}s): http://$(hostname -I | awk '{print $1}'):$PORT  (别名 qwen3.8-flash-next)"
else
    echo "30 分钟未就绪, 查看: tail -100 $LOG"; exit 1
fi
