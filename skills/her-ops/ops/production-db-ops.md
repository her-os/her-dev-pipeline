# her-web / gateway 数据库操作手册

> **不确定列名？** 先跑 `her-db <env> --schema <表>` 查运行时结构，不要猜。
> 本文档是缓存，运行时结构是真相。最后验证：2026-05-25。

## 快速连接

```bash
HERDB=~/.claude/skills/her-ops/scripts/her-db.sh

# 执行 SQL
bash $HERDB prod "SELECT id, name, email FROM \"user\" LIMIT 5"
bash $HERDB gw   "SELECT id, username, quota, used_quota FROM users LIMIT 5"

# 查表结构
bash $HERDB prod --schema user
bash $HERDB prod --schema              # 列出所有表

# 交互式 psql（需要复杂操作时）
bash $HERDB prod --connect

# 查连接信息（调试用）
bash $HERDB prod --check
```

**环境**: `prod`=her_web 生产 | `gw`=newapi 生产 | `test`=测试 her_web | `test-gw`=测试 gateway

**降级**：`her-db` 不可用时（如脚本损坏），直接 SSH:
```bash
SSH="/usr/bin/ssh ubuntu@192.144.187.174"
$SSH "PGPASSWORD='HerAgent#2026' psql -h 172.17.255.75 -U her -d her_web -t -A -c \"SQL\""
$SSH "PGPASSWORD='HerAgent#2026' psql -h 172.17.255.75 -U her -d newapi -t -A -c \"SQL\""
```

---

## 时区规则（关键）

**所有 timestamp 字段存 UTC，前端自动 +8 转北京时间。**

| 用户想要的北京时间 | 数据库应存的 UTC 值 | 转换 |
|-----------------|-------------------|------|
| 5/14 00:00:00 | 5/13 16:00:00 | -8h |
| 5/14 23:59:59 | 5/14 15:59:59 | -8h |

写入时间值**必须先减 8 小时**。

---

## 操作规范

1. **先 schema 后 SQL** — 操作不熟悉的表前，`her-db <env> --schema <表>` 确认列名
2. **先 SELECT 后 UPDATE** — 修改前先查当前值和影响行数
3. **WHERE 精确限定** — 能用主键就用主键，禁止无 WHERE 的 UPDATE/DELETE
4. **时间按 UTC** — 北京时间 -8h 存入
5. **改后立查** — UPDATE 后立即 SELECT 验证
6. **跨库同步** — 改 her_web 的 quota 相关字段时，同步改 gateway 的 users/tokens

---

## Schema Reference — her_web 库（prod）

### user

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | text PK | UUID |
| name | text | 昵称 |
| email | text UNIQUE | 邮箱 |
| email_verified | boolean | |
| image | text | 头像 URL |
| real_name | text | 真实姓名（邀请码 metadata 回写） |
| wechat_id | text | 微信号（邀请码 metadata 回写） |
| created_at | timestamp | |
| updated_at | timestamp | |
| utm_source | text | 注册来源 |
| ip | text | 注册 IP |
| locale | text | |
| her_club_tier | text | HerClub 等级 |
| her_club_source | text | |
| her_club_note | text | |
| her_club_granted_by | text | |
| her_club_granted_at | timestamp | |

> **常猜错**: 无 `role` 列（角色在 user_role 表）、无 `status` 列、无 `plan` 列、无 `gateway_token` 列、无 `quota` 列

### user_invite

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | text PK | |
| user_id | text | 关联 user.id |
| invite_code_id | text | 关联 invite_code.id |
| activated_at | timestamp | 激活时间 |
| trial_ends_at | timestamp | 试用到期（UTC） |

> **常猜错**: 无 `status` 列、无 `activated_by` 列、无 `tier` 列（tier 在 invite_code 表）

### invite_code

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | text PK | |
| code | text | 邀请码字符串 |
| max_uses | integer | |
| used_count | integer | |
| trial_days | integer | |
| note | text | 人读备注 |
| created_by | text | |
| expires_at | timestamp | |
| created_at | timestamp | |
| tier | text | pro/max/trial |
| balance_cents | integer | 额度（分） |
| is_hclub | boolean | |
| metadata | text | JSON（wechat/name） |

> **常猜错**: 无 `status` 列、无 `activated_by` 列

