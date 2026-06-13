# her-cicd changelog

> 存量归档：`changelog-archive/2026-05.md`。新条目 3 行封顶，格式见 SKILL.md。

### 2026-06-13 PR-4.1 合 dev + deploy test

> feat/refactor-p4 → PR #268 → dev（merge commit 825b52c）→ `deploy-test.sh deploy-web` @ 825b52c → T1 探针（旧表静默/gateway 零扣款/用量聚合正常/lazy 建池）全绿。回滚：`git revert 825b52c` on dev + redeploy。

### 2026-06-10 her-web-test 内存扩容（OOM 修复）

> P2.3a E2E 中 `her-web-test` 512MiB 限额 OOM（exit 139）一次；`docker service update --limit-memory 1024M --env-add NODE_OPTIONS=--max-old-space-size=768` 已生效（1/1，pricing 200，verify-web-gateway ok），`deploy-test.sh` create 块同步补上两参数，update 路径 `--env-add` 增量不冲掉。回滚：`sudo docker service update --limit-memory 512M --env-rm NODE_OPTIONS her-web-test` + 还原脚本两行。

### 2026-06-10 verify-web-gateway 批量化提速

> `deploy-test.sh` 的 `verify_test_web_gateway` 绑定检查从每用户 1 个 `docker run` psql（50 次容器冷启动）改为单容器 `(id, user_id) IN (...)` 批量查询 + shell 比对；实测 33.1s → 2.8s，输出与判定语义逐字不变（本地缺失分支模拟 + 真实环境 active_checked=50 双探针验证）。回滚：恢复 `deploy-test.sh.bak-batch-verify`。

### 2026-06-09 her-web P1 清理 PR → dev

> PR #231 更新为 P1.2-P1.6 合批清理（dead code + 社交登录/旧支付 Provider/英文站下线），`lint-and-test`、`build-and-push`、`trigger-codex` 均 success；未合入 dev、未部署 test。回滚：关闭 PR 或 revert `098eda5`。

### 2026-06-09 生产问题修复分支规则

> `hotfix.md` 改为：main/生产后发现问题默认从最新 main 新拉 fix/hotfix 分支；旧 PR 已 merged/closed 不继续追加；普通 follow-up 走 dev 测试，紧急 hotfix 可直接 PR→main，release 成功后自动 resync dev；SKILL.md 增加“生产发现问题/上线后继续修/已合 main 后继续改”触发词和路由。回滚：还原 hotfix.md 与 SKILL.md 对应段落。

### 2026-06-09 her-web v0.1.19 发布生产（#186 trial quota display）

> PR #224 合入 main，tag `v0.1.19`，`release.sh` 部署生产 commit `e124088`（postflight PASSED，dev 已与 main 同树无需重置）；修复用户/客户端/admin 的 Trial Credit 用量展示与 weekly sentinel 泄漏。回滚：`ssh ubuntu@192.144.187.174 "sudo docker service update --rollback her-herweb-a8y5ka"`。

### 2026-06-09 release.sh 临时 worktree 依赖前置

> `deploy-prod.md` 补充：传给 `release.sh` 的仓库若是临时/新建 worktree，先跑 `pnpm install --frozen-lockfile`，否则 TypeScript preflight 因缺 `node_modules` 阻断。回滚：删除该注意事项。

### 2026-06-09 生产部署不等待 CI

> 修正 `deploy-prod.md` / `merge-to-main.md` / `tag-release-flow.md`：Her-Web/gateway 的 GitHub Actions 只构建 GHCR/TCR 备份镜像和 draft Release，生产部署走服务器本地 build，tag 后可直接跑 release/deploy，不等 CI。回滚：还原上述文档说明。

### 2026-06-09 QUIET 模式压缩部署输出

> `deploy-test.sh` 的 `remote()` 在 `QUIET=1` 时捕获 SSH 子命令输出，成功静默、失败吐出捕获日志；deploy-web/deploy-gateway 成功只打印一行摘要，避免 docker build / DB 初始化刷屏。回滚：还原 deploy-test.sh 的 `remote()` 与摘要输出改动。

