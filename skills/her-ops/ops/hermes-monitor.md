# Hermes 7x24 值守监控

决策级别: 绿灯（监控本身只读）；它发出的告警按 SKILL.md 决策边界分级处理

## 架构

- **监控端**: 圣何塞 VPS `root@75.127.3.187`（RackNerd，与生产完全隔离），Hermes Agent v0.16.0，systemd 服务 `hermes-gateway`，模型 gpt-5.5 via ChatGPT OAuth（openai-codex provider）
- **被监控端**: 生产机 192.144.187.174，仅暴露一个 forced-command 只读入口
- **投递**: 飞书 DM `feishu:oc_7d3b7324bc36a2ed74e07ddb82713984`（夙愿；白名单 `ou_cc6e0d79a5d7ccea1f752d18377509e6`）；Telegram 通道并存

## cron 任务（VPS 上 `hermes cron list`）

| 任务 | 调度 | 模式 | 行为 |
|------|------|------|------|
| her-patrol | every 15m | no-agent（零 token） | 健康→静默；异常→飞书告警（同内容 1h 去重）；恢复→报平安一次 |
| her-gateway-errwatch | every 5m | no-agent（零 token） | 查 gateway 最近 5 分钟错误日志，过滤噪音（client_gone/eof/计费 INFO/2xx 行），有真实错误→飞书（同组错误 1h 去重），无→静默 |
| her-daily-report | `0 1 * * *` UTC = 北京 09:00 | agent | 读巡检日志写中文日报发飞书 |

## 检查范围

- **VPS 外部视角**: HTTP 探活 hersoul.cn / club.hersoul.cn / api.tokenic.cn/api/status（`curl -L` 跟随重定向看最终码）；SSL 三域名剩余 <14 天告警
- **生产内部（受限 SSH 白名单菜单）**: 容器 new-api/redis/dokploy-traefik、swarm 服务 her-herweb-a8y5ka/herclub/her-web-test 副本数、磁盘 80%/90% 双阈值、可用内存 <300MB、docker 磁盘占用
- **gateway 渠道**: 每轮巡检检查渠道状态。自动禁用（✗，系统因故障踢下线）触发告警；手动禁用（⊘，运维主动下线）不告警
- **AI 诊断能力**: Hermes 装有 her-ops skill，在飞书对话中可用 AI 分析：查容器日志（`logs <容器> [行数]`）、业务聚合指标（`db-stats`）、gateway 渠道列表（`gateway-channels`）、错误日志摘要（`gateway-errors [分钟]`）、用户 quota（`gateway-quota <uid>`）。同时可直接调用 gateway Admin API 查询/操作

## 安全围栏（第一阶段：只读，不自动修复）

- 专用 key `/root/.ssh/her-monitor_ed25519`（VPS）；生产机 `~ubuntu/.ssh/authorized_keys` 末行 `command="/usr/local/bin/her-health-internal.sh",restrict` —— 该 key 只能触发只读检查脚本，已实测请求 `echo HACKED` 仍只返回巡检输出（authorized_keys 备份: `.bak-20260612`）
- 生产机脚本 `/usr/local/bin/her-health-internal.sh`，root:root 755，纯只读
- Hermes cron_mode 默认 deny（拒绝危险命令）；Honcho 云端记忆未启用，记忆均在 VPS 本地
- 飞书 `FEISHU_GROUP_POLICY=allowlist`，仅夙愿一人可用

## 文件位置（改巡检项改哪里）

| 要改什么 | 文件 |
|----------|------|
| 外部探活域名 / SSL 阈值 / 去重时长 | VPS `~/.hermes/scripts/her-patrol.sh` |
| 生产内部检查项（容器/服务/磁盘/内存阈值） | 生产机 `/usr/local/bin/her-health-internal.sh` |
| 巡检历史日志（日报数据源） | VPS `/root/.hermes/logs/her-patrol.log` |
| 飞书/TG 凭据与白名单 | VPS `~/.hermes/.env`（备份 `.env.bak-20260612`） |

## 常用命令（VPS 上）

```bash
hermes cron list / run <name> / pause <name> / resume <name>
systemctl status hermes-gateway
tail -f ~/.hermes/logs/gateway.log
hermes auth list                     # 查 ChatGPT 登录状态
hermes update --yes --backup         # 升级（自动 drain + 重启 gateway）
```

## 已知坑

- 海外探活 hersoul.cn 返回 307（→/zh）、club.hersoul.cn 301（并入主站路径）——不是故障，是语言/合站重定向，探活必须 `-L` 跟随看最终码（2026-06-12 首跑误报）
- grep gateway 日志抓 5xx 必须加词边界 `\b(429|500|502|503|504)\b`——request_id 是长数字串，裸数字匹配会误中（如 `2035048` 含 504）。`stream ended: reason=eof`、`client_gone`、`record consume log` 都是正常业务行，要过滤
- gateway 进程是 cron 调度单点：systemd 自动重启兜底，但 gateway 挂掉这件事它自己发现不了（后续可加外部对 VPS 的探活）
- ChatGPT OAuth 凭据会过期（上次 5/31 失效）：掉登录后日报任务失败但 her-patrol 不受影响（no-agent 不走模型）。重登：`hermes auth add openai-codex --type oauth --no-browser`，把设备码 URL 转给用户

## 下线/回滚

- 暂停: `hermes cron pause her-patrol && hermes cron pause her-daily-report`
- 彻底移除生产侧入口: 删 `~ubuntu/.ssh/authorized_keys` 中 `hermes-her-monitor` 行 + `trash /usr/local/bin/her-health-internal.sh`
