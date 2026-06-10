# 综合健康巡检
决策级别: 绿灯
触发条件: 定期主动巡检（如每天一次），或接到用户"检查一下服务状态"的请求

## 前置检查
- 确认本机网络正常（能访问外网）
- health-check.sh 路径: `/Users/suyuan/.claude/skills/her-ops/scripts/gateway/health-check.sh`

## 步骤

1. 运行 gateway 全链路健康检查脚本
   ```bash
   bash /Users/suyuan/.claude/skills/her-ops/scripts/gateway/health-check.sh
   ```
   验证: 脚本输出 `=== 全部通过 ===`；如有 `✗` 项，记录具体失败内容

2. 检查 her-web 服务状态（脚本不含，额外补充）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker service ps her-herweb-a8y5ka --format "{{.Name}} {{.CurrentState}}" | head -3'
   ```
   验证: 最新 task 显示 `Running X hours/minutes ago`

3. 检查 herclub 服务状态
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker service ps herclub --format "{{.Name}} {{.CurrentState}}" | head -3'
   ```
   验证: 最新 task 显示 `Running X hours/minutes ago`

4. 检查 hersoul.cn 可达性
   ```bash
   curl -s -o /dev/null -w "%{http_code}" --max-time 15 https://hersoul.cn
   ```
   验证: 返回 `200`

5. 检查 club.hersoul.cn 可达性
   ```bash
   curl -s -o /dev/null -w "%{http_code}" --max-time 15 https://club.hersoul.cn
   ```
   验证: 返回 `200`

6. 检查 SSL 证书到期天数（三个域名）

   api.tokenic.cn:
   ```bash
   echo | openssl s_client -connect api.tokenic.cn:443 -servername api.tokenic.cn 2>/dev/null \
     | openssl x509 -noout -enddate \
     | python3 -c "import sys,datetime; line=sys.stdin.read().strip(); exp=datetime.datetime.strptime(line.replace('notAfter=',''),'%b %d %H:%M:%S %Y %Z'); days=(exp-datetime.datetime.utcnow()).days; print(f'api.tokenic.cn 到期: {exp.date()}，剩余 {days} 天')"
   ```

   hersoul.cn:
   ```bash
   echo | openssl s_client -connect hersoul.cn:443 -servername hersoul.cn 2>/dev/null \
     | openssl x509 -noout -enddate \
     | python3 -c "import sys,datetime; line=sys.stdin.read().strip(); exp=datetime.datetime.strptime(line.replace('notAfter=',''),'%b %d %H:%M:%S %Y %Z'); days=(exp-datetime.datetime.utcnow()).days; print(f'hersoul.cn 到期: {exp.date()}，剩余 {days} 天')"
   ```

   club.hersoul.cn:
   ```bash
   echo | openssl s_client -connect club.hersoul.cn:443 -servername club.hersoul.cn 2>/dev/null \
     | openssl x509 -noout -enddate \
     | python3 -c "import sys,datetime; line=sys.stdin.read().strip(); exp=datetime.datetime.strptime(line.replace('notAfter=',''),'%b %d %H:%M:%S %Y %Z'); days=(exp-datetime.datetime.utcnow()).days; print(f'club.hersoul.cn 到期: {exp.date()}，剩余 {days} 天')"
   ```

   验证: 三个域名剩余天数均 >= 14 天

7. 检查磁盘使用率
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'df -h /'
   ```
   验证: `Use%` < 80%

## 汇总结果格式

巡检完成后，按以下格式汇报：

```
=== 健康巡检汇总 [日期时间] ===
容器状态:
  new-api      ✓/✗ [状态]
  redis        ✓/✗ [状态]
  her-web      ✓/✗ [状态]
  herclub      ✓/✗ [状态]

域名可达:
  api.tokenic.cn   ✓/✗ [HTTP状态码]
  hersoul.cn       ✓/✗ [HTTP状态码]
  club.hersoul.cn  ✓/✗ [HTTP状态码]

SSL 证书:
  api.tokenic.cn   ✓/⚠ 剩余 X 天
  hersoul.cn       ✓/⚠ 剩余 X 天
  club.hersoul.cn  ✓/⚠ 剩余 X 天

磁盘: ✓/⚠/✗ Use%=XX%

结论: 全部正常 / 发现 N 项异常，见下方
```

## 回滚
只读检查，无操作，无需回滚。

## 升级条件
- 任意容器不在运行状态 → 执行 `container-restart.md`
- 任意域名返回非 200 → 执行 `container-restart.md`
- 任意 SSL 证书剩余 < 14 天，或颁发者变成自签名 → 执行 `ssl-ops.md` Part 2
- 磁盘 Use% >= 80% → 执行 `disk-cleanup.md`
- health-check.sh 显示 `=== X 项异常 ===` → 根据具体异常项目对应执行相关 runbook
