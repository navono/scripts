# vLLM 在 Jetson AGX Thor 上的安装实录

> 目标:在 thor(Jetson AGX Thor 开发套件)上源码构建 vLLM v0.22.0,
> 服务 Qwen3.8-27B-abliterated NVFP4 量化模型 + MTP 投机解码 + Anthropic 协议(Claude Code 可直连)。
>
> 最终成果:解码 21.7 t/s(MTP 接受率 53.8%),深上下文预填充 757 t/s,
> KV 池 108 万 token(4×256k 并发实测 needle 4/4 召回)。

## 0. 硬件与系统基线

| 项目 | 值 |
|---|---|
| 机型 | NVIDIA Jetson AGX Thor Developer Kit(T5000) |
| SoC | aarch64,14 核 Neoverse-V3AE @2.6GHz,Blackwell GPU **sm_110** |
| 内存 | 128GB LPDDR5x 统一内存(273GB/s),nvidia-smi 不报内存(正常) |
| 系统 | JetPack 7 / L4T R39.2.1(Ubuntu 24.04),驱动 595.78 |
| 电源 | MAXN(130W)。`nvpmodel -q` 确认 |
| 网络 | 出网须走代理 `http://192.168.50.50:18899`(DNS 指向宿主机 192.168.50.50) |

## 1. 前置条件

```bash
# CUDA 工具链(需要 sudo,一次即可)
sudo apt install -y cuda-toolkit-13-2
# 验证: /usr/local/cuda/bin/nvcc --version → release 13.2

# PyPI 官方源经此代理不通,统一用清华镜像
# HF / GitHub 经代理可达;rustup 官方源不通,用 TUNA 镜像(见 §4)
```

## 2. venv 与 PyTorch

```bash
python3 -m venv ~/venvs/vllm
~/venvs/vllm/bin/pip install --upgrade pip -i https://pypi.tuna.tsinghua.edu.cn/simple

# aarch64 cu130 轮子存在于官方源(vLLM v0.22.0 钉的版本)
~/venvs/vllm/bin/pip install torch==2.11.0+cu130 \
    --index-url https://download.pytorch.org/whl/cu130
```

## 3. 源码与依赖

```bash
git clone --depth 1 -b v0.22.0 https://github.com/vllm-project/vllm.git ~/code/vllm

# 运行依赖(common + cuda)
~/venvs/vllm/bin/pip install \
    -r ~/code/vllm/requirements/common.txt \
    -r ~/code/vllm/requirements/cuda.txt \
    -i https://pypi.tuna.tsinghua.edu.cn/simple

# 构建依赖(--no-build-isolation 模式必须自备,对应 pyproject [build-system])
~/venvs/vllm/bin/pip install "setuptools-rust>=1.9" "setuptools-scm>=8.0" \
    ninja cmake wheel "packaging>=24.2" \
    -i https://pypi.tuna.tsinghua.edu.cn/simple
```

## 4. Rust 工具链(免 sudo,经 TUNA 镜像)

```bash
export RUSTUP_DIST_SERVER=https://mirrors.tuna.tsinghua.edu.cn/rustup
export RUSTUP_UPDATE_ROOT=https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup
curl -sSfL -o /tmp/rustup-init \
    https://mirrors.tuna.tsinghua.edu.cn/rustup/rustup/dist/aarch64-unknown-linux-gnu/rustup-init
chmod +x /tmp/rustup-init && /tmp/rustup-init -y --profile minimal --default-toolchain stable
# 之后 source ~/.cargo/env
```

## 5. Python 头文件(免 sudo 的关键 hack)

系统没装 python3.12-dev,CMake FindPython 和 Triton JIT 都需要头文件:

```bash
# deb 拉下来解到用户目录(apt download 无需 root)
mkdir -p ~/tools/pydev-debs && cd ~/tools/pydev-debs
apt download libpython3.12-dev python3.12-dev
mkdir -p ~/tools/pydev && for d in *.deb; do dpkg -x "$d" ~/tools/pydev; done

# 扁平化合并:通用 pyconfig.h 会 #include 架构版,直接用架构版顶上
mkdir -p ~/tools/pyinc/python3.12
ln -sf ~/tools/pydev/usr/include/python3.12/* ~/tools/pyinc/python3.12/
ln -sf ~/tools/pydev/usr/include/aarch64-linux-gnu/python3.12/pyconfig.h \
    ~/tools/pyinc/python3.12/pyconfig.h
```

## 6. 编译

```bash
source ~/.cargo/env
cd ~/code/vllm
TORCH_CUDA_ARCH_LIST=11.0 \
PATH=$HOME/venvs/vllm/bin:$PATH \
CMAKE_ARGS="-DPython_INCLUDE_DIR=$HOME/tools/pyinc/python3.12 -DPython_LIBRARY=/usr/lib/python3.12/config-3.12-aarch64-linux-gnu/libpython3.12.so" \
~/venvs/vllm/bin/pip install -e . --no-build-isolation
```

注意:
- **CMAKE_ARGS 多个 -D 用空格分隔**,不要用分号(shlex 会把分号串当成单个参数传给 cmake,报 "Unknown keywords" 玄学错误)
- 编译分两段:CMake FetchContent 经代理拉 cutlass 等源码(~2.7GB,慢),然后 nvcc -j14 编译(全程约 40-60 分钟)

