# 部署到 Test 环境

> **绿灯操作**：Agent 可直接执行。

## 前置条件

- 需要测试的 her-web 代码已合入 `dev`
- 部署 worktree 的 `HEAD` 必须等于 `origin/dev`
- CI 验证构建通过（her-web / gateway）

## 环境概述

test 环境和生产 `hersoul.cn` 完全隔离，独立的 web/gateway/DB/Redis。

| 入口 | 作用 |
|------|------|
| `http://192.144.187.174:80` | her-web 测试版（首选入口） |
| `http://192.144.187.174:80/test-gateway` | gateway 测试版（Traefik stripPrefix） |
| `http://www.roome.cn` | her-web 测试版（域名未备案，公网可能被 DNSPod block） |

**脚本路径**：

```bash
CICD=~/.claude/skills/her-cicd/scripts
```

---

## 部署步骤

### 1. 部署 Her-Web

```bash
# 从 origin/dev 的干净 worktree 构建部署
git fetch origin dev
git worktree add -B deploy/dev-test /tmp/her-web-dev-test origin/dev
QUIET=1 $CICD/her-web/deploy-test.sh deploy-web /tmp/her-web-dev-test
git worktree remove /tmp/her-web-dev-test
```

`deploy-web` 使用固定 image tag `her-web:test-latest`（上一版保存为 `her-web:test-prev` 用于回滚）。已有 service 时用 `docker service update --force --update-order start-first`，不 rm + create。

`deploy-web` 默认只更新 `her-web-test` 代码和 env，**不刷新 DB、不覆盖 test 测试数据**。热更新时继续提交并合入 `dev`，然后重复上面的 `deploy-web`。

`deploy-web` 会固定写入两类不限流配置：
- `AUTH_RATE_LIMIT_ENABLED=false`：关闭 better-auth 登录/注册限流，支持批量测试账号操作。
- `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN`：从生产 web 继承，同步给 test web，用于 web → gateway 内部调用绕过 gateway 限流。

> **⚠️ 生产 vs 测试 service 名称**：`deploy-test.sh` 中断后需要手动 service update 时，**必须**更新 `her-web-test`（测试），**禁止**更新 `her-herweb-a8y5ka`（生产 hersoul.cn）。两者共享同一台机器，service 名字容易混淆。确认方法：`sudo docker service inspect <name> --format '{{json .Spec.TaskTemplate.ContainerSpec.Env}}' | grep APP_URL`。

部署完成后自动跑 `verify-web-gateway`，检查 gateway 绑定是否可用。

### 1a. 基于同事 PR 测试

不要用临时叠 PR 直接部署。正确流程：

1. 从同事 PR 分支创建补充分支，例如 `git switch -c feat/xxx origin/fix/subscription-page`
2. 提交你的补充改动并推远端
3. 创建 `feat/xxx → dev` PR，body 写明“包含 PR #166 + 本次补充”
4. CI 通过后合入 `dev`
5. 从 `origin/dev` 部署 test

### 2. 部署 her-gateway

```bash
QUIET=1 $CICD/her-web/deploy-test.sh deploy-gateway /path/to/her-gateway
```

直接 rsync 源码到服务器 + `DOCKER_BUILDKIT=1 docker build`（amd64 原生）。生产 + test gateway 共享 BuildKit cache。

test gateway 自动开启请求日志：`REQUEST_LOG_ENABLED=true`。

### 3. 刷新数据库（可选，默认不做）

只有用户明确说“同步生产数据”“刷新测试数据”“重置测试 DB”时才执行。普通部署和热更新不要刷新 DB：

```bash
# 推荐：同时刷新 web + gateway（保证 token binding 一致）
ALLOW_TEST_DB_REFRESH=1 $CICD/her-web/deploy-test.sh refresh-all

# 单独刷新
ALLOW_TEST_DB_REFRESH=1 $CICD/her-web/deploy-test.sh refresh-web-db
ALLOW_TEST_DB_REFRESH=1 $CICD/her-web/deploy-test.sh refresh-gateway-db
```

**优先用 `refresh-all`**：先刷 gateway DB → 再刷 web DB → token binding 基于最新 gateway 数据修复。单独刷会导致 token 不匹配。

`refresh-web-db` 安全修正：清空 session、改 app_url 为 test IP、改支付回调为 test IP、应用兼容 schema。

### 4. 验证

```bash
# 查看测试栈状态
$CICD/her-web/deploy-test.sh status

# 验证 web + gateway 绑定
$CICD/her-web/deploy-test.sh verify-web-gateway

# HTTP 检查
curl -s http://192.144.187.174:80/zh/pricing
curl -s http://192.144.187.174:80/test-gateway/api/status
```

