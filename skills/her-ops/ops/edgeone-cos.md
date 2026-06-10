# EdgeOne + COS 运维

从一次实际 EdgeOne 全站加速 + COS 接入操作中提炼的经验。腾讯云 tccli 和 EdgeOne API 的坑极多，本文档是踩完坑后的正确路径。

---

## 环境信息

| 项目 | 值 |
|------|-----|
| tccli 子账号 | `cli` |
| 凭证路径 | `~/.tccli/default.configure` |
| APPID | 1398915892 |
| OwnerUin | 100046064896 |
| SubAccount UIN | 100048746863 |
| ZoneId | `zone-3qe3x1f4ebma` |
| PlanId | `edgeone-3qe3wad8042w` |
| EdgeOne CNAME | `hersoul.cn.eo.dnse1.com` |
| hersoul.cn DNSPod DomainId | `99066914` |
| 当前 @ A 记录 RecordId | `2276892157`（指向 192.144.187.174） |

---

## 1. tccli 子账号权限

子账号默认只有 `QcloudDNSPodFullAccess` + `QcloudCVMFullAccess`。

- EdgeOne 需要 `QcloudTEOFullAccess`
- COS 需要 `QcloudCOSFullAccess`
- **权限不足时 `DescribeZones` 可能成功但 `CreateZone` 失败**（读写权限分离）
- CAM 操作需要单独权限，子账号无法自己给自己加权限

---

## 2. EdgeOne Zone 创建流程（正确顺序）

```
1. CreateZone (Type=partial 即 CNAME 接入，比 NS 安全)
2. DNS TXT 记录验证所有权 (edgeonereclaim.域名)
3. VerifyOwnership
4. DescribePlans 获取 PlanId
5. BindZoneToPlan
6. CreateAccelerationDomain (指定源站 IP)
7. ApplyFreeCertificate -> 需要 DNS 已切到 EdgeOne 才能完成
8. 配缓存规则
9. 切 DNS CNAME
```

**不要跳步。特别是 BindZoneToPlan 必须在 CreateAccelerationDomain 之前。**

---

## 3. SSL 证书签发的鸡生蛋问题

EdgeOne 免费证书（无论 `dns_challenge` 还是 `http_challenge`）都需要域名 DNS 已切到 EdgeOne：

- `dns_challenge` 报 "未检测到 DNS 委派记录" = 需要 CNAME 先指向 EdgeOne
- `http_challenge` 虽然验证文件可达但 EdgeOne 仍需要通过自己的边缘节点验证

**结论：必须先切 DNS，接受 5-15 分钟 HTTPS 证书空窗期。**

- 切 DNS 后 EdgeOne 自动签发证书
- 空窗期间默认证书是 `*.cdn.myqcloud.com`（不匹配，浏览器报警告）

---

## 4. 规则引擎 API 的坑

| API | 问题 |
|-----|------|
| 旧 API `CreateRule` | 2025-01-21 后停止迭代，参数结构复杂且文档不清晰 |
| 新 API `CreateL7AccRules` | tccli 3.1.88 版本 skeleton 生成报 `maximum recursion depth exceeded` |
| Python SDK `tencentcloud-sdk-python-teo` | model 类名与 API 文档不一致（如 `RuleAction` 不存在，应该用 `Action.NormalAction`） |
| REST API 直接调用 | `Rules.0.Rules` 嵌套报 `UnknownParameter`，扁平结构 `Rules.0.Conditions` 报 `ErrActionUnsupportTarget` |

**结论：缓存规则建议通过控制台 UI 配置，CLI/API 当前不可靠。**

---

## 5. COS 不在 tccli 里

- `tccli cos` **不存在**，COS 有自己的 CLI 工具 `coscmd`
- 需要单独安装：`pip3 install coscmd`
- 或者用 `tencentcloud-sdk-python-cos` Python SDK
- COS API 签名是独立体系（XML API），不走 tccli 标准签名

---

## 6. Next.js .well-known 路径不可直接访问

Next.js app router 会拦截 `.well-known/*` 路径返回 404。

解法：通过 Traefik 动态配置添加优先级更高的路由，指向 nginx 静态服务。her-web 的 Traefik 配置在 `/etc/dokploy/traefik/dynamic/` 下的 yml 文件。

---

## 7. Traefik 路由架构

```
hersoul.cn + PathPrefix(/releases/)      -> her-releases-static:80 (nginx, priority 1000)
hersoul.cn + PathPrefix(/.well-known/)    -> her-releases-static:80 (nginx, priority 1100) [临时]
hersoul.cn (其他)                          -> her-herweb-a8y5ka:3000 (Next.js)
```

---

## 8. hersoul.cn 静态资源清单

| 资源 | 路径 | 大小 | 缓存问题 |
|------|------|------|----------|
| 首页视频 | `/her/her-video-web.mp4` | 13.2MB | 源站返回 `Cache-Control: public, max-age=0`，EdgeOne FollowOrigin 不会缓存，必须规则覆盖 |
| 安装包 | `/opt/releases/her-beta/` | 单个 160-230MB，总 2.7GB | 无 Cache-Control 头，DefaultCacheTime=0 导致不缓存 |

- `latest/` 目录使用符号链接指向最新版本

---

## 9. 必须配的 3 条缓存规则

| 规则名 | 匹配条件 | 动作 |
|--------|----------|------|
| API-no-cache | URL 路径前缀 `/api/` | 不缓存 |
| Large-files-cache-30d | 文件后缀 mp4/dmg/exe/gz/zip/jpg/png/gif/webp/ico/svg | 自定义缓存 2592000 秒 |
| NextJS-static-cache-365d | URL 路径前缀 `/_next/static/` | 自定义缓存 31536000 秒 |

**注意**：这些规则建议通过控制台 UI 配置（参见第 4 节 API 的坑）。

---

## 10. DNS 切换步骤（待执行）

```
1. 修改 DNSPod @ A 记录 -> CNAME hersoul.cn.eo.dnse1.com (RecordId 2276892157)
2. 等待 EdgeOne 自动签发 SSL 证书
3. 验证 HTTPS 正常
4. 触发 CheckFreeCertificateVerification 确认
5. 启用 HTTPS 强制跳转
```

**预期空窗期 5-15 分钟**，期间 HTTPS 访问浏览器会报证书不匹配警告。

---

## 安全红线

- 不要在 CLI 命令中明文传递 SecretKey，始终使用 `~/.tccli/default.configure` 中的凭证
- DNS 切换前确认源站仍可达（回滚路径：CNAME 改回 A 记录 192.144.187.174）
- 不要删除 DNSPod 原有记录，只修改（保留 RecordId 以便回滚）
