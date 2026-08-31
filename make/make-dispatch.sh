#!/bin/bash
# make <thor|4090> <action> 的分发器; Makefile 把命令行动态目标都转到这里执行
# 兼容: 不带设备的单动作 (如 make start-flash) 按动作名自动路由到对应设备
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

usage() {
    cat <<'EOF'
用法: make <thor|4090> <动作>
  thor:
    start-vllm  start-ds  start-sglang  start-llama  start-flashnext  stop-all  status
  4090:
    start-flash  stop-flash  start-coldfusion  stop-coldfusion  status  logs
  4090 logs 附加参数: [行数] [follow]   如 make 4090 logs 100 follow
动作可省略设备前缀自动路由, 如 make start-flash
thor 动作在其他机器执行时自动经 ssh 转发到 thor
EOF
}

run_thor() {
    case "$1" in
        start-vllm)      thor/switch vllm ;;
        start-ds)        thor/switch ds ;;
        start-sglang)    thor/switch sglang ;;
        start-llama)     thor/switch llama ;;
        start-flashnext) thor/switch flashnext ;;
        stop-all)        thor/stop-all.sh ;;
        status)          thor/status.sh ;;
        *) echo "未知 thor 动作: $1" >&2; usage; exit 1 ;;
    esac
}

# thor 动作只能在 thor 主机本地执行; 其他机器 (如 Windows 工作站) 自动经 ssh 转发。
# 依赖 thor 端已部署本仓库 (~/scripts); 未部署时给明确指引
thor_action() {
    if uname -s | grep -qi linux; then
        run_thor "$1"
    else
        exec ssh thor -- "if [ -d ~/scripts/.git ]; then make -C ~/scripts thor $1; else echo 'thor 端未部署 scripts 仓库: 在本机执行 git push thor main 完成部署'; exit 127; fi"
    fi
}

run_4090() {
    case "$1" in
        start-flash)      bash rtx4090/start-qwen38-flash.sh ;;
        stop-flash)       bash rtx4090/stop-qwen38-flash.sh ;;
        start-coldfusion) bash rtx4090/start-qwen38-coldfusion.sh ;;
        stop-coldfusion)  bash rtx4090/stop-qwen38-coldfusion.sh ;;
        status)           bash rtx4090/status.sh ;;
        logs)             bash rtx4090/logs.sh ;;
        *) echo "未知 4090 动作: $1" >&2; usage; exit 1 ;;
    esac
}

case "${1:-}" in
    ""|-h|--help) usage; exit 1 ;;
    thor|4090)
        DEVICE="$1"
        shift
        [ $# -ge 1 ] || { echo "缺少动作" >&2; usage; exit 1; }
        while [ $# -gt 0 ]; do
            action="$1"; shift
            if [ "$DEVICE" = "4090" ] && [ "$action" = "logs" ]; then
                # logs 的附加参数 (行数/follow) 一并交给 logs.sh, 不再当作后续动作
                bash rtx4090/logs.sh "$@"
                break
            fi
            case "$DEVICE" in thor) thor_action "$action" ;; 4090) run_4090 "$action" ;; esac
        done
        ;;
    start-vllm|start-ds|start-sglang|start-llama|start-flashnext|stop-all)
        thor_action "$1" ;;
    start-flash|stop-flash|start-coldfusion|stop-coldfusion|logs)
        run_4090 "$1" ;;
    *)
        echo "未知目标: $1" >&2; usage; exit 1 ;;
esac