### 2026-06-09 her-web #186 admin trial 显示修复部署 test

> PR #223 合入 dev，`her-web-test` 从 `origin/dev` merge commit `b799328` 部署完成；admin 用户详情页试用积分改用 gateway 用量推算，复验 `remainingRmb=96.94689`。回滚：`git revert -m 1 b799328` 后重走 dev PR + deploy-test。

### 2026-06-09 her-web test 双库刷新

> `refresh-all` 同步生产到 test 的 gateway DB + web DB，`her-web-test` / `her-gateway-test` 均 1/1，`gateway_binding_check=ok`；未改代码。回滚：重新跑 `ALLOW_TEST_DB_REFRESH=1 deploy-test.sh refresh-all` 到目标快照。

### 2026-06-09 her-web #186 trial billing 修复部署 test

> PR #222 合入 dev，`her-web-test` 从 `origin/dev` merge commit `48d3463` 部署完成；修复 trial 剩余积分显示与 weekly sentinel 泄漏，未刷新 test DB。回滚：`git revert -m 1 48d3463` 后重走 dev PR + deploy-test。

### 2026-06-08 her-cicd skill 结构重整 + 流程修复

> SKILL.md 重整（删核心规则速记/已知坑/PR Review 工具链/决策边界，加系统概述，权限表三列合并）；merge-to-main 打 tag+部署合并为一次确认、新增远端分支检查、删分支清理步骤；merge-to-dev 删 watch Codex review 步骤；三仓库关闭 GitHub auto-delete head branch。

### 2026-06-07 her-web v0.1.15 发布生产（PR #211 内测批次自动化）

> PR #211（@Chuncheuk）合入 main，tag `v0.1.15`，`release.sh` 部署生产 commit `7952edf`（18s，全缓存，1/1，postflight PASSED）；内测批次自动化完整功能（官网申请→飞书表→群名单核对→发邀请码邮件→注册状态回填），无 schema 变更。dev 自动 resync（PR #212）。回滚：`ssh ubuntu@192.144.187.174 "sudo docker service update --rollback her-herweb-a8y5ka"`。

### 2026-05-31 her-web v0.1.14 发布生产（#192 修复购买开关间歇性 bug）

> PR #201 合入 main，tag `v0.1.14`，`release.sh` 部署生产 commit `2525e73`（无 schema/fingerprint 变更，直接 build+切换，current.json 写入、dev 自动 resync、lock 已清；独立复验 landing 200 / session 在线 / 1-1）；走完整 /bugfix 7-phase 修掉 v0.1.13 遗留的「一会表单一会关闭」——startJoinFlow 购买闸门原依赖 recover 成功(`json.code===0`)且困在 try 内，recover 抖动时泄露到购买表单。抽出纯函数 `decideJoinFlow`（闸门只看 purchaseOpen、与 recover 成败无关，recover 三态建模），10 用例单测锁定，pitfall 记入 `docs/specs/payment.md`。回滚：`ssh ubuntu@192.144.187.174 "sudo docker service update --rollback her-herweb-a8y5ka"`。

### 2026-05-30 her-web v0.1.13 发布生产（#192 待付款订单不受购买开关影响）

> PR #198 合入 main，tag `v0.1.13`，`release.sh` 部署生产 commit `c7023b6`（66s，1/1，postflight PASSED）；把 pending order 检查移到购买闸门之前，让已下单待付款用户在开关关闭时仍能完成支付。⚠️ 此修复不彻底（闸门仍依赖 recover 成功、困在 try 内），间歇性 bug 残留，已由 v0.1.14 彻底修复。回滚：`ssh ubuntu@192.144.187.174 "sudo docker service update --rollback her-herweb-a8y5ka"`。

### 2026-05-30 her-web v0.1.12 发布生产（#192 HerClub 购买开关 + 去邀请码门槛）

