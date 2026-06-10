# EdgeOne CDN 全站加速 — 操作手册

> **文档用途**：执行 CDN 接入的逐步操作指南。按步骤走就能完成，不需要问人。
> **决策依据**见配套文档：`edgeone-cdn-decisions.md`
>
> 创建日期：2026-05-22
> 最后更新：2026-05-25（v7 — COS 静态网站托管 + 强制下载头修复）

---

## 快速参考卡

| 项目 | 值 |
|------|-----|
| **源站 IP** | 192.144.187.174 |
| **域名** | hersoul.cn |
| **EdgeOne ZoneId** | zone-3qe3x1f4ebma |
| **EdgeOne PlanId** | edgeone-3qe3wad8042w |
| **当前套餐** | 基础版（399 元/月），原计划标准版 3800 降级 |
| **接入方式** | NS 接入（已完成） |
| **加速区域** | 全球 |
| **EdgeOne NS** | ns1.qeodns.com / ns2.qeodns.com |
| **COS 桶名** | her-releases-1398915892（ap-guangzhou） |
| **Traefik SSL 证书** | /etc/dokploy/traefik/dynamic/acme.json（runbook 旧路径有误） |
| **EdgeOne SSL** | eofreecert 自动续期（TrustAsia DV，到期 2026-08-22） |
| **DNSPod NS（回滚用）** | wet.dnspod.net / violinist.dnspod.net |
| **SSE 探针** | `/opt/scripts/sse-probe.sh`（cron 已关闭 2026-05-27，308 次零告警后退役。脚本+日志保留在服务器） |
| **腾讯云拨测** | 已删除（2026-05-27）。3 个任务从未产生有效数据，api-401 任务 expectedCode 配置错误触发误报 |
| **实时日志投递** | 2 个 S3(COS) 任务 → `her-releases-1398915892`，JSON+gzip，国内+海外各一个（2026-06-02 开通） |

### 执行状态（2026-05-25）

- [x] S1 代码部署 — PR #158 合入 main，已部署生产
- [x] S2 服务器备份 — acme.json 备份 + SSE 探针部署 + cron 已激活
- [x] S3 EdgeOne 控制台 — 基础版 399 元 + 全球 + HTTPS 回源 + 规则引擎
- [x] S4 DNS 迁移 + SSE 测试 — NS 模式 + 10 条 DNS + B½ SSE 通过
- [x] S5 NS 切换 + 验证 — 注册商 NS 已改 + Phase 0D 全链路验证通过
- [x] NS 全球传播 — Google/Cloudflare/Ali DNS 全部生效
- [x] eofreecert 切换 — TrustAsia DV 证书已签发（到期 2026-08-22，自动续期）
- [x] Phase 2 COS 迁移 — COS 桶 `her-releases-1398915892` 创建 + 2.7GB 上传 + 回源规则生效
- [x] Phase 2b COS 静态网站托管 — 开启 IndexDocument + 源站组/HostHeader 改 `cos-website` + 删除 `Content-Disposition: attachment` / `X-Cos-Force-Download` 响应头

### 流量与费用

| 套餐 | 月费 | 包含流量 | 超量单价（大陆） |
|------|------|---------|----------------|
| 基础版（当前） | 399 元 | 500GB | 0.31 元/GB |
| 标准版 | 3800 元（优惠券约 2500-3000） | 3TB | 同上 |

**升级决策线**：月流量 < 8TB → 基础版 + 超量更便宜。超过 8TB 再考虑升级标准版。

海外超量更贵：北美/欧洲 0.53 元/GB，亚太 0.77-0.86 元/GB。套餐内海外流量按 1:1.71~2.91 倍抵扣配额。

API 对话流量注意：多模态对话（图片 base64 上传 + 长上下文）单用户可达 50-100MB/天，是流量大头。上行（用户→CDN→源站）不计费，仅下行（CDN→用户）计入配额。

### 执行偏差记录

| runbook 原文 | 实际 | 原因 |
|-------------|------|------|
| 标准版 3800 元/月 | 基础版 399 元/月 | 100 人规模 ROI 不划算 |
| acme.json 路径 `/etc/dokploy/traefik/acme.json` | 实际 `/etc/dokploy/traefik/dynamic/acme.json` | runbook 路径错误 |
| api-v1-no-compression 规则 | 跳过 | EdgeOne 不支持按 URL 关闭压缩，代码层 no-transform 已覆盖 |
| eofreecert 免费证书 | 先上传 Let's Encrypt 证书 | NS 未传播无法 DV 验证，手动上传绕过 |
| UptimeRobot 3 endpoint | 腾讯云拨测（CAT）3 任务 | uptimerobot.com 国内无法访问 |

---

## 执行阶段总览

Phase 0 当天的工作拆成 5 个独立阶段。每个阶段有明确的完成标准，通过后再进下一个。前 3 个阶段对生产零影响，可以提前做完随时中断。

| 阶段 | 做什么 | 在哪做 | 耗时 | 影响 | 完成标准 |
|------|--------|--------|------|------|----------|
| **S1 代码部署** | 心跳+debug SSE+防缓冲头+Plan B 预埋 | her-web 代码 → 部署 | 30min | 零（只加不改） | debug SSE 端点返回流式数据 |
| **S2 服务器备份** | 备份 acme.json、配 UptimeRobot、部署 SSE 探针、确认注册商路径 | SSH + 网页 | 20min | 零 | 4 项全部打勾 |
| **S3 EdgeOne 控制台** | 升级套餐、改全球、改 https 回源、加规则、开智能加速 | EdgeOne 控制台 | 20min | 零（CNAME 模式流量没走 EdgeOne） | 控制台所有配置项确认 |
| **S4 DNS 迁移+SSE 测试** | 切 NS 模式、录 10 条 DNS、dig 验证、curl --resolve SSE 测试 | EdgeOne 控制台 + 终端 | 40min | 零（注册商 NS 仍指向 DNSPod） | dig 全部正确 + SSE 逐行输出 |
| **S5 NS 切换+验证** | 改注册商 NS、等传播、SSL 签发、全链路验证、邮件、Salon 测试 | 注册商控制台 + 终端 | 1-3h | **生产切流** | 验证清单全部通过 |

