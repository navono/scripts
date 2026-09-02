# rtx4090 (Windows 工作站) 的 Beszel agent 安装脚本
# 需管理员权限 (NSSM 服务注册 + 防火墙放行 45876):
#   powershell -ExecutionPolicy Bypass -File beszel-agent-install.ps1
# hub 部署在 WSL2 Ubuntu-24.04 内 (http://localhost:8090, 见 docs/beszel.md)
param(
    # hub 全局公钥 (/var/lib/beszel/hub-agent.pub), agent 用它校验 hub 身份
    [string]$Key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG8wqaW2li04q/Za0d3IZjL3LiSK5jZ6t5NYTNqHtKPQ",
    [int]$Port = 45876
)

$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "需要管理员权限运行 (NSSM 服务 + 防火墙规则)"
}

$installer = "$env:TEMP\beszel-install-agent.ps1"
Write-Host "== 下载官方安装脚本 =="
Invoke-WebRequest -UseBasicParsing https://get.beszel.dev -OutFile $installer

Write-Host "== 安装 agent (WinGet + NSSM 服务, 自动配置防火墙) =="
& powershell -ExecutionPolicy Bypass -File $installer -Key $Key -Port $Port -ConfigureFirewall

Write-Host "== 服务状态 =="
Get-Service beszel-agent | Format-Table Name, Status, StartType
Write-Host "日志目录: C:\ProgramData\beszel-agent\logs"
