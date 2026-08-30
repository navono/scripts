# LLM 推理部署脚本

按硬件组织的 LLM 推理服务部署与运维脚本集合：每台设备一个目录，共用模型下载器等工具，各引擎的安装实录与踩坑记录收在 `docs/`。

## 目录结构

```
thor/           thor 主机 (Jetson AGX Thor) 的推理服务启停脚本
  start-*.sh    各后端启动器 (nohup 后台拉起, 等待 /health 就绪)
  stop-*.sh     各后端停止脚本 (释放统一内存)
  stop-all.sh   依次调用全部 stop 脚本
  switch        后端切换器: 先停全部, 再启动目标后端 (目标已在跑则跳过)
rtx4090/        本机 (2× RTX 4090 Windows 工作站) 的推理服务脚本
docs/           各引擎安装实录与硬件对比笔记
skills/         可复用的 agent 技能 (SKILL.md 格式), 供各 agent 工具挂载
logs/           运行日志 (git 忽略)
hf-download.sh  HuggingFace 仓库批量下载器 (断点续传 + 重试 + 大小校验), 跨设备共用
Makefile        常用入口包装 (thor + rtx4090), make help 查看摘要
make-help.sh    make help 的中文输出文本 (本机 make 按 GBK 解析 Makefile, 中文需放 bash 脚本)
make-completion.bash  make 目标补全; clone 后跑一次 ./make-completion.bash install 写入 ~/.bashrc
```

新增设备时每台一个目录（如 `spark/`、`rtx/`、`mac/`），结构与 `thor/` 一致；模型下载等通用工具放仓库根目录复用。

## thor：推理后端

所有后端共用端口 **8301** 和统一内存，**一次只能跑一个**。用 `switch` 切换会自动先停掉其余服务。

| Make 目标 | 后端 | 模型 / 引擎 |
| --- | --- | --- |
| `make vllm` | vLLM v0.22.0 | Qwen3.8-27B NVFP4 + MTP 投机解码, Anthropic 协议 (Claude Code 可直连) |
| `make ds` | ds4 (antirez/ds4) | DeepSeek-V4-Flash Q2 (87GB) + DSpark 草稿 (6.97GB) |
| `make sglang` | SGLang 0.5.18 + DSpark | Qwen3.8-27B |
| `make llama` | llama.cpp (DFlash2 分支) | Qwen3.8-27B Q4_K_M + DFlash2 投机解码 |
| `make flashnext` | llama.cpp (qwen4exp 分支) | Qwen3.8-Flash-Next AD-4.27bpw (176B MoE, 激活 6B) + ngram-mod 投机解码, 支持图片输入 |

### 常用命令

```bash
make start-vllm      # 切换到 vLLM (等价: ./thor/switch vllm)
make start-sglang    # 切换到 SGLang
make start-llama     # 切换到 llama.cpp
make start-ds        # 切换到 dsv4flash
make start-flashnext # 切换到 Qwen3.8-Flash-Next

make stop-all        # 停止全部服务
make check           # 校验 (bash -n + git diff --check), 不启动服务
make help            # 查看全部目标
```

### 模型下载

```bash
# 无参数列出仓库内各量化档位, 不下载
make download REPO=AtomicChat/Qwen3.8-Flash-Next-GGUF

# 只下载指定前缀的档位 (最常用)
make download REPO=AtomicChat/Qwen3.8-Flash-Next-GGUF ONLY=Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64

# 只预览清单不下载; make download-stop 停止当前下载任务
make download REPO=... ONLY=... EXTRA=--dry-run
```

下载经代理 `http://192.168.50.50:18899` 出网，串行执行（勿多路并发）；已完整的文件自动跳过，支持断点续传。镜像备用：`HF_ENDPOINT=https://hf-mirror.com`。

### 排障与约定

