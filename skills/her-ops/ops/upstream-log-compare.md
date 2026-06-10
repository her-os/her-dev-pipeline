# Gateway 上游日志对比

> 最后更新：2026-05-15

用途：用户给出 gateway `request_id` 时，快速判断它在上游 new-api 兼容系统里的对应请求，以及慢/504 是卡在 gateway、relay，还是上游后端。

当前已知上游：imarouter，真实日志接口是 `https://api.imarouter.com/api/log/token`。如果 gateway channel 的 `base_url` 是 `https://relay.tokenic.cn`，排查日志时仍然要查 imarouter，不查 relay。

---

## 一键脚本

```bash
SKILL_DIR=/Users/suyuan/.claude/skills/her-ops
python3 $SKILL_DIR/scripts/gateway/compare-upstream-log.py <gateway_request_id>
```

可选参数：

```bash
python3 $SKILL_DIR/scripts/gateway/compare-upstream-log.py <gateway_request_id> \
  --upstream-base https://api.imarouter.com \
  --window-seconds 900 \
  --top 8
```

脚本只读：

- gateway 日志走 `scripts/gateway/gw-admin.sh GET /api/log/?request_id=...`
- channel key 走 SSH + psql 只读查询 `channels`
- 上游日志走 new-api 兼容接口 `/api/log/token`
- 不发模型请求，不改 gateway / relay / 上游配置
- 不打印 channel key

---

## 判断方法

gateway 的 `request_id` 是我们自己生成的，不等于上游请求 id。

对比时看这几项：

1. `gateway_start = gateway.created_at - gateway.use_time`
2. `upstream_start = upstream.created_at - upstream.use_time`
3. `model_name`
4. `prompt_tokens` / `completion_tokens`
5. `other.cache_tokens` / `other.cache_creation_tokens`
6. `request_path`

优先按开始时间对齐。504 场景下，gateway 往往没有完整 token 用量，只能用开始时间、模型、cache token 和附近请求顺序判断。

---

## 结论口径

如果出现：

- gateway 在约 180 秒记录 504；
- 上游日志在 300-400 秒后记录成功；
- 上游 `completion_tokens` / `quota` 正常；

那就不能说“上游直接失败”。

更准确的说法是：

> gateway 收到上游链路返回的 504，但上游后端任务继续跑完并计费。自动重试/切备用前，要先确认上游是否支持取消、幂等或不会重复计费。

如果上游没有对应日志，才继续看：

- gateway 到 relay 的 nginx access/error log；
- relay 到真实上游的 nginx upstream 时间；
- gateway 容器日志是否有 client disconnect、context canceled、timeout。

---

## 供应商排查要问什么

给供应商发上游 request id，不要只发 gateway request id。

问题要问清楚：

- 为什么客户端在 180 秒收到 504，但上游日志后来成功？
- 504 是 ALB / gateway / nginx 哪一层发的？
- 客户端断开或中间层 504 后，后端推理任务有没有取消？
- 已经 504 的请求是否还会计费？
- 长上下文请求首个 SSE event 前是否有 heartbeat？
- 是否能返回首段/首字耗时、排队耗时、prefill 耗时、生成耗时？

这几个答案决定我们能不能自动重试。没有取消或幂等保证时，自动重试可能造成重复生成和重复扣费。