### credit

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | text PK | |
| user_id | text | |
| user_email | text | |
| order_no | text | |
| subscription_no | text | |
| transaction_no | text | |
| transaction_type | text | grant/consume/refund |
| transaction_scene | text | gift/admin_grant/trial_policy_reduction/subscription/payment |
| credits | bigint | 变动额度 |
| remaining_credits | bigint | 剩余额度 |
| description | text | |
| expires_at | timestamp | |
| status | text | active/expired/consumed |
| created_at | timestamp | |
| updated_at | timestamp | |
| deleted_at | timestamp | 软删除 |
| consumed_detail | text | |
| metadata | text | |

> **常猜错**: 列名是 `transaction_type` 不是 `type`，`credits` 不是 `amount`

### user_gateway

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | text PK | |
| user_id | text | 关联 user.id |
| gateway_user_id | integer | 关联 gateway users.id |
| gateway_username | text | |
| token_id | integer | 关联 gateway tokens.id |
| api_key | text | |
| quota_granted | bigint | 已授予 gateway 的总额度 |
| invited | boolean | |
| revoked_at | timestamp | |
| created_at | timestamp | |
| updated_at | timestamp | |

### subscription

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | text PK | |
| subscription_no | text | |
| user_id | text | |
| user_email | text | |
| status | text | |
| payment_provider | text | |
| subscription_id | text | 第三方订阅 ID |
| subscription_result | text | |
| product_id | text | |
| description | text | |
| amount | integer | |
| currency | text | |
| interval | text | |
| interval_count | integer | |
| trial_period_days | integer | |
| current_period_start | timestamp | |
| current_period_end | timestamp | 当前周期结束 |
| created_at | timestamp | |
| updated_at | timestamp | |
| deleted_at | timestamp | |
| plan_name | text | |
| billing_url | text | |
| product_name | text | |
| credits_amount | bigint | |
| credits_valid_days | integer | |
| payment_product_id | text | |
| payment_user_id | text | |
| canceled_at | timestamp | |
| canceled_end_at | timestamp | |
| canceled_reason | text | |
| canceled_reason_type | text | |
| product_line | text | |
| plan_id | text | |
| model_regions | text | |
| usage_policy_id | text | |
| source | text | |

> **常猜错**: 到期列是 `current_period_end` 不是 `expires_at`

### herclub_member

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | text PK | |
| card_number | text | 会员卡号 |
| nickname | text | |
| email | text | |
| status | text | |
| valid_until | timestamp | |
| order_no | text | |
| invite_code_id | text | |
| her_user_id | text | 关联 user.id |
| bound_at | timestamp | |
| source | text | |
| campaign | text | |
| created_at | timestamp | |
| updated_at | timestamp | |

> **常猜错**: 关联用户的列是 `her_user_id` 不是 `user_id`、无 `plan` 列

### config

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| name | text PK | 配置键 |
| value | text | 配置值 |

> **常猜错**: 键列是 `name` 不是 `key`（12 次历史错误）

### order

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | text PK | |
| order_no | text | |
| user_id | text | |
| user_email | text | |
| status | text | |
| amount | integer | |
| currency | text | |
| product_id | text | |
| payment_type | text | |
| payment_interval | text | |
| payment_provider | text | |
| payment_session_id | text | |
| checkout_info | text | |
| checkout_result | text | |
| payment_result | text | |
| discount_code | text | |
| discount_amount | integer | |
| discount_currency | text | |
| payment_email | text | |
| payment_amount | integer | |
| payment_currency | text | |
| paid_at | timestamp | |
| created_at | timestamp | |
| updated_at | timestamp | |
| deleted_at | timestamp | |
| description | text | |
| product_name | text | |
| subscription_id | text | |
| subscription_result | text | |
| checkout_url | text | |
| callback_url | text | |
| credits_amount | bigint | |
| credits_valid_days | integer | |
| plan_name | text | |
| payment_product_id | text | |
| invoice_id | text | |
| invoice_url | text | |
| subscription_no | text | |
| transaction_id | text | |
| payment_user_name | text | |
| payment_user_id | text | |

### account (better-auth)

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | text PK | |
| account_id | text | 第三方账号 ID |
| provider_id | text | google/github/credential |
| user_id | text | |
| access_token | text | |
| refresh_token | text | |
| id_token | text | |
| access_token_expires_at | timestamp | |
| refresh_token_expires_at | timestamp | |
| scope | text | |
| password | text | 凭证登录的密码 hash |
| created_at | timestamp | |
| updated_at | timestamp | |

> **常猜错**: 列名是 `provider_id` 不是 `provider`，`user_id` 不是 `userId`

### 其他 her_web 表（低频）

