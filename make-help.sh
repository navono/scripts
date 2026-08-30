#!/bin/bash
# make help 的输出文本
# 说明: 中文放在此脚本 (bash 按 UTF-8 读取), Makefile 保持 ASCII;
#       本机的 Gow make 3.81 按 ANSI/GBK 解析 Makefile, 中文 recipe 会乱码
cat <<'EOF'
thor 切换推理后端 (共用端口 8301, 一次一个):
  make start-vllm      切换到 vLLM (Qwen3.8-27B NVFP4 + MTP)
  make start-ds        切换到 dsv4flash (DeepSeek-V4-Flash Q2)
  make start-sglang    切换到 SGLang + DSpark (Qwen3.8-27B)
  make start-llama     切换到 llama.cpp (Qwen3.8-27B Q4_K_M)
  make start-flashnext 切换到 Qwen3.8-Flash-Next (llama.cpp qwen4exp)
  make stop-all        停止 thor 全部服务

rtx4090 本机服务 (共用双卡显存, 一次一个):
  make start-flash / stop-flash              Qwen3.8-Flash-Next-Uncensored (端口 8301)
  make start-coldfusion / stop-coldfusion    Qwen3.8-27B Cold-Fusion NEO-MTP (端口 12234)

 模型下载 (无参数时列出仓库内各档位):
  make download REPO=xxx [ONLY=前缀] [EXTRA=...]   包装 hf-download.sh
   例: make download REPO=AtomicChat/Qwen3.8-Flash-Next-GGUF
       make download REPO=AtomicChat/Qwen3.8-Flash-Next-GGUF ONLY=Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64
       make download REPO=... ONLY=... EXTRA=--dry-run   # 只预览不下

  make download-stop   停止当前下载任务
  make check   校验 (bash -n + git diff --check), 不启动服务
EOF
