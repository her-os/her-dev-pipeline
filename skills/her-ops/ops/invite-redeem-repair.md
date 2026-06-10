# 邀请码兑现中途失败 / 未绑定修复

> 症状：用户「注册成功、能正常用，但邀请码没绑定」。后台看 `user_invite` 缺失。
> 本质：邀请码绑定链路从未成功落库，而 gateway/会员是另外的路径开的。

## 唯一绑定入口（代码事实）

邀请码绑定**只有一条入口**：`POST /api/invite-codes/complete-pending-signup` → `redeemInviteCode()`
（`her-web/src/modules/invite-codes/service.ts`）。该事务一次成功会写齐：

- `user_invite`（绑定记录）
- `invite_code.used_count + 1`
- `user.her_club_tier / her_club_source / her_club_granted_at`
- `her_club_audit`（grant）
- 码若有预建 `herclub_member`（按 `invite_code_id` 关联）→ 绑定 + `herclub_member_audit`

之后 route 再跑 `provisionUser`（gateway+credit）和 `markPendingInviteSignupRedeemed`（设 `redeemed_at`）。

**`getRedeemedInviteProvisioning` 的 `invited` 只看 `user_invite` 表**——查不到就 false。

## 常见根因（两类）

1. **会员是管理员手动开通的**（最常见）。`subscription.source='manual'`、credit/subscription
   description 形如 `Manual provision/subscription: Pro / 深度版`。`admin/subscriptions.ts` 手动开通
   **完全不兑现邀请码**；且开通后 `getUserPlan` 返回 `member`，前端不再引导兑现 →
   `pending_invite_signup` 永远停在未兑现，`user_invite` 始终为空。
2. **自助兑现链路中断**：`complete-pending-signup` 没被前端调用 / 抛错 / `emailVerified` 卡住。
3. **单次码被同人的另一个号抢兑**：用户注册两个号填同一张 `max_uses=1` 码，码被另一号兑掉（`used_count` 已满、`user_invite` 属另一号），本号 redeem 被拒「已用满」，运营再 manual 开通补偿。
   - 此时**不能复用原码**（`used_count+1` 会超用、绑定会与另一号冲突）→ 新建一张同规格码再绑（`used_count` 直接置 1）。
   - 若决定把 manual 会员**降级到该码档位的试用**（非默认！需用户拍板），除上面补录外还要：`subscription` 置 `canceled`（移出 `USABLE_SUBSCRIPTION_STATUSES`=active/trialing/pending_cancel，plan 才翻 trial）、原 credit 转 `expired` 并补该档 gift credit、`user_gateway.quota_granted` 与 gateway `users.quota`/`tokens.remain_quota` 降到目标总额（剩余=目标总额−`used_quota`）。案例：2026-05-30 gengmin1990@163.com。

> ⚠️ 误区：「gateway 开了、有试用额度」≠「邀请码绑定了」。注册默认惰性开通走
> `/api/user/gateway`、`/api/user/quota` → `provisionUser`，发的是 `Signup gift`，**不读邀请码**。

## 诊断（her_web 库）

```bash
HERDB=~/.claude/skills/her-ops/scripts/her-db.sh
EMAIL='xxx@example.com'
bash $HERDB prod "SELECT u.id, u.email, u.email_verified, u.her_club_tier,
  ui.id IS NOT NULL AS bound, ui.invite_code_id,
  p.invite_code, p.redeemed_at IS NOT NULL AS redeemed,
  ug.gateway_user_id, s.plan_name, s.source AS sub_source
FROM \"user\" u
LEFT JOIN user_invite ui ON ui.user_id=u.id
LEFT JOIN pending_invite_signup p ON p.user_id=u.id
LEFT JOIN user_gateway ug ON ug.user_id=u.id
LEFT JOIN subscription s ON s.user_id=u.id AND s.status='active'
WHERE u.email='$EMAIL'"
```

判定：`bound=f` + `redeemed=f` + pending 有码 → 邀请码兑现未落库，需补录。
拿到 `invite_code` 后查码详情（tier / trial_days / balance_cents / is_hclub / max_uses / used_count）。

## 修复（事务，her_web 库）

复刻 `redeemInviteCode` 事务效果。**用 her-db stdin heredoc 传完整事务**（`used_count+1` 非幂等，
必须 BEGIN/COMMIT 原子化）。先 dry-run（把末尾 `COMMIT` 改 `ROLLBACK` 并加验证 SELECT）再正式跑。

要点：
- **时间 UTC**：`activated_at` 对齐 `user.created_at`，`trial_ends_at = activated_at + trial_days`
- **tier**：取 `invite_code.tier`，sanitize 规则 `pro/vip→basic`、`premium→max`、空→max
- **her_club_source**：码有预建 `herclub_member`（按 `invite_code_id` 查到）→ `herclub_purchase`，否则 `invite_code`
- **herclub_member**：若按 `invite_code_id` 查到且 `her_user_id` 为空 → 事务里再加绑定 + `herclub_member_audit`（本模板未含，按需补）
- `used_count+1` 加条件 `used_count < max_uses`，防超用

```bash
HERDB=~/.claude/skills/her-ops/scripts/her-db.sh
U1=$(python3 -c "import uuid;print(uuid.uuid4())")   # user_invite.id
U2=$(python3 -c "import uuid;print(uuid.uuid4())")   # her_club_audit.id
# 下列变量按诊断结果替换
USER_ID='...'; CODE_ID='...'; PENDING_ID='...'
ACT='2026-05-30 07:08:54.498'; TRIAL='2026-06-06 07:08:54.498'
TIER='basic'; SOURCE='invite_code'; NOTE='balance_cents:10000'

bash $HERDB prod <<EOF
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO user_invite (id, user_id, invite_code_id, activated_at, trial_ends_at)
VALUES ('$U1','$USER_ID','$CODE_ID','$ACT','$TRIAL');
UPDATE invite_code SET used_count = used_count + 1
WHERE id='$CODE_ID' AND used_count < max_uses;
UPDATE "user" SET her_club_tier='$TIER', her_club_source='$SOURCE',
  her_club_granted_by=NULL, her_club_granted_at='$ACT', updated_at=NOW()
WHERE id='$USER_ID';
INSERT INTO her_club_audit (id, user_id, action, from_tier, to_tier, source, note, operator_id, operator_email, created_at)
VALUES ('$U2','$USER_ID','grant',NULL,'$TIER','$SOURCE','$NOTE',NULL,NULL,'$ACT');
UPDATE pending_invite_signup SET redeemed_at='$ACT', user_id='$USER_ID'
WHERE id='$PENDING_ID';
COMMIT;
EOF
```

dry-run 版：`COMMIT;` 前插入 `SELECT` 校验各表，末行改 `ROLLBACK;`。各语句应各影响 1 行。

## 验证

重跑诊断 SQL，确认 `bound=t`、`used_count=1`、`her_club_tier` 已设、`redeemed=t`，
且 `subscription` 仍 active（修复不应碰订阅/gateway/credit）。