**安全退出点：** S1-S4 随时可以停，生产不受影响。S5 开始后必须守到验证通过或回滚。

**对应关系：** S1-S3 = 前置准备，S4 = Phase 0 阶段 A+B+B½，S5 = Phase 0 阶段 C+D。

---

## 文档导航

| 章节 | 什么时候看 | 阻塞？ |
|------|----------|--------|
| 前置准备 | S1-S3（代码、备份、控制台） | 顺序做 |
| Phase 0 | S4-S5（DNS 迁移 + NS 切换） | 顺序做 |
| Phase 0.5 | S5 验证通过后立即激活探针 | **不阻塞**，后台自动跑 |
| Phase 1 | 探针 24-48h 全绿 + DNS 传播稳定 | 可提前做 |
| Phase 2 | COS 迁移 | **不依赖 Phase 1**，可并行 |
| Phase 3 | Phase 2 观察 48-72h 后 | 顺序做 |
| Phase 4 | 按需优化 | 不阻塞 |
| 回滚手册 | 出问题时 | — |
| Plan B 操作 | B½ 测试不通过时 | — |
| 扩容操作 | 500 用户时 | — |

---

## 前置准备（Phase 0 之前完成）

### DNS 记录完整列表（10 条用户记录，必须全部迁移）

| # | 主机记录 | 类型 | 值 | TTL | 用途 |
|---|---------|------|-----|-----|------|
| 1 | @ | A | 192.144.187.174 | 600 | 主站 |
| 2 | www | A | 192.144.187.174 | 600 | www |
| 3 | club | A | 192.144.187.174 | 600 | HerClub |
| 4 | resend._domainkey.mail | TXT | p=MIGfMA0GCSqGSIb3D...PQIDAQAB | 600 | DKIM 签名（~233 字节） |
| 5 | send.mail | MX | feedback-smtp.us-east-1.amazonses.com (优先级 10) | 600 | 出站邮件 |
| 6 | send.mail | TXT | v=spf1 include:amazonses.com ~all | 600 | SPF |
| 7 | _dmarc | TXT | v=DMARC1; p=none; | 600 | DMARC |
| 8 | mail | MX | inbound-smtp.us-east-1.amazonaws.com (优先级 10) | 600 | **入站邮件**（容易遗漏！） |
| 9 | edgeonereclaim | TXT | reclaim-odgvn2qav0wt4qfs... | 600 | EdgeOne 验证（Phase 3 删除） |
| 10 | _dnsauth | CNAME | hersoul.cn.eoacme0.com | 600 | EdgeOne SSL 验证 |

> ⚠️ **第 8 条 `mail MX` 入站邮件路由容易遗漏。** 漏抄会导致发到 `*@mail.hersoul.cn` 的邮件丢失。
> ⚠️ **EdgeOne MX 记录创建/修改时必须把优先级写进 Content，例如 `10 feedback-smtp...`。** 只传 `Priority=10` 会返回成功但不改值。API 默认是 0。2026-06-05 发现 `send.mail` / `mail` 两条 MX 都解析成优先级 0，Resend 判定 `mail.hersoul.cn` 未验证。
> ⚠️ **DKIM TXT 必须逐字符核对。** 2026-06-05 发现 EdgeOne 里 `resend._domainkey.mail` 把 `...zChvw2lJVWSw...` 漏成 `...zChvw2lJWSw...`，Resend 判定 DKIM failed。

### 代码改动清单（Phase 0 前全部完成并部署）

**改动 1：SSE 心跳保活工具函数**

新建 `src/app/api/v1/_lib/sse-keepalive.ts`：

```typescript
export function withKeepAlive(
  readable: ReadableStream<Uint8Array>,
  intervalMs = 25_000,
): ReadableStream<Uint8Array> {
  const heartbeat = new TextEncoder().encode(': keep-alive\n\n');
  let timer: ReturnType<typeof setInterval> | undefined;
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;

  return new ReadableStream<Uint8Array>({
    async start(controller) {
      reader = readable.getReader();
      timer = setInterval(() => {
        try { controller.enqueue(heartbeat); } catch {}
      }, intervalMs);
      try {
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          controller.enqueue(value);
        }
        controller.close();
      } catch (err) {
        controller.error(err);
      } finally {
        clearInterval(timer);
        timer = undefined;
      }
    },
    cancel() {
      if (timer !== undefined) { clearInterval(timer); timer = undefined; }
      reader?.cancel(); // 释放上游连接，防止连接池泄漏
    },
  });
}
```

**改动 2 & 3：SSE 代理路由加心跳 + 防缓冲头**

`src/app/api/v1/messages/route.ts` 和 `src/app/api/v1/chat/completions/route.ts`：

- 导入 `withKeepAlive`（messages 路径 `../_lib/sse-keepalive`，completions 路径 `../../_lib/sse-keepalive`）
- `stream: true` 时用 `withKeepAlive(upstreamRes.body)` 包装
- 流式响应 override headers：
  ```typescript
  headers.set('Cache-Control', 'no-cache, no-store, no-transform');
  headers.set('X-Accel-Buffering', 'no');
  ```

**改动 4：gateway route Plan B 预埋**

`src/app/api/user/gateway/route.ts`：

```typescript
// 原代码：
// const proxyBase = `${envConfigs.app_url}/api/v1`;

// 改为：
const proxyBase = process.env.SSE_PROXY_BASE_URL
  || `${envConfigs.app_url.replace(/\/$/, '')}/api/v1`;
```