## 7. 运行期必做的两处替换

### 7.1 Triton 的 ptxas 不认 sm_110a(启动即崩:PTXAS Internal error)

Triton 自带的 `ptxas-blackwell` 不支持 sm_110a,换成系统 CUDA 13.2 的:

```bash
T=~/venvs/vllm/lib/python3.12/site-packages/triton/backends/nvidia/bin
mv $T/ptxas-blackwell $T/ptxas-blackwell.orig
ln -s /usr/local/cuda/bin/ptxas $T/ptxas-blackwell
```

### 7.2 启动环境(缺一不可)

```bash
# torch.compile 要调 ninja 可执行文件 → venv/bin 必须在 PATH
# triton JIT 编译 cuda_utils.c 要 python 头文件 → CPATH 指向解包目录
export PATH="$HOME/venvs/vllm/bin:$PATH"
export CPATH="$HOME/tools/pyinc/python3.12:$HOME/tools/pydev/usr/include"
```

## 8. 启动参数(实测最优)

```bash
~/scripts/start-vllm.sh   # 封装了下面全部内容
```

要点:
- `--max-model-len 262144`(256k 上下文)
- `--gpu-memory-utilization 0.80` — **Jetson 上限就是 0.85**;0.92 会把系统逼到 404MB 可用,极易 OOM
- `--speculative-config '{"method":"mtp","num_speculative_tokens":3}'` — MTP 使解码 15→21.7 t/s;代价:KV 池 120万→108万 token
- `--reasoning-parser qwen3` — 分离思考段,否则 </think> 泄漏进正文
- `--enable-auto-tool-choice --tool-call-parser hermes` — Claude Code 必需(Qwen 系用 hermes 格式)
- `--served-model-name 名1 名2` — 多别名是**一个旗标后空格分隔**,逗号会被当成一个名字,重复旗标会后者覆盖前者

**重启纪律**:vLLM 的 EngineCore 子进程在 kill 后不会立刻释放 100GB 统一内存,
必须 kill APIServer → kill -9 EngineCore → `free -g` 确认 available>100G 再启新实例
(start-vllm.sh 已内置此检查)。

## 9. 为 Claude Code 打的两处源码补丁

Claude Code 会在 messages 数组内发 `role:"system"`(真 Anthropic API 容忍,vLLM 默认拒绝):

1. `vllm/entrypoints/anthropic/protocol.py` 的 Message.role:
   `Literal["user","assistant"]` → `Literal["user","assistant","system"]`
2. `vllm/entrypoints/anthropic/serving.py` 的 `_convert_anthropic_to_openai_request`:
   把内嵌 system 消息的文本**提升合并进开头的 system 消息**(Qwen 模板只接受
   system 在位置 0,否则报 "System message must be at the beginning")

可编辑安装的好处:改 .py 重启即生效,无需重编。

## 10. Claude Code 接入

```bash
export ANTHROPIC_BASE_URL=http://192.168.50.55:8302
export ANTHROPIC_AUTH_TOKEN=local          # server 未开鉴权,非空即可
export ANTHROPIC_MODEL=qwen3.8-27b-abliterated-nvfp4
export ANTHROPIC_SMALL_FAST_MODEL=qwen3.8-27b-abliterated-nvfp4
export ANTHROPIC_DEFAULT_SONNET_MODEL=qwen3.8-27b-abliterated-nvfp4
export ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen3.8-27b-abliterated-nvfp4
```

## 11. 坑总账(按出现顺序)

| # | 症状 | 根因 | 解法 |
|---|---|---|---|
| 1 | pip 报 No matching distribution | PyPI 经代理不通 | 清华镜像 |
| 2 | metadata 生成失败: No module named setuptools_rust | --no-build-isolation 需自备构建依赖 | pip 装齐 §3 清单 |
| 3 | rustup curl SSL_ERROR_SYSCALL | 代理掐 rust 官方源 | TUNA 镜像装 rustup-init |
| 4 | metadata 失败: No module named setuptools_scm | 同 #2 | pip 装 setuptools-scm |
| 5 | CMake: Unable to find python | 无 python3.12-dev 头文件 | §5 deb 解包 + 扁平化 |
| 6 | FindPackageHandleStandardArgs "Unknown keywords" | CMAKE_ARGS 用分号分隔 | 改空格分隔 |
| 7 | 启动崩: PTXAS sm_110a Internal error | Triton 捆绑 ptxas 不支持 sm_110a | §7.1 软链系统 ptxas |
| 8 | 启动崩: FileNotFoundError ninja | venv/bin 不在 PATH | §7.2 PATH |
| 9 | triton JIT 编译 cuda_utils.c 失败 | 缺 Python.h | §7.2 CPATH |
| 10 | 重启报 Free memory 10.77/122.86 GiB | EngineCore 僵尸占内存 | §8 重启纪律 |
| 11 | 空载内存只剩 404MB | util 0.92 过激 | 降到 0.80 |
| 12 | Claude Code 400: role should be user/assistant | anthropic 层校验严 | §9 补丁 1 |
| 13 | 500: System message must be at the beginning | Qwen 模板限制 | §9 补丁 2 |
| 14 | 400: auto tool choice requires flags | 工具调用未开 | §8 启动旗标 |
