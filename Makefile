# LLM inference service scripts Makefile (thor + rtx4090)
# Usage: make help  (Chinese help text lives in make-help.sh, keep this file ASCII:
#                    Gow make 3.81 parses the Makefile as ANSI/GBK and mangles UTF-8)
# Notes: thor backends share port 8301 and unified memory, one at a time;
#        rtx4090 services share the 2-GPU VRAM, one at a time
# Naming: service targets are start-xx / stop-xx so `make start-<TAB>` completes them all
# Hint: quote script paths in recipes - this make direct-spawns argument-free
#       simple commands without a shell, which fails silently for `bash <file>`
SHELL := /bin/bash
DIR := thor
RTX := rtx4090
.PHONY: help start-vllm start-ds start-sglang start-llama start-flashnext stop-all start-flash stop-flash start-coldfusion stop-coldfusion download download-stop check

.DEFAULT_GOAL := help

help:
	@bash "make-help.sh"

start-vllm:
	@$(DIR)/switch vllm

start-ds:
	@$(DIR)/switch ds

start-sglang:
	@$(DIR)/switch sglang

start-llama:
	@$(DIR)/switch llama

start-flashnext:
	@$(DIR)/switch flashnext

stop-all:
	@$(DIR)/stop-all.sh

start-flash:
	@bash "$(RTX)/start-qwen38-flash.sh"

stop-flash:
	@bash "$(RTX)/stop-qwen38-flash.sh"

start-coldfusion:
	@bash "$(RTX)/start-qwen38-coldfusion.sh"

stop-coldfusion:
	@bash "$(RTX)/stop-qwen38-coldfusion.sh"

download:
	@./hf-download.sh $(REPO) $(if $(ONLY),--only $(ONLY),) $(EXTRA)

download-stop:
	@./hf-download.sh --stop

check:
	@bash -n $(DIR)/*.sh $(DIR)/switch $(RTX)/*.sh hf-download.sh make-help.sh make-completion.bash
	@git diff --check
	@echo "check OK"