未设置 `SSE_PROXY_BASE_URL` 时行为不变。Plan B 激活时设置此环境变量 + 重新部署。

**改动 5：Debug SSE 端点**

新建 `src/app/api/debug/sse/route.ts`：

```typescript
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

export async function GET(req: Request) {
  const url = new URL(req.url);
  const duration = Math.min(Number(url.searchParams.get('duration') || 120), 600);

  const stream = new ReadableStream({
    start(controller) {
      const encoder = new TextEncoder();
      let tick = 0;
      const id = setInterval(() => {
        tick++;
        if (tick > duration) {
          controller.enqueue(encoder.encode('data: [DONE]\n\n'));
          controller.close();
          clearInterval(id);
          return;
        }
        const data = JSON.stringify({ tick, ts: new Date().toISOString() });
        controller.enqueue(encoder.encode(`data: ${data}\n\n`));
      }, 1000);
    },
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-store, no-transform',
      'X-Accel-Buffering': 'no',
      'Connection': 'keep-alive',
    },
  });
}
```

### 不需要改的代码（确认清单）

| 文件 | 硬编码值 | 为什么不用改 |
|------|---------|------------|
| `her-salon/src-tauri/tauri.conf.json:80` | `https://hersoul.cn/...latest.json` | 域名不变 |
| `her-salon/src-tauri/src/commands/auth.rs:23` | `https://hersoul.cn` | 域名不变 |
| `her-salon/src/stores/providerStore.ts:361` | baseUrl 来自服务端下发 | 域名不变 |
| `her-salon/src/lib/internal-telemetry-endpoints.ts:3` | `https://hersoul.cn` | 域名不变 |
| `her-web/.env.production` | `NEXT_PUBLIC_APP_URL=https://hersoul.cn` | 域名不变 |

### EdgeOne 配置（Phase 0 前在控制台或 tccli 完成）

- [ ] 加速区域改为「全球」
- [ ] 新增规则：api-v1-no-compression（`/api/v1/` 关闭 Gzip/Brotli）
- [ ] 新增规则：acme-challenge-passthrough（`/.well-known/acme-challenge/` 不缓存直接回源）

### 工具安装

```bash
# tccli（腾讯云命令行）
pip install tccli
tccli configure  # 配置 SecretId/SecretKey

# coscmd（COS 命令行，Phase 2 用）
pip install coscmd
coscmd config -a <SecretId> -s <SecretKey> -b her-releases-1398915892 -r ap-guangzhou
```

### 前置条件清单（全部打勾才能进 Phase 0）

- [ ] 代码改动 1-5 全部完成并部署
- [ ] 源站 SSL 证书已备份：`scp root@192.144.187.174:/etc/dokploy/traefik/acme.json ./acme.json.backup`
- [ ] EdgeOne 加速区域确认为「全球」
- [ ] EdgeOne 规则 api-v1-no-compression 已配置
- [ ] EdgeOne 规则 acme-challenge-passthrough 已配置
- [ ] DKIM TXT 233 字节 < 256 字节限制（已确认 ✓）
- [ ] Level 0 回滚操作已演练（见回滚手册）
- [ ] 应急卡片已准备（回滚步骤 + 控制台账号信息，至少告知一人）
- [ ] 提工单确认 EdgeOne 标准版单源站最大并发回源连接数
- [ ] 腾讯云账号手机可收验证码
- [ ] tccli 已安装可用
- [ ] 注册商控制台操作路径已确认并截图
- [ ] `dig hersoul.cn DS` 确认无 DNSSEC DS 记录
- [ ] UptimeRobot 3 个 endpoint 已配好（`hersoul.cn/`、`/api/user/info`、`/releases/her-beta/latest.json`）

---

## Phase 0：EdgeOne 升级 + NS 切换

> **预留 5-6 小时。** 选工作日上午开始（腾讯云客服在线、用户活跃度低）。
> NS 传播需 24-48 小时。改 NS 后必须守到本地传播确认 + SSL 签发完成 + 全链路验证通过。

### 阶段 A — 准备（DNSPod 仍生效，生产零影响）

```
步骤 1.  配好监控：UptimeRobot 3 个 endpoint（如未做）
步骤 2.  EdgeOne 控制台升级套餐：个人版 → 标准版（3,800 元/月）
步骤 3.  确认套餐生效（控制台套餐显示为「标准版」）
步骤 4.  EdgeOne 控制台 → 站点管理 → 接入方式改为 NS
步骤 5.  记录 EdgeOne 提供的 NS 地址（如 ns1.edgeonedns.com、ns2.edgeonedns.com）
步骤 6.  EdgeOne DNS 管理 → 逐条添加全部 10 条用户记录（见前置准备 DNS 列表）
步骤 7.  特别注意邮件四条：MX（send.mail）、SPF（send.mail TXT）、DKIM（resend._domainkey.mail TXT）、入站 MX（mail）
步骤 8.  新增规则：api-streaming-timeout（/api/v1/ HTTP 响应超时 600s）
步骤 9.  开启智能加速（控制台开关）
步骤 10. 回源协议从 follow 改为 https（始终 HTTPS 回源）
```

### 阶段 B — DNS 验证（硬性 checkpoint，全部通过才继续）

```bash
# 用 EdgeOne 的 NS 地址替换 EdgeOne-NS1
dig @EdgeOne-NS1 hersoul.cn A                              # 应返回 EdgeOne IP
dig @EdgeOne-NS1 hersoul.cn MX                              # 不应有结果（MX 在子域名）
dig @EdgeOne-NS1 send.mail.hersoul.cn MX                    # 应返回 feedback-smtp...
dig @EdgeOne-NS1 mail.hersoul.cn MX                         # 应返回 inbound-smtp...
dig @EdgeOne-NS1 resend._domainkey.mail.hersoul.cn TXT      # 应返回完整 DKIM
dig @EdgeOne-NS1 _dmarc.hersoul.cn TXT                      # 应返回 DMARC
dig hersoul.cn CAA                                           # 确认无 CAA 记录冲突
```

