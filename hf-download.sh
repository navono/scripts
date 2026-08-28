#!/bin/bash
# thor: HuggingFace 模型仓库批量下载器(断点续传 + 重试外壳 + 大小校验)
# 用法:
#   ~/scripts/hf-download.sh --stop <repo>                # 停止 <repo> 的下载任务(杀主脚本+全部curl)
#   ~/scripts/hf-download.sh <repo>                       # 列出仓库内各档位(按目录分组+大小), 不下载
#   ~/scripts/hf-download.sh <repo> --only <前缀>          # 只下载匹配<前缀>的文件(选量化档, 最常用)
#   ~/scripts/hf-download.sh <repo> <file...>             # 只下载指定文件(可多个,含目录相对路径)
#   ~/scripts/hf-download.sh <repo> --all                 # 全量下载整个仓库(需显式 --all)
#   ~/scripts/hf-download.sh <repo> --dest <DIR>          # 自定义目标目录
#   ~/scripts/hf-download.sh <repo> --dry-run             # 只列出清单, 不下载
# 例:
#   ~/scripts/hf-download.sh AtomicChat/Qwen3.8-Flash-Next-GGUF \
#       --only Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64
#   ~/scripts/hf-download.sh AtomicChat/Qwen3.8-Flash-Next-GGUF \
#       Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64/Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64-00002-of-00033.gguf
# 说明: 经代理下载(HF 需 http://192.168.50.50:18899);串行下载,勿多路并发(会撑爆代理解)
#       复用 HF API 的 size 字段做完整性校验;已完整文件自动跳过
set -euo pipefail

# --- 代理(thor 出网唯一通道) ---
export http_proxy=http://192.168.50.50:18899 https_proxy=http://192.168.50.50:18899
export HTTP_PROXY=http://192.168.50.50:18899 HTTPS_PROXY=http://192.168.50.50:18899

# --- 配置 ---
MAX_ATTEMPTS=60          # 单文件最大重试次数
RETRY_DELAY=20           # 重试间隔(秒)
MAX_ATTEMPTS_API=20      # 拉取文件清单(API)的最大重试次数
# 端点可覆盖: 主站 LFS/CDN 经代理断流时用镜像
#   HF_ENDPOINT=https://hf-mirror.com ~/scripts/hf-download.sh ...
HF_ENDPOINT="${HF_ENDPOINT:-https://huggingface.co}"
LOG_DIR="$HOME/scripts/logs"
mkdir -p "$LOG_DIR"

usage() {
    echo "用法: $0 <repo> [--only <前缀>|--all|文件...] [--dest DIR] [--dry-run]" >&2
    echo "      $0 --stop <repo>                          停止该仓库的下载任务(主脚本+全部curl)" >&2
    echo "  无参数: 列出仓库内各档位(按目录分组+大小)后退出" >&2
    exit 2
}

