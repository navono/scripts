# Beszel 多机负载监控部署实录

> 目标: 一台工作站 + 两台服务器的 GPU/CPU/内存/磁盘统一 Web 面板,
> 替代逐台 `ssh` + `nvtop/btop` 的手工巡检。
>
> 成果: h20 / thor / rtx4090 三台全部上线, GPU 指标 (利用率/显存/温度/功耗)、
> 进程级 CPU/内存、磁盘容量、每容器统计 (h20) 均可查看。
> 打开 <http://localhost:8090> (工作站浏览器) 即用。

## 架构

hub 部署在 **rtx4090 工作站的 WSL2 (Ubuntu-24.04)** 内。原因: 三台机器中只有
工作站与另外两台都互通 (h20 在 10.30.28.0/24, thor 在 192.168.50.0/24,
两者互不可达); 且 thor 的外网出口本就依赖工作站 (192.168.50.50:18899 代理)。

```
rtx4090 (WSL2, hub :8090)
 ├── thor   : hub ──SSH 直连──> 192.168.50.55:45876 (agent 二进制, tegrastats 采 GPU)
 ├── h20    : hub ──> 127.0.0.1:45876 ═SSH隧道(-L, 走 12222)═> h20 本地 45876 (agent 容器, NVML 采 GPU)
 └── 本机   : agent (Windows 原生 exe) ──WebSocket(HUB_URL+TOKEN)──> localhost:8090
```

三条路径各不相同, 全部是被迫的, 原因如下:

| 路径 | 为什么这么做 |
|---|---|
| thor 直连 | 工作站与 thor 同网段, hub 主动 SSH 轮询 (60s) 即可 |
| h20 走隧道 | WSL→h20:45876 的 SSH 协议数据被中途设备 RST (TCP 可握手, HTTP 却正常, 本机 45876 完全正常); 但 →h20:12222 的系统 sshd 一直可用, 故 `ssh -L` 借道 |
| 本机走 WebSocket | WSL→Windows 宿主 45876 被 Hyper-V 防火墙拒绝 (入站规则需管理员); 反向 WebSocket 走 localhost:8090 (WSL localhost 转发) 免防火墙免管理员 |

## 凭据与关键路径 (全部在 WSL2 内)

- 管理员账号: `/var/lib/beszel/superuser-credentials.txt` (仅 root/ping24 可读, 勿入仓库)
- hub 全局 agent 公钥: `/var/lib/beszel/hub-agent.pub` (源: `/var/lib/beszel/beszel_data/id_ed25519`, 有记录时首次轮询自动生成); **轮换公钥需同步改三台 agent 的 KEY**
- 本机 agent 的 universal token: 值 `beszel-767fff0b-...` 已写入 `rtx4090/beszel-agent-run.cmd` (hub 记录见 universal_tokens 集合)
- 普通用户 `navono@beszel.local` (密码未留存, 不常用; UI 用 superuser 登录即可)

## 部署文件对照

| 仓库文件 | 部署位置 | 说明 |
|---|---|---|
| `rtx4090/beszel-hub-install.sh` | WSL2 (root 执行) | hub 二进制 + beszel.service |
| `rtx4090/beszel-h20-tunnel-setup.sh` | WSL2 (root 执行) | 隧道密钥 + beszel-h20-tunnel.service |
| `rtx4090/beszel-agent-run.cmd` | `E:\data\tools\beszel\` (副本) | 本机 agent 启动 (WebSocket 模式, 用户态) |
| `rtx4090/beszel-agent-register.cmd` | 工作站执行一次 | HKCU Run 开机自启 (WSL 引导 + agent) |
| `rtx4090/beszel-agent-install.ps1` | 备用 (需管理员) | NSSM 服务化 + 防火墙规则, 日后想服务化再用 |
| `thor/install-beszel-agent.sh` | thor 执行 | 非 root 安装 (thor 无免密 sudo): 二进制 + nohup + crontab @reboot |
| `h20/docker-compose.beszel-agent.yml` | h20 `/data/scripts/` | agent 容器 (nvidia 镜像 + docker.sock + host 网络) |

h20 侧还需在其 `~/.ssh/authorized_keys` 保留隧道受限公钥行
(`restrict,port-forwarding,permitopen="127.0.0.1:45876" ...id_beszel`, 见
`beszel-h20-tunnel-setup.sh` 输出), 只能转发到 45876, 无 shell 权限。

hub 内三台 system 记录: h20 的 host 为 **127.0.0.1** (走隧道), 其余为各自 IP。

## 日常运维

```bash
# 在工作站 Git Bash:
wsl -d Ubuntu-24.04 -u root -- systemctl status beszel beszel-h20-tunnel   # hub/隧道
wsl -d Ubuntu-24.04 -u root -- journalctl -u beszel -n 30                  # hub 日志
tasklist //FI "IMAGENAME eq beszel-agent.exe"                              # 本机 agent
ssh thor 'tail ~/opt/beszel/agent.log; crontab -l | grep beszel'           # thor agent
ssh h20 'docker logs --tail 20 beszel-agent'                               # h20 agent