**任何一条不通过 → 停下修复，不继续。**

### 阶段 B½ — SSE 实测（硬性 checkpoint，不通过不改 NS）

> 决策依据：决策记录 §三 D7、D8

四项防线（超时+心跳+关压缩+防缓冲头）全部就位后，用 `curl --resolve` 强制走 EdgeOne 边缘节点测试。**注册商 NS 仍指向 DNSPod，生产零影响。**

```bash
# 1. 获取 EdgeOne 边缘节点 IP
EDGE_IP=$(dig @ns1.qeodns.com hersoul.cn A +short)

# 2. 用 debug SSE 端点测试（隔离 CDN 问题和模型问题）
curl -N --resolve hersoul.cn:443:$EDGE_IP \
  https://hersoul.cn/api/debug/sse?duration=120 \
  2>/dev/null | head -20 | while IFS= read -r line; do
    echo "[$(date +%H:%M:%S.%N)] $line"
  done

# 判断标准（对应决策记录 D14 SLO 基线）：
# ✅ 通过：每行 timestamp 递增，间隔 ~1 秒（P95 < 1.5s） → Plan A 生效
# ❌ 不通过：多行 timestamp 相同（被缓冲成批输出） → 执行 Plan B

# 3. 如果 debug SSE 通过，再用真实 AI 对话确认
curl -N --resolve hersoul.cn:443:$EDGE_IP \
  -X POST https://hersoul.cn/api/v1/messages \
  -H "Content-Type: application/json" \
  -H "x-api-key: <测试 API key>" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"claude-3-haiku-20240307","stream":true,"max_tokens":200,"messages":[{"role":"user","content":"从1数到20，每个数字单独一行"}]}' \
  2>/dev/null | while IFS= read -r line; do
    echo "[$(date +%H:%M:%S.%N)] $line"
  done
```

**B½ 通过 → 继续阶段 C**

**B½ 不通过 → 执行 Plan B**（见本文档「Plan B 操作」章节），然后继续阶段 C

### 安全退出点

> - **阶段 A + B + B½ 完成但 C 未做**：**可安全退出**。DNS 仍走 DNSPod，零影响，可改天继续。
> - **阶段 C 完成（NS 已改）**：**不能退出**。必须守到阶段 D 全链路验证通过。

### 阶段 C — NS 切换（开始后不能中途离开）

```
步骤 11. 截图当前注册商后台 NS 配置（wet.dnspod.net / violinist.dnspod.net）
步骤 12. 截图 EdgeOne 控制台当前完整配置（规则引擎、加速域名状态、回源配置）
步骤 13. 去域名注册商（腾讯云/广州云讯）修改 NS 为 EdgeOne 提供的地址
         （可能需要手机验证码）
步骤 14. 不要动 DNSPod 上的任何记录（保留作回滚备份，至少 1 周不删）
```

### 阶段 D — 传播与验证

```
步骤 15. whatsmydns.net 持续监控 DNS 传播（每 5 分钟查一次）
步骤 16. 等待 EdgeOne 自动签发 SSL（5-15 分钟）
步骤 17. 验证 SSL：
         tccli teo CheckFreeCertificateVerification \
           --cli-unfold-argument --ZoneId zone-3qe3x1f4ebma --Domain hersoul.cn
```

```bash
# 步骤 18. 全链路验证：
curl -sI https://hersoul.cn/ | head -5                        # 应含 Server: TencentEdgeOne
curl -sI https://hersoul.cn/her/her-video-web.mp4 | grep eo-cache  # 首次 MISS，再次 HIT
curl -sI https://hersoul.cn/releases/her-beta/latest.json | head -5
curl -s https://hersoul.cn/api/user/info | head -3             # 应返回 Unauthorized

# 步骤 19. 邮件验证（DNS 传播 15 分钟后再发）：
# 发一封邀请邮件确认邮件功能正常

# 步骤 20. MXToolbox 验证 MX/SPF/DKIM

# 步骤 21. mail-tester.com 测试邮件，确认 DKIM/SPF/DMARC pass

# 步骤 22. herclub 验证：
curl -sI https://club.hersoul.cn/                             # 确认正常

# 步骤 23. SSL 确认 OK 后启用 HTTPS 强制跳转

# 步骤 24. Salon 客户端发一条 AI 对话，确认 SSE 流式输出正常

# 步骤 25. 验证 acme-challenge-passthrough 规则：
curl -sI https://hersoul.cn/.well-known/acme-challenge/v5-passthrough-test
# 期望：返回 404（Traefik/nginx 的 404，不是 EdgeOne 错误页）
# 验证：响应头不含 eo-cache-status，或含 Server: Traefik
```

### 熔断机制

操作开始后 **5 小时为硬截止线**（如上午 10:00 开始 → 15:00 截止）。超时阶段 D 验证未全部通过 → 执行 Level 0 回滚，择日重做。

### CNAME → NS 过渡期说明

步骤 4 改为 NS 接入后到步骤 13 改注册商 NS 之间（约 1 小时），DNS 仍走 DNSPod，CNAME 加速可能失效。用户直连源站。预期行为，不影响可用性。

---

## Phase 0.5：切 NS 后自动监控（S5 当天部署，后台运行）

> **阶段 D 全链路验证通过后立即激活探针 cron。** 探针在后台自动运行，你不需要等待或盯盘——有问题它会告警找你。48h 无告警后可以推进 Phase 1 深度测试。

### 监控 1：SSE 缓冲探针（必须）

在服务器上部署 cron 脚本，每 10 分钟检测 EdgeOne 是否缓冲 SSE 流。