> PR #196 合入 main，tag `v0.1.12`，`release.sh` 部署生产 commit `20c68e7`（78s，1/1，postflight PASSED）；HerClub 购买开关 `herclub_purchase_open`（默认关）+ 买=已登录用户 AND 开关开（去掉邀请码门槛）。Codex review 👍 无大问题；release-check WARN 走 `CONFIRM_SMOKE=entitlement`（本变更不碰额度/entitlement）。回滚：`ssh ubuntu@192.144.187.174 "sudo docker service update --rollback her-herweb-a8y5ka"`。

### 2026-05-30 her-web #192 后续：去掉邀请码购买门槛 → dev/test

> PR #195 合入 dev，`her-web-test` 部署到 `4aaeb12`；反转 D4：买 = 已登录注册用户 AND 开关开，移除 createOrder/recover/前端三处 HerClub 邀请码 eligibility 闸门（保留函数+session eligible 字段作信息）。复验：非 eligible 用户开放态可下单/进表单/recover，关闭态仍被开关拦。回滚：`git revert -m 1 4aaeb12`。

### 2026-05-30 her-web #192 HerClub 购买开关 → dev/test

> PR #193 + 修复 PR #194 合入 dev，`her-web-test` 部署到 `639bf3f`（开关 `herclub_purchase_open`，默认关）；未刷新 test DB。E2E 全 11 AC 通过（直接读 config 表绕缓存，psql 改开关即时生效）。回滚：`git revert -m 1 639bf3f` 后重走 dev PR + deploy-test。

### 2026-05-29 Her-Web v0.1.11 发布生产（#190 club 邀请码 + #167 用户手册入口）

> #190（CLUB 邀请码可选 basic/max）+ #167（首页用户手册入口）合入 main，tag `v0.1.11`，`release.sh` 部署 commit `9e3fc3b` 到 `her-herweb-a8y5ka`（70s，1/1），hersoul.cn 200 + 手册入口生效。#167 与 main 冲突，手动合并 3 个 marketing 文件（lang+pricing/manual 共享样式）。回滚：`sudo docker service update --rollback her-herweb-a8y5ka`。

### 2026-05-29 修复 resync-dev.sh 的 gh pr create --json bug

> `resync-dev.sh` 用了 `gh pr create --json url -q .url`（create 不支持该 flag），导致 release 后自动重置 dev 失败（non-fatal）。改为直接取 create stdout 的 URL。本次发布手动补 PR #191 完成 dev=main。回滚：还原本次脚本改动。

### 2026-05-29 club 邀请码 tier 解锁，PR #190 → main

> CLUB 邀请码不再强制锁 max tier，HCLUB 前缀与 tier 选择解耦（可选 basic/max），清空失实的 hclub_description 文案。从最新 main 拉 `feat/club-invite-tiers`，仅取 5 个邀请码文件（含单测），刻意排除 dev 上的 billing-quota 积分显示改动（会致 32 用户假"用满"）。回滚：close PR #190 或 revert a6c1c52。

### 2026-05-29 CI/CD 流程重构（dev 重置 + Codex 并行 review + 放宽 review）

> 新建 `resync-dev.sh`（commit-tree 重置 dev=main，自动备份+7天prune+PR+admin merge），挂在 `release.sh` 末尾自动触发。`codex-auto-review.yml` 加 dev 分支 + synchronize 重审。文档全面重写：merge-to-dev/merge-to-main/branching-model/SKILL.md/CLAUDE.md。旧 `sync-dev.sh` 废弃。

### 2026-05-29 her-web dev 重新对齐 main + 重部署 test

> 上条 #186 cherry-pick 到陈旧 dev 导致 test 缺 #184（账单页积分显示成"元"）。用 `commit-tree` 造重置 commit（dev 树=main+#186），PR #188 合入 dev，重部署 test 到 `a61212e`。回滚：`backup/dev-before-reset-0529`(=旧 dev b678230)。

### 2026-05-29 Her-Web v0.1.6 发布生产

> PR #181 合入 `main` 并打 tag `v0.1.6`，`release.sh` 部署 commit `a47bda5` 到 `her-herweb-a8y5ka`，postflight/smoke 通过。回滚：`sudo docker service update --rollback her-herweb-a8y5ka`；数据已迁移时先按 her-ops 回滚数据。

