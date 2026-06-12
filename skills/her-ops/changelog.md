# Changelog

> 2026-05-15 之前的条目见 `changelog-archive/2026-05-early.md`（5/01-5/14）和 `changelog-archive/2026-04.md`（4 月及更早）

---

### 2026-06-12 relay 三反代 403：网关出口 IP 变更，白名单补新 IP

> 网关 CVM 出口 IP 自 6/9 16:34（北京）起从 192.144.187.174 变为 81.70.184.21（疑与 6/8 K8s 迁移期 VPC 网络变更有关），bwg-la 三反代（relay/relay-pl/relay-cr）IP 白名单将 gateway 流量全部 403，渠道 6/12/13 不可用三天。三个 nginx 配置追加 `allow 81.70.184.21;`（旧 IP 保留），渠道 6/12 Admin API 实测通过。回滚：`/usr/bin/ssh bwg-la 'cd /etc/nginx/sites-available && for f in relay relay-pipellm relay-codingrouter; do cp $f.bak-egress-20260611235720 $f; done && nginx -t && nginx -s reload'`

---

### 2026-06-08 手动补发 4 人邀请码 + auto-review 链路故障诊断

> 手动补发邀请码：星之白路(EMMTA8GT)、duyi(XQHX8HEA)、小小何(YSW5QHFB)、小七姐(W6LF3MXL)。均 pro/7天/¥1000。
> **auto-review 故障根因**：①群成员列表仅 5 人，申请者名称不匹配→进入人工确认流→②飞书 App(cli_a968d2518bf89ccb)缺 `im:message:send` 权限，通知水良子失败→③`AUTO_REVIEW_NOTIFY_OPEN_ID` 当前为空→记录卡在"待审"永远不发码。需修复：飞书 App 加权限 + 补 NOTIFY_OPEN_ID + 扩充群成员名单。

### 2026-06-08 基础设施迁移：EdgeOne 回源切 CLB + Gateway DNS 临时回滚

> **EdgeOne 回源**：hersoul.cn 回源从 CVM(192.144.187.174, HTTPS:443) 改为 K8s CLB(`lb-2rhklmgd`, HTTP:80)，EdgeOne CDN 继续 SSL 终止。回滚：`tccli teo ModifyAccelerationDomain --cli-unfold-argument --ZoneId zone-3qe3x1f4ebma --DomainName hersoul.cn --OriginInfo.OriginType IP_DOMAIN --OriginInfo.Origin 192.144.187.174 --OriginInfo.HostHeader hersoul.cn --OriginProtocol HTTPS --HttpsOriginPort 443`
> **Gateway DNS 临时回滚**：api.tokenic.cn 的 K8s CLB(`lb-1npe9gzp`) HTTPS 443 无证书无规则，CLB 有 OperateProtect 无法 API 修改。DNSPod 暂停 CNAME(ID=2273574618)，新增 A 记录(ID=2310507505)→192.144.187.174。K8s 团队配好 CLB HTTPS 后，启用 CNAME、禁用 A 记录即可切回。

### 2026-06-05 her-web 验证邮件未发送

> 修复 EdgeOne Resend DNS：两条 MX 优先级 0→10，并修正 DKIM TXT 漏字；Resend `mail.hersoul.cn` 已 verified，生产 key 发送测试 HTTP 200。回滚：按 Resend 页面恢复旧 DNS 值。

### 2026-06-04 her-gateway MiMo v2.5 变慢只读排查

> 近 24h `mimo-v2.5` 慢主要来自单账号上游慢/300s timeout + 30m token affinity 黏住；成功请求同分钟重叠峰值仅 3-4，不像并发打满。发现 #26 `tiny二号` 仍在 priority=0 但 401，无配置变更。

### 2026-06-02 磁盘清理 72%→58% + 发现发版未走 COS 断层

> 删 roome 全套（4 service + 4 volume，已 0/0）释放 5G + 清 /tmp 部署残留释放 5G，磁盘 72%→58%，test/生产零误伤。**未动**：/opt/releases 4.4G（要先改发版脚本）、gateway 容器 json 日志 8.1G 无轮转仍在涨（用户暂缓）。关键发现见坑速查表 #14。回滚：roome/tmp 不可逆。

### 2026-06-02 roome 已停环境退役

> 关键认知纠正：**当前活跃测试栈是 test（1/1），roome 早已停（0/0），用户原以为"只用 roome"记反了**。删的是 roome（gateway-roome-db/redis + web-roome-db/db-clone）。

### 2026-06-02 EdgeOne 日志投递开通 + /api/v1/messages 异常排查

> 开通 EdgeOne 实时日志投递（国内+海外，S3→COS `her-releases-1398915892`，JSON+gzip）。排查结论：EdgeOne 未误杀任何用户（DDoS OFF、WAF 仅监控、无自定义规则）；7 天 6737 个 403 全是 her-web enforceRequest 业务拦截（订阅过期/额度用完/模型区域）；海外用户正常访问；真正体验瓶颈是上游 FRT——CH12(pipellm/Claude) 平均 15.5s、52.7%>10s，MiMo 渠道平均 3-5s、~10%>10s。详见 `context/edgeone-cdn-runbook.md` 日志投递章节。

### 2026-05-30 gengmin1990 邀请码补绑 + Pro 转试用

> 注册没绑码真因：单次码 `HCLUB-MJ7LUTUEKKRD2FFM` 被同人另一号 gengmin02@meituan.com 抢兑（used_count 已满 1/1），163 号被运营 manual 开了 Pro（非兑现）。按用户决定：新发同规格 basic 码 `HCLUB-FSGB6AWTX94ACXB6` 绑定，并把 Pro 降回试用档（5000万/7天/到 6/6）——新建码+user_invite+her_club_tier+audit、subscription 置 canceled、原 1.5亿 credit 转 expired 补 5000万 gift、pending 标 redeemed；gateway 649/token 407 剩额降到 49817250（总≈5000万）。meituan 号未动。详见 ops/invite-redeem-repair.md。回滚：删 user_invite `e94f8516…`、credit `2ea87e9e…`、码 `afadac2c…`、audit `863ed1f7…`；subscription `f5b69506…` 回 active、credit `a9ec1e00…` 回 active+1.5亿、gateway 649 quota 回 1.5亿。

### 2026-05-30 universe_yue 邀请码绑定补录

> 注册成功但 `user_invite` 缺失：会员是管理员 manual provision 开的（不兑现邀请码），gateway/试用额度是注册默认惰性开通（与邀请码无关）→ 事务补录 user_invite/used_count/her_club_tier/audit/pending.redeemed_at，未动 subscription/gateway/credit。详见 ops/invite-redeem-repair.md。

### 2026-05-30 生产用户 Max/Pro 积分显示口径核查

> prod-only read-only：核查一名 Max 用户的 gateway quota、quota_data、credit 与 subscription；确认总消耗来自 gateway logs，Max/Pro 周期显示为 0 是当前窗口与整数截断口径导致。回滚：无数据变更。

### 2026-05-29 her-web #186 test E2E 数据

> test-only：创建 `e2e186-20260529180724` 邀请码和 `e2e186-20260529180724-basic@test.her`，设置 gateway test user `681` / token `437` 为 used ¥300；回滚：按 note/email 删除 test web 数据，并在 test-gw 软删 user/token。

### 2026-05-29 her-gateway 取消 claude-opus-4-6 到 Sonnet 的映射

> 删除 channels 6/11/12/13 中 `claude-opus-4-6 -> claude-sonnet-4-6` 的 `model_mapping`，保留 `claude-opus-4-5 -> claude-opus-4-5-20251101`；烟测返回 `claude-opus-4-6`。回滚：用 `/tmp/her-gateway-opus46-routing-before-20260529.json` 恢复这 4 个 channel。

### 2026-05-29 Plus/Pro/Max 生产数据迁移

> prod-only：fresh dump `20260529T012628Z` 校验通过，建回滚表后执行订阅 v2、gateway paid 额度和 1 名 trial 补额；`domestic_*` 活跃行归零，Pro 23 行、Max 38 行，trial credit 记录为 0/100w，trial token 仍 132/132 `unlimited_quota=true`。回滚：用 `subscription_backup_plus_pro_max_v2_20260529t013752z`、`credit_backup_trial_topup_v2_20260529t013752z`、gateway 对应 `*_20260529t013752z` 表恢复。

### 2026-05-28 生产影子账号重克隆

> prod-only：按当前生产原账号重建 6 个 `{local}@test.her` 影子账号（密码 `test123456`），同步 her-web 订阅/credit/usage/herclub 数据与 prod gateway users/tokens；原账号只读未改，旧影子备份后缀 `20260528235928`。回滚：删除 `clone-ann0209`、`clone-841455442`、`clone-981710`、`clone-door.zhou`、`clone-guanguan0987`、`clone-skortur` 及 gateway users `622-627`。

### 2026-05-28 Plus/Pro/Max 计划迁移 test 原型

> test-only：执行计划迁移与 gateway 额度原型，旧 domestic 订阅改为 Pro、Max 写入附赠 Pro 周期起点，test-gw 余额按新公式重置；备份表后缀 `20260528230455`。回滚：用同后缀备份表恢复。

### 2026-05-28 test-gateway MiMo 与 DeepSeek v4 定价同步

> test-gw 已同步生产新价：`mimo-v2.5` / `deepseek-v4-flash` 为输入 ¥1/M、输出 ¥2/M、缓存读 ¥0.02/M，`mimo-v2.5-pro` / `deepseek-v4-pro` 为输入 ¥3/M、输出 ¥6/M、缓存读 ¥0.025/M；`/api/pricing` 已确认生效。回滚：用 `/tmp/her-gateway-test-mimo-deepseek-price-before-20260528.txt` 恢复四个 options。

### 2026-05-28 重建 17 个 `[测试]` 影子账号到 test

> test-only：按 `/tmp/shadow-target-backup-20260514.csv` 映射，用当前生产原账号重建 17 个 `{local}@test.her` 账号（密码 `test123456`），同步 web credit/subscription/usage/herclub 数据与 test-gw users/tokens；登录与 `verify-web-gateway` 通过。回滚：删除这 17 个 test `user.email` + 对应 test `user_gateway.gateway_user_id` 的 test-gw users/tokens。

### 2026-05-28 5/21 内测批次延期至 5/29（补 credit）

> 68 名 5/21 注册用户 `user_invite.trial_ends_at` 统一改为 UTC `2026-05-28 16:00:00`；补充：65 条 active `credit.expires_at` 同步延期（3 名无 active credit 跳过）。1 名原到 6/5 未动。注意：延期须同时改 `trial_ends_at` 和 `credit.expires_at`。

### 2026-05-28 批量创建 14 个 test 账号

> test-only：为 wanshi/sanyi/kanmen/suyuan/tiny/xiaoqi/gaogao 创建 `-3`/`-4` 账号，均已 email verified 并完成 gateway binding；双库与 `verify-web-gateway` 通过。回滚：按 `ops/test-account-provisioning.md` 清理对应 test user/account/session/user_gateway，并软删 test-gw users/tokens。

### 2026-05-28 test 账号创建顺序修正

> `ops/test-account-provisioning.md` 改为注册后先补 test `email_verified` 再登录，并把 web/gateway bypass token 作为前置检查；当前 test web/gateway 验证通过。回滚：还原该 ops 文件本次修改。

### 2026-05-28 test/prod 不限流 env 固化

> test/prod 持久配置补 `AUTH_RATE_LIMIT_ENABLED=false`，her-web Dokploy env 与 test service 已更新；gateway raw compose 校验仍含 `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN`。回滚：用 `/home/ubuntu/her-web-release/env-backups/*before-rate-limit-20260528135329` 恢复 env，再按需重启对应 service。

### 2026-05-28 test 测试账号只读盘点

> 只读查询 test web/gateway DB：未发现 `id=clone-*` 的 clone-prod-user 账号；找到 wanshi/sanyi/kanmen/suyuan/tiny/xiaoqi/gaogao 命名测试账号 27 个，均有 gateway binding。回滚：无需，未写数据。

### 2026-05-28 订阅测试账号补 gateway binding

> test-only：为 wanshi/sanyi/kanmen/suyuan/tiny/xiaoqi/gaogao 共 13 个测试账号逐个核验并补齐 gateway binding；走正常登录 + `/api/user/provision-gateway`，双库与 `verify-web-gateway` 通过。回滚：按 `ops/test-account-provisioning.md` 清理对应 test `user_gateway` 与 test-gw `users/tokens`。

