# 容器重启
决策级别: 绿灯
触发条件: new-api / redis / her-herweb-a8y5ka / herclub 容器挂了（health-check 报 "未运行" 或 curl 返回 502/000）

## 前置检查
- 确认是容器挂了，而非服务器整机不可达（先确认 SSH 能连）
- 确认要重启的容器名称（用 `sudo docker ps -a` 看状态，不要凭记忆）
- 确认不是正在部署（Dokploy 面板 dok.tokenic.cn 上是否有 in-progress 任务）

## 步骤

### her-gateway（new-api + redis）

**重要**：必须先 redis，再 new-api。顺序反了 new-api 起来会拿不到缓存。

1. SSH 连上服务器，重启 redis
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker restart redis'
   ```
   验证: 命令返回 `redis`，无报错

2. 等 5 秒，重启 new-api
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker restart new-api'
   ```
   验证: 命令返回 `new-api`，无报错

3. 检查容器状态
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker ps --format "{{.Names}} {{.Status}}"'
   ```
   验证: `redis` 和 `new-api` 均显示 `Up X seconds`

4. 检查 API 可达
   ```bash
   curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://api.tokenic.cn/api/status
   ```
   验证: 返回 `200`

### her-web（her-herweb-a8y5ka）

1. 强制更新 Swarm service（不换镜像，仅重启 task）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker service update --force her-herweb-a8y5ka'
   ```
   验证: 输出 `her-herweb-a8y5ka`，无 ERROR

2. 等待新 task 就绪（最多 60 秒）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker service ps her-herweb-a8y5ka --format "{{.Name}} {{.CurrentState}}"'
   ```
   验证: 最新一条显示 `Running X seconds ago`

3. 检查域名可达
   ```bash
   curl -s -o /dev/null -w "%{http_code}" --max-time 15 https://hersoul.cn
   ```
   验证: 返回 `200`

### herclub

1. 强制更新 Swarm service
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker service update --force herclub'
   ```
   验证: 输出 `herclub`，无 ERROR

2. 等待 task 就绪（herclub 偶尔有 30-60 秒 Preparing 期）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker service ps herclub --format "{{.Name}} {{.CurrentState}}"'
   ```
   验证: 最新一条显示 `Running X seconds ago`

3. 检查域名可达
   ```bash
   curl -s -o /dev/null -w "%{http_code}" --max-time 15 https://club.hersoul.cn
   ```
   验证: 返回 `200`

## 回滚
容器重启本身是幂等操作，无需回滚。如果重启前后行为不一致，说明问题不在容器运行状态，见升级条件。

## 升级条件
- 重启后等待 3 分钟，curl 仍返回非 200（502、000 等）→ 升级到黄灯，执行 `container-repeated-crash.md`
- `docker ps` 显示容器不断重启（Restarting (1) X seconds ago 类似输出）→ 同上
- 重启后 API 可达，但业务报错（登录失败、数据库错误等）→ 可能是 `db-connection-fail.md` 场景
