# Her 产品运维 · 文档索引

## ops/ 操作文件

### her-gateway（API 网关 · api.tokenic.cn）

| 文档 | 摘要 | 最后更新 |
|------|------|---------|
| [ops/gateway-admin-api.md](ops/gateway-admin-api.md) | Admin API 鉴权、端点清单、请求/响应日志接口、Token Totals 与 her-web telemetry 口径边界、定价系统公式 | 2026-05-24 |
| [ops/channel-provisioning.md](ops/channel-provisioning.md) | 新建上游渠道完整 runbook：字段清单、定价换算、cache 同步延迟、DeepSeek Anthropic thinking 冲突和坑清单 | 2026-05-23 |
| [ops/upstream-log-compare.md](ops/upstream-log-compare.md) | gateway request_id 与 new-api 兼容上游 token 日志对比，定位 504/慢首段是否上游继续跑完并计费 | 2026-05-15 |

### her-web（产品前端 · hersoul.cn）

| 文档 | 摘要 | 最后更新 |
|------|------|---------|
| [ops/production-db-ops.md](ops/production-db-ops.md) | 生产数据库操作手册：her-db wrapper、完整 Schema Reference（her_web 30 表 + gateway 高频 6 表）、常猜错标注、UPDATE 模板、操作规范 | 2026-05-25 |
| [ops/test-account-provisioning.md](ops/test-account-provisioning.md) | test 账号创建：走 her-web 正常注册/登录路径，补 email verified，调用 gateway provisioning，并验证 web/gateway 两边绑定 | 2026-05-28 |
| [ops/invite-codes.md](ops/invite-codes.md) | 发邀请码（单人快速 / CSV 批量 → 创建码 → 发邮件 → 注册后自动回写微信号/姓名） | 2026-05-21 |
| [ops/invite-redeem-repair.md](ops/invite-redeem-repair.md) | 注册成功但邀请码没绑定的诊断与事务补录：根因（manual provision 不兑现邀请码 / 自助兑现中断）、heredoc 原子事务模板、dry-run 验证 | 2026-05-30 |
| [ops/email-verification.md](ops/email-verification.md) | 注册/重置密码收不到邮件：查 her-web Resend 配置、日志、发件域 DNS 与缓存生效规则 | 2026-06-05 |

### salon（客户端 · her-beta）

| 文档 | 摘要 | 最后更新 |
|------|------|---------|
| [ops/salon-backend-switching.md](ops/salon-backend-switching.md) | salon 本地/云端/prod 后端切换；`VITE_HER_*` 与 dev callback 规则 | 2026-04-25 |

### 运维操作

| 文档 | 决策级别 | 场景 |
|------|---------|------|
| [ops/container-restart.md](ops/container-restart.md) | 绿灯 | gateway/her-web/herclub 容器挂了重启 |
| [ops/disk-cleanup.md](ops/disk-cleanup.md) | 绿灯 | 磁盘使用 > 80% 清理 |
| [ops/ssl-ops.md](ops/ssl-ops.md) | 绿灯/黄灯 | SSL 证书检查 + 续签 |
| [ops/health-patrol.md](ops/health-patrol.md) | 绿灯 | 综合健康巡检 |
| [ops/db-connection-fail.md](ops/db-connection-fail.md) | 黄灯 | 数据库连接失败诊断 |
| [ops/container-repeated-crash.md](ops/container-repeated-crash.md) | 黄灯 | 容器重启后仍然挂 |
| [ops/k8s-cluster-access.md](ops/k8s-cluster-access.md) | 绿灯（只读） | TKE 集群连接（SSH 隧道 + kubectl）、kubeconfig 生成、RBAC 权限状态 |
| [ops/k8s-dns-switchover.md](ops/k8s-dns-switchover.md) | 黑灯 | DNS 切换到 K8s 的 runbook、回滚命令、切换后清单（roome label / TCR 迁移 / 证书续期） |
| [ops/hermes-monitor.md](ops/hermes-monitor.md) | 绿灯（只读） | Hermes 7x24 值守监控：圣何塞 VPS 巡检生产机，飞书告警 + 每日 09:00 日报 |

---

## context/ 背景知识

| 文档 | 摘要 | 最后更新 |
|------|------|---------|
| [context/topology.md](context/topology.md) | 服务器硬件、Docker 容器/网络、PostgreSQL、凭证、财务、域名与 SSL | 2026-05-09 |
| [context/zhipu-coding-plan.md](context/zhipu-coding-plan.md) | 智谱账号池、额度监控 JWT、错误码、并发控制、渠道亲和性 | 2026-04-15 |
| [context/hersoul-ai-static-site.md](context/hersoul-ai-static-site.md) | hersoul.ai 海外静态官网：75.127.3.187、nginx HTTPS、File Browser、Let's Encrypt | 2026-05-02 |
| [context/edgeone-cdn-runbook.md](context/edgeone-cdn-runbook.md) | EdgeOne CDN 全站加速操作手册：S1-S5 执行步骤、DNS 记录、规则引擎、SSE 防缓冲 | 2026-05-25 |
| [context/edgeone-cdn-decisions.md](context/edgeone-cdn-decisions.md) | EdgeOne CDN 选型决策记录：5 方案对比、NS vs CNAME、SSE 风险、Plan B | 2026-05-22 |

---

## 脚本

### her-gateway

| 脚本 | 用途 |
|------|------|
| [scripts/gateway/gw-admin.sh](scripts/gateway/gw-admin.sh) | Admin API 快捷调用（零登录，凭证在 `~/.config/her/gateway-admin.env`） |
| [scripts/gateway/compare-upstream-log.py](scripts/gateway/compare-upstream-log.py) | 按 gateway request_id 对比 new-api 兼容上游 `/api/log/token`，辅助定位 504/慢请求 |
| [scripts/gateway/export-daily-usage.py](scripts/gateway/export-daily-usage.py) | 导出 gateway 每日用量数据 |
| [scripts/gateway/health-check.sh](scripts/gateway/health-check.sh) | 全链路健康检查 |
| [scripts/gateway/backup-configs.sh](scripts/gateway/backup-configs.sh) | 从服务器拉配置到本地 backups/ |
| [scripts/gateway/stress-test.sh](scripts/gateway/stress-test.sh) | 压测 gateway（通用工具，不进部署流程） |

### her-web / herclub / salon

> her-web、herclub 部署脚本已迁移到 **her-cicd** skill。

| 脚本 | 用途 |
|------|------|
| `/Users/suyuan/Documents/her-source/salon/scripts/switch-her-backend.sh` | 切换 salon 的 her-web 后端：local / cloud / prod / status |

---

## Changelog

> 直接用 `grep -n "关键词" changelog.md` 搜索。更早条目见 `changelog-archive/`。

---

## 归档

| 文件 | 说明 |
|------|------|
| `changelog-archive/2026-05-early.md` | 2026-05-01 至 2026-05-14 的 changelog 条目 |
| `changelog-archive/2026-04.md` | 2026-04 及更早的 changelog 条目 |

---

## 更新说明

新增文档 / 运维操作后：
1. 操作文件放 `ops/`，背景知识放 `context/`
2. 本索引对应表格加一行（文档 / 摘要 / 最后更新）
3. `changelog.md` 顶部追加一条（3 行格式，见 SKILL.md）