### 2026-05-28 创建 3 个 test 第二账号

> 创建 `sanyi-2@test.com`、`wanshi-2@test.com`、`suyuan-2@test.com`，均可用 `test123456` 登录，已补 test gateway binding；未加入 0.01 支付白名单。回滚：按 `ops/test-account-provisioning.md` 清理对应 test user/account/session/user_gateway，并软删 test-gw users/tokens。

### 2026-05-28 test 账号 provisioning 流程

> 新增 `ops/test-account-provisioning.md`：test 账号必须走 her-web 注册/登录路径并调用 gateway provisioning，验证 web `user_gateway` 与 gateway `users`/`tokens` 后才算可用。回滚：删除该 ops 文件并还原 SKILL.md/index.md/changelog.md。

### 2026-05-28 test 订阅测试账号恢复真实价格

> test DB `config.payment_test_account_emails` 移除 wanshi/sanyi/kanmen/suyuan/tiny/xiaoqi/gaogao 测试账号，保留 `wechat_test_amount=1` / `alipay_test_amount=1`，并重启 `her-web-test` 清缓存。回滚：把移除的邮箱追加回该 config 值后再次 `sudo docker service update --force her-web-test`。

### 2026-05-28 误更新生产 service → 新增坑 #10

> deploy-test.sh 中断后手动 service update 误选 `her-herweb-a8y5ka`（生产）而非 `her-web-test`（测试），约 3 分钟后 rollback 恢复。新增坑速查 #10 + 仓库地图标注生产/测试 service 名 + her-cicd deploy-test.md 加安全警告。

### 2026-05-28 her-gateway DeepSeek v4 定价同步降价

> 将 `deepseek-v4-flash` 同步为输入 ¥1/M、输出 ¥2/M、缓存读 ¥0.02/M，将 `deepseek-v4-pro` 同步为输入 ¥3/M、输出 ¥6/M、缓存读 ¥0.025/M；VIP `mimo-v2.5-pro -> deepseek-v4-pro` 烟测日志按新价算平。回滚：用 `/tmp/her-gateway-deepseek-price-before-20260528.json` 恢复 `ModelRatio` / `CacheRatio`。

### 2026-05-28 her-gateway MiMo v2.5 定价降价

> 按小米 MiMo 官方 pay-as-you-go 新价，将 `mimo-v2.5` 调为输入 ¥1/M、输出 ¥2/M、缓存读 ¥0.02/M，将 `mimo-v2.5-pro` 调为输入 ¥3/M、输出 ¥6/M、缓存读 ¥0.025/M；`mimo-v2-pro` 价格不变。回滚：用 `/tmp/her-gateway-mimo-price-before-20260528.txt` 中四个 options 值恢复。

### 2026-05-27 清理 EdgeOne 监控：删拨测 + 关 SSE 探针

> 腾讯云拨测 3 任务（task-ir0gejh0/g8olu18w/ekzajanw）已删除——从未产生有效数据，api-401 任务 expectedCode 配错触发误报。SSE 探针 cron 已关闭（308 次零告警，退役）。脚本+日志保留在服务器。详见 `context/edgeone-cdn-runbook.md` 快速参考卡。

### 2026-05-26 SSH 安全加固：关闭密码登录 + 限制 root

> 腾讯云告警 57.154.172.164（GitHub Actions Azure 出口 IP）publickey 登录为误报。排查中发现 PasswordAuthentication=yes 且有暴力扫描，改为 no；PermitRootLogin 改为 prohibit-password。回滚：`sudo cp /etc/ssh/sshd_config.bak.20260526 /etc/ssh/sshd_config && sudo systemctl reload sshd`。

### 2026-05-25 DB 操作优化：her-db wrapper + 完整 Schema Reference

> 新增 `scripts/her-db.sh`（4 环境 DB wrapper，零转义 SQL 执行）、`scripts/gen-db-schema-ref.py`（从代码生成 schema）、`scripts/test-her-db.sh`（10 case 全绿）。重写 `ops/production-db-ops.md`：完整 schema reference（her_web 30 表 + gateway 6 高频表）、AI 常猜错列名标注（config.name 非 key、user 无 role、credit.transaction_type 非 type 等）、高频 UPDATE 模板。SKILL.md 加 HERDB 变量 + 坑速查 #8/#9。根因：扫描 110 个历史 session 发现 ~150 次 DB 操作错误，60% 为猜错列名。

---

### 2026-05-25 her-ops 垂直切片重构

> `runbooks/` + `references/` → `ops/`（12 个自包含操作文件）+ `context/`（5 个背景知识）。ssl-check + ssl-renew 合并为 ssl-ops.md；邀请码从 index.md 提取为 ops/invite-codes.md；topology 吸收 domains-and-ssl；channel-provisioning 删死引用段。SKILL.md 路由表直接指向 ops/，去掉 index.md 中间层。changelog 5/14 前条目归档，新增极简写入规范（3 行封顶）。index.md 从 305 行瘦身到 ~100 行。

---

### 2026-05-25 Phase 2 COS 安装包迁移完成

> 摘要：COS 桶 `her-releases-1398915892`（ap-guangzhou，公有读）创建，2.7GB 安装包（v0.0.2/v0.0.4/v0.0.5 + latest.json + index.html + latest/ 符号链接解析）通过 coscmd 从服务器上传。EdgeOne 规则 `releases-cos-origin`（ModifyOrigin + HostHeader + 30 天缓存）+ `latest-json-no-cache` 创建。缓存清除后验证 `server: tencent-cos` 回源成功，DMG 二次请求 RefreshHit。

涉及配置：COS 桶 ACL public-read、EdgeOne 源站组 `og-3qjr6cfspbjr`、规则 `rule-3qjradh4h56h` + `rule-3qjraq95rwfg`。服务器 coscmd 安装在 `/home/ubuntu/.local/bin/`。

---

### 2026-05-25 EdgeOne CDN S1-S5 完成，hersoul.cn 全站加速上线

> 摘要：EdgeOne CDN NS 接入完成。S1 代码部署（PR #158 心跳+防缓冲头+Plan B 预埋）→ S2 服务器备份（acme.json + SSE 探针）→ S3 控制台配置（基础版 399 元/月 + 全球 + HTTPS 回源 + 规则引擎）→ S4 DNS 迁移（NS 模式 + 10 条 DNS + B½ SSE 实测通过）→ S5 NS 切换（注册商改 NS + 上传 Let's Encrypt 证书 + Phase 0D 全链路验证通过）。5 个边缘节点 HTTPS/SSE/API 全部验证通过。SSE 探针 cron 已激活（每 10 分钟），腾讯云拨测 3 任务已创建（每 5 分钟×3 节点）。NS 全球传播中，传播后切 eofreecert 自动续期。

执行偏差：套餐从标准版 3800 降为基础版 399；acme.json 实际路径 `/etc/dokploy/traefik/dynamic/acme.json`；压缩规则跳过（EdgeOne 不支持按 URL 关闭）；UptimeRobot 改为腾讯云拨测；eofreecert 因 NS 未传播无法 DV 验证，先上传证书绕过。

涉及文档：edgeone-cdn-runbook.md, edgeone-cdn-decisions.md, index.md, changelog.md

---

### 2026-05-25 her-gateway MiMo #9 按量渠道降为低优先级兜底

> 摘要：排查 #9 `小米 MiMo API 按量付费（高高）` 用量偏高，确认主因是生产配置里 #9 已变成 `priority=0`，和 Coding Plan 渠道平级随机命中；命中后又被 `mimo coding plan cache` 按 token 黏住 30 分钟。已将 #9 改回 `priority=-1`，并清掉当前指向 #9 的 MiMo affinity 缓存。

commit: 无代码变更 | 备份：`/tmp/her-gateway-channel9-before-20260525-135145.csv`、`/tmp/her-gateway-channel9-abilities-before-20260525-135145.csv` | 回滚：`UPDATE channels SET priority=0 WHERE id=9; UPDATE abilities SET priority=0 WHERE channel_id=9;`，必要时等待 channel cache 下一次同步。

**操作**：
- 只读统计最近 24 小时 MiMo 日志：#9 成功消费约 1289 次，其中 1260 次来自 `channel_affinity` 黏住，真正 retry 成功切到 #9 约 5 次。
- 生产 Postgres 更新：
  - `channels.id=9 priority: 0 -> -1`
  - `abilities.channel_id=9 priority: 0 -> -1`
- Redis 删除当前指向 #9 的 4 个 `new-api:channel_affinity:v1:mimo coding plan cache:*` key。

**验证**：
- DB 读回：#9 在 `mimo-v2-pro` / `mimo-v2.5` / `mimo-v2.5-pro` 的 `abilities.priority` 均为 `-1`。
- Redis 读回：当前 MiMo affinity key 中 value 为 `9` 的数量为 0。
- `new-api` 在北京时间 `13:50:48` / `13:51:48` 已完成 `channels synced from database`，运行中 channel cache 已同步。

---

### 2026-05-25 her-ops 部署职责拆分到 her-cicd

> 摘要：CI/CD 流程改造第三步（规则文件对齐）和第四步（her-ops 清理）。部署/发布/回滚相关的触发词、场景路由、脚本引用、已知坑全部指向 her-cicd skill。分支命名从 `suyuan-MM-DD-<topic>` 改为 `feat/xxx` / `fix/xxx` / `hotfix/xxx` / `engine/xxx`。

**改动文件**：
- `SKILL.md`：description 移除部署触发词，场景路由表移除 6 个部署场景并加跳转行，关键入口移除 3 个部署脚本，已知坑 #8/#9/#13-17 加 her-cicd 跳转
- `index.md`：gateway/her-web/herclub 脚本表删除已迁移行并加跳转说明
- `~/.codex/AGENTS.md`：Git 协作改为 feat 分支模型 + 合并方向规则 + PR @codex review 规则 + her-cicd/her-ops 分界线
- `~/Documents/her-source/CLAUDE.md`：Skill 调用规则拆分 her-cicd/her-ops + Git 分支规则改为 feat 模型 + 合并方向 + PR review 规则

**无回滚需要**：纯文档改动。

---

### 2026-05-24 her-gateway 上游请求日志改为差异存储

> 摘要：PR #11 合入 `main` 并部署生产；`upstream` 请求日志在 JSON 场景下优先存相对 `inbound` 的 `json_diff`，避免原始请求和上游请求大面积重复占用空间。

commit: `4be8a3932` (`feat: store upstream request log diffs`) | PR: https://github.com/her-os/her-gateway/pull/11 | 回滚：服务器本地镜像 tag `her-newapi-e91gqn-new-api:pre-log-diff-20260524224730`，或回退 `main` 后重新执行 gateway deploy。

**操作**：
- 本地验证：`go test ./model ./relay ./controller ./router`、`bun run build`、`git diff --check`。
- 创建并合入 PR #11 到 `main`。
- 标准 `scripts/gateway/deploy.sh` 再次在 runtime `apt-get` 层超过 5 分钟；线上容器未切换，仍 healthy。
- 按已有兜底方式：停止卡住的完整 build，构建 `--target builder2`，基于旧 runtime 镜像只替换 `/new-api`，再 `docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api`。

**验证**：
- 容器镜像已切到 `sha256:6bba5e44b1548d8a7526c6831538534b2bcd1e0e11084b43080c0eedb36cd4bd`，状态 `healthy`。
- `https://api.tokenic.cn/api/status` 返回 HTTP 200。
- Admin API 可读 `request_body` 日志。
- request id `202605241449386515629168268d9d6HWHSGm75`：`upstream` 行 `body_encoding=json_diff`，真实上游 `body_bytes=395023`，实际存储 body 长度 `72`。
- 生产最近 15 分钟统计：`json_diff` upstream 27 行，真实上游体积约 `7054 kB`，实际存储 diff 约 `1944 bytes`；未命中 diff 的 upstream 仍按 text 存完整 body。

**坑**：
- 没有新增运维坑；runtime apt 层超时仍是既有 `dokploy-deploy.md` 2026-05-18 记录的问题。

---

### 2026-05-24 her-web telemetry 与 gateway token totals 口径核对

> 摘要：只读核对 `user_id=524` 的 gateway `logs`、`quota_data` 和 her-web telemetry，确认 `/api/user/usage/token-totals` 与 gateway 原始消费日志一致；her-web「API 日志」是客户端 telemetry/JSONL 快照口径，不是 gateway logs 同步副本。