不要把 `/zh/pricing` 200 当作部署完成——必须看 `verify-web-gateway` 通过（检查 gateway service 1/1 + web 容器能访问 gateway + active token 在 gateway DB 存在）。

同时检查 `her-web-test` env 中有 `AUTH_RATE_LIMIT_ENABLED=false` 和 `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN`；缺任意一个都不算完成。

### 5. 通知测试

群里发消息说明测试入口和测试内容。

---

## 刷新策略

| 场景 | 推荐动作 |
|------|---------|
| 测新代码 UI / API | 先合 `dev`，再 `deploy-web <origin-dev-worktree>` |
| 热更新 | 继续提交 → 合入 `dev` → 重跑 `deploy-web`，不刷新 DB |
| 需要生产用户/订单/权益快照 | `refresh-all`（推荐）或 `refresh-web-db` |
| 测 gateway 渠道、模型、价格配置 | `deploy-gateway <worktree>` + `refresh-gateway-db` |
| 测某个真实用户的状态 | 优先 `refresh-web-db`；只需单用户时用克隆脚本 |

---

## 生产影子账号克隆

脚本：`$CICD/her-web/clone-prod-user.py`

```bash
# 克隆生产用户到生产库里的影子账号（测试价 ¥0.01）
python3 $CICD/her-web/clone-prod-user.py SOURCE_EMAIL CLONE_EMAIL

# 预览 SQL
python3 $CICD/her-web/clone-prod-user.py SOURCE_EMAIL CLONE_EMAIL --dry-run

# 清理
python3 $CICD/her-web/clone-prod-user.py --cleanup CLONE_EMAIL
```

注意：该脚本当前连接生产 her_web / gateway，只能用于 `{local}@test.her` 这类生产影子账号。不要把它当成 test clone DB 写入工具。

克隆完成后如需立刻走支付测试，需重启生产 her-web 容器刷新 payment config 缓存（1h TTL）：
```bash
/usr/bin/ssh ubuntu@192.144.187.174 "sudo docker service update --force her-herweb-a8y5ka"
```

脚本自动：动态发现所有 FK 到 user 的表 → 逐表全量 INSERT SELECT → gateway API 创建 GW user + token → 追加 clone email 到支付测试白名单。新增表/字段时无需改脚本（除非非 FK 关联）。

---

## 支付测试

后台支付设置支持测试白名单：`payment_test_account_emails`（逗号分隔或 `*`）+ `wechat_test_amount=1` / `alipay_test_amount=1`（单位分，实付 ¥0.01）。

白名单内账号走完整支付闭环。定价页仍显示真实价格，测试金额只在生成二维码时覆盖。

**缓存注意**：`config` 表有 1 小时内存缓存。直接 psql 改 DB 必须重启 service 才生效，通过 admin 后台改会自动清缓存。

---

## 其他操作

```bash
# env 一致性审计（refresh-all 末尾自动跑，也可单独运行）
$CICD/her-web/deploy-test.sh audit-env

# 写 Traefik 路由
$CICD/her-web/deploy-test.sh write-routes
```

---

## 排障

### 公网 roome.cn 被 DNSPod 302

域名未备案，公网 HTTP 被 block page 拦截。用 IP 入口或 SSH 隧道：

```bash
/usr/bin/ssh -N -L 18080:127.0.0.1:80 ubuntu@192.144.187.174
curl --resolve www.roome.cn:18080:127.0.0.1 http://www.roome.cn:18080/zh/pricing
```

### Token binding 失效（401 Invalid token）

`/api/status` 200 但 `/v1/messages` 返回 401。原因：web DB 的 `user_gateway.api_key` 和新 gateway DB 的 `tokens` 表不匹配。

解决：跑 `refresh-all`（会自动修复 token binding），或手动 `refresh-web-db`。

### gateway 日志 duplicate key

`duplicate key value violates unique constraint "logs_pkey"` — 刷新后 sequence 没跟上。`refresh-gateway-db` 会自动修正 sequence，如果仍出现，手动修正。

### 事故信号（看到立即停下）

- test web env 里出现生产 `DATABASE_URL`
- test gateway env 指向生产 Redis
- Traefik test 文件里改了 `hersoul.cn` 或 `api.tokenic.cn`
- `refresh-gateway-db` 输出里出现 `ghcr.io` 或 `main` 浮动镜像
- `deploy-web` 来源不是 `origin/dev`
- `docker service update` 目标出现 `her-herweb-a8y5ka`
