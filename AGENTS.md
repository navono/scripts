# Repository Guidelines

## Project Structure & Module Organization

This repository contains operational Bash scripts for LLM inference deployments, organized one top-level directory per host. The `thor/` directory holds the scripts for the Jetson AGX Thor host (`thor`): `start-*.sh` launchers for vLLM, SGLang, llama.cpp, DS4, and Flash-Next; matching `stop-*.sh` scripts terminate them and release unified memory; `stop-all.sh` invokes every service stop script; `switch` restarts the stack for a chosen backend (stopping all first, skipping when the target backend is already running). New hosts get their own directory with the same layout (for example `spark/`, `rtx/`, `mac/`). The `rtx4090/` directory holds scripts for the local Windows workstation with 2× RTX 4090, using the same `start-<service>.sh` / `stop-<service>.sh` naming as `thor/`; its stop scripts resolve the listening PID via `netstat` + `taskkill` (engine binaries stay under `/e/data/tools`, outside the repository). On Windows hosts, Git Bash is the default shell environment: invoke all scripts with `bash <script>` and run the Makefile from Git Bash. The locally installed Gow `make` 3.81 parses the Makefile as ANSI/GBK and direct-spawns simple recipes without a shell, so keep the Makefile ASCII, put Chinese output text in bash scripts (see `make-help.sh`), and quote script paths in recipes. The root `Makefile` wraps the common `thor/` entry points (`make help` for a summary); shared tooling such as `hf-download.sh` stays at the repository root. The `skills/` directory holds reusable agent skills in SKILL.md format (`skills/<name>/SKILL.md`); keep them generic — no machine-specific absolute paths and no secrets — and mount them into agent tools via directory junctions (see README). Service-specific installation and troubleshooting notes live under `docs/`. Runtime output belongs in `logs/`, which is ignored by Git. Model weights, virtual environments, and compiled binaries remain outside this repository under paths such as `$HOME/models`, `$HOME/venvs`, and `$HOME/code`.

## Build, Test, and Development Commands

There is no build system or automated test suite. Validate every script edit before running a service:

```bash
make check   # bash -n thor/*.sh thor/switch rtx4090/*.sh hf-download.sh + git diff --check, does not start services
```

Run one service at a time because the launchers currently share port `8301` and may consume most unified memory:

```bash
make vllm     # thor/switch vllm
make ds       # thor/switch ds (dsv4flash)
make sglang   # thor/switch sglang
make llama    # thor/switch llama
make flashnext  # thor/switch flashnext
make stop     # thor/stop-all.sh
```

The `thor/` scripts can be called directly as well (`./thor/switch vllm`, `./thor/stop-all.sh`). Inspect startup failures with `tail -100 logs/<service>-server.log` (substitute the relevant service log). Do not execute stop or restart scripts as part of routine validation on a shared host.

## Coding Style & Naming Conventions

Use Bash with a `#!/bin/bash` shebang and fail-fast behavior (`set -e`; prefer `set -euo pipefail` for new standalone scripts when unset variables are handled). Indent continued commands and control-flow bodies with four spaces. Quote variable expansions, use uppercase names for configuration constants (`MODEL`, `PORT`, `LOG`), and derive companion-script paths from `BASH_SOURCE`. Name entry points `start-<service>.sh`, `stop-<service>.sh`, and the backend switcher `switch`. Makefile targets are lowercase after the `thor/switch` backends (`vllm`, `ds`, `sglang`, `llama`, `flashnext`), the rtx4090 services (`flash`, `flash-stop`, `coldfusion`, `coldfusion-stop`), plus `stop`, `download`, and `check`; recipe lines use tabs. Keep comments concise; Chinese is established for operator-facing messages and documentation.

## Testing Guidelines

At minimum, run `make check` (`bash -n` + `git diff --check`). For launcher changes, verify required files exist, the configured port is intentional, `/health` or `/version` readiness checks still match the backend, and shutdown logic targets only the intended process. Record manual TPS or compatibility findings in the corresponding file under `docs/`.

## Commit & Pull Request Guidelines

History uses short Conventional Commit-style subjects such as `fix:`, `docs:`, and `refactor:`. Keep each commit focused and use an imperative summary. Pull requests should describe the affected backend, list validation performed, call out model/port/memory changes, and include relevant log excerpts without secrets. Link an issue when one exists.

## Security & Agent Instructions

Never commit tokens, `.env` files, model weights, or runtime logs. Preserve host-specific paths deliberately. Make subsequent repository changes directly on the `main` branch unless the user explicitly requests a separate branch or worktree.

## Network Access

The `thor` host can reach external networks and download dependencies only through `http://192.168.50.50:18899`. Set both lowercase and uppercase proxy variables for networked commands, for example: `http_proxy=http://192.168.50.50:18899`, `https_proxy=http://192.168.50.50:18899`, `HTTP_PROXY=http://192.168.50.50:18899`, and `HTTPS_PROXY=http://192.168.50.50:18899`. Pass the same proxy to Docker builds and containers when they need network access. Keep `localhost`, `127.0.0.1`, and local subnets in `NO_PROXY`/`no_proxy` so service health checks remain direct.