**操作**：
- 查 gateway 生产库 `logs`：`user_id=524` 当前有 `2430` 条 `type=consume`，`sum(prompt_tokens)=7742675`、`sum(completion_tokens)=874148`、`sum(other.cache_tokens)=159385984`。
- 调 gateway 批量接口：返回 `input_tokens=7742675`、`output_tokens=874148`、`cache_read=159385984`、`total_tokens=168002807`，与 `logs` 原始聚合一致。
- 查 her-web 生产库 telemetry：同一 web 用户当前 telemetry 解析结果约 `2670` 条 token record，`input_tokens=4190937`、`output_tokens=780848`、`cache_read=166024192`、`total_tokens=170995977`。
- 查生产 `new-api` env：未配置 `HER_WEB_AGENT_OPS_*`，所以 gateway 消费日志没有同步到 her-web telemetry。

**结论**：
- gateway token totals 是 gateway 计费日志口径，可作为 gateway 消耗统计。
- her-web 导航里的「API 日志」读 `telemetry_events` / `telemetry_session_snapshots`，来自客户端事件和 JSONL 快照，可能包含非 gateway 或重复/不同粒度的会话 token，不适合反校验 gateway 账务口径。

**回滚**：只读排查，无生产变更；文档如需撤回，删除本条和 `admin-api.md` 的口径边界说明即可。

---

### 2026-05-24 her-gateway Token Totals 批量分页修复

> 摘要：修复 `/api/user/usage/token-totals` 在消费日志超过 1000 行时不返回的问题；原因是 `FindInBatches` 的 select 缺少主键 `id`，批次游标无法推进。

commit: `cc0660dc9` (`Fix token totals batch pagination`) | PR: 无（按本次会话要求直接推 main） | 回滚：优先将服务器镜像 tag 回 `her-newapi-e91gqn-runtime-base:pre-token-totals-batch-fix-1779615733` 后 recreate；代码层可 revert `cc0660dc9` 后重新执行 gateway deploy。

**操作**：
- `tokenTotalsLogRow` 增加 `id`，查询 `Select` 同步包含 `id`，让 GORM `FindInBatches` 能推进批次。
- 补 `1501` 条日志的回归测试，覆盖多批次读取。
- 本地验证通过：`go test ./model -run TokenTotals -count=1`、`go test ./controller ./router -count=1`。
- 推送 `main` 后按既有 builder2 + 旧 runtime 兜底路径部署，recreate `new-api`。

**验证**：
- 容器镜像已切到 `sha256:d8782a1ab4aedf3fa3e892a2a35f7f570f93d932805492facae86f8080da0e23`，状态 `healthy`。
- `https://api.tokenic.cn/api/status` 返回 HTTP 200。
- 最高消费日志用户 `user_id=341`（约 `10220` 条消费日志）返回 `success=true`，耗时约 `0.43s`。
- 目标用户 `user_id=524` / `username=89729945@qq.com-Her` 返回 `success=true`，耗时约 `0.15-0.23s`，`total_tokens=160511123`。

**坑**：
- GORM `FindInBatches` 如果自定义 select 到无主键结构体，超过一个 batch 时会反复读第一页。批量分页查询必须保留主键列，测试也要覆盖超过 batch size 的数据量。

---

### 2026-05-24 her-gateway 批量 Token Totals 接口发布

> 摘要：`main` 新增 `/api/user/usage/token-totals` Admin API，按 gateway 消费日志批量返回多个用户的 token 全量累计；已部署生产并用真实 gateway 用户验证。

commit: `254e6c2e6` (`Add gateway token totals admin API`) | PR: 无（按本次会话要求直接推 main） | 回滚：优先将服务器镜像 tag 回 `her-newapi-e91gqn-runtime-base:pre-token-totals-1779601123` 后 recreate；代码层可 revert `254e6c2e6` 后重新执行 gateway deploy。

**操作**：
- 新增 `POST /api/user/usage/token-totals`，沿用 AdminAuth，可一次传多个 `user_ids` / `usernames`。
- 只读 gateway `logs`，只统计 `type=consume`；Go 侧解析 `other.cache_tokens`、`cache_write_tokens`、`cache_creation_tokens(_5m/_1h)`，不使用 DB JSON 函数。
- 本地验证通过：`go test ./model -run TokenTotals -count=1`、`go test ./controller ./router -count=1`。
- 推送 `main` 到 `origin/main` 后按 gateway deploy 脚本发布。
- 完整 runtime build 再次卡在 `stage-2 apt-get` 层超过 5 分钟；线上容器未切换且保持 healthy。
- 按既有兜底方式：停止卡住的 build，构建 `--target builder2`，基于旧 runtime 镜像只替换 `/new-api`，再 `docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api`。

**验证**：
- 容器镜像已切到 `sha256:0e9c084c5d099c001c9226f89aeb5a2e4b63422014abb741abc566c7e3828d6d`，状态 `healthy`。
- `https://api.tokenic.cn/api/status` 返回 HTTP 200。
- Admin API：`POST /api/user/usage/token-totals -d '{"user_ids":[581]}'` 返回 `success=true`，用户 `581` 的 `total_tokens=50624478`、`request_count=607`。
- 混合输入测试：`user_ids=[581,999999999]` + 一个不存在 username，返回真实用户一条，`missing_user_ids=[999999999]`、`missing_usernames=[...]`。

**坑**：
- 没有新增运维坑；这次再次命中既有 `dokploy-deploy.md` 的 runtime apt 层卡点。
- 该接口是 gateway 口径，不与 her-web telemetry 对齐，也不回写 her-web。

---

### 2026-05-24 her-gateway 请求响应日志保留 24 小时并回收空间

> 摘要：将生产 gateway `request_body_logs` 保留期从默认 7 天改为 1 天；删除 24 小时前请求/响应日志，并用 `VACUUM FULL` 回收 PostgreSQL 物理空间。

commit: `964611a1a` (`chore: keep request logs for one day`) | PR: https://github.com/her-os/her-gateway/pull/10 | 回滚：代码层可移除 `REQUEST_LOG_RETENTION_DAYS=1` 后重新同步 compose 并 recreate；已删除的日志不能从应用侧回滚，只能依赖数据库备份。

**操作**：
- `docker-compose.yml` 增加 `REQUEST_LOG_RETENTION_DAYS=1`、`REQUEST_LOG_CLEANUP_INTERVAL_MINUTES=60`。
- 合入 PR #10 到 `main`。
- 同步 Dokploy raw `compose.composeFile`，并在服务器实际 compose 中保留本地镜像 `her-newapi-e91gqn-new-api:latest` / `pull_policy: never`，只补 env。
- recreate `new-api` 让 24 小时保留策略生效。
- 为避免 `VACUUM FULL` 锁 `request_body_logs` 时影响用户请求，临时在服务器 compose 加 `REQUEST_LOG_ENABLED=false` 并 recreate；空间回收完成后移除该临时 env，再 recreate 恢复日志写入。
- 删除 24 小时前日志，执行 `VACUUM (FULL, VERBOSE, ANALYZE) request_body_logs`，最后补删跨过边界的少量旧行并普通 `VACUUM ANALYZE`。

**结果**：
- `request_body_logs`：约 `17GB` -> `9161MB`。
- `newapi` 数据库：约 `17GB` -> `9297MB`。
- 根分区：约 `34GB used / 42GB available` -> `32GB used / 45GB available`。
- 最终 `rows_over_24h=0`，保留 `58091` 行、`20375` 个 request_id。
- 生产容器 healthy，`https://api.tokenic.cn/api/status` HTTP 200。
- 生产容器 env：`REQUEST_LOG_RETENTION_DAYS=1`、`REQUEST_LOG_CLEANUP_INTERVAL_MINUTES=60`，无 `REQUEST_LOG_ENABLED=false`。

**坑**：
- `VACUUM FULL` 会拿表级排它锁；请求日志写入是请求路径上的同步 DB 写入。回收空间前应临时关闭 `REQUEST_LOG_ENABLED`，避免用户请求卡在日志表写入。

---

### 2026-05-23 her-gateway 上游响应日志发布

> 摘要：PR #9 合入 `main` 后部署生产 gateway，请求/响应日志新增 `upstream_response` stage，管理员可在同一 `/api/log/request_body` 接口查看可读上游响应元信息和正文。

commit: `b304670f9` (`feat: capture upstream response logs`) | PR: https://github.com/her-os/her-gateway/pull/9 | 回滚：服务器本地镜像 tag `her-newapi-e91gqn-new-api:pre-response-log-20260523154515`，或回退 `main` 后重新执行 gateway deploy；容器回滚命令可用 `docker tag her-newapi-e91gqn-new-api:pre-response-log-20260523154515 her-newapi-e91gqn-new-api:latest && docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api`。

**操作**：
- 本地验证：`go test ./model ./relay`、`go test ./controller ./router`、`bun run build`、`git diff --check`。
- 创建并合入 PR #9 到 `main`。
- `scripts/gateway/deploy.sh` 的完整 runtime build 再次在 `stage-2 apt-get` 层超过 5 分钟；线上容器未切换，仍 healthy。
- 按 `dokploy-deploy.md` 已有兜底方式：停止卡住的 build，构建 `--target builder2`，基于旧 runtime 镜像只替换 `/new-api`，再 `docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api`。

**验证**：
- 容器镜像已切到 `sha256:60e7face53ff88e02d7e27ed447ba9d94c9475c39a04c75f7d2bb1aa44a3e53c`，状态 `healthy`。
- `https://api.tokenic.cn/api/status` 返回 HTTP 200。
- Admin API：`GET /api/log/request_body?p=1&page_size=1` 返回最新 `stage=upstream_response`、`status_code=200`、`model=mimo-v2.5-pro`。
- `include_body=true` 按 request id 查询返回 inbound + upstream + upstream_response 三条；`upstream_response` 为 `text/event-stream`，有 `body_bytes`，正文可读取。
- slysasnf 旧请求仍只能看到部署前已有 inbound/upstream；新版本上线后产生的请求已经开始记录响应 stage。

**坑**：
- 没有新增运维坑；这次命中的是既有 `dokploy-deploy.md` 2026-05-18 记录的 runtime apt 层卡点。

---

### 2026-05-23 her-gateway 请求体日志查看发布

> 摘要：PR #8 合入 `main` 后部署生产 gateway，请求日志新增管理员查看 inbound/upstream request body 的入口；生产 `GET /api/log/request_body` 已返回数据。

commit: `7bb7a1ab9` (`feat: add gateway request body log viewer`) | PR: https://github.com/her-os/her-gateway/pull/8 | 回滚：服务器本地镜像 tag `her-newapi-e91gqn-new-api:pre-request-body-20260523140649`，或回退 `main` 后重新执行 gateway deploy；容器回滚命令可用 `docker tag her-newapi-e91gqn-new-api:pre-request-body-20260523140649 her-newapi-e91gqn-new-api:latest && docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api`。

**操作**：
- 本地验证：`go test ./model ./relay`、`go test ./controller ./router`、`bun run build`。
- 创建并合入 PR #8 到 `main`。
- `scripts/gateway/deploy.sh` 的完整 runtime build 在 `stage-2 apt-get` 层超过 5 分钟；线上容器未切换，仍 healthy。
- 按 `dokploy-deploy.md` 已有兜底方式：停止卡住的 build，构建 `--target builder2`，基于旧 runtime 镜像只替换 `/new-api`，再 `docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api`。

**验证**：
- 容器镜像已切到 `sha256:5656ddab5444c6bc807a1eb5dc748c77a397e1fa48a1df609be6fa0e8024056a`，状态 `healthy`。
- `https://api.tokenic.cn/api/status` 返回 HTTP 200。
- Admin API：`GET /api/log/request_body?p=1&page_size=1` 返回 `success=true`、`total=60775`，最新记录包含 upstream request body 元信息。
- `include_body=true` 按 request id 查询返回 inbound + upstream 两条正文，body 长度分别约 202 KB / 204 KB。
- `health-check.sh` 中 `api.tokenic.cn`、new-api/redis/traefik、SSL、HTTP redirect、磁盘均 OK；`api.roome.cn` 仍按既有 roome 域名/证书限制失败，不属于本次生产 gateway 异常。

**坑**：
- 部署脚本 5 分钟超时对 runtime apt 层偏紧；这次命中的是既有 `dokploy-deploy.md` 2026-05-18 记录的卡点，不新增规则。
- `health-check.sh` 文件没有执行权限；用 `bash scripts/gateway/health-check.sh` 执行即可。