```bash
# /opt/scripts/sse-probe.sh
#!/bin/bash
# 每次跑 12 秒，抓 debug SSE 输出判断 tick 间隔
# 正常：每秒一个 tick，间隔 ~1000ms
# 异常（被缓冲）：多个 tick 攒批到达，间隔 > 2000ms

THRESHOLD=2000
LOG="/var/log/sse-probe.log"

max_interval=$(curl -sN --max-time 12 https://hersoul.cn/api/debug/sse?duration=10 \
  2>/dev/null | while IFS= read -r line; do
    [[ "$line" == data:* ]] && echo "$(date +%s%3N)"
  done | awk 'NR>1{diff=$1-prev; if(diff>max) max=diff} {prev=$1} END{print max+0}')

ts=$(date '+%Y-%m-%d %H:%M:%S')

if [ "${max_interval:-0}" -gt "$THRESHOLD" ]; then
  echo "[$ts] ALERT: SSE buffered, max_interval=${max_interval}ms" >> "$LOG"
  # TODO: 接通知渠道（webhook/邮件/Telegram）
  exit 1
else
  echo "[$ts] OK: max_interval=${max_interval}ms" >> "$LOG"
fi
```

```bash
# 部署
chmod +x /opt/scripts/sse-probe.sh
echo '*/10 * * * * root /opt/scripts/sse-probe.sh' > /etc/cron.d/sse-probe

# 验证
/opt/scripts/sse-probe.sh && cat /var/log/sse-probe.log
```

**判断标准**：
- `max_interval < 1500ms` → 正常，EdgeOne 逐 chunk 透传
- `1500-2000ms` → 边界，可能有轻微网络抖动，继续观察
- `> 2000ms` → SSE 被缓冲，执行 Plan B

### 监控 2：UptimeRobot（必须，S2 阶段配好）

3 个 endpoint，间隔 5 分钟，连续 2 次失败告警：

| Endpoint | 期望 |
|----------|------|
| `https://hersoul.cn/` | HTTP 200/307 |
| `https://hersoul.cn/api/user/info` | HTTP 401 |
| `https://hersoul.cn/releases/her-beta/latest.json` | HTTP 200 |

### 监控 3：邮件送达验证（S5 阶段 D 执行一次）

已在阶段 D 步骤 19-21 覆盖。切 NS 后 1 小时 + 48 小时各发一封测试邮件到个人 Gmail，确认不进垃圾箱。

### 何时推进 Phase 1

Phase 0.5 不阻塞你做其他事——探针后台跑着，你该干嘛干嘛。

- 探针连续 48h 无告警 + DNS 全球传播完成 → 可以做 Phase 1 深度测试
- 探针告警 → 检查 `/var/log/sse-probe.log` 确认是持续缓冲还是偶发抖动
  - 持续缓冲（连续 3 次以上 > 2000ms）→ 激活 Plan B
  - 偶发（单次）→ 继续观察，不动
- Phase 2（COS 迁移）不依赖 Phase 1，可以并行推进

---

## Phase 1：SSE 深度验证 + VPN ��试

> 探针 48h 无告警 + DNS 全球传播稳定后执行。不是硬性等待——如果 whatsmydns.net 显示全球已解析到 EdgeOne，且探针 24h 全绿，提前做也可以。

```
步骤 25. Salon SSE 深度测试：
         - 首字延迟 >30s 的请求不断连
         - >10 分钟长对话不中断
         - debug SSE 端点 10 分钟测试：curl https://hersoul.cn/api/debug/sse?duration=600

步骤 26. VPN 多地区测试（从以下 VPN 出口各测一次）：
         - 日本
         - 香港
         - 美国西部
         每个地区测试：
         a. 首页加载
         b. 登录
         c. debug SSE 2 分钟
         d. 真实 AI 对话
         e. 记录 TTFB 对比

步骤 27. 48h 后二次邮件验证
         （Phase 0 当晚可能走 DNSPod 缓存，需确认 EdgeOne DNS 下 DKIM/SPF pass）

步骤 28. 源站证书续签监控——设以下日历提醒：
         - 2026-06-14：首次续签检查
           → SSH 登录服务器执行：
           openssl s_client -connect 192.144.187.174:443 -servername hersoul.cn \
             2>/dev/null | openssl x509 -noout -enddate
           确认到期日延后到 ~09 月
         - 2026-06-30：硬截止线
           如果到期日仍为 07-14 → 自动续签失败，立即手动续签

         手动续签 fallback：
         方案 A（推荐，~5分钟）：
           1. EdgeOne 控制台临时停用 hersoul.cn 加速
           2. 用户直连源站 → Traefik 自动完成 HTTP-01 续签
           3. 重新启用加速
         方案 B（无停服）：
           Traefik 切换 DNS-01 challenge（需安装 DNSPod/EdgeOne DNS provider plugin）
```

---

## Phase 2：COS 安装包迁移

> Phase 1 观察 48h 无异常后执行。

```
步骤 29. 创建 COS 桶 her-releases-1398915892（ap-guangzhou，私有读）
步骤 30. 授权 EdgeOne 读取 COS 桶
步骤 31. 子账号加权限 QcloudCOSFullAccess
         （⚠️ 权限偏大，Phase 3 收窄为仅该桶的 PutObject/GetObject）
步骤 32. 上传安装包（注意符号链接处理）：
```

```bash
# 上传实际版本目录
coscmd upload -r /opt/releases/her-beta/v0.0.5/ /releases/her-beta/v0.0.5/

# latest.json 单独上传
coscmd upload /opt/releases/her-beta/latest.json /releases/her-beta/latest.json

# latest/ 目录：解析符号链接后上传
mkdir -p /tmp/releases-latest
cp -rL /opt/releases/her-beta/latest/ /tmp/releases-latest/
coscmd upload -r /tmp/releases-latest/ /releases/her-beta/latest/
rm -rf /tmp/releases-latest

# 下载页 HTML
coscmd upload /opt/releases/her-beta/index.html /releases/her-beta/index.html
```