### 2026-05-29 Her-Web v0.1.7 发布生产

> PR #182 合入 `main` 并打 tag `v0.1.7`，`release.sh` 部署 commit `57d6e19` 到 `her-herweb-a8y5ka`，修正 Admin trial 积分显示为 points；postflight/smoke 通过。回滚：`sudo docker service update --rollback her-herweb-a8y5ka`。

### 2026-05-29 fix trial 用户周上限回归，PR #180 → main

> 基于 prod 只读审计（137 trial 用户 7 天 max 已用 ¥730.6），定 `TRIAL_WEEKLY_LIMIT_CREDITS = 7,500,000`（¥750），修掉 trial 用户复用 Pro ¥12.5 兜底的回归。PR #180 直接 → main（dev 与 main 双向分叉严重，无法自动合并）。回滚：revert commit cbbb028。

### 2026-05-28 clone-prod-user 生产影子账号说明修正

> 本地 `scripts/her-web/clone-prod-user.py` 的 `GW_ADMIN` 改为 her-ops 实际路径，并修正 `ops/deploy-test.md`：该脚本写生产 her_web/gateway，只用于生产影子账号。回滚：还原本次脚本常量和文档改动。

### 2026-05-28 Max Pro 附赠额度修正部署 test

> PR #177 合入 `dev`，`her-web-test` 从 `origin/dev` merge commit `0b66e5b` 部署完成；未刷新 test DB。回滚：`sudo docker service update --rollback her-web-test`。

### 2026-05-28 Admin Max 积分显示修正部署 test

> PR #176 合入 `dev`，`her-web-test` 从 `origin/dev` merge commit `0e5b453` 部署完成；未刷新 test DB。回滚：`sudo docker service update --rollback her-web-test`。

### 2026-05-28 Max 额度修正部署 test

> PR #175 合入 `dev`，`her-web-test` 从 `origin/dev` merge commit `6e6dc4d` 部署完成；未刷新 test DB。回滚：`sudo docker service update --rollback her-web-test`。

### 2026-05-28 Plus/Pro/Max 权益层级部署 test

> PR #174 合入 `dev`，`her-web-test` 从 `origin/dev` merge commit `40cb00d` 部署完成；未刷新 test DB。回滚：`sudo docker service update --rollback her-web-test`。

### 2026-05-28 记录 AI 长会话 worktree 脏状态问题

> 新增 `context/agent-session-worktree-hygiene.md`，记录长会话连续修复、热部署、干净部署 worktree 后原仓库残留，以及 dev PR 合并后远端分支可能自动删除的问题；暂不改流程。

### 2026-05-28 WeChat 优惠券支付 PR 合入 dev

> PR #172 `fix/wechat-coupon-payment-amount` CI 通过并合入 `dev`，`origin/dev` 最新 merge commit `60c4f94`，包含修复 commit `dac6b5f`。此前 test 热部署已验证通过；未动生产。

### 2026-05-28 WeChat 优惠券支付 test 热部署

> 用户要求跳过 CI，临时本地提交 `dac6b5f` 直接部署 `her-web-test`，修复 WeChat `payer_total` 低于 `total` 时误判支付失败；未刷新 test DB、未动生产。回滚：`sudo docker service update --rollback her-web-test`。

### 2026-05-28 test/prod 不限流部署守卫

> her-web 增 `AUTH_RATE_LIMIT_ENABLED`，test/prod 部署入口固化 `AUTH_RATE_LIMIT_ENABLED=false` + `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN` 检查；gateway deploy 缺 bypass token 会拒绝重建。回滚：还原本次 her-web auth/config 与 her-cicd 脚本/文档改动。

### 2026-05-28 测试部署规则收口

> test 部署固定为 feat/补充分支 → dev PR → origin/dev 部署；`sync-dev.sh` 改为创建 PR，`deploy-test.sh` 阻止非 dev 来源/生产 service/默认 DB refresh。回滚：恢复本次 her-cicd skill 文档和脚本改动。

