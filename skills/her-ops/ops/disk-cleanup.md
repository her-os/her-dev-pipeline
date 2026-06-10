# 磁盘清理
决策级别: 绿灯
触发条件: health-check 报磁盘使用 >= 80%，或 `df -h /` 显示 Use% >= 80

## 前置检查
- 确认是根分区（`/`）使用率高，而非其他挂载点误报
- 确认没有正在进行的 docker build（`sudo docker ps` 里有 build 相关容器）；有的话等 build 完再清理

## 步骤

1. 查当前磁盘用量，记录基线
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'df -h /'
   ```
   验证: 记下 `Use%` 数值，后续步骤后与之对比

2. 清理 Docker build cache（通常最大，优先清）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker builder prune -f'
   ```
   验证: 输出显示释放的空间，例如 `Total reclaimed space: 1.2GB`

3. 清理旧系统日志（保留最近 3 天）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo journalctl --vacuum-time=3d'
   ```
   验证: 输出 `Vacuuming done, freed XXX` 或显示已删除的文件数

4. 清理未使用的 Docker 镜像（不含正在运行容器使用的镜像）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker image prune -f'
   ```
   验证: 输出释放空间，或 `Total reclaimed space: 0B`（无可清理时正常）

5. 重新检查磁盘用量
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'df -h /'
   ```
   验证: `Use%` 低于 80%

## 禁止清理的内容
- 运行中容器挂载的 volume（`sudo docker volume ls` 列出的，不要 `volume prune`）
- `/etc/dokploy/traefik/dynamic/acme.json`（SSL 证书存储，丢了要重新申请）
- `/home/ubuntu/her-web-release/`（her-web 发布记录和 dump）
- 任何 `sudo docker rmi` 手动删镜像（先确认不是当前服务在用的镜像）

## 回滚
磁盘清理是单向操作，不可回滚。清理前已确认的禁止清理内容不会被上述步骤触及。

## 升级条件
- 执行完所有步骤后磁盘仍 >= 80% → 手动调查大文件来源：
  ```bash
  /usr/bin/ssh ubuntu@192.144.187.174 'sudo du -sh /var/lib/docker/* 2>/dev/null | sort -rh | head -10'
  ```
  结果告知负责人，升级到黄灯
- 清理过程中发现 acme.json 异常或 volume 数据异常 → 立即停止，通知负责人
