---
name: her-ops
description: |
  Her 产品运维（192.144.187.174）：her-gateway + her-web + herclub + salon 的基础设施运维、监控、排障。
  部署/发布/回滚/分支/CI 已迁移到 her-cicd skill。
  **触发场景**：SSL 证书、Dokploy、Traefik、容器重启、数据库、API 网关、hersoul.cn、club.hersoul.cn、api.tokenic.cn、salon、her-beta、客户端后端切换、`switch-her-backend.sh`、gateway 模型/API key/quota、邀请码无效、生产数据库、修改用户数据、psql、trial_ends_at、user_invite、herclub_member、用户有效期、订阅到期、EdgeOne、TEO、CDN、COS、全站加速、缓存规则。
---

# Her 产品运维

你是那个凌晨两点被证书过期告警叫醒过的人。你信日志不信记忆，信 changelog 不信口头描述。你不急着动手，但一旦动手，每一步可逆、可追溯。

**SSH 绝对路径**：`/usr/bin/ssh`（shell 有 wrapper 会报错）。

---

## 工作流（强制）

收到运维请求：① 读本 SKILL.md 定位 `ops/` 文件 → ② 读完再动手 → ③ 完成后更新 changelog。**不凭记忆直接动手。**

---

## 路径定义

```bash
SKILL_DIR=/Users/suyuan/.claude/skills/her-ops
OPS=$SKILL_DIR/ops          # 操作文件（一个任务读一个）
CTX=$SKILL_DIR/context      # 背景知识（正常不读）
```

---

## 仓库地图

本地代码根目录：`/Users/suyuan/Documents/her-source/`

| 仓库 | 本地路径 | 服务器容器 | 域名 |
|------|----------|-----------|------|
| her-gateway | `her-gateway` | `new-api` + `redis` (Dokploy compose) | `api.tokenic.cn` |
| her-web | `her-web` | **生产** `her-herweb-a8y5ka` (Swarm) / **测试** `her-web-test` (Swarm) | `hersoul.cn` / `test.hersoul.cn` |
| herclub | `herclub` | `herclub` (Swarm) | `club.hersoul.cn` |
| salon | `salon` | 本地 Tauri/Vite | - |
| 基础设施 | - | `dokploy-traefik` + `dokploy` | `dok.tokenic.cn` |

> **⚠️ her-web 生产 vs 测试 service 辨识**：`her-herweb-a8y5ka`（Dokploy 随机后缀）是**生产**，`her-web-test` 是**测试**。手动 `docker service update` 前**必须**先确认 service env 中的 `NEXT_PUBLIC_APP_URL`。误操作回滚：`sudo docker service update --rollback <service>`。

---

## 决策边界

**绿灯（自主处理）**：容器挂了按序重启 → `ops/container-restart.md`；磁盘 > 80% 清理 → `ops/disk-cleanup.md`；5xx 偶发等 5 分钟复查

**黄灯（处理完通知）**：SSL 14 天内到期 → `ops/ssl-ops.md`；DB 连接失败 → `ops/db-connection-fail.md`；容器反复挂 → `ops/container-repeated-crash.md`

**红灯（立刻通知）**：全部 API 连续 5 分钟不可用；三域名完全不可达；疑似安全问题

**黑灯（等人拍板）**：生产重启/切镜像/scale、改数据库、改 Traefik/Dokploy 配置、删除任何东西、编辑 `acme.json`。部署新代码走 **her-cicd** skill。

---

## 连接

```
SSH="/usr/bin/ssh ubuntu@192.144.187.174"   # sudo 执行 docker 命令
HERDB=$SKILL_DIR/scripts/her-db.sh          # DB wrapper（prod/gw/test/test-gw）
```

公钥免密（`~/.ssh/id_ed25519`）。三个服务共用同一台。

**数据库操作优先用 `her-db`**：`bash $HERDB prod "SQL"` / `bash $HERDB prod --schema user`。详见 `ops/production-db-ops.md`。

---

## 场景路由表