### 2026-05-28 her-web #166 + credits precision 部署 test

> PR #168 同步 dev 到 main，PR #169 将 #166 + `feat/credits-precision` 合入 dev，部署 `her-web-test` 到 `c9bed75`；修复 deploy-test schema patch 在缺 `invite_code`/`user` 表时误失败。回滚：`bash ~/.claude/skills/her-cicd/scripts/her-web/deploy-test.sh status` 后 `sudo docker service update --rollback her-web-test`。

### 2026-05-25 auto-review cron 配置 + filter 修复

> v0.1.4 修复飞书 Bitable compound filter 语法（`AND()` 函数式，非 SQL 风格）(#162)。服务器 cron `*/30 * * * *` 调 `/api/cron/auto-review`。飞书通知发送失败待查（bot 权限问题）。回滚 cron：`ssh ubuntu@192.144.187.174 "sudo crontab -l | grep -v auto-review | sudo crontab -"`

### 2026-05-25 her-web v0.1.3 发布

> 合并 #154（统一试用额度展示）+ #161（自动审核内测申请 cron）→ tag v0.1.3 → release.sh 部署生产，65s 完成。回滚：`ssh ubuntu@192.144.187.174 "sudo docker service update --rollback her-herweb-a8y5ka"`

### 2026-05-25 SKILL.md 密度重写

> 参照 her-ops 垂直切片方法论压缩：加路径定义 + 坑速查表 + PR Review 工具链 + changelog 格式规范 + 内容增删改规则。存量 changelog 归档。

### 2026-05-29 her-web v0.1.8 发布

> PR #183 合入 main，tag `v0.1.8`，`release.sh` 部署生产 commit `b3f8171`；trial 剩余显示改为读取 her-web credit ledger，gateway 用量仅保留为 gatewayTotal。回滚：`ssh ubuntu@192.144.187.174 "sudo docker service update --rollback her-herweb-a8y5ka"`。

### 2026-05-29 her-web v0.1.9 发布

> PR #184 合入 main，tag `v0.1.9`，`release.sh` 部署生产 commit `dfb9fd6`；用户账单页试用积分改为显示“已用 / 总量 积分”，与 admin 口径一致。回滚：`ssh ubuntu@192.144.187.174 "sudo docker service update --rollback her-herweb-a8y5ka"`。

### 2026-05-29 her-web v0.1.10 发布

> PR #185 合入 main，tag `v0.1.10`，`release.sh` 部署生产 commit `715bd46`；active trial 的 usage report 不再返回付费 weekly blocker。回滚：`ssh ubuntu@192.144.187.174 "sudo docker service update --rollback her-herweb-a8y5ka"`。

### 2026-05-29 her-web #186 部署 test

> `main→dev` 自动同步冲突后，PR #187 从 `origin/dev` cherry-pick #186 修复并合入，`her-web-test` 部署到 `b678230`；未刷新 test DB。回滚：`git revert -m 1 b678230` 后重新走 dev PR + deploy-test。

### 2026-06-04 her-gateway v0.13.1 发布

> PR #13 合入 main，tag `v0.13.1`，生产 `new-api` 部署到 commit `83b6e6a`；MiMo affinity 新绑定按渠道 soft limit 分散。回滚：`ssh ubuntu@192.144.187.174 'cd /etc/dokploy/compose/her-newapi-e91gqn/code && sudo mv docker-compose.yml.bak docker-compose.yml && sudo docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api'`。

### 2026-06-09 her-web P1.7 cleanup 部署 test

> PR #231 合入 `dev`，`her-web-test` 从 `origin/dev` merge commit `d2f38b4` 部署完成；未刷新 test DB。回滚：`sudo docker service update --rollback her-web-test`。

### 2026-06-10 her-web #233 #234 合 dev 并部署 test

> P2.2 大文件拆分（#233）+ P2.1 Codex review 修复（#234）合入 dev，`deploy-test` 部署 `e3e77c5`，deployed E2E PASS（记录在 her-web docs/refactor/verify/P2-validation.md）。回滚：dev 重新部署上一 merge commit。

### 2026-06-10 P2.3a 重构合入 dev 并部署 test

> PR #235（feat/refactor-p2 → dev，merge commit）：8 项纯函数/组件去重合并，净减 351 行。deploy-web@b399554 + verify-web-gateway ok，deployed E2E PASS。回滚：`git revert b399554`。
> 备注：E2E 期间 her-web-test 容器 OOM 一次（512MiB 限额、Node heap 默认 ~256MB），Swarm 自动恢复；与本次改动无关，test 容器内存配置待加固。

### 2026-06-10 P2.3b 重构合入 dev 并部署 test

> PR #236（feat/refactor-p2 → dev，merge commit）：requireUser 60 处 + handleRouteError 45 处横切抽取，响应壳 curl diff 逐字一致。deploy-web@46ad661 + E2E PASS。回滚：`git revert 46ad661`。

### 2026-06-10 P2.4 配置收口合 dev 并部署 test

> PR #237（env loader 合并 / 3 配置进 admin / QUOTA 常量化 / mock 生产硬禁用）+ #238（zh 文案修复）merge commit 合 dev `9d142a0`，deploy-test 两轮 verify-web-gateway ok。候选 main 不发布。回滚：`git revert -m 1 9d142a0 4801ff3`。

### 2026-06-10 P2.5 masking/审计/FEISHU 收口合 dev 并部署 test

> PR #239 + #240（Codex 3 条修复）merge commit 合入 dev `e8f177f`，deploy-test 两轮 + verify-web-gateway ok。回滚：`从 dev revert 两个 merge commit 后重跑 deploy-test.sh deploy-web`。

### 2026-06-10 P2.6 payment 拆分合 dev 并部署 test

> PR #242 纯结构拆分合入 dev `6f7a146`，deploy-test + verify-web-gateway ok，五支付入口壳逐字回归。回滚：`从 dev revert merge commit 后重跑 deploy-test.sh deploy-web`。

### 2026-06-10 P2 审计修复轮合 dev 并部署 test

> PR #244（saveConfigs 未改动不落行，防 env 兜底被 UI 保存固化）合入 dev `60823ee`，deploy-test + verify-web-gateway ok，deployed E2E 红转绿。回滚：`从 dev revert merge commit 后重跑 deploy-test.sh deploy-web`。

### 2026-06-11 P3-W1 合 dev 并部署 test（PR #247）

> naming prep + quota 新表 schema 合入 dev（`2b07b9e`，GitHub org 账单挡 CI，用户裁决 admin bypass，CI/Codex 补跑义务挂起）→ deploy-web + verify-web-gateway 通过；test 库手工应用两新表 DDL（空表）。回滚：`DROP TABLE pool_transaction; DROP TABLE quota_pool;` + `docker service update --rollback her-web-test`。

### 2026-06-11 test AUTH_URL 切域名修复浏览器登录

> deploy-test.sh WEB_URL 默认 IP→`https://test.hersoul.cn`（AUTH_URL/app_url/支付回调跟随），新增 `AUTH_TRUSTED_ORIGINS` 保留 IP 入口浏览器登录，安全闸改精确拦生产域名；config 表三行同步改域名，deploy-web 重建后两入口登录 POST 均过 origin 校验。回滚：`WEB_URL=http://192.144.187.174:80 deploy-test.sh deploy-web <worktree>` + config 表改回 IP。

### 2026-06-11 P3-G1 gateway external-billing 合 dev 并部署 test（her-gateway PR #14）

> token 级 external_billing meter-only path 合入 dev（`22ba27813`，账单挡 CI 继续 bypass）→ deploy-gateway 成功（bun integrity 抖动重试一次）；test 栈四条验收全过，wallet 回归无变化。回滚：`sudo docker service update --image her-gateway:test-prev her-gateway-test`（或重部署旧 dev）。

### 2026-06-11 W2 quota 管线核心合入 dev 并部署 test

> Her-Web PR #248（enforce-v2/settle/worker，纯新增）admin bypass 合入 dev `4cae8f2` → deploy-web + verify-web-gateway PASS。回滚：revert merge commit 后重跑 deploy-web。

### 2026-06-11 CI 政策：PR 只跑 Codex review

> Her-Web ci.yml 改 workflow_dispatch only、docker-build 去 PR 触发（用户裁决，代码验证本地跑）；PR #249。gateway #15/#16 修 external_billing admin-only + violation fee 短路并重部署 test。回滚：revert #249。

### 2026-06-11 P3 W3 迁移脚本合 dev + test 演练

> feat/refactor-p3 PR #254 merge 合 dev → deploy-test（ab9a3f5）→ test 克隆库全量迁移演练全绿。回滚：`rollback-pre-traffic.ts --execute`（test 克隆库）。

### 2026-06-11 W3 实现整体回退（用户裁定重做）

> feat/refactor-p3 force push 回 `a93c815`（W3 实现前），完整备份 `backup/w3-rollback-0611`（d3790ca）已推远端；dev 保留 PR #254、test 不重部署（用户裁定）。重做入口：`her-web docs/handoff-w3-redo-0611.md`。回滚（取回 W3 实现）：`git reset --hard d3790ca`。

### 2026-06-11 W3 回退收尾：test 双库从生产重刷 + 本地 rehearsal 重置

> 清理上一轮 W3 演练残留：refresh-gateway-db → refresh-web-db（顺序必须 gateway 先，否则 web 应用会在 gateway 重建窗口自动 re-provision 写出悬空绑定）→ verify-web-gateway 全绿；克隆库补回 quota_pool/pool_transaction 空表 DDL（dev 构建的 quota worker 需要）；本地 her_web_rehearsal 用 golden TEMPLATE 重置；test 会话已清空（已登录的测试账号需重新登录）。已知问题：deploy-test.sh 内置 repair_test_web_gateway_bindings 的 psql() 只取首行，COPY 多行绑定只修第 1 条，依赖它兜底会漏修。回滚：无需（恢复性操作）。

### 2026-06-12 W3-redo 合 dev + test 部署（PR #255/#256）

> her-web feat/refactor-p3 两轮 PR 合 dev（merge 不 squash；#255 与 dev 冲突 = 上轮回退实现的 verify 文档，整文件取本轮）→ deploy-test 成功（source=7f560f2）。test 克隆库全量迁移演练 + 生产只读 dry-run 全绿，证据见 her-web `docs/refactor/verify/P3-validation.md` W3-redo 章节。回滚：`gh pr revert` 两个 PR 或等 release 自动 resync-dev。

### 2026-06-12 W4 管线切换 PR #259 合 dev + test 部署

> feat/refactor-p3 → dev（merge 不 squash），test 栈部署 source=4504d30，verify-web-gateway PASS。
> 附带：test 全量 353 token 翻 meter-only（快照在 /tmp/token-cutover-test-snapshot*.json，回滚 `tsx src/scripts/quota-migration/token-cutover.ts --rollback`）。

### 2026-06-12 K8s 生产管线文档 + 构建缓存优化

> 新增 `context/k8s-deploy-pipeline.md`（双轨部署、tag 语义、紧急通道、待确认项），deploy-prod/rollback 加双轨提示。her-web 构建缓存迁 GHCR registry 消除 ~18min 全量构建（PR #260，已合 dev，待合 main）。回滚：revert PR #260。

### 2026-06-12 W4 修复窗口：her-web + gateway 双部署 test

> her-web PR #266（BUG-001/003/005 修复）合 dev 部署 test（source=e975eda）；her-gateway PR #17（上游 X-Oneapi-Request-Id 透传覆盖修复）合 dev 部署 test。探针全绿。回滚：`docker service update --image her-web:test-prev her-web-test`（gateway 同理 test-prev）。

### 2026-06-13 BUG-007 修复合 dev 并部署 test

> her-web PR #267（feat/refactor-p3 5ae6e97，stacked 第二轮，merge commit）合 dev=e844812 → deploy-web test 栈 + verify-web-gateway 通过。回滚：重部署 her-web:test-prev 镜像。
