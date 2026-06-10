# 创建 test 账号 + gateway binding

## 范围

只用于 **test**。生产账号、生产额度、生产 API key 修改走单独高风险流程，不能套用本文。

目标不是“DB 里有一个 user”，而是完整可用账号：

1. her-web test 能正常注册/登录。
2. her-web test DB 有 `user_gateway` 绑定。
3. gateway test DB 有对应 `users` 和有效 `tokens`。
4. quota/API key 能通过正常 provisioning 路径生成。

禁止只用 SQL 直接插 her-web 用户后结束。

## 前置检查

```bash
CICD=/Users/suyuan/.claude/skills/her-cicd/scripts
HERDB=/Users/suyuan/.claude/skills/her-ops/scripts/her-db.sh
WEB=http://192.144.187.174:80
COOKIE=/tmp/her-test-account.cookie

bash $CICD/her-web/deploy-test.sh status
bash $CICD/her-web/deploy-test.sh verify-web-gateway
bash $HERDB test --check
bash $HERDB test-gw --check
/usr/bin/ssh ubuntu@192.144.187.174 \
  "sudo docker service inspect her-web-test --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' | grep '^AUTH_RATE_LIMIT_ENABLED=false$'"
/usr/bin/ssh ubuntu@192.144.187.174 \
  "for svc in her-web-test her-gateway-test; do sudo docker service inspect \$svc --format '{{range .Spec.TaskTemplate.ContainerSpec.Env}}{{println .}}{{end}}' | grep '^HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=' >/dev/null || exit 1; done"
```

检查点：

- web service 必须是 `her-web-test`，不能是 `her-herweb-a8y5ka`。
- web URL 必须是 test IP/test 域名，不能是 `https://hersoul.cn`。
- gateway 必须是 `her-gateway-test`，DB 必须是 `test-gw`。
- `her-web-test` 必须有 `AUTH_RATE_LIMIT_ENABLED=false`，否则批量注册/登录会被 better-auth 的生产模式默认限流挡住。
- `her-web-test` 和 `her-gateway-test` 必须都有 `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN`。

### test-only 限流规则

- web → gateway 内部调用不限流依赖 `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN`，web 和 gateway 必须同时有同一个 token；test/prod 都要保留。
- 注册/登录接口的 `Too many requests. Please try again later.` 来自 better-auth，不是 gateway。test 账号批量操作依赖 `AUTH_RATE_LIMIT_ENABLED=false`。
- Her 当前要求 test/prod 都关闭 better-auth rate limit：`AUTH_RATE_LIMIT_ENABLED=false`。本 runbook 只允许检查 test；不要在创建测试账号时改生产 service。

## 1. 走 her-web 正常注册/登录路径

优先用浏览器打开 `$WEB/zh/sign-up` 手动注册。需要命令行时，用 better-auth 正常 API。test 当前开启了 email verification，所以顺序必须是：注册 → 补 verified → 登录；不要注册后立刻登录。

```bash
EMAIL='person+test@example.com'
PASSWORD='replace-with-test-password'
NAME='Test User'
rm -f "$COOKIE"

curl -sS -c "$COOKIE" -b "$COOKIE" \
  -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\",\"name\":\"$NAME\",\"callbackURL\":\"$WEB/zh/dashboard\"}" \
  "$WEB/api/auth/sign-up/email"
```

不要用 SQL 伪造 `account` / `session` / password hash。

## 2. 只在 test DB 补 email verified，然后登录

```bash
bash $HERDB test "UPDATE \"user\" SET email_verified=true, updated_at=now() WHERE lower(email)=lower('$EMAIL') RETURNING id,email,email_verified;"

curl -sS -c "$COOKIE" -b "$COOKIE" \
  -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
  "$WEB/api/auth/sign-in/email"
```

如果 update 没有返回用户，停止。不要去生产库找。登录响应不能是 `Email verification required` 或 `Too many requests`。

## 3. 邀请码账号：先保留 pending invite

没有邀请码时跳过本节。