```
步骤 33. 文件完整性核对：
```

```bash
coscmd list /releases/her-beta/ -r
coscmd info /releases/her-beta/v0.0.5/Her_0.0.5_aarch64.dmg
md5sum /opt/releases/her-beta/v0.0.5/Her_0.0.5_aarch64.dmg
```

```
步骤 34. 新增 EdgeOne 规则：latest-json-no-cache（latest.json 不缓存）
步骤 35. 新增 EdgeOne 源站组 "COS-releases"（COS 桶域名）
步骤 36. 新增 EdgeOne 规则：releases-cos-origin（/releases/her-beta/ 回源 COS）
步骤 37. 验证：
```

```bash
curl -sI https://hersoul.cn/releases/her-beta/latest.json | grep eo-cache   # 不是 HIT
# 下载 DMG 正常
curl -sI https://hersoul.cn/releases/her-beta/latest/Her_aarch64.dmg | head -5
# 下载页 HTML 正常
curl -s https://hersoul.cn/releases/her-beta/ | head -20
```

```
步骤 38. 更新发版 SOP（COS 已接管 /releases/，新版本必须同步上传 COS）
```

**COS 回退方案**：EdgeOne 控制台一键禁用 COS 回源规则 → 流量自动回到默认源站。秒级生效。

### Phase 2b：COS 静态网站托管（2026-05-25 修复）

**问题**：COS 默认不对目录路径自动解析 `index.html`，导致 `/releases/her-beta/` 返回 NoSuchKey 404。

**修复步骤**：

1. 开启 COS 静态网站托管（`PutBucketWebsite`，IndexDocument.Suffix = `index.html`）
2. 更新 EdgeOne 源站组 `COS-releases`（`og-3qjr6cfspbjr`）：Record 从 `cos.ap-guangzhou.myqcloud.com` 改为 `cos-website.ap-guangzhou.myqcloud.com`
3. 更新 EdgeOne 规则 `releases-cos-origin` 的 HostHeader：同步改为 `cos-website` 端点
4. 规则 `releases-cos-origin` 新增 `ResponseHeader` 动作：删除 `Content-Disposition` 和 `X-Cos-Force-Download` 响应头（COS 对非绑定域名的请求强制注入下载头）

**注意事项**：
- COS 的 `force-download` 安全机制：当 HostHeader 不是 COS 桶绑定的自定义域名时，COS 自动添加 `Content-Disposition: attachment` + `X-Cos-Force-Download: true`，导致浏览器下载而非渲染 HTML
- 开发者上传安装包的 `coscmd` 命令不受影响（走 COS API 端点，不走 website 端点）
- 更新 COS 上的 `index.html` 时，必须从 COS 下载当前版本来改，不要用 git 里的本地版本覆盖（两者已分叉，git 版已通过 PR #92 同步）

---

## Phase 3：清理 + 安全加固

> Phase 2 观察 48-72h 后执行。

```
步骤 39. EdgeOne DNS 删除 edgeonereclaim TXT 记录
步骤 40. 确认 _dnsauth CNAME 是否仍需要（NS 接入后可能不需要）
步骤 41. 删除服务器 /etc/dokploy/traefik/dynamic/her-well-known.yml
步骤 42. CVM 安全组：443 端口入站限制只允许 EdgeOne 回源 IP
步骤 43. COS 子账号权限从 QcloudCOSFullAccess 收窄为仅 her-releases 桶的读写
步骤 44. 更新 edgeone-ops skill + her-ops skill
```

**发版 SOP**（Phase 2 步骤 38 开始执行，Phase 3 完善）：

```bash
# 假设新版本 v0.0.6，构建产物在 $STAGING 目录

# 1. 上传新版本目录
coscmd upload -r $STAGING/v0.0.6/ /releases/her-beta/v0.0.6/

# 2. 生成 latest.json
node scripts/generate-updater-manifest.mjs \
  --artifacts $STAGING --version 0.0.6 \
  --base-url https://hersoul.cn/releases/her-beta \
  --out $STAGING/latest.json

# 3. 上传 latest.json（覆盖）
coscmd upload $STAGING/latest.json /releases/her-beta/latest.json

# 4. 更新 latest/ DMG
coscmd upload $STAGING/v0.0.6/Her_0.0.6_aarch64.dmg /releases/her-beta/latest/Her_aarch64.dmg
coscmd upload $STAGING/v0.0.6/Her_0.0.6_x64.dmg /releases/her-beta/latest/Her_x64.dmg

# 5. 清 CDN 缓存（latest/ DMG 文件名不变，有 30 天缓存）
tccli teo CreatePurgeTasks --cli-unfold-argument \
  --ZoneId zone-3qe3x1f4ebma --Type prefix \
  --Targets '["https://hersoul.cn/releases/her-beta/latest/"]'
```

---

## Phase 4：后续优化（不阻塞，按需）

| # | 优化项 | 说明 |
|---|--------|------|
| 45 | HTML 页面缓存 | `/zh` 返回 `private, no-cache, no-store`，当前无需配。用户增长后可加 `s-maxage` |
| 46 | Query String | 忽略 `utm_*` 参数用于缓存 key（回源时保留） |
| 47 | HSTS | 全链路稳定一周后先 `max-age=300` 测试，不加 `includeSubDomains` |
| 48 | 安全头分层 | HSTS/X-Frame-Options/X-Content-Type-Options 在 EdgeOne 配；CSP 在源站配 |
| 49 | 视频文件名加 hash | 长期，需改 `VideoSection.tsx` + 部署流程 |
| 50 | 安全组 IP 自动更新 | cron + API 自动同步 EdgeOne 回源 IP 段到 CVM 安全组 |

---

## 验证清单

### Phase 0 前置条件验证