---

### 2026-05-23 her-gateway VIP MiMo v2.5 默认关闭 thinking

> 摘要：按小米 MiMo 文档，在 VIP 专用 `mimo-v2.5` pass-through channels 19-25 增加 `param_override`，当请求未显式传 `thinking` 时默认补 `thinking={"type":"disabled"}`，使 VIP 分组下 `mimo-v2.5` 默认关闭思考；`mimo-v2.5-pro` 仍走 DeepSeek channel 18。

commit: 无代码变更 | 备份：`/tmp/her-gateway-vip-mimo-v25-thinking-disabled-before-20260523-131757.tsv` | 回滚：用 gateway Admin API 将 channels 19-25 的 `param_override` 恢复为空字符串。

**操作**：
- channels 19-25 写入：
  - `operations[0].path=thinking`
  - `operations[0].mode=set`
  - `operations[0].value={"type":"disabled"}`
  - `operations[0].keep_origin=true`
- 含义：默认补 `thinking.disabled`，但不覆盖客户端显式传入的 `thinking`。

**验证**：
- DB 读回 channels 19-25 均有新 `param_override`。
- VIP token 180 请求 `mimo-v2.5` 且入站不带 `thinking`：HTTP 200，response content 为 text `ok`，无 thinking block。
- request id `202605230518465386370378268d9d6gX2WqarO`：
  - inbound model `mimo-v2.5`，无 `thinking`
  - upstream channel 22 `VIP MiMo v2.5 passthrough from #9`
  - upstream model `mimo-v2.5`
  - upstream `thinking={"type":"disabled"}`
- VIP token 180 请求 `mimo-v2.5-pro` 复查：HTTP 200，request id `202605230519121188317988268d9d6uP9wkiHL`，仍走 channel 18，upstream model `deepseek-v4-pro`。

---

### 2026-05-23 her-gateway VIP MiMo v2.5 保持原上游

> 摘要：为 VIP 分组补 `mimo-v2.5` 可用渠道，但不把它加到 DeepSeek channel 18。复制原 MiMo 渠道 5/7/8/9/14/15/17 为 VIP 专用 pass-through channels 19-25，只暴露 `mimo-v2.5`；`mimo-v2.5-pro` 仍由 channel 18 映射到 `deepseek-v4-pro`。

commit: 无代码变更 | 备份：`/tmp/her-gateway-vip-mimo-v25-pass-through-before-20260523-125644.tsv` | 回滚：删除 channels 19-25；原 channels 5/7/8/9/14/15/17 和 channel 18 未改。

**背景**：
- 不能直接把 `mimo-v2.5` 加到 DeepSeek channel 18；否则未映射时会上游发送 `model=mimo-v2.5` 到 DeepSeek，模型不匹配。
- 也不改原 MiMo channels 的 `group=default` 为 `default,vip`，避免 `mimo-v2.5-pro` 在 DeepSeek 失败后 fallback 到旧 MiMo Coding Plan。

**操作**：
- 通过 gateway Admin API `copy` 保留原 MiMo key/header/setting，创建 VIP 专用 `mimo-v2.5` pass-through：
  - 19 from 5
  - 20 from 7
  - 21 from 8
  - 22 from 9
  - 23 from 14
  - 24 from 15
  - 25 from 17
- 新 channels 均为 `type=58`、`group=vip`、`models=mimo-v2.5`、`priority=10`、无 `model_mapping`。
- 原 MiMo channels 5/7/8/9/14/15/17 保持 `group=default`，channel 18 保持只含 `mimo-v2.5-pro`。

**验证**：
- abilities 读回：`vip/mimo-v2.5` 只在 channels 19-25；`vip/mimo-v2.5-pro` 只在 channel 18。
- VIP token 180 请求 `mimo-v2.5`：HTTP 200，request id `20260523050235563994148268d9d6egj4J5Mu`，upstream channel 19，channel_type 58，upstream model `mimo-v2.5`。
- VIP token 180 请求 `mimo-v2.5-pro`：HTTP 200，request id `202605230502368242960178268d9d6bk72SXbP`，upstream channel 18，channel_type 14，upstream model `deepseek-v4-pro`。

---

### 2026-05-23 her-gateway DeepSeek thinking disabled 与 output_config 冲突修复

> 摘要：修复 VIP `mimo-v2.5-pro -> deepseek-v4-pro` 路由的 400：`thinking options type cannot be disabled when reasoning_effort is set`。channel 18 增加 `param_override`，当 `thinking.type=disabled` 时删除 `output_config` 和 `reasoning_effort`；无需部署 gateway 代码。

commit: 无代码变更 | 备份：`/tmp/her-gateway-channel18-deepseek-param-before-20260523-010448.tsv` | 回滚：用 gateway Admin API 将 channel 18 的 `param_override` 恢复为空字符串。

**证据**：
- 生产 newapi 日志：channel 18 `DeepSeek for VIP MiMo v2.5 Pro` 有 9 条同类 400，均来自 user 292 / token 180 / `mimo-v2.5-pro`。
- 请求体日志 `202605221648029056102118268d9d65VXB0aLF`：
  - inbound/upstream 都有 `thinking={"type":"disabled"}`。
  - upstream 同时保留 `output_config={"effort":"high"}`。
  - upstream model 已正确映射为 `deepseek-v4-pro`。
- DeepSeek 直连最小复现：
  - `thinking.disabled + output_config.effort=high` -> HTTP 400，同样错误。
  - 只保留 `thinking.disabled`、删除 `output_config` -> HTTP 200。

**操作**：
- 通过 gateway Admin API 更新 channel 18 `param_override`：
  - `thinking.type == disabled` 时删除 `output_config`
  - `thinking.type == disabled` 时删除 `reasoning_effort`
- 未修改 channel key、base_url、models、model_mapping、priority、group 或代码。

**验证**：
- DB 和 Admin API 均读回 channel 18 新 `param_override`。
- 模拟真实 Claude Code 形状请求：`stream=true`、tools、历史 `assistant tool_use` / `user tool_result`、Claude Code UA、`X-Claude-Code-Session-Id`、入站体保留 `thinking.disabled + output_config.effort=high`。
- Gateway 返回 HTTP 200，SSE 响应模型 `deepseek-v4-pro`，文本 `ok`。
- 请求体日志 `202605221710348307516568268d9d6y0PXLCh7`：
  - inbound：`thinking={"type":"disabled"}`，`output_config={"effort":"high"}`，tools=true，messages=4
  - upstream：`model=deepseek-v4-pro`，保留 `thinking={"type":"disabled"}`，`output_config` 已删除，`reasoning_effort` 为空，tools=true，messages=4

---

### 2026-05-23 her-web Operations Admin gateway VIP 分组

> 摘要：按 her-web 生产库 `role.name=operations_admin` 查到 7 个 Operations Admin 账号；将对应 gateway 用户分组改为 `vip`，并将 6 个未删除 her-web 默认 token 分组改为 `vip`，使这些账号可使用 VIP 分组下的 `mimo-v2.5-pro -> deepseek-v4-pro` 路由。

commit: 无代码变更 | 备份：`/tmp/her-gateway-operations-admin-vip-before-20260523-004038.tsv` | 回滚：用 gateway Admin API 将用户 329/291/281/290/292/283/296 分组改回 `default`，将 token 190/161/162/164/180/160 分组改回空字符串；token 28 保持软删除状态。

**名单来源**：
- 生产 her_web：`role.name='operations_admin' AND role.status='active'`
- 对应账号：
  - `chuncheuk@yeah.net` -> gateway user 329, token 190
  - `door.zhou@gmail.com` -> gateway user 291, token 161
  - `h87836346@163.com` -> gateway user 281, token 162
  - `shuiliangzi727@gmail.com` -> gateway user 290, token 164
  - `slysasnf@hotmail.com` -> gateway user 292, token 180
  - `yiliqi78@gmail.com` -> gateway user 296, token 160
  - `yiliqi7777@gmail.com` -> gateway user 283, token 28；her-web `user_gateway.revoked_at=2026-05-10 02:34:03.11`，gateway token 28 已软删除，未恢复。

**操作**：
- 通过 gateway Admin API `PUT /api/user/:id/group` 将 7 个用户分组改为 `vip`。
- 通过 gateway Admin API `PUT /api/user/:id/token/:token_id` 将 6 个未删除 token 分组改为 `vip`，保留原额度、过期时间、模型限制和 IP 限制。

**验证**：
- newapi 生产库复查：目标用户 `vip_users=7/7`。
- newapi 生产库复查：目标未删除 token `vip_active_tokens=6/6`。
- channel 18 `DeepSeek for VIP MiMo v2.5 Pro` 仍为 `status=1`、`group=vip`、`models=mimo-v2.5-pro`、`model_mapping={"mimo-v2.5-pro": "deepseek-v4-pro"}`。

---

### 2026-05-23 her-gateway VIP MiMo v2.5 Pro 路由到 DeepSeek

> 摘要：新增 `vip` 专用高优先级渠道，让 `vip` group 请求 `mimo-v2.5-pro` 时实际转发到 DeepSeek `deepseek-v4-pro`；`mimo-v2.5` 不在新渠道模型列表内，仍走原 MiMo 渠道。

commit: 无代码变更 | 备份：`/tmp/her-gateway-vip-mimo-to-deepseek-before-20260523-000537.json` | 回滚：删除 channel 18 `DeepSeek for VIP MiMo v2.5 Pro`。

**操作**：
- 新增 channel 18 `DeepSeek for VIP MiMo v2.5 Pro`
  - `type=14`（Anthropic）
  - `base_url=https://api.deepseek.com/anthropic`
  - `models=mimo-v2.5-pro`
  - `group=vip`
  - `priority=10`
  - `auto_ban=0`
  - `model_mapping={"mimo-v2.5-pro":"deepseek-v4-pro"}`
- 未修改原 MiMo 渠道；`mimo-v2.5` 仍只在原 MiMo 渠道中。

**验证**：
- channel 18 指定渠道测试：`mimo-v2.5-pro` Anthropic `stream=false` / `stream=true` 均成功
- 原 channel 5 指定渠道测试：`mimo-v2.5` Anthropic `stream=true` 成功
- 临时 `vip` token 从 Gateway 入口请求 `mimo-v2.5-pro`，HTTP 200，响应模型为 `deepseek-v4-pro`
- 请求体日志 `202605221609436329088688268d9d67G4msHnZ`：
  - inbound model：`mimo-v2.5-pro`
  - upstream channel：`DeepSeek for VIP MiMo v2.5 Pro`
  - upstream model：`deepseek-v4-pro`
- 临时 token `tmp-vip-route-smoke-20260523` 已删除。

**备注**：
- 当前 Gateway 用户表没有 `group=vip` 的用户；现有 token 也没有 `group=vip`。这条规则会对后续使用 `vip` group 的请求生效。
- her-ops 无需更新 runbook；本次按现有 `gateway/channel-provisioning.md` 和 `gateway/admin-api.md` 执行。

---

### 2026-05-22 her-web telemetry unknown 模型统计排查

> 摘要：排查后台「模型 Token 分布」里 `unknown` 模型。结论：该页面来自 her-web telemetry 聚合，不是 gateway `logs.model_name`；最近 1 天 `assistant_result` 事件上报了 token/cost，但 payload 没有 `model` 字段，服务端按代码兜底归为 `unknown`。

commit: 无代码变更 | 回滚：只读查询 + 文档记录，无需回滚。

**验证**：
- 页面代码：`/api/admin/telemetry/analytics` → `getTelemetryAnalytics()` → `tokenModelFromPayload()`，模型为空时 `normalizeTokenModel()` 返回 `unknown`
- 生产 her_web 最近 1 天 `assistant_result` 事件聚合约 `640.1M` total tokens、`17.7M` input、`3.0M` output、`606.3M` cache read，和截图里的 `unknown` 行一致
- 最近 1 天 `assistant_result` payload keys 只有 `inputTokens/outputTokens/cacheCreationInputTokens/cacheReadInputTokens/totalCostUsd/duration/subtype/...`，没有 `model`
- 已知模型行主要来自 snapshot JSONL；有 `assistant_result` 事件的 session 会跳过 snapshot 回填，导致缺模型事件被归到 `unknown`

