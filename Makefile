# thor: 推理服务脚本 Makefile
# 用法: make help
# 说明: 各后端共用端口 8301 与统一内存,一次只跑一个
SHELL := /bin/bash
DIR := llm
.PHONY: help vllm ds sglang llama stop download download-stop check

.DEFAULT_GOAL := help

help:
	@echo "切换推理后端 (共用端口 8301, 一次一个):"
	@echo "  make vllm    切换到 vLLM (Qwen3.8-27B NVFP4 + MTP)"
	@echo "  make ds      切换到 dsv4flash (DeepSeek-V4-Flash Q2)"
	@echo "  make sglang  切换到 SGLang + DSpark (Qwen3.8-27B)"
	@echo "  make llama   切换到 llama.cpp (Qwen3.8-27B Q4_K_M)"
	@echo ""
	@echo "  make stop    停止全部服务"
	@echo ""
	@echo " 模型下载 (无参数时列出仓库内各档位):"
	@echo "  make download REPO=xxx [ONLY=前缀] [EXTRA=...]   包装 hf-download.sh"
	@echo "   例: make download REPO=AtomicChat/Qwen3.8-Flash-Next-GGUF"
	@echo "       make download REPO=AtomicChat/Qwen3.8-Flash-Next-GGUF ONLY=Qwen3.8-Flash-Next-AD-4.27bpw-Q4_K_M-M64"
	@echo "       make download REPO=... ONLY=... EXTRA=--dry-run   # 只预览不下"
	@echo ""
	@echo "  make download-stop   停止当前下载任务"
	@echo "  make check   校验 (bash -n + git diff --check), 不启动服务"

vllm:
	@$(DIR)/switch vllm

ds:
	@$(DIR)/switch ds

sglang:
	@$(DIR)/switch sglang

llama:
	@$(DIR)/switch llama

stop:
	@$(DIR)/stop-all.sh

download:
	@./hf-download.sh $(REPO) $(if $(ONLY),--only $(ONLY),) $(EXTRA)

download-stop:
	@./hf-download.sh --stop

check:
	@bash -n $(DIR)/*.sh $(DIR)/switch hf-download.sh
	@git diff --check
	@echo "check OK"
