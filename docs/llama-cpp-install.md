# llama.cpp(DFlash2 分支)在 Jetson AGX Thor 上的安装实录

> 目标:在 thor 上构建带 **DFlash2 投机解码**的 llama.cpp(z-lab fork),
> 服务 Qwen3.8-27B GGUF 系列(从 Windows 本地库迁入)。
>
> 最终成果:Q4_K_M + DFlash2 解码 **17.5 t/s**(基线 11.8 → +48%),
> 预填充 374 t/s;Q6_K 基线 8.87 t/s。

## 0. 硬件与系统基线

同 vLLM-install.md §0。构建前置:nvcc(随 cuda-toolkit-13-2 已装)、gcc/make/git。

## 1. 源码选型(重要)

DFlash2 **不在上游 llama.cpp**(截至 2026-08 仍是 PR #27342),真源在:

```bash
git clone --depth 1 -b dflash2 https://github.com/z-lab/llama.cpp-fork.git \
    ~/code/llama.cpp-dflash2
```

GitHub 上另有两个 "llama-dflash2" 仓库(adicrescenzo / haol666)只是
Docker 镜像封装(x86 GPU 云 / sm_121),对 Thor 无用,不要走弯路。

## 2. cmake(免 sudo)

pip 拉 cmake 经此代理不通(报 No matching distribution),
用 GitHub Releases 的 aarch64 预编译包:

```bash
mkdir -p ~/tools && cd ~/tools
curl -sL --retry 5 -o cmake.tar.gz \
    https://github.com/Kitware/CMake/releases/download/v4.4.2/cmake-4.4.2-linux-aarch64.tar.gz
tar xzf cmake.tar.gz && rm cmake.tar.gz
CMAKE=~/tools/cmake-4.4.2-linux-aarch64/bin/cmake
```

## 3. 构建

```bash
export PATH=/usr/local/cuda/bin:$PATH
cd ~/code/llama.cpp-dflash2
$CMAKE -B build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=110 \
       -DCMAKE_BUILD_TYPE=Release
$CMAKE --build build -j 14          # 14 核约 10 分钟
```

产物:build/bin/{llama-server, llama-cli, llama-bench, ...}

## 4. 模型布局

从 Windows(E:\data\hf_models)经局域网 scp 迁入(~63GB,~44MB/s):

```
~/models/JonathanColetti/Qwen3.8-27B-Uncensored-GGUF/   # Q4_K_M 16G + vision mmproj
~/models/HuiHui/Huihui-Qwen3.8-27B-abliterated/         # Q6_K 21G + mmproj
~/models/DavidAU/Qwen3.8-27B-Cold-Fusion-...-GGUF/      # Q6_K 23G + mmproj
```

DFlash2 草稿模型(HF 下载,断点续传,代理下约 9 分钟):

```
~/models/incoai/Qwen3.8-27B-DFlash2-GGUF/Qwen3.8-27B-DFlash2-Q8_0.gguf   # 1.91GB
# 同仓库另有 BF16(3.87GB)/Q4_K_M(1.1GB)版
```

## 5. 基准与调优结论(MAXN 130W 实测)

```bash
# 基线(无投机)
./llama-bench -m <Q4_K_M.gguf> -p 384 -n 192
# → pp384: 373.9 t/s, tg192: 11.79 t/s   (120W 模式为 335/11.18)

# DFlash2(n_max 逐档扫: 3/4/5/8/12)
./llama-server -m <目标> -md <草稿> --spec-type draft-dflash \
    --spec-draft-n-max <N> --port 8301 ...
```

| n_max | tg t/s | 接受率 | 平均采纳 |
|---|---|---|---|
| **3(默认)** | **17.11** | 0.540 | 2.62 |
| **4(最优)** | **17.67** | 0.549 | 3.19 |
| 5 | 16.27 | 0.466 | 3.31 |
| 8 | 13.36 | 0.364 | 3.54 |
| 12 | 13.34 | 0.364 | 3.54 |

**结论:n_max 3~4 是甜点,再高草稿越写越长、被毙率陡增。**
BF16 草稿与 Q8_0 接受率逐位相同(贪心解码下量化无损决策),不必用 BF16。

## 6. 启动

```bash
~/scripts/start-llamacpp.sh   # 8301 端口, 别名 qwen3.8-27b-uncensored, n_max=4
```

需要视觉能力时,取消脚本里 --mmproj 注释行。

## 7. 坑总账

| # | 症状 | 根因 | 解法 |
|---|---|---|---|
| 1 | pip 装 cmake 报无匹配发行版 | PyPI 经代理不通 | GitHub aarch64 包解到 ~/tools |
| 2 | llama-cli 不识别 --no-cnv/--simple-io | 此分支旗标名不同 | 用 `-no-cnv` |
| 3 | llama-cli 跑基准卡死到 timeout | 会话模式等 stdin,EOF 后死循环刷提示符 | 基准一律用 llama-bench / llama-server;CLI 必须 `< /dev/null` |
| 4 | n_max 调高反而掉速 | 草稿接受率崩塌,纯浪费算力 | 锁 3~4 |
| 5 | DFlash2 草稿下载中断 | 代理抖动 | 断点续传循环(curl -C -) |
| 6 | 对比数字忽高忽低 | 120W vs MAXN 电源模式 | 测前 `nvpmodel -q` 确认 MAXN |

## 8. 三栈对比终局(Qwen3.8-27B @ thor)

| 栈 | 解码 t/s | 预填充 | 特长 |
|---|---|---|---|
| llama.cpp + DFlash2(本篇) | 17.5 | 374 t/s(浅层) | 轻量、GGUF 生态、单二进制 |
| vLLM + NVFP4 + MTP | 21.7 | 757 t/s(22万深度) | 高并发、120万 KV 池、Anthropic/OpenAI 双协议 |
| ds4 + DSpark(DeepSeek 用) | 未测 | — | 671B 级模型的唯一本地方案 |
