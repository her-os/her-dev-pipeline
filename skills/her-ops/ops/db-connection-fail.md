# 数据库连接失败
决策级别: 黄灯
触发条件: new-api 日志出现数据库连接错误（`connection refused`、`dial tcp`、`too many connections`），或 API 返回数据库相关 5xx 错误

## 前置检查
- 确认是数据库问题，而非应用自身问题
  - 纯应用问题：new-api 起来、日志无数据库报错，但业务逻辑出错
  - 数据库连接问题：new-api 日志显示连接失败，或容器反复重启
- 先看 new-api 日志，确认错误类型后再动手
- **绝对不要直接操作数据库**（改数据、改表结构、强制关闭连接等），这是黑灯操作

## 数据库信息

| 项目 | 值 |
|------|-----|
| 类型 | PostgreSQL |
| 地址 | 172.17.255.75:5432（服务器内网地址） |
| 数据库名 | newapi |
| 用户名 | her |
| 备注 | 外部独立数据库，不在本服务器上 |

## 步骤

### 第一阶段：确认症状

1. 查看 new-api 最新日志
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker logs new-api --tail 50 2>&1 | grep -i "error\|fail\|connect\|sql\|postgres"'
   ```
   验证: 记录具体报错信息，是 `connection refused`、`too many connections` 还是 `authentication failed`

2. 查看容器当前状态
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker ps --format "{{.Names}} {{.Status}}" | grep new-api'
   ```
   验证: 记录状态，是 `Up` 还是 `Restarting`

### 第二阶段：诊断连通性

3. 检查数据库端口是否可达（从服务器内部测试）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'nc -zv 172.17.255.75 5432 2>&1'
   ```
   验证:
   - 成功: `Connection to 172.17.255.75 5432 port [tcp/postgresql] succeeded!`
   - 失败: `Connection refused` 或 `No route to host` → 说明数据库服务器本身不可达，这不是本服务器能修的问题

4. 如果 nc 成功但 new-api 仍然报错，检查从容器内部的网络连通性
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker exec new-api wget -qO- http://172.17.255.75:5432 2>&1 | head -5'
   ```
   验证: 看到任何响应（哪怕是 `Connection refused`）说明容器网络到数据库路由正常；如果完全超时说明容器网络有问题

5. 检查当前连接数（如果 nc 成功，推断连接数可能打满）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker logs new-api --tail 100 2>&1 | grep -i "too many\|connection pool\|max_connections"'
   ```
   验证: 如果日志有 `too many connections`，说明连接池打满

### 第三阶段：收集信息

6. 收集完整诊断日志（用于通知负责人）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker logs new-api --tail 100 2>&1'
   ```

7. 检查内核日志是否有 OOM 或网络相关异常
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo dmesg | tail -20'
   ```
   验证: 有无 `OOM killer` 或网络相关报错

## 可以自主尝试的最小干预

如果诊断显示是 new-api 自身的连接池问题（而非数据库服务器宕机），可以尝试重启 new-api 释放连接：

```bash
/usr/bin/ssh ubuntu@192.144.187.174 'sudo docker restart redis && sleep 5 && sudo docker restart new-api'
```

等待 30 秒后验证：
```bash
curl -s -o /dev/null -w "%{http_code}" --max-time 10 https://api.tokenic.cn/api/status
```

如果重启后 API 恢复 200，记录到 changelog 后通知负责人（黄灯：处理完通知）。

## 回滚
new-api 重启是幂等操作，无特殊回滚步骤。

## 通知负责人

无论是否自主尝试重启，必须通知负责人，包含以下信息：

1. 发现时间
2. 症状描述（日志中的报错）
3. nc 测试结果（端口可达/不可达）
4. 自主尝试步骤和结果（如有）
5. 当前 new-api 状态

当前通知渠道：在会话中告知，写入 changelog.md。

## 升级条件
- `nc -zv 172.17.255.75 5432` 失败（数据库服务器不可达）→ 超出本服务器处理范围，立即通知负责人，升级为红灯
- 重启 new-api 后 API 仍不恢复，且日志持续显示数据库连接错误 → 同上
- 日志显示 `authentication failed`（认证失败）→ 不要动，通知负责人（可能是密码或 DSN 配置问题）
