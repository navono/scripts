---
name: ssh-passwordless-login
description: 配置本机到远程服务器的免密 SSH 登录（密钥生成、~/.ssh/config 别名、公钥上传、sshd 端检查、BatchMode 验证）。当用户要求配置 SSH 免密登录、设置 ssh key 登录远程主机、或 scp/rsync 远程机器时反复要密码时使用。Set up passwordless SSH (public key auth) from this machine to a remote server, including Windows Git Bash clients.
---

# 免密 SSH 登录远程服务器

目标：让 `ssh <别名>`（以及 scp/rsync/git 远端）不再输密码。全程幂等——每步先检查现状，已存在的密钥与配置**不得覆盖**，除非用户明确确认。

## 0. 需要向用户确认的信息

| 信息 | 必需性 | 说明 |
| --- | --- | --- |
| 目标主机地址 | 必需 | IP 或域名 |
| 登录用户名 | 必需 | |
| 端口 | 可选 | 默认 22 |
| config 别名 | 可选 | 缺省用 `user@host` |
| 登录密码 | 仅一次 | 第 4 步上传公钥时输一次，**agent 不经手**，用户在交互提示输入 |
| sudo/root 权限 | 条件需要 | 仅第 5 步服务器端排障可能用到 |
| 既有密钥对 | 可选 | 用户要求复用别处的 key 时才需要，且必须**私钥+公钥一起**装入本机 `~/.ssh`（权限 600）；单有公钥无法登录——登录验证靠本机私钥，公钥只是贴到服务器 `authorized_keys` 的名单。正常流程公钥由第 2 步生成，无需用户提供 |

## 1. 检查现状

```bash
# 已有哪些密钥（ed25519 优先, 老机器可能只有 rsa）
ls ~/.ssh/ 2>/dev/null
# 是否已能免密登录目标（BatchMode 禁止交互, 直接成功/失败）
ssh -o BatchMode=true -o ConnectTimeout=5 <user>@<host> 'echo ok'
# 已有的 config 别名
grep -A4 "^Host " ~/.ssh/config 2>/dev/null
```

已能 BatchMode 登录 → 免密已就绪，直接结束。已有密钥 → 复用，跳过第 2 步。

## 2. 生成密钥（无则做）

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

- `-N ""` 空口令，适合自动化场景；用户在意可自行设。
- **绝不用 `yes` 覆盖已存在的密钥文件**；目标主机很老（不支持 ed25519）时退回 `-t rsa -b 4096`。

## 3. 写入客户端别名（~/.ssh/config）

```
Host <别名>
    HostName <IP 或域名>
    Port 22
    User <登录名>
    IdentityFile ~/.ssh/id_ed25519
    ServerAliveInterval 30
```

- 追加前先确认无同名 Host 条目；Windows 下 config 就在 `C:\Users\<用户>\.ssh\config`。
- 私钥权限：Linux/macOS `chmod 600`；Windows 下文件在 `%USERPROFILE%\.ssh` 内即可（OpenSSH 会校验该目录 ACL）。

## 4. 上传公钥到服务器

Linux/macOS 客户端：

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub <user>@<host>
```

**Windows Git Bash 没有 ssh-copy-id**，用等价管道（注意权限设置一并做）：

```bash
cat ~/.ssh/id_ed25519.pub | ssh <user>@<host> \
  'mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

这一步会要一次密码——之后就不需要了。追加而非覆盖 `authorized_keys`。

**agent 执行注意**：agent 的 shell 通常没有 TTY，直接跑这条命令会因读不到密码而挂起或报 `can't open /dev/tty`。正确做法是把命令原样交给用户在交互终端执行（或征得同意后由用户粘贴执行），**绝不要求用户把密码交给 agent 代输**。若第 1 步发现已有其他免密通道（跳板机、云控制台注入密钥），优先走那条通道。

## 5. 服务器端（仅当第 4 步后仍不免密才动）

检查 `/etc/ssh/sshd_config`：`PubkeyAuthentication yes`、`AuthorizedKeysFile` 含 `.ssh/authorized_keys`，然后 `sudo systemctl restart sshd`（或 `ssh`，Debian 系服务名为 `ssh`）。改 sshd 与重启服务需要 root/sudo——用户无 sudo 权限时停在信息收集，把需改的行和命令报告给用户处理。

安全红线：

- **不要**为图省事加 `PermitRootLogin yes`；`PasswordAuthentication` 保持现状作为后备，等第 6 步验证通过、用户明确要求后再考虑关闭。
- `RSAAuthentication` 参数已废弃，不要写入。
- 远端 `~/.ssh` 权限必须是 700、`authorized_keys` 600，权限过松会被 sshd 拒绝。

## 6. 验证

```bash
ssh -o BatchMode=true -o ConnectTimeout=5 <别名> 'echo ok'
```

输出 `ok` 即免密生效；失败回看第 4/5 步。之后 `scp`/`rsync`/`ssh <别名>` 均不再要密码。
