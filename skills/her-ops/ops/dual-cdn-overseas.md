# 双 CDN 海外加速：EdgeOne 国内 + Cloudflare 海外

> **文档用途**：当海外用户延迟/连通性成为痛点时，配置 Cloudflare 接管海外流量。
> 创建日期：2026-05-26

---

## 快速参考卡

| 项目 | 值 |
|------|-----|
| **方案** | Cloudflare for SaaS + DNSPod 分线路 |
| **前提** | 购买一个辅助域名（NS 托管在 Cloudflare） |
| **成本** | 辅助域名 ~5 元/年 + Cloudflare 免费版 |
| **现有架构不变** | EdgeOne NS 接入不动，国内用户不受影响 |
| **触发条件** | 海外用户增多且延迟/连通性成为普遍投诉 |

## 背景与决策

### 为什么不直连源站

源站在广州腾讯云 CVM（192.144.187.174），海外直连意味着走公网跨境（经 GFW），实测：
- **开 EdgeOne 之前**：多个用户反馈连不上
- **开 EdgeOne 之后**：仅 1 个用户（挂美国 VPN）偶尔断连

EdgeOne 即使绕道新加坡，新加坡→广州走**腾讯内部骨干网**，连通性远优于公网跨境。海外直连源站反而更差。

### 为什么不升级 EdgeOne 标准版（3800 元/月）

调研结论（2026-05-26）：**套餐差异不在节点覆盖**。官方套餐对比文档（5 个档位完整功能表）没有"节点覆盖区域"或"POP 数量"的区分。基础版海外流量全走新加坡是 EdgeOne 的 anycast 调度问题，升级不解决。

### 为什么选 Cloudflare for SaaS

- **不需要改 EdgeOne NS 接入方式**（最大优势）
- Cloudflare 全球节点覆盖好（美/欧/日/港都有本地 POP）
- 免费版前 100 个自定义主机名不收费
- 社区有成熟的 EdgeOne + CF 共存教程

---

## 架构

```
hersoul.cn  (NS → EdgeOne/DNSPod)
├── 境内线路 → EdgeOne（现有，不变）
└── 境外线路 → Cloudflare SaaS CNAME
                    ↓
        Cloudflare 全球节点（美/欧/日/港本地 POP）
                    ↓
        回源 → 192.144.187.174:443（广州源站）
```

辅助域名（如 `hercdn.xyz`）作为 Cloudflare for SaaS 的回退源（fallback origin），用户不直接访问。

---

## 准备清单

- [ ] 购买辅助域名（推荐直接在 Cloudflare 注册，省去迁移 NS 步骤）
  - 推荐：`hercdn.xyz` / `her-relay.xyz` / 类似，~$1 首年
  - 入口：dash.cloudflare.com → Domain Registration → Register Domains
  - 备选购买站：Porkbun / Spaceship（买完需改 NS 指向 Cloudflare）
- [ ] Cloudflare 账号（需绑信用卡，不扣费）
- [ ] 确认 EdgeOne 控制台可操作 DNS 记录

---

## 操作步骤

### 步骤 1：配置辅助域名

辅助域名 NS 已在 Cloudflare（直接注册的话自动就在）。

1. Cloudflare 控制台 → 辅助域名 → DNS → 添加记录：
   ```
   类型: A
   名称: cdn-fallback (或 @)
   值: 192.144.187.174
   代理状态: 已代理（橙云）
   ```
2. SSL/TLS → 模式选 **完全（严格）**
3. 确认 `https://cdn-fallback.hercdn.xyz`（示例）能正常访问到源站

### 步骤 2：开通 Cloudflare for SaaS

1. Cloudflare 控制台 → 辅助域名 → SSL/TLS → **自定义主机名**
2. 添加**回退源**（Fallback Origin）：填 `cdn-fallback.hercdn.xyz`（步骤 1 创建的 A 记录）
3. 等待回退源状态变为 Active

### 步骤 3：添加自定义主机名

1. 在自定义主机名页面 → **添加自定义主机名**
2. 输入 `hersoul.cn`
3. 选择验证方式 **TXT 记录**（不要选 HTTP）
4. Cloudflare 会给你一条 TXT 记录，格式类似：
   ```
   名称: _cf-custom-hostname.hersoul.cn
   值: <Cloudflare 提供的验证值>
   ```
5. 记下这条 TXT 和 Cloudflare SaaS 给的 CNAME 目标地址（类似 `hersoul.cn.cdn.cloudflare.net`）

