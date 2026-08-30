# LLM inference service scripts Makefile (thor + rtx4090)
# Usage: make help  (Chinese help text lives in make-help.sh, keep this file ASCII:
#                    Gow make 3.81 parses the Makefile as ANSI/GBK and mangles UTF-8)
# Notes: thor backends share port 8301 and unified memory, one at a time;
#        rtx4090 services share the 2-GPU VRAM, one at a time
# Hint: quote script paths in recipes - this make direct-spawns argument-free
#       simple commands without a shell, which fails silently for `bash <file>`
SHELL := /bin/bash
DIR := thor
RTX := rtx4090
.PHONY: help vllm ds sglang llama flashnext stop flash flash-stop coldfusion coldfusion-stop download download-stop check

.DEFAULT_GOAL := help

help:
	@bash "make-help.sh"

vllm:
	@$(DIR)/switch vllm

ds:
	@$(DIR)/switch ds

sglang:
	@$(DIR)/switch sglang

llama:
	@$(DIR)/switch llama

flashnext:
	@$(DIR)/switch flashnext

stop:
	@$(DIR)/stop-all.sh

flash:
	@bash "$(RTX)/start-qwen38-flash.sh"

flash-stop:
	@bash "$(RTX)/stop-qwen38-flash.sh"

coldfusion:
	@bash "$(RTX)/start-qwen38-coldfusion.sh"

coldfusion-stop:
	@bash "$(RTX)/stop-qwen38-coldfusion.sh"

download:
	@./hf-download.sh $(REPO) $(if $(ONLY),--only $(ONLY),) $(EXTRA)

download-stop:
	@./hf-download.sh --stop

check:
	@bash -n $(DIR)/*.sh $(DIR)/switch $(RTX)/*.sh hf-download.sh make-help.sh
	@git diff --check
	@echo "check OK"
