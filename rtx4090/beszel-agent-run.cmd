@echo off
rem beszel agent (rtx4090 Windows workstation) - user mode, no admin required.
rem WebSocket mode: agent connects OUT to the hub via localhost (WSL localhost
rem forwarding bypasses the Hyper-V firewall that blocks inbound 45876 from WSL).
rem Binary lives in E:\data\tools\beszel (outside the repo, per AGENTS.md).
rem To fetch/update the binary:
rem   cd /d E:\data\tools\beszel
rem   curl -sL -o agent.zip https://github.com/henrygd/beszel/releases/download/v0.18.8/beszel-agent_windows_amd64.zip
rem   tar -xf agent.zip && del agent.zip
rem Registered for autostart via HKCU Run (see rtx4090/beszel-agent-register.cmd).
rem For a full service install (NSSM + firewall rule) run beszel-agent-install.ps1 as admin instead.
set HUB_URL=http://localhost:8090
set TOKEN=beszel-767fff0b-a2c4-4cc2-a11c-27ead580fac4
set KEY=ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG8wqaW2li04q/Za0d3IZjL3LiSK5jZ6t5NYTNqHtKPQ
"E:\data\tools\beszel\beszel-agent.exe"