**建议修复**：
- 采集端在 `assistant_result` 上报里补 `model` / `modelName`
- her-web 聚合端可在 event 缺模型时，从同 session 最新 snapshot 的 assistant/result 行回填模型，避免已有 snapshot 的会话继续显示 `unknown`

---

### 2026-05-22 her-gateway DeepSeek Anthropic 渠道开通

> 摘要：在生产 Gateway 后台新增 `DeepSeek` 渠道，走 Anthropic `/v1/messages` 接口，模型为 `deepseek-v4-pro`、`deepseek-v4-flash`；`deepseek-v4-flash` 定价按 CodingRouter 已配置的 `deepseek-v4-pro` 同步。

commit: 无代码变更 | 备份：`/tmp/her-gateway-deepseek-channel-before-20260522-235803.json`、`/tmp/her-gateway-deepseek-price-before-20260522-235803.json` | 回滚：删除 channel 16 `DeepSeek`，并从 `ModelRatio` / `CompletionRatio` / `CacheRatio` / `CreateCacheRatio` 中删除 `deepseek-v4-flash`，或恢复到备份中的旧配置。

**操作**：
- 新增 channel 16 `DeepSeek`
  - `type=14`（Anthropic）
  - `base_url=https://api.deepseek.com/anthropic`
  - `models=deepseek-v4-pro,deepseek-v4-flash`
  - `group=default`
  - `auto_ban=0`
- 定价：
  - `ModelRatio.deepseek-v4-pro = 6`
  - `ModelRatio.deepseek-v4-flash = 6`
  - `CompletionRatio.deepseek-v4-pro = 2`
  - `CompletionRatio.deepseek-v4-flash = 2`
  - `CacheRatio.deepseek-v4-pro = 0.1`
  - `CacheRatio.deepseek-v4-flash = 0.1`
  - `CreateCacheRatio.deepseek-v4-pro = 0`
  - `CreateCacheRatio.deepseek-v4-flash = 0`

**验证**：
- 直连 DeepSeek Anthropic `deepseek-v4-flash`：`x-api-key` 和 `Authorization: Bearer` 均 HTTP 200
- Gateway channel test：channel 16 `deepseek-v4-flash`，Anthropic `stream=false` / `stream=true` 均成功
- Gateway channel test：channel 16 `deepseek-v4-pro`，Anthropic `stream=false` / `stream=true` 均成功
- `/api/pricing` 能返回 `deepseek-v4-pro`、`deepseek-v4-flash`，vendor 显示为 DeepSeek，enabled group 为 `default`
- `/api/channel/models_enabled` 能看到两个模型

**备注**：
- 这里用 `type=14` 是为了固定按 Anthropic 上游路径拼成 `https://api.deepseek.com/anthropic/v1/messages`；DeepSeek 自身 `type=43` 会在 Claude 请求中自动追加 `/anthropic/v1/messages`，不能直接填带 `/anthropic` 的 base URL。
- her-ops 无需更新 runbook；本次按现有 `gateway/channel-provisioning.md` 和 `gateway/admin-api.md` 执行。

---

### 2026-05-22 her-gateway request_body_logs 只读查看

> 摘要：按 request body 日志排查 `unknown`，确认生产 `newapi.request_body_logs` 有数据，Admin API 需要 `include_body=true` 才返回正文；补充 Admin API 和生产库表速查文档。

commit: 无代码变更 | 回滚：恢复 `references/gateway/admin-api.md`、`references/her-web/production-db-ops.md`、`index.md` 的本次文档改动。

**验证**：
- 生产库 `request_body_logs` 当前可查，字段包括 `request_id`、`stage`、`attempt`、`body`、`body_bytes`、`read_error`
- `GET /api/log/request_body?request_id=...` 返回 inbound/upstream 元信息
- `GET /api/log/request_body?request_id=...&include_body=true` 返回正文
- `keyword=unknown` 当前不是有效过滤参数，会返回普通分页
- 最近 500 条中正文包含 `unknown` 的记录，多数是 prompt 普通文本；`request_id/model_name/username/token_name/channel_name = unknown` 未命中

---

### 2026-05-21 单人发邀请码操作文档 + 坑记录

> 摘要：给阿里（18939971945@163.com）和 MaomaoLihua（Fragrance2022@126.com）各发了一个邀请码（pro/7天/¥1000）。发现 local-prod-snapshot 缺 `invite_code.metadata` 列导致脚本插入失败，必须通过 SSH 隧道连生产库才能发码。更新 index.md 单人快速发码操作步骤，SKILL.md 新增坑 #20。

操作：
1. SSH 隧道 15432→172.17.255.75:5432，显式 DATABASE_URL 覆盖 .env.local
2. 阿里 → HH6DTNAU，MaomaoLihua(yaye) → 4TM33C6D，邮件均已发送
3. index.md 新增「单人快速发码」完整步骤（含 Resend 配置获取）
4. SKILL.md 坑速查表新增 #20：local-prod 缺 metadata 列

回滚：邀请码可在 admin 后台删除

### 2026-05-21 gateway bypass token + 批量 provision 429 修复

> 摘要：内测首批 134 人批量注册，gateway GlobalAPIRateLimit 限流 /api/user/ 返回 429，导致 4 个用户 gateway 账号创建不完整（有用户无 token、无 user_gateway 绑定）。

操作：
1. 手动补齐 4 个用户的 gateway token + user_gateway 绑定 + quota
2. gateway 容器添加 `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN` env（与 her-web 侧 token 一致），compose recreate 生效
3. her-web client.ts 429 重试从仅 GET 扩展到所有请求，最多 4 次指数退避
4. `sanitizeInviteTier` 添加 `'pro' → 'basic'` 映射
5. 134 条邀请码 tier 从 max 批量修正为 basic（Pro 试用）

PR: her-gateway#7, her-web#148 | 回滚：gateway 移除 env 变量并 recreate

### 2026-05-21 her-gateway CodingRouter deepseek-v4-pro 非流式恢复

> 摘要：按供应商反馈复测 `deepseek-v4-pro` Anthropic 非流式路径，确认 CodingRouter 直连和 Gateway 入口都已恢复 HTTP 200。

commit: 无代码变更 | 回滚：只读查询 + 小流量 smoke，无配置变更，无需回滚。

**验证**：
- 直连 `https://api.codingrouter.com/v1/messages`，`stream:true`：HTTP 200
- 直连 `https://api.codingrouter.com/v1/messages`，`stream:false`：HTTP 200
- Gateway `https://api.tokenic.cn/v1/messages`，`stream:false`：
  - token `217`：HTTP 200，Request ID `202605211017301631670798268d9d6uywDGsFS`
  - token `193`：HTTP 200，Request ID `20260521101736226961038268d9d6XUD7zEYL`
  - token `180`：HTTP 200，Request ID `202605211017402298070308268d9d61Y9bzZPD`

**备注**：
- token `232` 的 Gateway smoke 返回 401，是该测试 token 的缓存/状态问题；换生产有效 token 后 Gateway 路径正常。

---

### 2026-05-21 her-gateway CodingRouter deepseek-v4-pro 非流式复测

> 摘要：复测 `deepseek-v4-pro` 的 CodingRouter Anthropic 路径，确认 `stream:true` 可用，`stream:false` 在直连 CodingRouter 和经 Gateway 时均返回上游 400。

commit: 无代码变更 | 回滚：只读查询 + 小流量 smoke，无配置变更，无需回滚。

**验证**：
- 直连 `https://api.codingrouter.com/v1/messages`，`stream:true`：HTTP 200
- 直连 `https://api.codingrouter.com/v1/messages`，`stream:false`：HTTP 400，`Unsupported model: 'deepseek-v4-pro'`
- Gateway `https://api.tokenic.cn/v1/messages`，`stream:true`：HTTP 200，Request ID `202605210252509952869888268d9d6ByPRxmxn`
- Gateway `https://api.tokenic.cn/v1/messages`，`stream:false`：HTTP 400，Request ID `202605210252534292376298268d9d6VF3eOy22`，同样是上游 `Unsupported model`

---

### 2026-05-20 her-gateway CodingRouter deepseek-v4-pro 开通

> 摘要：在生产 Gateway 现有 `CodingRouter Anthropic` 渠道中新增 `deepseek-v4-pro`，走 Anthropic `/v1/messages` 格式，并补齐模型定价。

commit: 无代码变更 | 备份：`/tmp/her-gateway-codingrouter-before-deepseek-v4-pro-20260520-235324.json`、`/tmp/her-gateway-deepseek-v4-pro-price-before-20260521-001254.json` | 回滚：用备份恢复 channel 6 的 `models`，并从 `ModelRatio` / `CompletionRatio` / `CacheRatio` / `CreateCacheRatio` 中删除 `deepseek-v4-pro`，或恢复到备份中的旧定价。

**操作**：
- 渠道 6 `CodingRouter Anthropic` 的 `models` 增加 `deepseek-v4-pro`
- 定价：
  - `ModelRatio.deepseek-v4-pro = 6`
  - `CompletionRatio.deepseek-v4-pro = 2`
  - `CacheRatio.deepseek-v4-pro = 0.1`
  - `CreateCacheRatio.deepseek-v4-pro = 0`
- 未创建 `models` 元数据表记录；API 可用不依赖该记录，模型管理页展示才需要创建

**验证**：
- CodingRouter `/v1/models` 能返回 `deepseek-v4-pro`
- 直连 CodingRouter Anthropic stream `/v1/messages`：HTTP 200
- Gateway smoke：Request ID `202605201554527800907878268d9d65uWpGuzm`，channel 6，model `deepseek-v4-pro`，HTTP 200
- Gateway 日志计费参数读回：`model_ratio=6.25`、`completion_ratio=2`、`cache_ratio=0.1`、`cache_creation_ratio=0`
- 后续按用户要求调价：`ModelRatio=6`，即展示输入 `¥12/M`、输出 `¥24/M`、缓存命中 `0.1`
- `/api/pricing` 能返回 `deepseek-v4-pro`；`/api/models/missing` 也能看到该模型，说明它缺模型元数据展示记录但不影响 API 路由

**注意**：
- CodingRouter 对 `deepseek-v4-pro` 的 Anthropic 非流式 `/v1/messages` 当前返回 400：`Unsupported model: 'deepseek-v4-pro'`
- 按用户给的 `stream:true` 调用路径正常；非流式客户端暂时不要用这个模型。

---

### 2026-05-20 her-gateway MiMo 400 二次复查与最小复现

> 摘要：扩大时间窗后发现请求体日志上线后还有 4 个真实 MiMo 400 request，均来自 `shadle@test.her-Her` / token `217`，模型为 `mimo-v2.5-pro`。根因不是并发不足，而是 MiMo 对历史 `assistant tool_use` 的参数校验：当请求没有 top-level `thinking` 字段，且历史 assistant 只有 `tool_use`、没有 `thinking` block 时，MiMo 返回 `400 Param Incorrect`。

commit: 无代码变更 | 回滚：只读查询 + 三条小流量 synthetic smoke，无配置变更，无需回滚。

**操作**：
- 查询 `mimo%` 今日错误和成功分布
- 查询 MiMo 渠道配置：5/7/8/14/15 priority=0，9 priority=-1；均未配置 `max_concurrency_per_key`，且不是 multi-key
- 检查今日 MiMo 错误内容，没有 429 / 1302 / concurrent / rate limit 类错误
- 对 request body 日志做结构化检查
- 强制 channel 7 做三条 synthetic smoke

**证据**：
- 真实 400 request：`202605200826227891190018268d9d6JfZR4Vrb`、`202605200826281050933888268d9d6qBgS4vYu`、`20260520083140892378338268d9d6DUjH5ZnS`、`202605200831439022911148268d9d6ZrO6vA7c`
- 这些请求都在北京时间 `16:26` / `16:31`，路径均为同优先级互兜底后多个 MiMo 渠道全部 400
- 失败 upstream body 特征：`model=mimo-v2.5-pro`、`stream=true`、有 tools、历史 assistant content 只有 `tool_use`、没有 top-level `thinking`、没有 assistant `thinking` block
- synthetic `mimo-v2.5-pro` 无 thinking + assistant tool_use：`202605201546427350562598268d9d68Nwbgzm6`，HTTP 400
- synthetic `mimo-v2.5-pro` 加 assistant `thinking:" "`：`202605201546587058168138268d9d6YyTqaHmH`，HTTP 200
- synthetic `mimo-v2.5` 无 thinking + assistant tool_use：`202605201547186203880068268d9d6yUzrajVb`，HTTP 400
- synthetic `mimo-v2.5` top-level `thinking:disabled` + assistant tool_use：`202605201547535752674208268d9d6naC30IdK`，HTTP 200
- 北京时间 `18:20` 后除 synthetic 外没有新的用户 MiMo 400；MiMo 成功仍在继续，最新成功到 `23:12`

