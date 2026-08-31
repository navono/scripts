#!/bin/bash
# 给管道输入每行加本地时间前缀 (服务日志补墙钟时间; 引擎自带的是运行时长戳)
# 用法: <服务进程> 2>&1 | bash make/logstamp.sh <日志文件>
# 纯 bash 实现: printf %(...)T 是内建, 不依赖 gawk (thor 上只有 mawk, 无 strftime)
log="$1"
exec >> "$log"
while IFS= read -r line; do
    [ -z "$line" ] && { echo; continue; }
    printf '%(%F %T)T %s\n' -1 "$line"
done