[[ $# -ge 1 ]] || usage
REPO="$1"; shift

# --- 子命令: --stop 停止下载任务 (先杀 curl 再杀主脚本; 防孤儿与自匹配) ---
# 用法: --stop <repo> 停指定仓库; --stop 无参停全部(按 PID 文件精确杀 + curl 兜底)
if [[ "$REPO" == "--stop" ]]; then
    TARGET="${1:-}"
    if [[ -z "$TARGET" ]]; then
        # --- 无参: 停止全部下载任务 ---
        # 安全原则: 基于 PID 文件精确杀; curl 用进程名(-x)枚举后按 /proc/ 命令行
        # 白名单确认(命令文本匹配会命中自身与外层 shell, 一律不用)
        STOPPED=()
        for pf in "$LOG_DIR"/hf-download-*.pid; do
            [[ -e "$pf" ]] || continue
            while read -r pid; do
                pkill -P "$pid" 2>/dev/null || true   # 该任务的 curl 子进程(按父 PID, 精确)
                kill "$pid" 2>/dev/null && STOPPED+=("$pid")
            done < "$pf"
            rm -f "$pf"
        done
        # 兜底孤儿 curl: 枚举进程名==curl 的, 只杀下载我们模型的
        curl_stop() {
            local sig="${1:-}"
            for p in $(pgrep -x curl 2>/dev/null || true); do
                local args
                args=$(tr "\0" " " < "/proc/$p/cmdline" 2>/dev/null) || continue
                case "$args" in
                    *"huggingface.co"*resolve*"$HOME/models"*)
                        if [[ "$sig" == "-9" ]]; then kill -9 "$p" 2>/dev/null || true
                        else kill "$p" 2>/dev/null || true; fi ;;
                esac
            done
        }
        curl_stop
        sleep 2
        curl_stop -9
        # 复查: 同类 curl 是否已清(同样白名单方式, 无自匹配风险)
        if pgrep -x curl >/dev/null 2>&1; then
            for p in $(pgrep -x curl 2>/dev/null || true); do
                args=$(tr "\0" " " < "/proc/$p/cmdline" 2>/dev/null) || continue
                case "$args" in *"huggingface.co"*resolve*"$HOME/models"*)
                    echo "仍有残留 curl (PID $p), 请手动处理" >&2
                    exit 1 ;;
                esac
            done
        fi
        if [[ ${#STOPPED[@]} -gt 0 ]]; then
            echo "[$(date +%T)] 已停止 ${#STOPPED[@]} 个下载任务 (PID: ${STOPPED[*]})"
        else
            echo "[$(date +%T)] 当前没有下载任务在运行"
        fi
        exit 0
    fi
    PIDFILE="$LOG_DIR/hf-download-$(echo "$TARGET" | tr / _).pid"
    pid=""
    [[ -f "$PIDFILE" ]] && pid=$(cat "$PIDFILE")
    pkill -f "[c]url .*${TARGET}" 2>/dev/null || true
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        rm -f "$PIDFILE"
    fi
    pkill -f "[h]f-download.sh ${TARGET}" 2>/dev/null || true
    sleep 2
    pkill -9 -f "[c]url .*${TARGET}" 2>/dev/null || true
    pkill -9 -f "[h]f-download.sh ${TARGET}" 2>/dev/null || true
    if pgrep -f "[c]url .*${TARGET}" >/dev/null 2>&1 || pgrep -f "[h]f-download.sh ${TARGET}" >/dev/null 2>&1; then
        echo "仍有残留进程, 请手动处理:" >&2
        pgrep -af "${TARGET}" 2>/dev/null | head -5 >&2
        exit 1
    fi
    echo "[$(date +%T)] 已停止: $TARGET ${pid:+(PID $pid)}"
    exit 0
fi

DEST_BASE="$HOME/models"
FILES=()
ALLOW_ALL=0
ONLY_PREFIX=""
DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dest)     DEST_BASE="$2"; shift 2 ;;
        --all)      ALLOW_ALL=1; shift ;;
        --only)     ONLY_PREFIX="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=1; shift ;;
        *)          FILES+=("$1"); shift ;;
    esac
done
DEST="$DEST_BASE/$REPO"
mkdir -p "$DEST"
LOG="$LOG_DIR/hf-download-$(echo "$REPO" | tr / _).log"

log() { echo "[$(date +%F\ %T)] $*" | tee -a "$LOG"; }

# --- 1. 拉取文件清单(带重试); API 失败会中止, 不会静默空跑 ---
log "拉取文件清单: $REPO"
API_JSON=""
API_FILE=$(mktemp)
for i in $(seq 1 "$MAX_ATTEMPTS_API"); do
    if API_JSON=$(curl -sL --retry 2 --connect-timeout 30 -m 60 \
        "${HF_ENDPOINT}/api/models/${REPO}?blobs=true") && [[ -n "$API_JSON" ]]; then
        echo "$API_JSON" > "$API_FILE"
        python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$API_FILE" 2>/dev/null && break
    fi
    log "  清单重试 $i/$MAX_ATTEMPTS_API"
    API_JSON=""
    sleep "$RETRY_DELAY"
done
[[ -n "$API_JSON" ]] || { log "无法获取文件清单, 终止"; exit 1; }

# --- 2. 解析清单: "size\t相对路径" 每行一个 ---
MAP_FILE=$(mktemp)
python3 - "$API_FILE" "$MAP_FILE" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w") as f:
    for s in d.get("siblings", []):
        f.write(f"{s.get('size', 0)}\t{s['rfilename']}\n")
PY

# --- 3. 大小表 ---
declare -A SIZES
while IFS=$'\t' read -r size rel; do
    [[ -n "$rel" ]] && SIZES["$rel"]="$size"
done < "$MAP_FILE"

