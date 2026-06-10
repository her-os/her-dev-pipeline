# 容器反复崩溃
决策级别: 黄灯
触发条件: 已执行 container-restart.md 后，容器仍然无法稳定运行（重启后 3 分钟内再次挂掉，或 `docker ps` 显示 `Restarting (N) X seconds ago`）

## 前置检查
- 确认已经执行过 `container-restart.md` 的步骤（不是初次发现容器挂）
- 确认是哪个容器反复崩溃（new-api / redis / her-herweb-a8y5ka / herclub）
- **不要自主修复**：本 runbook 只做诊断和信息收集，不改配置、不改代码、不切镜像

## 步骤

### 第一阶段：确认崩溃状态

1. 查看容器当前状态
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker ps -a --format "{{.Names}} {{.Status}}" | grep -E "new-api|redis|herweb|herclub"'
   ```
   验证: 记录状态。`Restarting (N)` 表示正在反复重启；`Exited (N)` 表示已停止

2. 查看容器重启次数
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker inspect new-api --format "RestartCount: {{.RestartCount}}"'
   ```
   （将 `new-api` 替换为实际容器名）
   验证: 记录重启次数

### 第二阶段：收集崩溃日志

3. 查看最近 50 行日志（含崩溃前的错误信息）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker logs --tail 50 new-api 2>&1'
   ```
   （将 `new-api` 替换为实际容器名）
   验证: 记录最后的错误信息，特别注意 panic、fatal、OOM、permission denied 等关键词

4. 查看容器退出码和完整状态
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker inspect new-api --format "ExitCode: {{.State.ExitCode}} | Error: {{.State.Error}} | OOMKilled: {{.State.OOMKilled}}"'
   ```
   验证:
   - `ExitCode: 137` + `OOMKilled: true` → 内存不足被系统杀死，见第三阶段
   - `ExitCode: 1` → 应用启动失败，看日志中的具体错误
   - `ExitCode: 0` → 应用正常退出（异常行为，检查是否有误触发关闭信号）

5. 检查 OOM（Out of Memory，内存溢出）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo dmesg | tail -30 | grep -i "oom\|killed\|memory"'
   ```
   验证: 有无 `Out of memory: Kill process` 或 `oom_killer` 相关信息

### 第三阶段：检查资源和配置

6. 检查磁盘是否满（满盘会导致容器无法写日志或临时文件，进而崩溃）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'df -h /'
   ```
   验证: `Use%` 是否 >= 95%。如果是，先执行 `disk-cleanup.md` 再观察

7. 检查内存使用
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'free -h && sudo docker stats --no-stream --format "{{.Name}} CPU:{{.CPUPerc}} MEM:{{.MemUsage}}"'
   ```
   验证: 记录各容器内存占用情况

8. 查看容器 inspect 完整信息（特别是 Mounts 和 Env）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker inspect new-api 2>&1 | python3 -c "import json,sys; d=json.load(sys.stdin)[0]; print(\"Image:\",d[\"Config\"][\"Image\"]); print(\"Mounts:\",len(d[\"Mounts\"])); [print(\" \",m[\"Source\"],\"->\",m[\"Destination\"]) for m in d[\"Mounts\"]]"'
   ```
   验证: 确认镜像名称、挂载路径是否有异常

### 第四阶段：如果是 Swarm service（her-web / herclub）

9. 查看 service 事件历史
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker service ps her-herweb-a8y5ka --no-trunc 2>&1 | head -10'
   ```
   （将 `her-herweb-a8y5ka` 替换为 `herclub` 如适用）
   验证: 查看历史 task 的状态和 Error 列

10. 查看 service 日志
    ```bash
    /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker service logs her-herweb-a8y5ka --tail 50 2>&1'
    ```
    验证: 记录错误信息

## 回滚
本 runbook 不执行任何配置变更，无需回滚。

## 通知负责人

诊断完成后，必须通知负责人，包含以下信息：

1. 容器名称和崩溃开始时间
2. 重启次数
3. 退出码和 OOMKilled 状态
4. 关键日志片段（最后的 panic/fatal/error）
5. dmesg OOM 信息（如有）
6. 磁盘和内存状态
7. 初步判断：OOM / 磁盘满 / 应用 panic / 配置错误 / 未知

当前通知渠道：在会话中告知，写入 changelog.md。

## 升级条件
- OOMKilled: true，且增加内存或调整容器 memory limit 需要改 compose 配置 → 黑灯，需负责人拍板
- 日志显示镜像版本异常（运行的不是预期镜像）→ 通知负责人，不自主切镜像
- 日志显示配置错误（env 缺失、文件路径不存在）→ 通知负责人，不自主修改配置
- 所有三个域名同时不可达超过 5 分钟 → 升级为红灯，立即通知负责人