# 重启顺序: WSL 重启会同时拉起 hub 与隧道 (systemd); 本机 agent 由 HKCU Run 只在登录时
# 启动, 手动重启: 先 taskkill //IM beszel-agent.exe //F, 再双击 E:\data\tools\beszel\beszel-agent-run.cmd
```

- 数据落盘在 WSL `/var/lib/beszel/beszel_data/`, 备份该目录即备份全部历史。
- 升级 hub: 改 `beszel-hub-install.sh` 的 VERSION 重跑 (数据保留); agent 升级同理,
  thor 需先 `rm ~/opt/beszel/beszel-agent` 再跑安装脚本。

## 新增机器

1. 可被工作站直连 45876 的 Linux 机器: 参考 `thor/install-beszel-agent.sh` (root 机器可改用官方
   `curl -sL https://get.beszel.dev | sudo bash -k "<hub-agent.pub>"`), 再在 hub UI 添加 system。
2. 网络受限机器: 优先 WebSocket 模式 (agent 设 `HUB_URL` + `TOKEN`, 需能访问 hub:8090);
   若只有系统 sshd 可达, 参考 h20 的隧道方案。

## S.M.A.R.T. 磁盘健康

- **thor**: agent 以普通用户直调 smartctl, 读盘需 root。已在 `~/bin/smartctl` 放 sudo 包装
  (仅授权 `/usr/sbin/smartctl`, 见 `/etc/sudoers.d/beszel-smart`), `run.sh` 的 PATH 优先命中它。
  前置是人工执行过一次: `sudo apt install -y smartmontools` + sudoers 条目 (见
  `thor/install-beszel-agent.sh` 头部注释)。已验证: WD PC SN5000S 数据完整入库。
- **h20**: 容器为 root 且镜像自带 smartctl 7.5。compose 仅透传 `/dev/megaraid_sas_ioctl_node`
  并加 `cap_add: SYS_ADMIN` (megaraid ioctl 的 open() 要求该能力)——**不要**挂 /dev/sda、/dev/sdb,
  否则会额外上报两块 RAID 逻辑卷(虚拟盘无 SMART, 面板显示 UNKNOWN/N/A 噪音)。
  已验证: 4x INSPUR NS8500G2U 7.68TB + 2x Samsung MZ7L3960HCJR 960GB 全部 PASSED。
  限制: MegaRAID 对 NVMe 盘只透传健康/温度/容量, **通电时长(Power On)读不到显示 0**
  (三星 SATA 盘可读到); 这是控制器 SAT 透传的限制, smartctl 无法绕过。
  ⚠️ 主机重启后 `/dev/megaraid_sas_ioctl_node` 会消失, compose 引用缺失设备会启动失败;
  持久化方案: 在 h20 上 `sudo apt install -y smartmontools` (smartd 每次启动自动重建节点),
  或临时把该行从 compose `devices:` 中注释掉。
- **rtx4090**: Windows agent 自带 smartctl.exe, 三块盘开箱即用, 无需配置。

## 已知限制

- **Windows 无每进程 GPU 归属**: WDDM 驱动不向 nvidia-smi 报告每进程显存,
  4090 上"GPU 被谁占"只能看总占用/任务管理器 (h20 上 agent 可见容器级归属)。
- **hub 依赖工作站开机**: 工作站关机则面板与 thor/h20 的采集同时中断 (网络现状决定的,
  非新引入依赖); 开机登录后 HKCU Run 自动恢复。
- thor 的 agent 为用户态 nohup + cron 自启 (无免密 sudo 装不了 systemd 服务),
  thor 重启后由 crontab `@reboot` 拉起; GPU/温度数据来自 tegrastats (统一内存机器
  显存即内存, hub 中 GPU 显存=系统内存占用)。
- 轮询间隔 60s, 状态刷新非实时; 面板中 system 的 "down" 判定在重启 hub 后最多滞后一个周期。

## 故障排查速查

| 症状 | 检查 |
|---|---|
| 某台 down | 先 `journalctl -u beszel` 看握手报错; 对应 agent 日志有无 "SSH connected" |
| h20 down | WSL 内 `systemctl status beszel-h20-tunnel` (隧道断则 127.0.0.1:45876 不通); h20 上 `docker ps` 看 beszel-agent |
| thor GPU 无数据 | `ssh thor tegrastats` 能否出数据 (需 video/render 组); agent 日志有无采集报错 |
| 本机 agent 不上报 | `HUB_URL/TOKEN` 是否仍有效 (hub 重建过 universal_tokens 会失效); tasklist 看进程 |
| 改了 hub 公钥 | 三台 agent 的 KEY 全要更新 (thor 的 run.sh、h20 compose 的 KEY、本机 run.cmd) |