- [ ] SSE 心跳代码已部署
- [ ] Debug SSE 端点已部署
- [ ] SSE 防缓冲响应头代码已部署
- [ ] gateway SSE_PROXY_BASE_URL 预埋已部署
- [ ] 源站 SSL 证书已备份（acme.json）
- [ ] EdgeOne 加速区域改为「全球」
- [ ] EdgeOne 规则 api-v1-no-compression 已配置
- [ ] EdgeOne 规则 acme-challenge-passthrough 已配置
- [x] DKIM TXT 233 字节 < 256 字节限制（已确认）
- [ ] Level 0 回滚操作已演练
- [ ] 应急卡片已准备
- [ ] `dig hersoul.cn DS` 确认无 DNSSEC DS 记录
- [ ] tccli 已安装可用
- [ ] 注册商控制台操作路径已确认
- [ ] UptimeRobot 已配好

### Phase 0 验证

- [ ] `dig hersoul.cn A` 返回 EdgeOne IP（不是 192.144.187.174）
- [ ] `https://hersoul.cn/` 正常，含 `Server: TencentEdgeOne`
- [ ] `https://hersoul.cn/her/her-video-web.mp4` 二次访问 `eo-cache-status: HIT`
- [ ] `https://hersoul.cn/releases/her-beta/latest.json` 正常
- [ ] `https://hersoul.cn/api/user/info` 返回 Unauthorized
- [ ] `https://club.hersoul.cn/` 正常
- [ ] 邀请邮件发送正常
- [ ] MXToolbox MX/SPF/DKIM 全部 pass
- [ ] mail-tester.com 不进垃圾箱
- [ ] HTTPS 强制跳转已启用
- [ ] acme-challenge-passthrough 穿透验证通过
- [ ] Salon 客户端 AI 对话 SSE 正常

### Phase 1 验证

- [ ] Salon 登录正常
- [ ] SSE 首字延迟 >30s 不断连
- [ ] SSE >10 分钟长对话不中断
- [ ] debug SSE 10 分钟测试通过（tick 间隔 P95 < 1.5s）
- [ ] 自动更新检查正常
- [ ] VPN（日本）测试通过
- [ ] VPN（香港）测试通过
- [ ] VPN（美西）测试通过
- [ ] 日历提醒已设：06-14 + 06-30
- [ ] 源站证书到期日已确认

### Phase 2 验证

- [ ] latest.json 从 COS 返回
- [ ] DMG 下载正常
- [ ] 下载页 HTML 正常
- [ ] Tauri 更新包（.app.tar.gz）正常
- [ ] COS 回源 eo-cache-status 首次 MISS 后续 HIT
- [ ] 安装包下载不再回源站（nginx 日志无新请求）
- [ ] 发版 SOP 已更新

---

## 回滚手册

### Level 0 回滚（5-30 分钟，首选）

> 适用：CDN 规则/缓存有问题，DNS 本身没问题

```
1. EdgeOne 控制台 → DNS 管理 → 确认 @ A 记录值为 192.144.187.174
2. EdgeOne 控制台 → 域名服务 → 域名管理 → hersoul.cn → 停用加速
3. 等待 A 记录 TTL 过期（建议设为 60 秒）
4. 验证：
   dig hersoul.cn A                              # 应返回 192.144.187.174
   curl -sI https://hersoul.cn/                   # 不含 Server: TencentEdgeOne
```

**注意**：Level 0 回滚后用户直连源站，需要源站 SSL 证书有效。当前到期 2026-07-14。

### Level 1 回滚（6-48 小时，最后手段）

> 适用：EdgeOne 整体不可用

```
1. 去域名注册商修改 NS 回 DNSPod：wet.dnspod.net / violinist.dnspod.net
2. DNSPod 上的记录保持不变（Phase 0 步骤 14 说了不删）
3. 等待 NS 传播（6-48 小时，NS TTL=86400）
```

**Level 1 是最后手段，不能依赖它做快速恢复。**

### 回滚恢复

Level 0/1 回滚后恢复到 CDN：
1. 排查并修复问题
2. 重新走 Phase 0 阶段 B（验证 DNS）→ B½（验证 SSE）→ C（改 NS）→ D（验证）

---

## Plan B 操作

> 决策依据：决策记录 §三 D8

### 什么时候触发

Phase 0 阶段 B½ SSE 实测不通过（EdgeOne 缓冲 SSE）。

### 激活步骤（~30 分钟，NS 切换前完成）

```
1. 腾讯云控制台创建 GAAP 加速通道：
   - TCP 模式
   - 监听 443 + 80
   - 源站 192.144.187.174:443 和 :80
   - 多入口区域（亚太 + 北美 + 欧洲）

2. EdgeOne DNS 添加：stream CNAME <GAAP加速域名>
   （代理状态设为「仅 DNS」，不经 CDN）

3. Dokploy 给 her-web 容器添加域名 stream.hersoul.cn
   （Traefik 自动签发 Let's Encrypt，HTTP-01 经 GAAP TCP 透传到源站）

4. .env.production 设置：
   SSE_PROXY_BASE_URL=https://stream.hersoul.cn/api/v1

5. 重新部署 her-web

6. 验证 SSE：
   curl -N https://stream.hersoul.cn/api/debug/sse?duration=10 \
     2>/dev/null | while IFS= read -r line; do
       echo "[$(date +%H:%M:%S.%N)] $line"
     done
   # 每行 timestamp 递增 = 通过

7. 通过 → 继续 Phase 0 阶段 C（改 NS）
```

### 回退 Plan B

```
1. 删除 .env.production 中的 SSE_PROXY_BASE_URL
2. 重新部署 her-web
3. SSE 回到 EdgeOne CDN 通道
```

---

## 扩容操作（500 用户触发）

> 决策依据：决策记录 §五

### 触发信号

- 单机 CPU 持续 >70%
- Node.js event loop lag >100ms
- AI 对话 SSE 首字延迟明显增加
- 用户反馈变多

### 操作步骤（概要，到时候需要细化）

