# LLM inference service scripts Makefile (thor + rtx4090)
# Usage: make help  (Chinese help text lives in make-help.sh, keep this file ASCII:
#                    Gow make 3.81 parses the Makefile as ANSI/GBK and mangles UTF-8)
# Syntax: make <thor|4090> <action> - all dynamic goals dispatch via make/make-dispatch.sh;
#         a bare single action (make start-flash) is auto-routed to its device
# Hint: quote script paths in recipes - this make direct-spawns argument-free
#       simple commands without a shell, which fails silently for `bash <file>`
SHELL := /bin/bash
# completion: thor=start-vllm,start-ds,start-sglang,start-llama,start-flashnext,stop-all,status 4090=start-flash,stop-flash,start-coldfusion,stop-coldfusion,status
.PHONY: help thor 4090 download download-stop check

.DEFAULT_GOAL := help

help:
	@bash "make/make-help.sh"

thor 4090:
	@bash "make/make-dispatch.sh" $@ $(wordlist 2,99,$(MAKECMDGOALS))

# fallback: single unknown goal (bare action or typo) also dispatches;
# no-op when goals >= 2 because the device rule above already dispatched
%:
	@if [ "$(words $(MAKECMDGOALS))" -eq 1 ]; then bash "make/make-dispatch.sh" $(MAKECMDGOALS); fi

download:
	@./hf-download.sh $(REPO) $(if $(ONLY),--only $(ONLY),) $(EXTRA)

download-stop:
	@./hf-download.sh --stop

check:
	@bash -n thor/*.sh thor/switch rtx4090/*.sh hf-download.sh make/*.sh
	@git diff --check
	@echo "check OK"
