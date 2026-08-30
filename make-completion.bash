#!/bin/bash
# make 目标补全 (从当前目录的 Makefile 动态取目标; Git Bash 不自带 bash-completion)
# 用法:
#   ./make-completion.bash install   注册到 ~/.bashrc (幂等), 新开终端生效
#   . ./make-completion.bash         仅当前 shell 生效
# 之后任意含 Makefile 的目录里 make <TAB> 即可补全目标
__make_complete() {
    local cur targets
    cur="${COMP_WORDS[COMP_CWORD]}"
    targets=$(awk -F: '/^[a-zA-Z0-9][a-zA-Z0-9_-]*:/ {print $1}' Makefile 2>/dev/null | sort -u)
    COMPREPLY=($(compgen -W "$targets" -- "$cur"))
}
complete -F __make_complete make

# install 模式: 往 ~/.bashrc 追加一行 source 本脚本 (按 MARKER 幂等去重)
if [ "${1:-}" = "install" ]; then
    MARKER="# make-completion (scripts repo)"
    SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/make-completion.bash"
    if grep -qF "$MARKER" ~/.bashrc 2>/dev/null; then
        echo "已安装过, 跳过 (~/.bashrc 已有 $MARKER)"
    else
        { echo ""; echo "$MARKER"; echo "[ -f \"$SRC\" ] && . \"$SRC\""; } >> ~/.bashrc
        echo "已写入 ~/.bashrc -> . \"$SRC\""
    fi
fi