- 启动失败先看日志：`tail -100 ~/scripts/logs/<service>-server.log`。
- 启动器有前置检查（引擎/模型/模板缺失会直接报路径退出）；模型权重、虚拟环境、引擎编译产物均在仓库外（`$HOME/models`、`$HOME/venvs`、`$HOME/code`）。
- 脚本注释与操作提示使用中文；脚本改动用 `make check` 验证，不要在共享主机上随手执行 stop/restart 来做验证。
- Flash-Next 首次请求有 IO 高峰属正常（95GB 分片 mmap 按需加载）；视觉输入必须保留 `--no-mmproj-offload`，见 `thor/start-flashnext.sh` 注释。

## rtx4090：本机（2× RTX 4090）

两套 llama.cpp 服务，命名与 `thor/` 一致（`start-*.sh` / `stop-*.sh` 成对），端口不同；同时只建议跑一个（共用双卡显存）。

**qwen38-flash** — Qwen3.8-Flash-Next-Uncensored IQ4_XS（125B 级 MoE + SSM 混合，约 97.5GB，3 分片），llama.cpp b10679 官方构建（CUDA 13.3），专家按层卸载到双卡、其余留 CPU mmap；端口 8301，支持图片输入。生成 ~22 t/s，显存占用与提速备选方案见脚本头部注释。

```bash
bash rtx4090/start-qwen38-flash.sh     # 启动并等待 /health 就绪
bash rtx4090/stop-qwen38-flash.sh
```

**qwen38-coldfusion** — DavidAU 修改版 Qwen3.8-27B-Cold-Fusion-GAIN NEO-MTP Q6_K，LM Studio 内置 llama.cpp 2.30.0（CUDA 12）；双卡张量并行（tensor-split 1,1）、128K 上下文、NEO-MTP 投机解码、API-Key 鉴权；Claude Code 模板并保留思考过程，Claude Code 可直连。

```bash
bash rtx4090/start-qwen38-coldfusion.sh    # 端口 12234, API-Key 见脚本内 API_KEY 变量
bash rtx4090/stop-qwen38-coldfusion.sh
```

以上也对应 make 目标：`make start-flash` / `make stop-flash`、`make start-coldfusion` / `make stop-coldfusion`。

## 连接与同步

本机（rtx4090 工作站）到 thor 的免密登录已配置：`ssh thor` 直连（`~/.ssh/config` 条目：192.168.50.55:22, user supcon）。免密配置的完整方法沉淀为 [skills/ssh-passwordless-login](skills/ssh-passwordless-login/SKILL.md)。仓库经 GitHub（`navono/scripts`）同步：本机 push 后 thor 端 `~/scripts` pull；模型权重等大文件走 scp/rsync，不入库。

## skills 目录（供 agent 工具使用）

`skills/<name>/SKILL.md` 采用通用 Agent Skills 格式（frontmatter 的 name/description + Markdown 正文），作为各 agent 工具技能的唯一事实源。工具侧挂载后即被自动发现，例如 Windows 下用目录联接：

```
mklink /J "%USERPROFILE%\.zcode\skills\<name>"  "D:\sourcecode\scripts\skills\<name>"   # ZCode
mklink /J "%USERPROFILE%\.claude\skills\<name>" "D:\sourcecode\scripts\skills\<name>"   # Claude Code
```

约定：技能内容保持通用（不写死本机绝对路径、不含密钥），可执行辅助脚本与 SKILL.md 同目录放置。

## 文档索引

- [硬件横向对比](docs/hardware-compare.md) — Thor / DGX Spark / RTX 4090 / 5090 / PRO 6000 / M5 系列
- [vLLM 安装实录](docs/vLLM-install.md) — Thor 源码构建 v0.22.0 + NVFP4 + MTP
- [SGLang 安装笔记](docs/SGLang-install.md) — Thor SM110 隔离环境 (venvs/sglang)
- [llama.cpp 安装实录](docs/llama-cpp-install.md) — Thor DFlash2 分支构建
- [ds4 安装实录](docs/ds-v4-flash-install.md) — Thor DeepSeek-V4-Flash + DSpark
- [TensorRT-Edge-LLM 评估](docs/tensorrt-edge-llm-eval.md) — Thor 硬件适用但暂不投入
