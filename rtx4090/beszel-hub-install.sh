#!/bin/bash
# Beszel hub 安装脚本 —— 在 rtx4090 工作站的 WSL2 (Ubuntu-24.04) 内以 root 运行:
#   MSYS_NO_PATHCONV=1 wsl -d Ubuntu-24.04 -u root -- bash /mnt/d/sourcecode/scripts/rtx4090/beszel-hub-install.sh
# 产物: /usr/local/bin/beszel + systemd 服务 beszel.service (0.0.0.0:8090)
# 注意: release 的 tar.gz 产物名不带版本号前缀 (与 deb 命名不同)。
# 若 WSL 内直连 GitHub 下载失败(曾经出现过 "Not Found"), 在 Windows 侧下载后拷入:
#   curl -sL -o %TEMP%\beszel-hub.tgz https://github.com/henrygd/beszel/releases/download/v<VER>/beszel_linux_amd64.tar.gz
#   wsl -u root -- install -m755 $(wslpath %TEMP%\beszel-hub.tgz 解包后) /usr/local/bin/beszel
set -euo pipefail

VERSION="0.18.8"
URL="https://github.com/henrygd/beszel/releases/download/v${VERSION}/beszel_linux_amd64.tar.gz"

cd /tmp
curl -fsSL -o beszel-hub.tgz "$URL"
rm -rf beszel-pkg && mkdir beszel-pkg
tar xzf beszel-hub.tgz -C beszel-pkg
install -m 755 beszel-pkg/beszel /usr/local/bin/beszel
mkdir -p /var/lib/beszel && chown ping24:ping24 /var/lib/beszel

# 数据目录为 CWD 下的 beszel_data (Beszel 默认), 私钥 id_ed25519 也在其中
tee /etc/systemd/system/beszel.service >/dev/null <<'EOF'
[Unit]
Description=Beszel monitoring hub
After=network.target

[Service]
User=ping24
WorkingDirectory=/var/lib/beszel
Environment=APP_URL=http://localhost:8090
ExecStart=/usr/local/bin/beszel serve --http 0.0.0.0:8090
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now beszel
sleep 2
echo "service: $(systemctl is-active beszel)"
echo "http: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:8090/)"
echo "完成。后续初始化(管理员/agent 公钥/隧道)见 docs/beszel.md"