| 表名 | 关键列 | 用途 |
|------|--------|------|
| session | id, token, user_id, expires_at | better-auth 会话 |
| verification | id, identifier, value, expires_at | 验证码 |
| admin_user_note | user_id, note, updated_by | 管理员备注 |
| role | id, name, title, status | 角色定义 |
| user_role | user_id, role_id, expires_at | 用户-角色关联 |
| permission | id, code, resource, action | 权限定义 |
| role_permission | role_id, permission_id | 角色-权限关联 |
| manual_recharge | id, user_id, product_line, amount, operator_email | 手动充值记录 |
| usage_record | id, user_id, metric, amount, model | 用量记录 |
| pending_invite_signup | id, email, invite_code, user_id, redeemed_at | 待注册邀请 |
| ai_task | id, user_id, provider, model, status, cost_credits | AI 任务 |
| chat / chat_message | 聊天和消息 | Chat 功能 |
| apikey | id, user_id, key, title, status | API Key |
| post / taxonomy | CMS 内容 | 博客/CMS |
| herclub_order | id, order_no, email, amount_cents, status, member_id | HerClub 订单 |
| herclub_member_audit | member_id, action, detail | 会员操作审计 |
| herclub_sequence | key, current_value | 序号生成器 |
| her_club_audit | user_id, action, from_tier, to_tier | HerClub 等级审计 |

---

## Schema Reference — gateway 库（newapi / gw）

### users

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | bigint PK | 自增 |
| username | text | |
| password | text | |
| display_name | text | |
| role | bigint | 角色（1=普通 10=管理 100=root） |
| status | bigint | 状态（1=启用 2=禁用） |
| email | text | |
| github_id | text | |
| discord_id | text | |
| oidc_id | text | |
| wechat_id | text | |
| telegram_id | text | |
| linux_do_id | text | |
| access_token | char(32) | |
| quota | bigint | **剩余**额度（非总额） |
| used_quota | bigint | 已用额度 |
| request_count | bigint | |
| group | varchar(64) | 用户组（影响渠道路由） |
| aff_code | varchar(32) | |
| aff_count | bigint | |
| aff_quota | bigint | |
| aff_history | bigint | |
| inviter_id | bigint | |
| setting | text | |
| remark | varchar(255) | |
| stripe_customer | varchar(64) | |
| deleted_at | timestamptz | |

> **关键**: `quota` 是**剩余值**不是总额度。总额度 = quota + used_quota

### tokens

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | bigint PK | |
| user_id | bigint | |
| key | char(48) | sk-xxx |
| status | bigint | 1=启用 2=禁用 3=过期 4=耗尽 |
| name | text | |
| created_time | bigint | Unix 时间戳 |
| accessed_time | bigint | |
| expired_time | bigint | -1=永不过期 |
| remain_quota | bigint | |
| unlimited_quota | boolean | |
| model_limits_enabled | boolean | |
| model_limits | text | |
| allow_ips | text | |
| used_quota | bigint | |
| group | text | |
| cross_group_retry | boolean | |
| deleted_at | timestamptz | |

### channels

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | bigint PK | |
| type | bigint | 渠道类型 |
| key | text | API key |
| status | bigint | |
| name | text | |
| weight | bigint | |
| base_url | text | |
| models | text | 支持的模型列表 |
| group | varchar(64) | |
| model_mapping | text | |
| priority | bigint | |
| balance | numeric | |
| used_quota | bigint | |
| settings | text | |
| remark | varchar(255) | |
| 其他 | | test_model, other, tag 等 |

### logs

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | bigint PK | |
| user_id | bigint | |
| created_at | bigint | Unix 时间戳 |
| type | bigint | |
| content | text | |
| username | text | |
| token_name | text | |
| model_name | text | |
| quota | bigint | |
| prompt_tokens | bigint | |
| completion_tokens | bigint | |
| use_time | bigint | 耗时(ms) |
| is_stream | boolean | |
| channel_id | bigint | |
| channel_name | text | |
| token_id | bigint | |
| group | text | |
| ip | text | |
| request_id | varchar(64) | |

### options

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| key | text PK | 配置键 |
| value | text | 配置值（含 ModelRatio 等定价） |

> **注意**: gateway 的 options 用 `key`，her_web 的 config 用 `name`

### request_body_logs

| DB 列名 | 类型 | 说明 |
|---------|------|------|
| id | bigint PK | |
| request_id | varchar(64) | 关联 logs.request_id |
| stage | varchar(32) | inbound/upstream |
| attempt | bigint | |
| user_id | bigint | |
| model_name | text | |
| channel_id | bigint | |
| body | text | 请求体 |
| body_bytes | bigint | |
| read_error | text | |
| status_code | bigint | |