**结论**：
- 不是 Gateway 并发不足：没有配置 Gateway per-key 并发限制，也没有并发/限流类错误。
- 不是新增账号本身导致：新 channel 14/15 有成功请求；失败是同一个 payload 形状在多个渠道都被拒。
- 修复方向：MiMo adaptor 需要处理 `thinking == nil` 的 tool_use 历史；可在有 assistant `tool_use` 且缺 top-level thinking 时补 `thinking: disabled`，enabled/adaptive 时继续注入最小 thinking block。

---

### 2026-05-20 her-gateway MiMo 400 复查

> 摘要：复查生产 MiMo `status_code=400, Param Incorrect`。请求体日志上线后未再出现 MiMo 400；最近一组 400 发生在请求体日志上线前，无法回看原始 body，但普通日志显示是单请求 payload 被 7/5/8/9 全部立即拒绝，不像渠道故障。

commit: 无代码变更 | 回滚：只读查询 + 两条小流量 smoke，无配置变更，无需回滚。

**操作**：
- 用 Admin API 查询 `mimo-v2.5` 错误日志
- 用 `GET /api/log/request_body` 查询旧 400 request id，确认上线前请求没有 body 快照
- 检查旧容器落盘日志 `/etc/dokploy/compose/her-newapi-e91gqn/code.bak.1779252070/logs/oneapi-20260519144929.log`
- 用线上真实链路构造 “thinking enabled + 历史 assistant tool_use 缺 thinking” 请求，强制 channel 7 验证 thinking 注入
- 用线上真实链路构造 “thinking enabled + redacted_thinking 无 tool_use” 请求，验证 MiMo 不会因此 400

**验证**：
- 请求体日志上线后，`mimo-v2.5` error total：0
- 请求体日志上线后，`mimo-v2.5` consume total：22
- 旧 400 Request ID：`202605200348226000353948268d9d6Rk6zI9xD`，北京时间 `2026-05-20 11:48:22`，路径 `7->5->8->9`
- 同用户同 token 在旧 400 前 3 秒有 channel 7 成功请求；请求体日志上线后也有成功请求
- synthetic tool_use smoke：`20260520101859413343738268d9d6RETrHK04`，channel 7，HTTP 200；upstream body 有 `thinking:" "`，inbound body 没有
- synthetic redacted smoke：`20260520102034728638738268d9d6G1868T0B`，channel 7，HTTP 200；upstream body 原样包含 `redacted_thinking`

**结论**：
- 当前没有证据表明 MiMo 渠道整体故障，也没有证据表明 thinking 注入失效。
- 旧 400 更像某一轮会话 payload 本身有 MiMo 不接受的参数或消息结构；当时没有请求体日志，无法继续还原。
- 下次如果再出现 400，应直接用 `GET /api/log/request_body?request_id=<id>&include_body=true` 对比 inbound 和 upstream body。

---

### 2026-05-20 her-gateway 全量请求体日志发布

> 摘要：发布 Gateway 请求体日志功能。全局默认开启，每个 request id 最多保留一份 inbound 和一份最终 upstream 请求体，保留 7 天，超过后后台任务自动清理。

commit: `5339575e6` | PR: `https://github.com/her-os/her-gateway/pull/6` | 分支：`suyuan-05-20-request-body-logging` | 回滚：使用服务器上一版代码目录 `/etc/dokploy/compose/her-newapi-e91gqn/code.bak.1779252070` 重新构建并替换 `new-api`；或合并回滚提交后按 Gateway 标准发布流程重新部署。

**操作**：
- 新增 `request_body_logs` 表，写入 `LOG_DB`
- 新增 `REQUEST_LOG_ENABLED`、`REQUEST_LOG_RETENTION_DAYS`、`REQUEST_LOG_CLEANUP_INTERVAL_MINUTES`，默认分别为 `true`、`7`、`60`
- 新增 Admin API：`GET /api/log/request_body`
- relay 入站请求写 `stage=inbound`
- 发给上游前的最终请求写 `stage=upstream`
- 自动降级多次尝试时，同一个 request id 的 upstream 只保留最终一次
- 使用 `scripts/gateway/deploy.sh` 上传代码；标准 build 又卡在 runtime apt 层后，按既有 runbook 用 `--target builder2` 产出新二进制，再基于旧 runtime 镜像替换 `/new-api`
- 通过 `docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api` 重建生产容器

**验证**：
- 本地通过：`go test ./model ./relay`、`go test ./controller ./service ./model ./relay`、`go test ./relay/channel/mimo ./relay/common`、`git diff --check`
- `go test ./...` 仍只失败于既有 `relay/channel/claude` 三个文件内容转换测试，和本次改动无关
- 生产容器镜像切到 `sha256:8217cc284396cfba5d3ee74fc828c0dbd13c4b67fd61bc3f49fb8601fc53e314`
- `new-api` healthy，仍在 `dokploy-network` 和 `her-newapi-e91gqn_new-api-network`
- `https://api.tokenic.cn/api/status` HTTP 200
- 线上 smoke Request ID：`20260520045305190533988268d9d6vDrjtE4V`
- smoke 请求在 `request_body_logs` 中有且只有两条：`inbound attempt=0 channel=0 body_bytes=83`、`upstream attempt=1 channel=5 body_bytes=82`
- Admin API 查询该 request id 返回 `success=true`

**坑**：
- 主机 `127.0.0.1:3000` 是 Dokploy 页面，不是 Gateway；线上 smoke 需要走生产域名或容器网络。
- 当前生产 compose 已改成本地镜像 `her-newapi-e91gqn-new-api:latest` 且 `pull_policy: never`；直接 Dokploy Redeploy 可能不等价于这次运行中的本地镜像。

---

### 2026-05-19 her-gateway MiMo retry/thinking 正式发布

> 摘要：PR #5 合并到 `main` 后发布生产 Gateway，启用 MiMo thinking block 注入、同优先级互兜底、PipeLLM 同渠道一次重试开关，并清理 MiMo 关闭 thinking 的 param_override。

commit: `49eff526` | PR: `https://github.com/her-os/her-gateway/pull/5` | 回滚：优先用 `/tmp/her-gateway-channel-config-before-mimo-retry-20260519-145132.json` 恢复渠道配置；镜像回滚可用服务器 tag `her-newapi-e91gqn-new-api:runtime-base-20260519144910`

**操作**：
- PR `suyuan-05-19-mimo-peer-retry-pr` 合并到 `main`
- 使用 `scripts/gateway/deploy.sh` 的标准路径上传代码并服务器 build
- build 卡在 runtime apt 层后，按文档 fallback：`--target builder2` 复用缓存编译二进制，再基于旧 runtime 镜像替换 `/new-api`
- `docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api`
- 清空 MiMo 渠道 5/7/8/9 的 `param_override`
- 给 PipeLLM 渠道 12 设置 `setting.retry_strategy=same_channel_once_then_fallback`

**验证**：
- 容器镜像切到 `sha256:68a40ac42ac187df186192a7d0f1a054eb2bcc0c1a0233a89f7ce3000e7a478f`
- `new-api` 约 31 秒后 healthy，仍在 `dokploy-network` 和 `her-newapi-e91gqn_new-api-network`
- `api.tokenic.cn/api/status` HTTP 200
- `api.roome.cn/api/status` HTTP 200（按健康脚本使用 `--insecure`；证书仍是既有 Traefik 自签名警告）
- `health-check.sh` 全部通过
- 线上 MiMo thinking smoke：Request ID `2026051906524394032948268d9d6nngQlJHU`，channel 8，HTTP 200，返回 `text + thinking`，`cache_read_input_tokens=448`
- 配置读回：5/7/8/9 `param_override_len=0`；12 `retry_strategy=same_channel_once_then_fallback`

**坑**：
- 标准 build 仍会卡在 runtime `apt-get update && apt-get install ...` 层；这次未切流量前终止 build，再用 builder2 fallback 发布。
- Dokploy Redeploy 可能回到 registry 版本；本次生产实际运行的是服务器本地镜像。

---

### 2026-05-19 her-gateway MiMo fallback 与 thinking 本地验证

> 摘要：同步生产 Gateway PostgreSQL 到本地快照库，用当前工作区代码构建本地 Docker 镜像并验证 MiMo thinking 注入、同优先级 fallback、渠道级同渠道一次重试代码路径。

commit: 未提交（本地任务分支 `suyuan-05-19-mimo-peer-retry`） | 回滚：停止并删除本地容器 `her-gateway-codex-local`，恢复到上一版代码；生产未改配置、未部署

**操作**：
- 用生产 Postgres 18 容器内 `pg_dump` 导出 `newapi`，恢复到本地 `newapi_local_prod`
- 本地容器：`her-gateway-codex-local`
- 本地地址：`http://127.0.0.1:3004`
- 镜像：`her-gateway-codex-local:20260519`

**验证**：
- `go test ./controller ./service ./model ./relay/channel/mimo` 通过
- `git diff --check` 通过
- `go test ./...` 仍只失败于既有 `relay/channel/claude` 三个文件内容转换测试
- Docker build 完成，前端 Vite build 在镜像构建中通过，只有既有 chunk / Browserslist 警告
- MiMo thinking 真请求通过：历史 assistant `tool_use` 缺 thinking block 时，Gateway 注入最小 thinking，上游返回 HTTP 200、text + thinking、cache_read tokens
- MiMo fallback 故障注入通过：临时打坏本地 7 号 MiMo base_url，请求路径为 `7 -> 5`，未直接降到 9；测试后已恢复本地 base_url 与 ability 权重

**坑**：
- 本地 `MemoryCacheEnabled=false` 时走数据库查询路径，最初只改内存缓存路径会漏掉同优先级互兜底；已补 `GetChannelExcluding`
- 本地旧二进制 3002 和旧 Docker 3001 不是本次代码；本次验证使用 3004 的 `her-gateway-codex-local`
- 生产 MiMo 渠道仍有关闭 thinking 的 `param_override`，代码注入发生在 param_override 前，因此条件会因已存在 thinking block 而不再触发关闭；上线后仍建议按计划清理该 override

---

### 2026-05-18 Claude SDK 渠道黏性规则

> 摘要：为避免 Claude SDK 请求在 12/13/11 之间跨请求反复跳转、导致上游 prompt cache 命中变差，新增两条 channel affinity 规则。客户端传 `X-Her-Session-Id` 时按会话 30 分钟黏住成功渠道；客户端暂未传该 header 时，临时按 `token_id + model + group` 30 分钟黏住成功渠道。

**操作**：
- `channel_affinity_setting.rules` 新增 `claude sdk session cache`
  - key：header `X-Her-Session-Id`
  - TTL：1800 秒
  - `skip_retry_on_failure=false`
- `channel_affinity_setting.rules` 新增 `claude sdk token cache fallback`
  - key：`context_int/token_id`
  - TTL：1800 秒
  - `include_model_name=true`
  - `skip_retry_on_failure=false`
- 保留原 `claude cli trace`，且规则顺序在新规则之前；Claude Code 仍走原规则。

**备份**：
- session 规则前：`/tmp/her-gateway-channel-affinity-rules.before-claude-sdk-20260518192818.json`
- token fallback 前：`/tmp/her-gateway-channel-affinity-rules.before-claude-token-fallback-20260518193213.json`

**回滚**：
- 用 Admin API 恢复上述备份中的 `channel_affinity_setting.rules`，或删除 `claude sdk session cache` / `claude sdk token cache fallback` 两条规则。

---

### 2026-05-18 relay nginx body limit 提升到 100M

> 摘要：按用户确认，将 BandwagonHost LA relay 服务器上三个 Claude 相关反代的 `client_max_body_size` 从 10M 提升到 100M，避免大 Claude `/v1/messages` 请求在到达上游前被 nginx 直接 413。

**操作**：
- 服务器：`bwg-la`
- 配置文件：
  - `/etc/nginx/sites-available/relay`
  - `/etc/nginx/sites-available/relay-pipellm`
  - `/etc/nginx/sites-available/relay-codingrouter`
- 备份：同目录 `.bak-20260518041013`
- `nginx -t` 通过，已 `nginx -s reload`

