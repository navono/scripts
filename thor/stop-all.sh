#!/bin/bash
# thor: 停止全部推理服务
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/stop-ds4.sh"
"$SCRIPT_DIR/stop-llamacpp-qwen38.sh"
"$SCRIPT_DIR/stop-vllm-qwen38.sh"
"$SCRIPT_DIR/stop-sglang-qwen38.sh"
"$SCRIPT_DIR/stop-flashnext.sh"