# --- 4. 单文件下载函数 -- 断点续传 + 重试 + 大小校验 ---
download_file() {
    local rel="$1" size="$2" out="$DEST/$rel"
    local url="${HF_ENDPOINT}/${REPO}/resolve/main/${rel}"
    mkdir -p "$(dirname "$out")"

    # 已完整: 跳过(中断重启时生效)
    if [[ "$size" -gt 0 ]] && [[ -f "$out" ]] && [[ "$(stat -c%s "$out")" -eq "$size" ]]; then
        log "  跳过(已完整): $rel"
        return 0
    fi

    local attempts=0 rc got
    while :; do
        attempts=$((attempts + 1))
        set +e
        # 断流守卫: 速度 <10KB/s 持续 30s 即放弃本次连接(rc=28), 快速进入重试
        curl -sL --path-as-is --connect-timeout 30 --max-time 900 \
            --speed-limit 10240 --speed-time 30 \
            -C - -o "$out" "$url" >/dev/null 2>&1
        rc=$?
        set -e
        got=0
        [[ -f "$out" ]] && got=$(stat -c%s "$out")

        # 完成判定: 大小匹配(curl 可能带 rc=0 或 rc=33 的 416); 大小未知时 curl 0 退出即完成
        if [[ "$size" -gt 0 ]]; then
            if [[ "$got" -eq "$size" ]]; then
                log "  完成: $rel ($got 字节)"
                return 0
            fi
        else
            [[ "$rc" -eq 0 ]] && { log "  完成(大小未知): $rel"; return 0; }
        fi
        log "  重试($attempts/$MAX_ATTEMPTS): $rel (rc=$rc got=$got size=$size)"
        [[ "$attempts" -ge "$MAX_ATTEMPTS" ]] && { log "! 放弃: $rel"; return 1; }
        sleep "$RETRY_DELAY"
    done
}

# --- 5. 目标列表: 指定文件 > --only 前缀 > 全量(需确认) ---
TARGETS=()
mode="files"
if [[ ${#FILES[@]} -gt 0 ]]; then
    TARGETS=("${FILES[@]}")
    TOTAL_BYTES=0
    for f in "${FILES[@]}"; do TOTAL_BYTES=$((TOTAL_BYTES + ${SIZES[$f]:-0})); done
elif [[ -n "$ONLY_PREFIX" ]]; then
    mode="only"
    TOTAL_BYTES=0
    while IFS=$'\t' read -r size rel; do
        [[ "$rel" == "$ONLY_PREFIX"* ]] && { TARGETS+=("$rel"); TOTAL_BYTES=$((TOTAL_BYTES + ${SIZES[$rel]:-0})); }
    done < "$MAP_FILE"
    [[ ${#TARGETS[@]} -gt 0 ]] || { log "无匹配 '$ONLY_PREFIX' 的文件"; exit 1; }
else
    # 无参数: 不下载, 列出各档位(按目录分组)供选择
    if [[ "$ALLOW_ALL" -ne 1 ]]; then
        log "未指定下载目标, 仓库内容如下(选档请用 --only <前缀>, 全量用 --all):"
        python3 - "$MAP_FILE" <<'PY'
import sys, collections
d = collections.defaultdict(lambda: [0, 0])
for line in open(sys.argv[1]):
    sz, name = line.rstrip("\n").split("\t", 1)
    key = name.split("/")[0] if "/" in name else "(根目录)"
    d[key][0] += int(sz)
    d[key][1] += 1
for k in sorted(d, key=lambda x: -d[x][0]):
    print(f"    {d[k][0]/1e9:9.2f} GB  {d[k][1]:5d} 个文件  {k}")
PY
        log "例: $0 $REPO --only <前缀>"
        rm -f "$MAP_FILE" "$API_FILE"
        exit 3
    fi
    mode="all"
    mapfile -t TARGETS < <(sort -k1,1nr "$MAP_FILE" | cut -f2-)
    TOTAL_BYTES=$(awk -F'\t' '{s+=$1} END{print s+0}' "$MAP_FILE")
fi

# --- 6. dry-run 只列清单 ---
log "目标目录: $DEST"
log "待下载: ${#TARGETS[@]} 个文件, 合计 $(python3 -c "print(round($TOTAL_BYTES/1e9,2))") GB (模式: $mode)"
if [[ "$DRY_RUN" -eq 1 ]]; then
    log "== 清单(${mode}) =="
    for rel in "${TARGETS[@]}"; do log "  ${SIZES[$rel]:-?}  $rel"; done
    log "dry-run 结束, 未下载"
    rm -f "$MAP_FILE" "$API_FILE"
    exit 0
fi

# --- 7. 顺序下载 (写 PID 文件供 --stop 使用; EXIT 时自清) ---
PIDFILE="$LOG_DIR/hf-download-$(echo "$REPO" | tr / _).pid"
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT
FAILED=()
for rel in "${TARGETS[@]}"; do
    download_file "$rel" "${SIZES[$rel]:-0}" || FAILED+=("$rel")
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    log "=== 完成, 但 ${#FAILED[@]} 个文件仍失败 ==="
    for f in "${FAILED[@]}"; do log "  FAIL: $f"; done
    rm -f "$MAP_FILE" "$API_FILE"
    exit 1
fi
rm -f "$MAP_FILE" "$API_FILE"
log "=== 全部完成 ==="
