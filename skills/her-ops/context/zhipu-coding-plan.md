# 智谱 Coding Plan

> 最后更新：2026-04-15

## 账号池概况

3 个 Z.AI Max 账号，走 Anthropic 协议端点 `https://api.z.ai/api/anthropic`。

| 渠道 ID | 名称 | 套餐 | 状态 |
|---------|------|------|------|
| 1 | 智谱 Coding Plan #1（小七） | Max | 启用 |
| 2 | 智谱 Coding Plan #2（夙愿） | Max | 启用 |
| 4 | 智谱 Coding Plan #3（一号） | Max | 启用 |

兜底渠道：渠道 3「智谱官方 API」。

## 额度监控（JWT）

后台任务 `StartZhipuQuotaMonitorTask()`（`main.go:116` 启动），10-20 分钟随机轮询。

接口：`GET https://api.z.ai/api/monitor/usage/quota/limit`，Bearer JWT 鉴权。

JWT 来源：智谱控制台登录后浏览器 localStorage 里的 token，配在渠道「额外设置」的 `zhipu_quota_jwt` 字段。

返回结构中关键的两个限制：
- `TOKENS_LIMIT unit=3`：5 小时滚动窗口 token 限额
- `TOKENS_LIMIT unit=6`：周 token 限额

**自动停用逻辑**：`percentage >= 80-90%`（随机阈值）→ 停用渠道；`percentage < 50%` → 恢复。

### 2026-04-15 验证结果

| 渠道 | 5h token | 周 token | 工具月限 |
|------|---------|---------|---------|
| #2 夙愿 | 1% | 1% | 35% |
| #3 一号 | 1% | 1% | 0% |

## 智谱错误码

| 错误码 | 含义 | 网关行为 |
|--------|------|---------|
| 1302 | 临时并发限流 | 重试（不禁用） |
| 1308 | 5 小时窗口额度耗尽（带 nextFlushTime） | 禁用该 Key |
| 1310 | 周额度耗尽 | 禁用该 Key |
| 1309 | 套餐过期 | 禁用 + 告警 |

代码位置：`service/channel.go`（错误码判断），`controller/relay.go`（重试逻辑）。

## 每 Key 并发控制

`service/key_concurrency.go`：atomic CAS 无锁计数器。当前 Key 并发数达上限时自动分流到其他 Key。

上限通过渠道设置 `max_concurrency_per_key` 配置（Max 建议 2-3）。

## 渠道亲和性

`channel_affinity_setting.go` 中的 `"glm coding plan cache"` 规则。

同一个用户（token_id）30 分钟内的 GLM 请求锁定同一个渠道，提升上下文缓存命中率。渠道被额度监控停用时允许 failover。

### 2026-04-15 验证结果

**亲和性**：发 3 个 GLM 请求，日志确认全走渠道 2。改动前同一用户的请求在 1-4 之间乱跳。

**并发**：单渠道（单 Coding Plan 账号）实际能撑 7-8 并发。Z.AI 的 1302 限流是滑动窗口机制，短时间密集请求会收紧窗口。3 渠道总并发约 20-24。

**上下文缓存**：Z.AI Anthropic 端点支持上下文缓存，但有最小 token 阈值。压测时用的系统提示词太短（~100-190 token）没触发缓存。真实 Claude Code 会话的系统提示词上万 token，缓存正常命中。

**测试脚本**：`scripts/stress-test.sh`（运维 skill 目录下）。

## SystemPromptRewrite

渠道级系统提示词文本替换，把 Agent SDK 身份改写成 Claude Code 身份（行为伪装）。

配置在渠道「设置」的 `system_prompt_rewrite` 字段（JSON map: old→new）。
代码位置：`relay/claude_handler.go`。
