#!/bin/bash
# make help 的输出文本
# 说明: 中文放在此脚本 (bash 按 UTF-8 读取), Makefile 保持 ASCII;
#       本机的 Gow make 3.81 按 ANSI/GBK 解析 Makefile, 中文 recipe 会乱码
cat <<'EOF'
用法: make <thor|4090> <动作>

thor 推理后端 (共用端口 8301, 一次一个):
  make thor start-vllm      切换到 vLLM (Qwen3.8-27B NVFP4 + MTP)
  make thor start-ds        切换到 dsv4flash (DeepSeek-V4-Flash Q2)
  make thor start-sglang    切换到 SGLang + DSpark (Qwen3.8-27B)
  make thor start-llama     切换到 llama.cpp (Qwen3.8-27B Q4_K_M)
  make thor start-flashnext 切换到 Qwen3.8-Flash-Next (llama.cpp qwen4exp)
  make thor stop-all        停止 thor 全部服务
  make thor status          查看当前后端/PID/统一内存 (其他机器自动经 ssh 转发)

rtx4090 本机服务 (共用双卡显存, 一次一个):
  make 4090 start-flash / stop-flash          Qwen3.8-Flash-Next-Uncensored (端口 8301)
  make 4090 start-coldfusion / stop-coldfusion  Qwen3.8-27B Cold-Fusion NEO-MTP (端口 12234)
  make 4090 status          两服务状态 + 双卡显存占用

兼容写法: 动作可省略设备前缀自动路由, 如 make start-flash / make stop-all

 模型下载 (无参数时列出仓库内各档位):
  make download REPO=xxx [ONLY=前缀] [EXTRA=...]   包装 hf-download.sh
   例: make download REPO=AtomicChat/Qwen3.8-Flash-Next-GGUF
       make download REPO=AtomicChat/Qwen3.8-Flash-Next-GGUF ONLY=Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64
       make download REPO=... ONLY=... EXTRA=--dry-run   # 只预览不下

  make download-stop   停止当前下载任务
  make check   校验 (bash -n + git diff --check), 不启动服务
  make deploy  提交后推送部署到 thor (git push thor main)
EOF
