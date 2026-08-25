#!/bin/bash
# thor: 停止全部推理服务
set -e

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/stop-ds4.sh"
"$SCRIPT_DIR/stop-llamacpp.sh"
"$SCRIPT_DIR/stop-vllm.sh"
"$SCRIPT_DIR/stop-sglang.sh"