优先调用正常 pending endpoint。`signupUserId` 用注册响应里的 user id；拿不到时从 test DB 查：

```bash
USER_ID=$(bash $HERDB test "SELECT id FROM \"user\" WHERE lower(email)=lower('$EMAIL') LIMIT 1;" | tr -d '[:space:]')
INVITE_CODE='HCLUB-xxxx'

curl -sS -c "$COOKIE" -b "$COOKIE" \
  -H 'content-type: application/json' \
  -d "{\"email\":\"$EMAIL\",\"inviteCode\":\"$INVITE_CODE\",\"signupUserId\":\"$USER_ID\",\"callbackUrl\":\"$WEB/zh/dashboard\"}" \
  "$WEB/api/invite-codes/pending-signup"
```

如果 endpoint 因临时链路问题不可用，才允许在 **test DB** 补 pending 记录。列名必须是：

```sql
email, invite_code_id, invite_code, callback_url, expires_at, user_id
```

补完后，必须在已登录 cookie 下走正常完成接口：

```bash
curl -sS -c "$COOKIE" -b "$COOKIE" \
  -H 'content-type: application/json' \
  -d '{}' \
  "$WEB/api/invite-codes/complete-pending-signup"
```

## 4. 无邀请码账号：调用 gateway provisioning

```bash
curl -sS -c "$COOKIE" -b "$COOKIE" \
  -H 'content-type: application/json' \
  -d '{}' \
  "$WEB/api/user/provision-gateway"
```

如果是邀请码账号，一般 `complete-pending-signup` 已经调用 provisioning；仍可再调一次 `/api/user/provision-gateway`，该接口是幂等的。

## 5. 双库验证

先查 web test：

```bash
bash $HERDB test "
SELECT u.id, u.email, u.email_verified,
       ug.gateway_user_id, ug.token_id, left(ug.api_key, 12) AS api_key_prefix,
       ug.quota_granted, ug.revoked_at
FROM \"user\" u
LEFT JOIN user_gateway ug ON ug.user_id = u.id
WHERE lower(u.email)=lower('$EMAIL');
"
```

必须看到 `gateway_user_id`、`token_id`、`api_key_prefix`，且 `revoked_at` 为空。

再查 gateway test：

```bash
GW_USER_ID='<gateway_user_id>'
TOKEN_ID='<token_id>'

bash $HERDB test-gw "
SELECT id, username, quota, used_quota, deleted_at
FROM users
WHERE id = $GW_USER_ID;
"

bash $HERDB test-gw "
SELECT id, user_id, remain_quota, unlimited_quota, status, deleted_at
FROM tokens
WHERE id = $TOKEN_ID AND user_id = $GW_USER_ID;
"
```

最后跑全局绑定检查：

```bash
bash $CICD/her-web/deploy-test.sh verify-web-gateway
```

只要 web 有账号但 gateway 没绑定，流程就是失败。先修 provisioning 或绑定，不要把账号标记为可测。

## 清理 / 回滚（test only）

```bash
bash $HERDB test "
DELETE FROM user_gateway WHERE user_id IN (SELECT id FROM \"user\" WHERE lower(email)=lower('$EMAIL'));
DELETE FROM account WHERE user_id IN (SELECT id FROM \"user\" WHERE lower(email)=lower('$EMAIL'));
DELETE FROM session WHERE user_id IN (SELECT id FROM \"user\" WHERE lower(email)=lower('$EMAIL'));
DELETE FROM \"user\" WHERE lower(email)=lower('$EMAIL');
"
```

如果已经创建 gateway 用户/token，再按验证步骤拿到 `GW_USER_ID` 后只改 test-gw：

```bash
bash $HERDB test-gw "
UPDATE tokens SET deleted_at=now() WHERE user_id=$GW_USER_ID;
UPDATE users SET deleted_at=now() WHERE id=$GW_USER_ID;
"
```

不要重启 `her-herweb-a8y5ka`，不要碰 prod/gw 环境。
