#!/bin/bash
# make 目标补全 (Git Bash 不自带 bash-completion)
# 支持两级补全: make <TAB> 列 Makefile 字面目标 (thor/4090/...);
#              make thor <TAB> / make 4090 start-<TAB> 列 # completion: 提示行里的动作
# 用法:
#   ./make-completion.bash install   注册到 ~/.bashrc (幂等), 新开终端生效
#   . ./make-completion.bash         仅当前 shell 生效
__make_complete() {
    local cur prev dev pairs pair key val targets
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    if [ "$COMP_CWORD" -eq 1 ] || [ "$prev" = "make" ]; then
        # 第一词: Makefile 字面目标 (排除变量赋值 := 与 .开头/注释/recipe 行)
        targets=$(awk -F: '/^[a-zA-Z0-9]/ && !/:=/ {print $1}' Makefile 2>/dev/null | sort -u)
    else
        # 第二词起: 按 # completion: <设备>=<动作,...> 提示行补全
        dev="$prev"
        pairs=$(sed -n 's/^# completion://p' Makefile 2>/dev/null)
        for pair in $pairs; do
            key="${pair%%=*}"
            if [ "$key" = "$dev" ]; then
                val="${pair#*=}"
                targets="${val//,/ }"
            fi
        done
    fi
    COMPREPLY=($(compgen -W "$targets" -- "$cur"))
}
complete -F __make_complete make

# install 模式: 往 ~/.bashrc 追加一行 source 本脚本 (按 MARKER 幂等去重)
if [ "${1:-}" = "install" ]; then
    MARKER="# make-completion (scripts repo)"
    SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/make-completion.bash"
    if grep -qF "$MARKER" ~/.bashrc 2>/dev/null; then
        DESIRED="[ -f \"$SRC\" ] && . \"$SRC\""
        if grep -qF "$DESIRED" ~/.bashrc; then
            echo "已安装过, 跳过 (~/.bashrc)"
        else
            # 标记在但路径不同 (仓库被移动过): 删除旧块(标记+其后一行)重写
            sed -i "/^${MARKER}\$/ { N; d; }" ~/.bashrc
            { echo ""; echo "$MARKER"; echo "$DESIRED"; } >> ~/.bashrc
            echo "已更新 ~/.bashrc 路径 -> $SRC"
        fi
    else
        { echo ""; echo "$MARKER"; echo "$DESIRED"; } >> ~/.bashrc
        echo "已写入 ~/.bashrc -> . \"$SRC\""
    fi
fi
