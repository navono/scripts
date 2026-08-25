# Repository Guidelines

## Project Structure & Module Organization

This repository contains operational Bash scripts for inference services on the `thor` host. Top-level `start-*.sh` scripts launch vLLM, llama.cpp, or DS4; matching `stop-*.sh` scripts terminate them and release unified memory. `stop-all.sh` invokes all three stop scripts. Service-specific installation and troubleshooting notes live under `docs/`. Runtime output belongs in `logs/`, which is ignored by Git. Model weights, virtual environments, and compiled binaries remain outside this repository under paths such as `$HOME/models`, `$HOME/venvs`, and `$HOME/code`.

## Build, Test, and Development Commands

There is no build system or automated test suite. Validate every script edit before running a service:

```bash
bash -n *.sh
git diff --check
```

Run one service at a time because the launchers currently share port `8301` and may consume most unified memory:

```bash
./start-vllm.sh
./start-llamacpp.sh
./start-ds4.sh
./stop-all.sh
```

Inspect startup failures with `tail -100 logs/vllm-server.log` (substitute the relevant service log). Do not execute stop or restart scripts as part of routine validation on a shared host.

## Coding Style & Naming Conventions

Use Bash with a `#!/bin/bash` shebang and fail-fast behavior (`set -e`; prefer `set -euo pipefail` for new standalone scripts when unset variables are handled). Indent continued commands and control-flow bodies with four spaces. Quote variable expansions, use uppercase names for configuration constants (`MODEL`, `PORT`, `LOG`), and derive companion-script paths from `BASH_SOURCE`. Name entry points `start-<service>.sh` and `stop-<service>.sh`. Keep comments concise; Chinese is established for operator-facing messages and documentation.

## Testing Guidelines

At minimum, run `bash -n` and `git diff --check`. For launcher changes, verify required files exist, the configured port is intentional, `/health` or `/version` readiness checks still match the backend, and shutdown logic targets only the intended process. Record manual TPS or compatibility findings in the corresponding file under `docs/`.

## Commit & Pull Request Guidelines

History uses short Conventional Commit-style subjects such as `fix:`, `docs:`, and `refactor:`. Keep each commit focused and use an imperative summary. Pull requests should describe the affected backend, list validation performed, call out model/port/memory changes, and include relevant log excerpts without secrets. Link an issue when one exists.

## Security & Agent Instructions

Never commit tokens, `.env` files, model weights, or runtime logs. Preserve host-specific paths deliberately. Make subsequent repository changes directly on the `main` branch unless the user explicitly requests a separate branch or worktree.
