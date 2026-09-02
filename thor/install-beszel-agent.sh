#!/bin/bash
# thor (Jetson AGX Thor) 的 Beszel agent 部署脚本 —— 非 root 方案
# 背景: thor 无免密 sudo, 官方安装脚本需要 root (创建用户/systemd 服务),
#   因此改用: 二进制 + nohup 当前进程 + crontab @reboot 自启, 全部在用户态完成。
# GPU 指标走 tegrastats 自动检测 (supcon 已在 video/render 组, 无需 root)。
# hub 端口公钥变更时: 重新执行本脚本并传入新公钥, 或直接改 ~/opt/beszel/run.sh。
# 用法: bash install-beszel-agent.sh ["ssh-ed25519 AAAA..."]
set -euo pipefail

KEY="${1:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG8wqaW2li04q/Za0d3IZjL3LiSK5jZ6t5NYTNqHtKPQ}"
VERSION="0.18.8"
DIR="$HOME/opt/beszel"
PROXY="http://192.168.50.50:18899"
ARCH="linux_arm64"

mkdir -p "$DIR"
cd "$DIR"

if [ ! -x beszel-agent ]; then
    # thor 仅能通过工作站代理访问外网
    # 注意: release 的 tar.gz 产物名不带版本号前缀 (deb 才带)
    export http_proxy="$PROXY" https_proxy="$PROXY" HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
    curl -fsSL -o agent.tgz "https://github.com/henrygd/beszel/releases/download/v${VERSION}/beszel-agent_${ARCH}.tar.gz"
    tar xzf agent.tgz beszel-agent
    rm -f agent.tgz
fi

# S.M.A.R.T.: agent 以普通用户直调 smartctl, 而读盘需要 root,
# 故放一个 sudo 包装到 ~/bin 并让 run.sh 优先命中它。
# 前置(需人工执行一次, 见 docs/beszel.md):
#   sudo apt install -y smartmontools
#   echo 'supcon ALL=(root) NOPASSWD: /usr/sbin/smartctl' | sudo tee /etc/sudoers.d/beszel-smart
if sudo -n /usr/sbin/smartctl --version >/dev/null 2>&1; then
    mkdir -p "$HOME/bin"
    printf '#!/bin/bash\n# beszel agent SMART 专用: 借助受控 sudo 调用真实 smartctl\nexec sudo -n /usr/sbin/smartctl "$@"\n' > "$HOME/bin/smartctl"
    chmod 755 "$HOME/bin/smartctl"
fi

cat > run.sh <<EOF
#!/bin/bash
# beszel agent 启动器 (由 install-beszel-agent.sh 生成)
export PATH="$HOME/bin:\$PATH"
exec "$DIR/beszel-agent" -key "$KEY"
EOF
chmod +x run.sh

# 幂等: 停掉旧进程再拉起
pkill -f "$DIR/beszel-agent" 2>/dev/null || true
sleep 1
nohup "$DIR/run.sh" >> "$DIR/agent.log" 2>&1 < /dev/null &
echo "agent pid: $!"

# crontab @reboot 自启 (幂等替换)
( crontab -l 2>/dev/null | grep -v 'opt/beszel/run.sh' || true
  echo "@reboot $DIR/run.sh >> $DIR/agent.log 2>&1"
) | crontab -
echo "--- crontab ---"
crontab -l | grep beszel

echo "--- 进程与端口 ---"
sleep 2
pgrep -af beszel-agent || echo "WARN: agent 未在运行, 查看 $DIR/agent.log"
ss -tln 2>/dev/null | grep 45876 || echo "WARN: 45876 未监听"
