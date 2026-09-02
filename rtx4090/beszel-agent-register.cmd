@echo off
rem Register beszel autostart entries in HKCU Run (no admin required).
rem - BeszelHub  : boots the WSL2 distro at logon; systemd then starts
rem                 beszel.service + beszel-h20-tunnel.service (both enabled).
rem - BeszelAgent: starts the local Windows agent (WebSocket mode) hidden.
rem Re-run anytime; idempotent (reg add /f overwrites).
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v BeszelHub /t REG_SZ /d "wsl.exe -d Ubuntu-24.04 --exec true" /f
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v BeszelAgent /t REG_SZ /d "powershell.exe -NoProfile -WindowStyle Hidden -Command \"Start-Process -FilePath 'E:\data\tools\beszel\beszel-agent-run.cmd' -WindowStyle Hidden\"" /f
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v BeszelHub
reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v BeszelAgent
