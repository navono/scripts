# DeepSeek V4 Flash(ds4)在 Jetson AGX Thor 上的安装实录

> 目标:在 thor 上部署 antirez/ds4(DwarfStar 4)推理引擎,
> 跑 DeepSeek-V4-Flash 0731 Q2 量化(87GB)+ DSpark 投机解码草稿(6.97GB)。
>
> 最终成果:安装完成、构建产物 SASS 全部 sm_110、冒烟测试通过
> (capital of France → 正确产出 Paris)。DSpark 投机解码可用(基座+草稿齐备)。

## 0. 硬件与系统基线

同 vLLM-install.md §0(Jetson AGX Thor / sm_110 / 128GB 统一内存 / CUDA 13.2 / 代理出网)。

## 1. 方案来源与适配

上游为 DGX Spark(GB10/sm_121)打造的一键安装器:
`entrpi/ds4-on-spark`(install.sh),对非 GB10 的 Blackwell 芯片**官方支持通用路径**:

```bash
curl -sSL https://raw.githubusercontent.com/entrpi/ds4-on-spark/main/install.sh \
    | bash -s -- --cuda-arch sm_110 --force
```

- `--cuda-arch sm_110`:走 `make cuda CUDA_ARCH=sm_110`(非 sm_121 一律走此分支)
- `--force`:跳过 GB10/SM121 机型检查(Thor 的 compute_cap 是 11.0,不加必退)
- Makefile 用绝对路径 `/usr/local/cuda/bin/nvcc`,不依赖 PATH,链接路径
  `targets/sbsa-linux/lib` 与 Jetson 布局一致

## 2. install.sh 各阶段与 thor 的对照

| 阶段 | 脚本行为 | thor 上的结果 |
|---|---|---|
| verify_host | aarch64/nvidia-smi/nvcc/磁盘≥120GiB | 全过(需 --force 过机型关) |
| clone_and_build | 克隆 Entrpi/ds4 @v0.6.3 到 ~/code/ds4,make -j14 | ~10 分钟,产出 ds4/ds4-server/ds4-bench/ds4-eval/ds4-agent/ds4_weight_server |
| download_models | 87GiB 基座 + 6.97GiB DSpark 草稿到 ~/gguf,curl -C - 可续传 | 经代理耗时数小时,靠重试外壳(§3)撑完 |
| smoke_test | 单问 "capital of France" 期待 Paris | **通过** |
| install_launcher | 装 ~/.local/bin/ds4-serve + Codex 模型目录 | 完成(注意 ~/.local/bin 默认不在 PATH) |

**构建验证**(确认真是 sm_110 的 SASS,防止旧目标文件混入):

```bash
/usr/local/cuda/bin/cuobjdump ~/code/ds4/ds4-server | grep -oE "arch = sm_[0-9a-z]+" | sort | uniq -c
# 期望: 17 arch = sm_110
```

## 3. 断点重试外壳(应对代理抖动)

87GB 下载期间代理连接反复中断,裸跑 install.sh 会半途而废。
脚本本身幂等(git fast-forward / make 增量 / GGUF 断点续传),套一层重试即可:

```bash
# ~/ds4-retry.sh 要点(完整版见当时部署):
# - curl 先把 install.sh 落盘再 bash 执行
#   (避免 curl 失败输出空流,bash 吞到退出码 0,重试循环误判成功)
# - 失败后 sleep 10 重试,上限 500 次
# - nohup 挂后台,日志 ~/ds4-install.log
```

## 4. DSpark 草稿的坑(重要)

install.sh 对草稿下载失败**只警告、删半成品、继续走完**(设计上容错),
整体退出码仍为 0 → 重试外壳判定"安装成功"退出 → 草稿永远没机会补下。

症状:日志出现 `WARN: DSpark drafter ... not downloadable`,~/gguf 里无草稿文件。
(当时根因:代理多路并发时吞吐崩塌,下载停滞在 0 字节直到连接重置。)

补救:单独断点续传拉草稿(落位后 ds4-serve 启动时自动启用投机解码):

```bash
D=~/gguf/DSpark-drafter-Q2K-Q8-0731.gguf
URL="https://huggingface.co/bleysg/DeepSeek-V4-Flash-DSpark-drafter-GGUF/resolve/main/DSpark-drafter-Q2K-Q8-0731.gguf"
for i in $(seq 1 60); do curl -sL --retry 5 -C - -o "$D" "$URL" && break; sleep 10; done
# 完整大小: 6,971,241,504 字节
```

## 5. 权重与目录布局

```
~/code/ds4/           源码 + 全部二进制(ds4/ds4-server/ds4-bench/...)
~/gguf/
  DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf   (86,720,111,488 B)
  DSpark-drafter-Q2K-Q8-0731.gguf                                                ( 6,971,241,504 B)
~/.local/bin/ds4-serve   启动器(full stack 默认)
~/.config/ds4/            Codex 模型目录
```

## 6. 启动

```bash
~/scripts/start-ds4.sh    # 封装:清理旧实例 + 显式 -m/--dspark + 0.0.0.0:8000 + 端口轮询
```

ds4-serve 常用参数(完整见 `~/.local/bin/ds4-serve --help`):

| 参数 | 说明 |
|---|---|
| `--host 0.0.0.0 --port 8000` | 默认只绑 127.0.0.1,局域网访问必须改 |
| `-c N` | 上下文,CUDA 默认 262144;demand-mapped,不用不占内存 |
| `--dspark FILE` | DSpark 草稿(不给则纯解码,明显慢) |
| `--warm-weights` | 预热权重页:启动更慢,首问不卡 |
| `--reasoning-effort` | low(默认)/high/max/off |
| `--power N` | GPU 占空比 1-100,默认 100 |

注意:87GB 权重 demand-mapped,冷启动首问较慢属正常现象。

## 7. 与其他路线的关系

- 同机还有 vLLM+NVFP4 Qwen3.8(8302 端口)和 llama.cpp DFlash2(8301 端口),
  端口规划与启停脚本见 ~/scripts/。
- DGX Spark 上的 EXL3 替代方案(MiaAI-Lab/DeepSeek-v4-Flash-One-DGX-Spark)
  **不适用于 Thor**:Docker 前置缺失 + sparkinfer 内核钉死 sm_121 镜像不可重编。
- 性能预期:解码为带宽瓶颈(273GB/s 与 Spark 相同),预填充/投机验证受 Thor
  算力(约为 Spark 四成)限制;精确 tps 未测,可跑 ds4-bench 获取。

## 8. 坑总账

| # | 症状 | 根因 | 解法 |
|---|---|---|---|
| 1 | 机型检查直接退出 | thor 非 GB10/SM121 | `--force` |
| 2 | 87GB 下载反复中断 | 代理抖动 | 重试外壳 + 断点续传(§3) |
| 3 | 装完没有 DSpark 草稿 | 草稿失败被静默容忍,整体仍退出 0 | 手动补下(§4) |
| 4 | 草稿下载 0 字节停滞 | 代理多路并发吞吐崩塌 | 错峰单独下载 |
| 5 | 重试外壳误判成功 | curl空流 + 管道 bash 退出码 0 | 先落盘再执行 |
| 6 | pkill 清理时误杀自己 | 命令串含目标关键字 | 按精确进程名/PID 杀 |