**验证**：
- `nginx -T` 当前加载配置中 3 处均为 `client_max_body_size 100M`

**回滚**：
- 将上述 3 个文件恢复为 `.bak-20260518041013`，再执行 `nginx -t && nginx -s reload`

---

### 2026-05-18 her-gateway 用户会话大请求 413/500 排查

> 摘要：只读排查用户 `lolihahaha7777@gmail.com-Her` 的 Claude 会话错误。结论是单会话历史里嵌入了大量图片/base64，导致请求体超过 relay nginx 10M 限制；12/13 的 413 先发生在 `relay-pl.tokenic.cn` / `relay.tokenic.cn`，不是供应商模型上下文不足的直接证据。Evolink/CodingRouter 在部分 fallback 上 300s 后 `do request failed`，不是 gateway 全局故障。

**范围**：
- 未改生产配置、未重启服务、未改数据库。
- 对话 JSON session_id：`600c7e90-a4e9-4102-b010-11427a1f0c87`。
- 当前对齐的 gateway request_id：`202605180640327109545028268d9d6aOp5A4Mx`。

**证据**：
- 会话 JSON 中 98 段嵌入图片数据，总 base64 约 12.3M。
- relay 服务器 `bwg-la` 的 `relay.tokenic.cn`、`relay-pl.tokenic.cn` nginx server block 均配置 `client_max_body_size 10M`；nginx error log 命中 `client intended to send too large body: 11786964 bytes`，并对 `POST /v1/messages` 返回 413。
- 当前 request 成功日志显示 `cache_creation_tokens=157098`，先后尝试渠道 `12 -> 13 -> 11`；同会话多次 fallback 到 11 后，下一次请求仍从 12/13 开始。
- 渠道 12/13/11 的 `claude-opus-4-6` 当前已映射到 `claude-sonnet-4-6`，因此“换 1M 模型”不是这次 413 的主要解法；先要处理 relay body size 和会话级 sticky。
- 同一时间段错误日志 82 条中，该用户占 70 条；不是供应商全局不可用。
- `compare-upstream-log.py` 对 Evolink `/api/log/token` 返回 403，未拿到上游 request id。

**回滚**：无，只读排查。

---

### 2026-05-18 her-gateway 关闭 MiMo 流式首字强切

> 摘要：部署 commit `7d5b81693`。MiMo 模型（`mimo-*`）不再启用 stream first chunk failover；Claude、Gemini 等其他模型保持 30s 首字超时切换、sticky 和供应商降级统计。

**改动**：
- MiMo 流式请求不再创建首字超时 timer，不生成 `stream:first_chunk_timeout`。
- MiMo 不再读写 stream failover sticky，因此历史 sticky 到 9 号按量通道的记录会被代码忽略。
- 不改生产 channel 配置、tag、数据库或公开 API。

**验证**：
- 本地通过：`go test ./service ./controller ./middleware ./relay/helper ./relay/common ./relay/channel`
- 生产容器 image id：`sha256:c068889d8ffe96cea78e9891b0b7705c528b947794101556b97e4775d97dc7d7`
- 外部验证：`api.tokenic.cn/api/status` 200；`api.roome.cn/api/status` 200。
- 启动日志正常，部署后未见新的 MiMo `stream first chunk timeout`。

**部署备注**：
- 常规 build 在 runtime `apt-get update && apt-get install` 层卡住；已停止卡住的 build。
- 使用 `--target builder2` 产出 `/build/new-api`，再基于旧 runtime 镜像复制新二进制，最后 `docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api`。

**回滚**：
```bash
/usr/bin/ssh -n ubuntu@192.144.187.174 "sudo docker tag her-newapi-e91gqn-new-api:pre-7d5b81693-20260518160616 her-newapi-e91gqn-new-api:latest && cd /etc/dokploy/compose/her-newapi-e91gqn/code && sudo docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api"
```

---

### 2026-05-18 mudimewe 试用期延长 + claude-opus-4-6 映射到 sonnet 并调价

> 摘要：两项操作——(1) 延长牟頔试用期一个月；(2) 所有渠道的 claude-opus-4-6 通过 model_mapping 映射到 claude-sonnet-4-6，并将 ModelRatio 从 17.5 改为 10.5 使计费按 sonnet 价格。

**操作 1：试用期延长**（用户 `mudimewe@gmail.com`，user_id `30eecba6-b291-4319-8236-4cd16a96e83c`）：
- `user_invite.trial_ends_at`：`2026-05-21 08:18:39.503` → `2026-06-21 08:18:39.503`（UTC，北京时间 6/21 16:18:39）
- 额度未改动，仅延长试用期

**操作 2：claude-opus-4-6 → claude-sonnet-4-6 映射 + 调价**：
- 渠道 6 (CodingRouter Anthropic)、11 (Evolink)、12 (pipellm)、13 (imarouter) 的 model_mapping 新增 `"claude-opus-4-6": "claude-sonnet-4-6"`
- `options` 表 `ModelRatio` 中 `claude-opus-4-6` 从 17.5 改为 10.5（与 claude-sonnet-4-6 一致）
- 重启 new-api 刷新内存缓存
- 测试验证：请求 claude-opus-4-6 返回 model=claude-sonnet-4-6，新请求 quota 按 sonnet 价格计费
- 注意：旧请求已扣额度不追溯，仅新请求生效

**回滚**：
```sql
-- 试用期回滚
UPDATE user_invite SET trial_ends_at = '2026-05-21 08:18:39.503' WHERE user_id = '30eecba6-b291-4319-8236-4cd16a96e83c';

-- ModelRatio 回滚（base64 方式执行）
UPDATE options SET value='{"glm-5": 3.0, "glm-5.1": 4.0, "mimo-v2.5": 1.4, "glm-5-turbo": 3.5, "mimo-v2-pro": 3.5, "mimo-v2.5-pro": 3.5, "claude-opus-4-5": 17.5, "claude-opus-4-6": 17.5, "claude-opus-4-7": 17.5, "claude-sonnet-4-6": 10.5, "claude-haiku-4-5-20251001": 0.5}' WHERE key='ModelRatio';
-- 然后重启 new-api
```
- model_mapping 回滚：通过 `PUT /api/channel/` 从 4 个渠道的 model_mapping 中删除 `"claude-opus-4-6": "claude-sonnet-4-6"` 条目

---

### 2026-05-17 her-gateway 流式首字超时切换上线

> 摘要：部署 commit `6062f4812`，新增流式请求首字 30s 超时自动切换、供应商慢首字按比例临时降级、用户 sticky 到备用通道 30 分钟。非流式请求不切换。

**操作**：
- 本地用生产库副本 + fake upstream 验证：慢流式 2s 超时切换，4 个用户触发供应商降级，第 5 个用户直接走备用通道。
- 生产 build 到镜像 `her-newapi-e91gqn-new-api:latest`，容器 image id `sha256:2aba03631d2d056844f8dca8936fce1d45b7b9a8d10e37f0c3c4a47d8776cde7`。
- 旧镜像保留为 `her-newapi-e91gqn-new-api:pre-6062f4812-20260517130416`。
- 外部验证：`api.tokenic.cn/api/status` 200；`api.roome.cn/api/status` 200（服务器 curl 需 `-k`）。

**脚本修正**：
- `scripts/gateway/deploy.sh` 非 main 分支确认提示中的 `$BRANCH` 改为 `${BRANCH}`，避免中文标点旁变量名解析异常。
- compose recreate 固定 `-p her-newapi-e91gqn`，避免从 `code/` 目录执行时默认项目名变成 `code`。

**回滚**：
```bash
/usr/bin/ssh -n ubuntu@192.144.187.174 "sudo docker tag her-newapi-e91gqn-new-api:pre-6062f4812-20260517130416 her-newapi-e91gqn-new-api:latest && cd /etc/dokploy/compose/her-newapi-e91gqn/code && sudo docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api"
```

---

### 2026-05-17 klalaklilicheng 试用期延长 + 试用额度作废

> 摘要：延长用户试用期一个月（到 6/17 北京0点），同时作废试用额度让其无法使用。验证"试用期与试用额度独立控制"可行。

**操作**（用户 `klalaklilicheng@gmail.com`，user_id `eaf2ac64-ec9d-4924-89bb-811a6702e6e2`）：
- `user_invite.trial_ends_at` 从 `2026-05-17 05:00 UTC` → `2026-06-16 16:00 UTC`
- 3条 credit（gift + admin_grant + trial_policy_reduction）status → expired，remaining_credits → 0
- `user_gateway.quota_granted` → 0
- gateway `users.quota` (id=310) → 0
- gateway `tokens.remain_quota` (id=168) → 0

**效果**：用户 plan=trial 能进入系统，界面显示试用额度已过期，实际调用被 gateway 拒绝。

**回滚 SQL**：
```sql
-- her_web
UPDATE user_invite SET trial_ends_at = '2026-05-17 05:00:00' WHERE user_id = 'eaf2ac64-ec9d-4924-89bb-811a6702e6e2';
UPDATE credit SET status = 'active', remaining_credits = 285283890, updated_at = NOW() WHERE id = 'f2596ff3-cef7-4f3d-ab1e-f77fc887cb1a';
UPDATE credit SET status = 'active', remaining_credits = 0, updated_at = NOW() WHERE id IN ('54d50b58-948c-41c6-aef4-959b519308d6', 'a9f6a928-9c34-45af-833a-e99da2221485');
UPDATE user_gateway SET quota_granted = 1000000000, updated_at = NOW() WHERE user_id = 'eaf2ac64-ec9d-4924-89bb-811a6702e6e2';
-- newapi
UPDATE users SET quota = 285283890 WHERE id = 310;
UPDATE tokens SET remain_quota = 285283890 WHERE id = 168;
```

**新增文档**：`production-db-ops.md` 追加"延长试用期但作废试用额度"Runbook。

---

### 2026-05-17 测试号 h0uyosssy 试用期延长（验证用）

> 摘要：测试号 `5d9eb01c-1c1e-40dd-9399-1d58919be3b0` 延长 trial_ends_at 到 `2026-06-16 16:00 UTC`，用于验证"试用期延长 + 额度已过期"的界面表现。

---

### 2026-05-16 relay 反代新增 pipellm + CodingRouter 加速节点

> 摘要：在 BandwagonHost LA CN2 relay 服务器上新增两个反向代理，加速 gateway 到 pipellm（3.9x）和 CodingRouter（3.6x）的 API 访问。

**操作**：
- DNS：新增 `relay-pl.tokenic.cn`、`relay-cr.tokenic.cn` A 记录 → 104.194.94.116
- SSL：certbot 申请 Let's Encrypt 证书（到期 2026-08-14）
- nginx：新增 `/etc/nginx/sites-available/relay-pipellm`、`relay-codingrouter` 两个 server block
- nginx：`worker_connections` 从 768 提升到 4096
- cron：每 6h `nginx -s reload` 刷新上游 DNS 缓存
- gateway：渠道 12 (pipellm) base_url → `https://relay-pl.tokenic.cn`
- gateway：渠道 6 (CodingRouter) base_url → `https://relay-cr.tokenic.cn`
- topology.md：更新域名表和 SSL 证书表

**未改**：Evolink 直连已足够快（0.59s），不走 relay。

**回滚**：
1. gateway 渠道 12 base_url 改回 `https://cc-api.pipellm.ai`
2. gateway 渠道 6 base_url 改回 `https://api.codingrouter.com`
3. relay 服务器删除 nginx 配置并 reload：`rm /etc/nginx/sites-enabled/relay-{pipellm,codingrouter} && nginx -s reload`
4. DNS 删除 `relay-pl`、`relay-cr` 记录

---

### 2026-05-15 her-gateway 上游日志对比脚本

> 摘要：新增 gateway request_id 到 new-api 兼容上游 `/api/log/token` 的只读对比脚本和 runbook，方便排查 504、首段慢、上游继续跑完并计费等问题。

**操作**：
- 新增 `scripts/gateway/compare-upstream-log.py`
- 新增 `references/gateway/upstream-log-compare.md`
- 更新 `SKILL.md` / `index.md` 的 gateway 场景入口

**回滚**：删除上述新增文件，并从 `SKILL.md` / `index.md` 移除对应入口。

---

### 2026-05-15 release.sh 增加 report 缓存复用

> 摘要：传入 `ACCEPT_RELEASE_REPORT` 时，如果缓存的 report 文件存在且 `reportId` 匹配，跳过重新生成 report，直接复用。修复部署两步之间 Docker task ID 轮换导致 `reportHash` 变化、token 失效的问题。

