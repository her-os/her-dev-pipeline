# K8s DNS 切换 runbook + 切换后清单

> 黑灯操作：DNS / EdgeOne 回源变更，必须用户在场拍板执行。
> 背景与 6/8 翻车教训：`her-web/docs/postmortem-k8s-dns-switch-0608.md`、`docs/handoff-k8s-migration-ops-0608.md`。

## 切换前状态（2026-06-12 已全部就绪）

- ✅ 两个 CLB HTTPS 443 已配好，证书分别覆盖 api.tokenic.cn / hersoul.cn（hersoul 证书 2026-07-14 到期，注意续期机制待问 idoubi）
- ✅ K8s 与 CVM 共用云 PG 同库（实测验证）；env ConfigMap 齐全（FEISHU_* 等）
- ✅ 零中断发布已配（readinessProbe + preStop，实测 0 失败）
- ✅ K8s 与 CVM 当前跑同一构建版本
- ⬜ 待拍板：hersoul.cn 走 (a) EdgeOne 回源改 CLB（保留 CDN，推荐）还是 (b) 直接 CNAME 到 CLB（放弃 EdgeOne）

## 切换步骤

### api.tokenic.cn（DNSPod）

启用 CNAME 记录 `2273574618`（→ lb-1npe9gzp-...clb.bj-tencentclb.com），禁用 A 记录 `2310507505`（→ 192.144.187.174）。

### hersoul.cn（二选一）

方案 a（保留 EdgeOne，推荐）——改回源到 CLB HTTPS：

```bash
tccli teo ModifyAccelerationDomain --cli-unfold-argument \
  --ZoneId zone-3qe3x1f4ebma --DomainName hersoul.cn \
  --OriginInfo.OriginType IP_DOMAIN \
  --OriginInfo.Origin lb-2rhklmgd-ymjc1wivg40o79sb.clb.bj-tencentclb.com \
  --OriginInfo.HostHeader hersoul.cn \
  --OriginProtocol HTTPS --HttpsOriginPort 443
```

方案 b：EdgeOne DNS 里把 hersoul.cn 改 CNAME 到 CLB（CDN/DDoS/边缘 SSL 全部失效，需用户明确接受）。

### 切换后立即验证（全链路，缺一不可）

首页 200 → 注册/登录 → AI 对话 → `/api/beta/apply` 表单（写飞书）→ 邮件验证码 → 支付回调地址确认。
观察 `kubectl logs -n her -l app=her-web` 与 gateway 日志确认流量进入 K8s。

## 回滚（任一步出问题立即执行）

- api.tokenic.cn：DNSPod 禁用 CNAME、启用 A 记录（6/8 已演练过，分钟级生效）
- hersoul.cn 方案 a 回滚：同上 tccli 命令，Origin 改回 `192.144.187.174`、HostHeader 不变
- 心法（6/8 教训）：改完立刻群里同步；出事一人主导恢复

## 切换后清单（流量稳定后逐项做）

| # | 事项 | 说明 |
|---|------|------|
| 1 | 清理生产 new-api 容器的 roome.cn Traefik label | 需改 compose（仓库 + Dokploy DB 双写）+ recreate，~30s 中断（此时已无流量）。消除 ACME 报错日志 |
| 2 | CVM 旧生产栈保留观察 ≥2 周 | 作为 DNS 回滚备胎；之后再议降配 |
| 3 | TCR 迁广州个人版（下月） | 省 664/月；CI 改推送地址 + K8s 改拉取地址，先双推过渡 |
| 4 | 向 idoubi 确认 hersoul.cn 证书续期机制 | Let's Encrypt 2026-07-14 到期，手动传的话会再断一次 |
| 5 | her 命名空间操作权限长期化讨论 | CVM 退役前必须有操作权限（单点风险） |