```
1. 购买第二台腾讯云 CVM（广州同可用区，同配置）
2. 创建腾讯云 CLB
3. 将两台 CVM 加入 CLB 后端
4. 在第二台 CVM 上部署 her-web + her-gateway（Docker）
5. EdgeOne 回源地址从 CVM IP 改为 CLB IP
6. 验证：两台 CVM 都能收到请求
7. 验证：SSE 长连接不被 CLB 中断
```

---

## 日常运维

### EdgeOne 回源 IP 段变更

腾讯云会在变更前 14/7/3/1 天通知（站内信+短信+邮件）。**14 天是硬截止，逾期强制切换，不在 SLA 赔付范围。**

Phase 3 后应实现自动化：定时任务调用「查询源站防护详情」API → 检查 `NextOriginACL` 字段 → 更新安全组 → 调用「确认回源 IP 网段更新」API。

### CDN 缓存清除

```bash
# 按 URL 清除
tccli teo CreatePurgeTasks --cli-unfold-argument \
  --ZoneId zone-3qe3x1f4ebma --Type url \
  --Targets '["https://hersoul.cn/her/her-video-web.mp4"]'

# 按前缀清除
tccli teo CreatePurgeTasks --cli-unfold-argument \
  --ZoneId zone-3qe3x1f4ebma --Type prefix \
  --Targets '["https://hersoul.cn/releases/her-beta/latest/"]'
```

### 预热

```bash
tccli teo CreatePrefetchTasks --cli-unfold-argument \
  --ZoneId zone-3qe3x1f4ebma \
  --Targets '["https://hersoul.cn/releases/her-beta/v0.0.6/Her_0.0.6_aarch64.dmg"]'
```

### 实时日志投递（2026-06-02 开通）

两个 S3(COS) 投递任务，JSON+gzip 格式，投递到 `her-releases-1398915892` 桶：

| 任务 | TaskId | Area |
|------|--------|------|
| hersoul-l7-access-logs-mainland | `21d044b5-d2c2-43ef-af7e-11d7a7eb791f` | mainland |
| hersoul-l7-access-logs-overseas | `facfb9b9-886a-4ad8-81a5-358ddcce1708` | overseas |

日志字段：RequestID, ClientIP, ClientRegion, RequestTime, RequestHost, RequestUrl, RequestMethod, HttpProtocol, EdgeResponseStatusCode, OriginResponseStatusCode, EdgeCacheStatus, EdgeResponseTime, OriginResponseTime, ClientUserAgent, SecurityAction, SecurityRuleID, EdgeResponseBytes, RequestReferer, ClientCountry, RequestBytes

```bash
# 查看日志文件（COS 路径自动按日期分目录）
coscmd list /edgeone-logs/ -r | head -20

# 下载并分析某时段的日志
coscmd download /edgeone-logs/<path>.gz /tmp/eo-log.gz
zcat /tmp/eo-log.gz | python3 -c "
import json, sys
for line in sys.stdin:
    r = json.loads(line)
    if r.get('EdgeResponseStatusCode') >= 400:
        print(f'{r[\"RequestTime\"]} {r[\"ClientIP\"]} {r[\"EdgeResponseStatusCode\"]} {r[\"RequestUrl\"][:60]}')
"

# 管理日志投递任务
tccli teo DescribeRealtimeLogDeliveryTasks --cli-unfold-argument --ZoneId zone-3qe3x1f4ebma
```

> **注意**：CLS 未开通（`CLS service is unregistered`），日志投递到 COS 后需手动下载分析。后续如需实时搜索，先去控制台开通 CLS，再改投递目标。

---

## 文件索引

| 文件 | 说明 |
|------|------|
| `edgeone-cdn-decisions.md` | 决策记录（为什么这么做） |
| `edgeone-cdn-runbook.md` | **本文档**（怎么做） |
| `~/.claude/skills/edgeone-ops/SKILL.md` | EdgeOne 运维经验 skill |
| `her-web/src/app/api/v1/_lib/sse-keepalive.ts` | SSE 心跳保活（待创建） |
| `her-web/src/app/api/debug/sse/route.ts` | Debug SSE 端点（待创建） |
| `her-web/src/app/api/v1/messages/route.ts` | AI 对话 SSE 代理路由 |
| `her-web/src/app/api/v1/chat/completions/route.ts` | OpenAI 格式代理路由 |
| `her-web/src/app/api/user/gateway/route.ts` | 网关配置下发 |
| `her-salon/src-tauri/tauri.conf.json` | 客户端更新 URL |
| `her-salon/scripts/generate-updater-manifest.mjs` | latest.json 生成 |
| `/etc/dokploy/traefik/acme.json` | 源站 SSL 证书 |
| `/opt/releases/her-beta/` | 源站安装包目录 |

---

## 术语表

| 术语 | 含义 |
|------|------|
| NS 接入 | 把域名的 DNS 服务器指向 EdgeOne，EdgeOne 管理所有 DNS 记录 |
| CNAME 接入 | 在现有 DNS 添加 CNAME 指向 EdgeOne，EdgeOne 只管加速不管 DNS |
| CNAME 展平 | DNS 提供商把 CNAME 解析为 A 记录返回，绕过根域名限制 |
| 智能加速 | EdgeOne 优化回源链路，走腾讯受管网络（非 VPC 内网），优化动态请求速度 |
| HTTP 响应超时 | EdgeOne 等待源站返回数据的最长时间，超时返回 524 |
| SSE | Server-Sent Events，单向 HTTP 长连接，AI 对话流式响应协议 |
| 强制缓存 | CDN 忽略源站 Cache-Control，按规则时间缓存 |
| DV 证书 | Domain Validation，域名验证级 SSL 证书 |
| GAAP | 全球应用加速，腾讯云四层 TCP/UDP 加速产品 |
| CLB | 负载均衡器，分发请求到多台后端服务器 |