| 场景/症状 | 文档 | 脚本 |
|----------|------|------|
| 容器挂了/502/5xx | `ops/container-restart.md` | SSH 直接操作 |
| 磁盘满/build cache 过大 | `ops/disk-cleanup.md` | SSH 直接操作 |
| SSL 证书检查/续签 | `ops/ssl-ops.md` | openssl 命令 |
| 综合健康巡检 | `ops/health-patrol.md` | `scripts/gateway/health-check.sh` |
| Hermes 7x24 值守监控（飞书告警/日报、巡检任务管理） | `ops/hermes-monitor.md` | VPS `~/.hermes/scripts/her-patrol.sh` |
| DB 连接失败 | `ops/db-connection-fail.md` | SSH 诊断 |
| 容器反复挂 | `ops/container-repeated-crash.md` | SSH 诊断 |
| gateway 渠道/用户/quota | `ops/gateway-admin-api.md` | `scripts/gateway/gw-admin.sh` |
| 新建上游渠道 | `ops/channel-provisioning.md` | Python + curl |
| gateway request_id 对比上游日志/504 慢请求 | `ops/upstream-log-compare.md` | `scripts/gateway/compare-upstream-log.py` |
| salon 后端切换 | `ops/salon-backend-switching.md` | `salon/scripts/switch-her-backend.sh` |
| 查/改生产数据（用户、试用期、quota、订阅） | `ops/production-db-ops.md` | `scripts/her-db.sh` |
| 注册/重置密码收不到邮箱验证码 | `ops/email-verification.md` | `scripts/her-db.sh` + SSH 日志 |
| 创建 test 账号 + gateway binding | `ops/test-account-provisioning.md` | her-web 正常注册路径 + `scripts/her-db.sh` + her-cicd `verify-web-gateway` |
| 发邀请码（单人/批量） | `ops/invite-codes.md` | SSH 隧道 + npx |
| 注册成功但邀请码没绑定/兑现中途失败 | `ops/invite-redeem-repair.md` | `her-db` 事务补录 |
| **部署/发布/回滚/test 测试栈** | **→ her-cicd skill** | — |
| gateway 拓扑/端口/DSN/域名 SSL | `context/topology.md` | — |
| 智谱额度/错误码/并发 | `context/zhipu-coding-plan.md` | — |
| hersoul.ai 海外静态站 | `context/hersoul-ai-static-site.md` | — |
| EdgeOne CDN 全站加速 | `context/edgeone-cdn-runbook.md`（决策依据见 `context/edgeone-cdn-decisions.md`） | — |
| 海外加速（双 CDN：EdgeOne 国内 + Cloudflare 海外） | `ops/dual-cdn-overseas.md` | — |
| EdgeOne 接入/证书/缓存规则/COS（tccli 踩坑） | `ops/edgeone-cos.md` | tccli + 控制台 UI |
| K8s 集群访问 / kubectl / TKE 集群状态与日志 | `ops/k8s-cluster-access.md` | SSH 隧道 + kubectl |
| K8s DNS 切换 runbook / 切换后清单（roome label 清理等） | `ops/k8s-dns-switchover.md` | DNSPod + tccli teo |

---

## 已知坑速查

| # | 症状 | 详情 |
|---|------|------|
| 1 | salon dev 不要默认用 `her://` 回调 | `ops/salon-backend-switching.md` |
| 2 | 生产 DB 时间是 UTC，北京时间要 -8h 再存 | `ops/production-db-ops.md` |
| 3 | her-web 生产库 DSN 要从容器 env 获取 | `ops/production-db-ops.md` |
| 4 | 生产 env 文件没补新变量，线上功能静默失败 | 新功能上线前核查 `/home/ubuntu/.her-web-env-production` 是否补齐。2026-05-20 飞书 FEISHU_* 四变量漏配 |
| 5 | gateway `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN` 缺失导致 429 | gateway docker-compose.yml 必须包含此 env 变量（与 her-web swarm service 同值）；test/prod 都要保留。2026-05-21 内测首批 134 人同时注册触发 |
| 6 | 发邀请码必须连生产库，不能用本地库 | SSH 隧道 15432→172.17.255.75:5432，命令行显式传 `DATABASE_URL` 覆盖即可 |
| 7 | DeepSeek Anthropic `thinking.disabled` 与 `output_config.effort` 冲突 | 上游会报 `thinking options type cannot be disabled when reasoning_effort is set`。VIP MiMo -> DeepSeek channel 18 用 `param_override` 在 `thinking.type=disabled` 时删除 `output_config` / `reasoning_effort` |
| 8 | her_web config 表键列是 `name` 不是 `key` | `SELECT value FROM config WHERE name='xxx'`。gateway options 表键列才是 `key` |
| 9 | 不确定列名时先查 schema | `bash $HERDB <env> --schema <表>` 查运行时列名，不要猜。常猜错：user 无 role/status/plan、credit 用 transaction_type 非 type、herclub_member 用 her_user_id 非 user_id |
| 10 | **手动 service update 前必须确认是生产还是测试** | `her-herweb-a8y5ka`=**生产**（hersoul.cn），`her-web-test`=**测试**。名字相似极易混淆。确认方法：`sudo docker service inspect <name> --format '{{json .Spec.TaskTemplate.ContainerSpec.Env}}' \| grep APP_URL`。2026-05-28 误更新生产约 3 分钟后回滚 |
| 11 | test 账号不能只插 her-web SQL 后结束 | 必须走 her-web 正常注册/登录路径，再调用 gateway provisioning，并同时验 her-web test DB 的 `user_gateway` 与 gateway test DB 的 `users`/`tokens`。只造 web 用户会导致登录后无可用 API key/quota |
| 12 | better-auth 登录/注册 `Too many requests` 不是 gateway 限流 | Her 当前要求 test/prod 都设置 `AUTH_RATE_LIMIT_ENABLED=false`。test 批量建号前查 `her-web-test`；生产发布由 her-cicd `deploy.sh` 固化并在 postflight 检查。 |
| 13 | 注册成功但邀请码没绑定 | 绑定唯一入口是 `complete-pending-signup`→`redeemInviteCode`；管理员 manual provision 开会员**不兑现邀请码**，gateway/试用额度是注册默认惰性开通（与邀请码无关），故"能用、有额度"≠"已绑定"。补录见 `ops/invite-redeem-repair.md` |
| 14 | 客户端发版未走 COS，与 CDN 架构脱节 | 发版脚本 `her-salon/scripts/build-macos-local.sh` 仍 `rsync` 到服务器 `/opt/releases`，但 EdgeOne 已只读 COS 桶（源站组仅 `COS-releases`）。中间无自动同步，COS 靠 5/25 手动 coscmd 迁移+人工补，已不一致（本地 `latest/` 符号链接停 v0.0.6 vs latest.json v0.0.7）。**退役本地 /opt/releases 4.4G + 停 her-releases-static nginx 前，必须先改发版脚本 rsync→coscmd 直传 COS 并验证一次**。属 her-cicd 范畴。2026-06-02 磁盘清理时发现 |
| 15 | Resend 发件域未验证会导致验证码静默失败 | her-web 只把 `sendVerificationEmail failed` 写日志，前端不一定暴露 Resend 错误。2026-06-05 生产 `mail.hersoul.cn` 曾因 EdgeOne DNS 的 Resend MX 优先级为 0 且 DKIM TXT 漏 1 个字符而验证失败，详见 `ops/email-verification.md` |
| 16 | 海外探活 hersoul.cn 307 / club 301 不是故障 | 语言重定向（/zh）+ club 并入主站，海外视角探活必须 `curl -L` 看最终码。2026-06-12 Hermes 值守首跑误报。详见 `ops/hermes-monitor.md` |
| 17 | 网关出口 IP 已变：81.70.184.21 | 6/9 gateway 迁 K8s 后出口从 192.144.187.174 变为 81.70.184.21（CVM 出站同走此 IP，用户已确认）。凡按 IP 白名单放行 gateway 的外部服务需放行两个 IP；排查上游 403 先在 CVM 跑 `curl ifconfig.me` 确认当前出口。bwg-la relay 三反代已修（2026-06-12） |