### 其他 gateway 表（低频）

| 表名 | 用途 |
|------|------|
| abilities | 模型-渠道能力矩阵 |
| models / vendors | 模型和供应商管理 |
| redemptions | 兑换码 |
| top_ups | 充值记录 |
| subscription_plans / subscription_orders / user_subscriptions | gateway 内部订阅 |
| quota_data | 配额数据 |
| tasks / midjourneys | 异步任务 |
| two_fas / two_fa_backup_codes / passkey_credentials | 2FA |
| custom_oauth_providers / user_oauth_bindings | OAuth |
| prefill_groups | 预填充组 |
| idempotency_records | 幂等记录 |
| checkins | 签到 |
| setups | 安装信息 |

---

## 高频 UPDATE 模板

### 查用户全貌

```sql
-- her_web：用户基本信息 + 邀请码 + 试用期 + credit + gateway 映射
SELECT u.id, u.name, u.email, u.her_club_tier,
       ui.trial_ends_at, ui.activated_at,
       ic.code, ic.tier, ic.trial_days,
       ug.gateway_user_id, ug.token_id, ug.quota_granted
FROM "user" u
LEFT JOIN user_invite ui ON ui.user_id = u.id
LEFT JOIN invite_code ic ON ic.id = ui.invite_code_id
LEFT JOIN user_gateway ug ON ug.user_id = u.id
WHERE u.email = 'xxx@example.com';

-- gateway：额度信息
SELECT id, username, quota, used_quota, quota + used_quota AS total, "group"
FROM users WHERE id = <gateway_user_id>;
```

### 延长试用期

```sql
-- 1. 查当前值
SELECT user_id, trial_ends_at FROM user_invite WHERE user_id = '<USER_ID>';

-- 2. 延长（北京时间 6/15 00:00 → UTC 6/14 16:00）
UPDATE user_invite SET trial_ends_at = '2026-06-14 16:00:00'
WHERE user_id = '<USER_ID>';

-- 3. 验证
SELECT user_id, trial_ends_at FROM user_invite WHERE user_id = '<USER_ID>';
```

### 延长试用期但作废试用额度

```sql
-- her_web 库 --

-- 1. 延长试用期
UPDATE user_invite SET trial_ends_at = '<UTC时间>'
WHERE user_id = '<USER_ID>';

-- 2. 作废试用 credit
UPDATE credit SET status = 'expired', remaining_credits = 0, updated_at = NOW()
WHERE user_id = '<USER_ID>' AND status = 'active' AND deleted_at IS NULL
  AND transaction_scene IN ('gift', 'admin_grant', 'trial_policy_reduction');

-- 3. 同步 user_gateway
UPDATE user_gateway SET quota_granted = 0, updated_at = NOW()
WHERE user_id = '<USER_ID>';

-- newapi 库 --

-- 4. 扣回 gateway quota
UPDATE users SET quota = 0 WHERE id = <GW_USER_ID>;

-- 5. 同步 token
UPDATE tokens SET remain_quota = 0 WHERE id = <TOKEN_ID>;
```

### 修改 gateway 额度

```sql
-- 查当前
SELECT id, username, quota, used_quota FROM users WHERE id = <GW_USER_ID>;

-- 设置剩余额度（注意 quota 是剩余值）
UPDATE users SET quota = <新剩余值> WHERE id = <GW_USER_ID>;

-- 同步 token
UPDATE tokens SET remain_quota = <新值> WHERE user_id = <GW_USER_ID> AND status = 1;
```

### 升降级 HerClub

```sql
-- 查当前
SELECT id, email, her_club_tier FROM "user" WHERE email = 'xxx@example.com';

-- 升级
UPDATE "user" SET her_club_tier = 'pro', her_club_source = 'admin',
  her_club_note = '手动升级', her_club_granted_by = 'admin',
  her_club_granted_at = NOW()
WHERE email = 'xxx@example.com';
```

---

## 数据修改检查清单

修改生产数据前：

1. **先 `--schema`**：确认表和列名存在
2. **先 SELECT**：确认影响范围、当前值、行数
3. **WHERE 精确限定**：避免全表 UPDATE
4. **时间字段按 UTC 转换**：北京时间 - 8 小时
5. **UPDATE 后立刻 SELECT 验证**
6. **跨库同步**：改 credit/quota → 同步 gateway users/tokens
7. **记录变更**：修改前后值 + 回滚 SQL