**操作**：修改 `scripts/her-web/release.sh`，在调用 `release-check.sh` 前增加缓存命中判断。

**回滚**：删掉缓存判断块，恢复为始终调用 `release-check.sh`。

---

### 2026-05-15 her-web 部署 commit 6392d47 — block Pro年付→Max月付 + 按钮文案修复

> 摘要：Pro年付用户不能升级到 Max月付（三层拦截）。按钮显示"不可升级" + 下方小字"已有 Pro 年付订阅"。

**操作**：PR #118 合并 + release.sh 部署。

**回滚**：`rollback.sh` 回到 `13a035a`。

---

### 2026-05-15 her-web 部署 commit 13a035a — dashboard 重定向 + 首小时用量修复

> 摘要：PR #117 修复 PageHeader 控制台链接被 redirect 参数劫持 + Max 首小时用量被 floorHour 过滤排除。

**操作**：PR #117 合并 + release.sh 部署。

**回滚**：`rollback.sh` 回到 `8d83d0c`。

---

### 2026-05-29 普通 trial her-web 积分刷新

> 生产库按实时 scope 刷新 132 个普通 trial：全部 `credits=50000000`，`23473216@qq.com` 为已用满 `remaining_credits=0`，其余 131 人 `remaining_credits=50000000`；新增备份表 `credit_backup_trial_refresh_20260529t021930_scope` / `_credit`。回滚：按备份表恢复 `credit`，删除本次新增 `transaction_no LIKE 'trial-refresh-20260529t021930-%'` 记录。

### 2026-05-29 trial 代表影子账号

> prod-only：创建 4 个 `trial-*@test.her` 影子账号（密码 `test123456`），覆盖已用满、gateway 有历史用量、普通 fresh、补 active credit 四类 trial；同步 web/gateway 绑定并修正补 credit metadata。回滚：删除 `clone-trial-fullused`、`clone-trial-gateway-used`、`clone-trial-fresh`、`clone-trial-missing-credit` 及 gateway users `631-634`。

### 2026-05-29 23473216 trial 剩余额度改回未用

> prod-only：备份 `23473216@qq.com` credit 到 `credit_backup_23473216_trial_remaining_20260529t0238`，将 active trial `remaining_credits` 改为 `50000000`；当前 132 个普通 trial 全部为 `0/100w` 显示口径。回滚：用备份表恢复该用户 credit。

### 2026-05-29 trial 代表影子账号按最新口径刷新

> prod-only：备份并重建 4 个 `trial-*@test.her` 影子账号 web 数据，gateway users/tokens `631-634` 从源账号重新同步；4 个账号 active trial 均为 `credits=50000000` / `remaining_credits=50000000`。回滚：用 `*_backup_trial_clone_refresh_20260529t0248` 表恢复 web/gateway。

### 2026-05-29 gateway 绑定 token remain_quota 加 1000

> prod-only：备份 220 个 her-web 当前绑定 active gateway token 到 `tokens_backup_remain_quota_plus1000_20260529t0258`，并将 `tokens.remain_quota` 逐个加 `1000`；未改 `unlimited_quota`。回滚：用备份表按 token id 恢复 `remain_quota`。

### 2026-05-29 gateway 绑定 token remain_quota 加 500000000

> prod-only：备份同一批 220 个 her-web 当前绑定 active gateway token 到 `tokens_backup_remain_quota_plus500m_20260529t0303`，并将 `tokens.remain_quota` 逐个加 `500000000`；`451513@qq.com` token remain 变为 `493685951`。回滚：用备份表按 token id 恢复 `remain_quota`。

### 2026-05-29 gateway 绑定 user quota 加 500000000 并保底

> prod-only：备份 220 个 her-web 当前绑定 gateway users 到 `users_backup_quota_plus500m_20260529t033420Z`，`users.quota` 正常加 `500000000`，加完仍低于 `50000000` 的保底到 `50000000`；修后 user/token 均无非正额度。回滚：用备份表按 user id 恢复 `quota`。

### 2026-05-29 克隆 451513 / 280118709 试用账号

> prod-only：创建 `451513@test.her`、`280118709@test.her`（密码 `test123456`），复制源账号 trial/credit/gateway 状态并新建独立 gateway users `637/638`、tokens `394/395`；验证登录、usage weekly bypass、models 200。回滚：删除两个 clone 用户、account、invite、credit、user_gateway，并软删 gateway users/tokens，备份表后缀 `20260529t035530Z` / `20260529t035607Z`。

### 2026-05-15 her-web 4.28 沙龙试用到期调整到 5/17 13 点，关关到 5/18 13 点

> 摘要：按运营要求，把 `invite_code.note = '4.28沙龙'` 的 Max 试用到期调整为北京时间 `2026-05-17 13:00:00`，其中真实用户 `guanguan0987@gmail.com` / 关木麟单独调整为北京时间 `2026-05-18 13:00:00`。生产库按 UTC 存储，普通用户写入 `2026-05-17 05:00:00`，关木麟写入 `2026-05-18 05:00:00`，影响 33 行。

**操作**：
- 选择条件：`invite_code.note = '4.28沙龙'`
- 真实普通用户 16 个 + `@test.her` 测试副本 16 个：`trial_ends_at = 2026-05-17 05:00:00`（北京时间 5/17 13 点）
- 真实关木麟 `guanguan0987@gmail.com`：`trial_ends_at = 2026-05-18 05:00:00`（北京时间 5/18 13 点）
- `guanguan0987@test.her` 按测试副本处理，随普通 4.28 沙龙账号到北京时间 5/17 13 点

**验证**：
- SELECT 复查：`note=4.28沙龙` 共 33 条，真实普通 16 条到 5/17 13 点，测试副本 16 条到 5/17 13 点，真实关木麟 1 条到 5/18 13 点
- `door.zhou@gmail.com` 备注为 `看门`，未被本次更新影响，仍为北京时间 5/15 0 点
- 用真实关木麟当前 session 调 `https://hersoul.cn/api/user/info` 返回 `authorized:true`，`trialEndsAt:"2026-05-18T05:00:00.000Z"`，`modelChannelStatus:"active"`

**回滚**：
- 如需回到上一轮状态：普通 4.28 沙龙用户设回 `2026-05-16 16:00:00`，真实关木麟设回 `2026-05-17 16:00:00`。

---

### 2026-05-15 her-web 三池 admin + 数据修复上线

> 摘要：合并 3 个 PR（#105 quota cleanup, #107 AI slop copy, #111 admin three-pool display）到 main 并部署到生产（commit `6a5a1ac`，68 秒完成）。关闭 PR #108（Codex P1 反馈有效，admin 分支 BUG-002 已覆盖）。执行生产 DB 数据修复：批次 A-E（trial credit quotaKind）、批次 G（subscription credits_amount 回填 4 行）、批次 H（48 条 bulk grant wallet 修复）。全量验证通过。关闭 GitHub Issues #101 和 #65。

**部署过程卡点**：
1. `nonMainOverride` 生产 commit 导致 `TARGET_REMOVES_PRODUCTION_COMMITS` BLOCK → 验证 zero diff 后更新 `current.json`
2. SSH 传输超时（无 keepalive）→ 添加 `~/.ssh/config` ServerAliveInterval
3. `NOW_EPOCH` 不固定导致 token 死循环 → 两步调用模式

**回滚方法**：
- 代码：`rollback.sh` 回滚到 `e231e9e`
- 数据：从 `backup_credit_fix_20260514` / `backup_subscription_fix_20260514` 恢复
- 备份表 7 天后可清理

**skill 更新**：standard-deploy.md 新增三个 section（token 两步调用、SSH keepalive、nonMainOverride 处理）；SKILL.md 坑速查 +3 条（#14/#15/#16）

---

### 2026-06-04 gateway MiMo affinity soft limit

> 生产 `channel_affinity_setting.rules` 的 `mimo coding plan cache` 增 `active_channel_soft_limit=5`，TTL 保持 `1800`；随 gateway v0.13.1 重启加载。回滚：把该规则的 `active_channel_soft_limit` 删除或设为 `0` 后重启 `new-api`。

### 2026-06-11 test 环境启用 HTTPS（test.hersoul.cn）

> EdgeOne DNS 加 A 记录 `test.hersoul.cn → 192.144.187.174`（record-3r7ppdvkyw1o，仅 DNS 不加速），`her-test.yml` 加 4 个 domain router（web/websecure × web/test-gateway），Let's Encrypt 证书签发成功（到期 2026-09-09）。IP HTTP 入口保留为备用。回滚：`sudo cp /etc/dokploy/traefik/dynamic/her-test.yml.bak-20260611-https /etc/dokploy/traefik/dynamic/her-test.yml` + tccli 删 DNS 记录。

### 2026-06-12 test 库本地直连：socat 临时代理 + SSH 隧道

> test 双库（her-web-test-db-clone / her-gateway-test-db）无 published port 且宿主机不通 overlay；用 `docker run --rm --network dokploy-network -p 127.0.0.1:PORT:5432 alpine/socat tcp-listen:5432,fork tcp:<容器IP>:5432` + `ssh -L` 即可从本地以 postgres 协议直连（W3 迁移演练用）。用完 `docker stop` 即拆。注意：远程链路逐行 INSERT 1 行 1 RTT，批量写入脚本必须分批。

### 2026-06-12 K8s 迁移调查 + 集群访问通道建立

> 实测确认：K8s（cls-4n0yzaz7）与 CVM 共用云 PG 172.17.255.75 同两库（pg_stat_activity 验证）；K8s 部署=轮询 TCR 无 webhook；TCR=企业版基础版 664/月（计划迁广州个人版）。新增 `ops/k8s-cluster-access.md`（kubeconfig+隧道，RBAC 待管理员授权）。部署链路详见 her-cicd `context/k8s-deploy-pipeline.md`。

### 2026-06-12 Hermes 7x24 值守监控上线（圣何塞 VPS → 飞书）

> 圣何塞 VPS 的 Hermes v0.13→v0.16 升级 + ChatGPT 重登 + 飞书接入（白名单+home chat）；新增 cron `her-patrol`（15min 只读巡检，静默/告警/恢复三态）与 `her-daily-report`（北京 09:00 日报），生产机仅暴露 forced-command 只读检查脚本（实测无法执行任意命令）。详见 `ops/hermes-monitor.md`。回滚：`hermes cron pause her-patrol her-daily-report`。

### 2026-06-12 Hermes 加 5 分钟 gateway 错误监控 + 智谱渠道全部下线

> 新增 cron `her-gateway-errwatch`（5min 查 gateway 错误日志：4xx/5xx 全覆盖、404 聚合 ≥20 才报、同组错误 1h 去重、无错静默）。生产机诊断菜单升级为多子命令（status/logs/db-stats/gateway-channels/gateway-errors/gateway-quota），Hermes 装 her-ops skill 支持飞书对话诊断。应用户指令禁用全部智谱渠道 ch1/ch3/ch4（gateway 已弃用智谱模型，ch4 持续报 500"当前用户不存在coding plan"），禁用后 zhipu quota monitor 停止报错；gateway-channels 区分手动禁用（⊘ 不告警）/自动禁用（✗ 告警）。恢复渠道：`gw-admin.sh PUT /api/channel/ -d '{"id":N,"status":1}'`。坑：grep 日志抓 5xx 必须 `\b` 词边界（request_id 数字串会误中），详见 `ops/hermes-monitor.md`。

### 2026-06-12 K8s 零中断发布配置（her-web 探针 + 双服务 preStop）

> her 命名空间获开发权限后：her-web 加 readinessProbe(/zh:3000)+maxUnavailable=0，her-web/gateway 加 preStop sleep 15 → 滚动更新逐秒探测 0 失败（改前 her-web 每次发布断流 ~2s）。回滚：`kubectl apply -f ~/.config/her/backup-her-{web,gateway}-deploy-*.yaml`。

### 2026-06-12 her-test.yml 清理 roome.cn 废路由

> 删除 4 个 roome 路由块（her-test-web-router / her-test-api-router 及 websecure），test.hersoul.cn web+gateway 验证 200。回滚：`sudo cp /etc/dokploy/traefik/dynamic/her-test.yml.bak-20260612-roome-cleanup /etc/dokploy/traefik/dynamic/her-test.yml`。遗留 roome label 清理已列入 `ops/k8s-dns-switchover.md` 切换后清单。
