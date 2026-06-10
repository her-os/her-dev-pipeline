# her-web 邮箱验证码排查
决策级别: 只读排查为绿灯；改 DNS / Resend / 生产 config / 重启生产为黑灯，需用户确认
触发条件: 新用户注册或重置密码收不到邮件，垃圾箱没有，换邮箱也没有

## 关键链路

- 代码入口: `her-web/src/core/auth/index.ts` 的 `sendVerificationEmail`
- 邮件服务: Resend
- 配置来源: her_web `config` 表，键为 `email_verification_enabled`、`resend_api_key`、`resend_email_from`
- 常见日志:
  - `[auth] sendVerificationEmail: Resend is not configured`
  - `[auth] sendVerificationEmail failed: ...`

`getAllConfigs()` 有 1 小时进程缓存。只改 `config` 表不一定立刻生效；若需要立即生效，要等缓存过期或在用户确认后重启 her-web 生产服务。

## 步骤

1. 查生产配置，只显示 key 长度和发件地址，禁止打印完整 API key

   ```bash
   bash /Users/suyuan/.claude/skills/her-ops/scripts/her-db.sh prod \
     "SELECT name, length(value) AS len,
             CASE WHEN name='resend_email_from' THEN value ELSE left(value,6)||'...' END AS preview
        FROM config
       WHERE name IN ('email_verification_enabled','resend_api_key','resend_email_from')
       ORDER BY name;"
   ```

2. 查 her-web 生产日志

   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 \
     "sudo docker service logs --since 24h her-herweb-a8y5ka 2>&1 \
      | grep -Ei 'sendVerificationEmail|sendResetPassword|Resend|verification email|email verification|resend' \
      | perl -pe 's/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/***EMAIL***/ig' \
      | tail -120"
   ```

3. 查发件域 DNS

   ```bash
   dig +short TXT mail.hersoul.cn
   dig +short MX mail.hersoul.cn
   dig +short CNAME mail.hersoul.cn
   dig +short NS hersoul.cn
   ```

4. 如需查 Resend 域名状态，先确认 key 权限。当前生产 key 可能是 send-only，读域名 API 会返回 `restricted_api_key`，这不是发送失败本身。

## 判断

- `The <domain> domain is not verified`:
  - Resend 已拒绝发送，问题在发件域验证，不在用户邮箱。
  - 去 Resend Dashboard 的 Domains 页面查看该域需要的 DNS 记录。
  - 在当前 DNS 托管方补齐 TXT/CNAME/MX 等记录后，再在 Resend 点 Verify。
- `Resend is not configured`:
  - 生产 `config` 表缺 `resend_api_key` 或 `resend_email_from`。
- `Too many requests`:
  - better-auth 限流问题，先查 `AUTH_RATE_LIMIT_ENABLED=false` 是否仍在生产 service env。

## 2026-06-05 事故记录

生产和 test 都使用 `Her <no-reply@mail.hersoul.cn>`，Resend 返回 `The mail.hersoul.cn domain is not verified`。`hersoul.cn` 当前是 EdgeOne NS 接入：`ns1.qeodns.com` / `ns2.qeodns.com`。

Resend Dashboard → Domains 列表显示 `mail.hersoul.cn` 状态为 `failed`。详情页曾卡在 `Loading...`，无法读取 checklist；不要在未确认页面状态时点 Verify。

EdgeOne DNS 里 Resend 相关记录不是完全缺失，而是有两类错误：

1. 两条 MX 优先级与迁移文档不一致：

```bash
dig @ns1.qeodns.com +short MX send.mail.hersoul.cn  # 故障时返回 0 feedback-smtp...
dig @ns1.qeodns.com +short MX mail.hersoul.cn       # 故障时返回 0 inbound-smtp...
```

迁移文档要求两条 MX 优先级为 10。EdgeOne `CreateDnsRecord` 的 `Priority` 默认值是 0；创建 MX 时如果漏传 `--Priority 10`，公网会返回 `0 ...`。

2. DKIM TXT 有一处字符漏抄：EdgeOne 里是 `...zChvw2lJWSw...`，Resend 期望是 `...zChvw2lJVWSw...`。

her-web 当前容器 72 小时日志中，第一次 Resend 拒发是 `2026-06-05T03:56:01Z`（北京时间 2026-06-05 11:56）。这符合“5 月 25 日迁移后还能用一段时间，直到 Resend 后续复查才 fail”的时间线。

### 2026-06-05 修复记录

已把 EdgeOne 两条 MX 改为优先级 10：

```bash
tccli teo ModifyDnsRecords --cli-unfold-argument \
  --ZoneId zone-3qe3x1f4ebma \
  --DnsRecords.0.RecordId record-3qjlvc1vgbz6 \
  --DnsRecords.0.Name send.mail.hersoul.cn \
  --DnsRecords.0.Type MX \
  --DnsRecords.0.Content '10 feedback-smtp.us-east-1.amazonses.com' \
  --DnsRecords.0.TTL 600

tccli teo ModifyDnsRecords --cli-unfold-argument \
  --ZoneId zone-3qe3x1f4ebma \
  --DnsRecords.0.RecordId record-3qjlvf54xm7w \
  --DnsRecords.0.Name mail.hersoul.cn \
  --DnsRecords.0.Type MX \
  --DnsRecords.0.Content '10 inbound-smtp.us-east-1.amazonaws.com' \
  --DnsRecords.0.TTL 600
```

注意：EdgeOne `ModifyDnsRecords` 只传 `Priority=10` 会返回成功但不改值；必须把 `10 <target>` 写进 MX `Content`，EdgeOne 才会解析成 `Priority: 10`。修后权威 NS 和公共解析均返回 `10 ...`。

已修正 DKIM TXT 漏字，并在 Resend Dashboard 对 `mail.hersoul.cn` 点 Restart/Verify。最终状态：

- Resend Dashboard 显示 `mail.hersoul.cn` 为 `verified`
- DKIM / SPF MX / SPF TXT 均为 `verified`
- 生产 Resend key 直发测试返回 HTTP 200 和邮件 id
- her-web 生产日志近 30 分钟无新的 `sendVerificationEmail` / Resend 失败

## 回滚

只读排查无回滚。若后续改生产 `config`，回滚为把对应键改回原值；若改 DNS，回滚为删除或恢复原 DNS 记录。
