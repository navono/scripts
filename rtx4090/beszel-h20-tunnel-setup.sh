#!/bin/bash
# WSL -> h20 的 SSH 隧道安装脚本 —— 在 rtx4090 工作站的 WSL2 内以 root 运行:
#   MSYS_NO_PATHCONV=1 wsl -d Ubuntu-24.04 -u root -- bash /mnt/d/sourcecode/scripts/rtx4090/beszel-h20-tunnel-setup.sh
# 背景: WSL -> h20:45876 的 SSH 流量被中途 DPI 掐断(TCP 可握手, 协议数据被 RST;
#   同路径 HTTP 正常), 但 workstation -> h20:12222 (系统 sshd) 一直可用。
#   故 hub 经由本隧道访问 h20 agent: hub -> 127.0.0.1:45876 ==> ssh -L ==> h20 的 127.0.0.1:45876。
# hub 侧对应 system 记录 host 必须填 127.0.0.1 (端口仍 45876)。
set -euo pipefail

if [ ! -f /home/ping24/.ssh/id_beszel ]; then
    runuser -u ping24 -- bash -c 'mkdir -p ~/.ssh && chmod 700 ~/.ssh && ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_beszel -q'
fi
PUB=$(cat /home/ping24/.ssh/id_beszel.pub)
echo "请将下面一行加入 h20 的 ~/.ssh/authorized_keys (受限: 仅允许转发到 45876, 无 shell):"
echo "restrict,port-forwarding,permitopen=\"127.0.0.1:45876\" $PUB"

tee /etc/systemd/system/beszel-h20-tunnel.service >/dev/null <<'EOF'
[Unit]
Description=Beszel SSH tunnel to h20 agent (DPI blocks direct :45876)
After=network-online.target
Wants=network-online.target

[Service]
User=ping24
ExecStart=/usr/bin/ssh -N -L 127.0.0.1:45876:127.0.0.1:45876 \
    -p 12222 -i /home/ping24/.ssh/id_beszel \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes pingqixing@10.30.28.173
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now beszel-h20-tunnel.service
sleep 3
echo "tunnel: $(systemctl is-active beszel-h20-tunnel.service)"
echo "验证: ss -tln | grep 45876 应看到 127.0.0.1:45876"