### 步骤 4：在 EdgeOne DNS 添加验证记录

1. EdgeOne 控制台 → DNS 管理 → 添加 TXT 记录：
   ```
   主机记录: _cf-custom-hostname
   类型: TXT
   值: <步骤 3 的验证值>
   ```
2. 等待 Cloudflare 验证通过（通常几分钟）

### 步骤 5：配置 DNSPod 分线路解析

EdgeOne NS 接入模式下，DNS 管理在 EdgeOne 控制台。需要添加**境外线路**记录：

1. EdgeOne 控制台 → DNS 管理
2. 找到 `hersoul.cn` 的 A 记录（@ 指向 192.144.187.174）
3. 添加一条新的 CNAME 记录：
   ```
   主机记录: @
   类型: CNAME
   值: <步骤 3 记下的 Cloudflare SaaS CNAME 地址>
   线路: 境外
   ```

> ⚠️ **关键确认**：EdgeOne NS 接入的 DNS 管理是否支持分线路解析（境内/境外）。如果不支持，需要评估是否改为 CNAME 接入（见备选方案）。

### 步骤 6：SSL 证书处理

境外流量走 Cloudflare 后，Let's Encrypt HTTP-01 验证可能失败（境外验证请求被 CF 拦截）。

**解决方案**：
- Cloudflare for SaaS 会自动为自定义主机名签发 SSL 证书（覆盖境外用户）
- EdgeOne 的 eofreecert 仍覆盖境内用户
- 源站 Traefik 的 Let's Encrypt 证书续签改为 **DNS-01** 验证（避免 HTTP-01 被拦截）：
  ```bash
  # acme.sh + DNSPod API 自动续签
  acme.sh --issue -d hersoul.cn --dns dns_dp \
    --dnssleep 120 \
    --server letsencrypt
  ```

### 步骤 7：验证

```bash
# 境内解析（应返回 EdgeOne IP）
nslookup hersoul.cn 119.29.29.29

# 境外解析（应返回 Cloudflare IP，如 104.x.x.x）
nslookup hersoul.cn 8.8.8.8
nslookup hersoul.cn 1.1.1.1

# 在线多地测速
# itdog.cn 国际版 Ping hersoul.cn，确认境外节点走 Cloudflare
```

---

## 备选方案：EdgeOne 改 CNAME 接入

如果 EdgeOne NS 模式的 DNS 管理不支持分线路，可以：

1. EdgeOne 控制台切换为 **CNAME 接入**
2. DNS 迁回 DNSPod（或其他支持分线路的 DNS 服务商）
3. DNSPod 配置：
   ```
   hersoul.cn  默认/境内  CNAME  <EdgeOne 提供的 CNAME>
   hersoul.cn  境外       CNAME  <Cloudflare SaaS CNAME>
   ```
4. CNAME 接入功能与 NS 接入基本一致，只是不能接管整个域名 DNS

---

## 已知坑

| # | 坑 | 解决 |
|---|-----|------|
| 1 | 境外 Let's Encrypt HTTP-01 验证被 CF 拦截 | 改 DNS-01 验证 |
| 2 | EdgeOne 从新加坡检测域名可能报 CNAME 异常 | 一般不影响，忽略告警 |
| 3 | Cloudflare IPv6 可能导致 EdgeOne 回源问题 | CF 控制台关闭 IPv6 兼容性 |
| 4 | 回源 Host 头必须一致 | 两个 CDN 都设 `hersoul.cn` |
| 5 | 需要注意客户端 IP 透传头统一 | 建议 EdgeOne 和 CF 都用 `X-Real-IP` |

---

## 回退

1. EdgeOne DNS 删除境外 CNAME 记录
2. 所有流量回到 EdgeOne（恢复原状）
3. 秒级生效（DNS TTL 内）

---

## 参考来源

| 来源 | 内容 |
|------|------|
| nodeseek.com/post-397773-1 | Cloudflare for SaaS + 国内 CDN 完整教程 |
| forum.naixi.net/thread-4569-1-1 | EdgeOne + CF 共存实战（含证书坑） |
| zhuanlan.zhihu.com/p/1947603154314176411 | CF for SaaS 免费额度说明 |
| blog.shiina.fun/2025/07/02/edgeone-cloudflare-geo-dns-cdn-guide | EdgeOne+CF 地理分区加速指南 |