---

## 关键入口

- **gateway Admin API**：`$SKILL_DIR/scripts/gateway/gw-admin.sh GET /api/channel/`（凭证 `~/.config/her/gateway-admin.env`）
- **gateway 上游日志对比**：`python3 $SKILL_DIR/scripts/gateway/compare-upstream-log.py <gateway_request_id>`（只读，new-api 兼容上游）
- **gateway 重启顺序**：Redis → new-api → Traefik（Traefik 最后动）
- **herclub 紧急下线**：`/usr/bin/ssh -n ubuntu@192.144.187.174 'sudo docker service scale herclub=0'`
- 部署/发布/回滚脚本已迁移到 **her-cicd** skill

---

## 操作完成后（强制）

当用户说"收尾""结束""弄好了"或操作自然完成时，逐条执行：

1. **changelog.md** 追加一条，格式见下方
2. **经验捕获**（3 个 yes/no）：
   - 踩了坑？→ 坑速查表已有则跳过；新坑则加一行 + 更新对应 ops/ 文件
   - 发现新连接方式/命令技巧/环境差异？→ 更新对应 ops/ 或 context/ 文件
   - 用了路由表中不存在的路径？→ 补一行到路由表
3. 没有新增事实时明说"her-ops 无需更新"

### Skill 内容增删改规则

**新增文件**：
- 操作手册（agent 按步骤执行的）→ `ops/`，一个操作一个文件，自包含
- 背景知识（跨操作共享、正常不读的）→ `context/`
- 新增后必须：① SKILL.md 路由表加一行 ② index.md 对应表格加一行

**修改文件**：
- 信息只写一处。如果 ops/ 文件已有的内容，changelog 不重复（写"详见 ops/xxx.md"）
- 修改 ops/ 文件内容后，确认 SKILL.md 路由表的场景描述是否还准确

**删除文件**：
- 用 `trash` 删除（可恢复）
- 删除后必须：① SKILL.md 路由表删对应行 ② index.md 删对应行 ③ grep 确认无其他文件引用它

**不该做的**：
- 不在 SKILL.md 或 index.md 里内嵌操作内容——操作步骤只写在 ops/ 文件里，SKILL.md 只放路由表，index.md 只放索引链接
- 不创建 `runbooks/` 或 `references/` 子目录（已废弃，统一用 ops/ + context/）

### Changelog 写入格式

每条 3 行封顶，只记事实不记过程：

```
### YYYY-MM-DD 一句话标题

> 改了什么 → 结果/影响。回滚：`一行命令`。
```

规则：
- 操作步骤、验证过程、SSH 命令 → 不写（ops/ 文件里有）
- 其他文件已记录的信息 → 不重复（写"详见 ops/xxx.md"）
- commit/PR 链接 → 只在有代码变更时写
- 一次性数据操作（延期、改 quota、加 SSH key）→ 同样 3 行格式
