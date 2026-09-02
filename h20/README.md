# h20 部署脚本 (快照副本)

拷贝自 h20 主机 `/data/scripts`(datashare 组共享目录, 多人维护, 本身是**无 remote 的本地 git 仓库)。
h20 部署方式与 thor 不同: 模型服务全部走 docker compose, 本目录只存 compose 文件, 不包一层启动脚本。

- 真源在 h20 端, 这里的副本用于版本管理与参考; 需要同步时用
  `scp h20:/data/scripts/docker-compose*.yml h20/` 覆盖更新
- 各文件内含 /data 下主机路径, 属刻意保留
- 主机信息: ubuntu, Linux 5.15, 8 x NVIDIA H20-3e
