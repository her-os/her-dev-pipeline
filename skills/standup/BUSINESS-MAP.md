# Her 产品矩阵 — 业务逻辑地图

> 用途：issue 分诊路由。帮 subagent 判断一个 issue 归哪个仓库、哪个业务域。
> 这是路由地图，不是代码地图。具体代码位置由 subagent 自行搜索。

## 架构总览

```
salon (桌面客户端)    hersoul.cn (Web)    club.hersoul.cn
      │                    │                    │
      │    ┌───────────────┤                    │
      ▼    ▼               ▼                    ▼
 her-gateway          her-web  ◄──────── herclub 前端
 AI 模型网关          SaaS 引擎          (纯静态 SPA，API 全走 her-web)
 api.tokenic.cn       hersoul.cn
      │                    │
      ▼                    ▼
 35+ AI 供应商       Stripe / 微信 / 支付宝
```

**关键交互**：
- salon → her-gateway（OpenAI 兼容 API，AI 对话）
- salon → her-web（用户信息、计费、配额、官方通道配置）
- her-web → her-gateway（Admin API，同步用户 token/quota/group）
- herclub → her-web（订单、支付、鉴权）
- 支付平台 → her-web / her-gateway（Webhook 回调）

## 仓库 × 业务域

### her-web（SaaS 引擎）

| 域 | 一句话 |
|----|--------|
| 用户与鉴权 | 注册、登录、邀请码入场 |
| 订阅与套餐 | Pro/Max 订阅生命周期（购买、续费、升级、取消） |
| 额度管理（三池） | Trial / Subscription / Wallet 三个独立额度池；her-web 变动后通过 Admin API 同步到 gateway 的 Token.RemainQuota |
| 支付与订单 | 结账、支付回调、退款；对接 Stripe / 微信 / 支付宝 / Creem |
| API 网关接入控制 | 同步用户的模型访问权限和额度到 her-gateway |
| HerClub 会员 | 独立于 AI 订阅的实体会员卡（77元/年），微信支付 |
| 管理后台 | 用户管理、订单财务、额度调整、邀请码 |

### her-gateway（AI 模型网关）

| 域 | 一句话 |
|----|--------|
| AI 中继 | 接收请求 → 路由渠道 → 转发上游 AI → 结算 token；含 retry / failover / 渠道亲和 |
| 渠道管理 | 上游 API 供应商配置、健康检测、模型列表同步 |
| 用户与认证 | Token(API Key) 鉴权、OAuth、2FA |
| 计费与额度 | Quota 预扣/结算、充值码、支付、邀请返利；三层：Token 限额 / User 余额 / Subscription 周期额度 |
| 订阅 | 时长型订阅计划，独立额度池，按日/周/月重置 |
| 模型元数据 | 全局模型目录、input/output 价格比率 |

### salon（桌面客户端）

| 域 | 一句话 |
|----|--------|
| 对话 (Chat) | 多会话 AI 对话、工具调用、Agent 子任务、流式输出 |
| 模型 & Provider | 官方通道 + 自定义第三方 provider，远程模型列表下发 |
| 账户 / 计费 | 登录态、订阅状态、配额同步、到期提醒 |
| Skills | 内置 + 自定义 Skill，启用/禁用开关 |
| Ear（语音随记） | 本地语音录制 + 跨设备同步 |
| IM 远程适配器 | Telegram / 飞书桥接 AI 对话 |

### herclub（静态站）

纯前端 SPA，所有后端逻辑在 her-web 的 herclub service 层。herclub 的 issue 通常需要在 her-web 侧修复。

## 分诊路由规则

收到一个 issue 时，按关键词路由：

1. **额度、quota、三池、Trial/Subscription/Wallet、remain_quota** → her-web 额度管理
2. **支付、订单、微信支付、Stripe、checkout** → her-web 支付与订单（herclub 支付问题也在这里）
3. **订阅、套餐、Pro/Max、升级、续费** → her-web 订阅与套餐
4. **模型调用失败、超时、渠道、relay、channel** → her-gateway AI 中继
5. **客户端 UI、消息气泡、语音、Skill、Ear** → salon
6. **HerClub、会员卡、club.hersoul.cn** → herclub 前端 + her-web herclub service
7. **注册、登录、邀请码** → her-web 用户与鉴权
8. **管理后台、admin 页面** → her-web 管理后台
9. **quota 同步、gateway 余额不一致** → 跨域：her-web 额度管理 + API 网关接入控制

路由只是缩小范围，不能替代代码搜索。拿到路由结果后仍需在对应仓库中搜索确认。
