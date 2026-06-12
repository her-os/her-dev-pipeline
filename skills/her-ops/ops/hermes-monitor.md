# Hermes 7x24 值守监控

决策级别: 绿灯（监控本身只读）；它发出的告警按 SKILL.md 决策边界分级处理

## 架构

- **监控端**: 圣何塞 VPS `root@75.127.3.187`（RackNerd，与生产完全隔离），Hermes Agent v0.16.0，systemd 服务 `hermes-gateway`，模型 gpt-5.5 via ChatGPT OAuth（openai-codex provider）
- **被监控端**: 生产机 192.144.187.174，仅暴露一个 forced-command 只读入口
- **投递**: 飞书 DM `feishu:oc_7d3b7324bc36a2ed74e07ddb82713984`（夙愿；白名单 `ou_cc6e0d79a5d7ccea1f752d18377509e6`）；Telegram 通道并存

## cron 任务（VPS 上 `hermes cron list`）

| 任务 | 调度 | 模式 | 行为 |
|------|------|------|------|
| her-patrol | every 15m | no-agent（零 token） | 健康→静默；异常→**人话模板告警**（业务名+影响+建议，1h 去重）；恢复→报平安。含渠道主动测试（逐个真实调上游 test 接口，~1min/轮） |
| her-gateway-errwatch | every 5m | no-agent + 按需 AI | 查 gateway 最近 5 分钟错误日志。回声过滤（channel test/zhipu monitor 等自家监控产生的日志）→ GIN 4xx 聚合（≥100/5min 才报）→ 真错误交 `hermes -z -t todo`（禁工具防注入）翻译成人话发飞书。无错完全静默，AI 只在有真错误时调用 |
| her-daily-report | `0 1 * * *` UTC = 北京 09:00 | agent | 读巡检日志写中文日报发飞书 |
| her-cloud-watch | `30 0 * * *` UTC = 北京 08:30 | no-agent（零 token） | 云资源/资金日检：腾讯云余额（<3000 元告警）、CVM/云 PG 到期（<10 天提醒）、SSL 托管证书（<14 天）、搬瓦工流量（KiwiVM API，≥80%）、丽萨流量（vnstat 受限通道，≥2400G/3000G）。有问题才发，无事静默（结果写 `her-cloud-watch.log` 供日报引用） |

**腾讯云接入**：VPS `/root/tccli-venv/bin/tccli`，只读子账号 `her-ops`（UIN 100049758963，6 个策略：CVM/PG/Monitor/SSL/账单只读 + 自定义 `hermes-balance-readonly` 余额只读）。凭据 `/root/.tccli/default.credential`。patrol 内置云 PG 指标检查（磁盘≥80 红、连接≥80 黄、CPU≥90 黄）和 CVM 按需诊断（仅探活失败时调 API 区分机器停了/服务挂了，平时零调用）。
**丽萨受限通道**：VPS key `~/.ssh/lisa-traffic_ed25519` → lisa-sea（104.247.120.130:3944）forced command `/usr/local/bin/traffic-report.sh`，只返回 vnstat 月流量。
**搬瓦工**：KiwiVM API 凭据放 `/root/.hermes/secrets/bwg-kiwivm.env`（`BWG_VEID`/`BWG_APIKEY`），文件存在时 cloud-watch 自动启用。

## 共享账本（Hermes ↔ Claude 变更同步，坚果云双向）

her-ops 的 changelog.md 即共享账本，单一真相源。布局：
- 真实文件：Mac `~/Documents/夙愿's库/her-ops-sync/changelog.md`（坚果云同步对内）
- Mac 软链接：`her-dev-pipeline/skills/her-ops/changelog.md` → 真实文件
- VPS 软链接：`/root/.hermes/skills/her-ops/changelog.md` → `/root/Nutstore Files/夙愿's库/her-ops-sync/changelog.md`

实测双向各约 10 秒同步；VPS 坚果云客户端能捕获经软链接的写入。软链接方向铁律：**真实文件在同步目录内、链接在外**——反过来（同步目录里放链接）VPS 改动回传时会把链接撞成普通文件。Hermes 的记账义务写在 VPS `~/.hermes/SOUL.md`（每条消息注入，比 skill 加载可靠）。同时写的冲突落在坚果云冲突文件夹，手工合并。

**告警设计原则（最高约束）**：消息单位是「事件+影响+是否需要行动」，不是日志行。日志原文永不进消息正文（存档在 VPS `~/.hermes/logs/her-gateway-errwatch-raw.log` 和 `her-patrol.log`，对话追查用）。同根因只报一次：渠道好坏由 patrol 主动测试权威判定，errwatch 必须过滤渠道测试产生的回声日志。

**架构边界**：gateway 业务操作（渠道列表/测试/quota）直连 Admin API（`https://api.tokenic.cn/api/`，token 在 VPS 脚本与 skill 内）；SSH 受限通道只取必须登机器的信息（容器状态/容器日志/磁盘/DB 聚合指标），菜单仅 status/logs/db-stats/gateway-errors 四个子命令。

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
