# Admin API 与定价

> 最后更新：2026-05-24

## 鉴权

所有管理接口在 `/api/` 下。**默认用脚本调，零登录。**

### 首选：gw-admin.sh（一行命令，零配置）

```bash
GW=/Users/suyuan/.claude/skills/her-ops/scripts/gateway/gw-admin.sh

$GW GET /api/channel/                                          # 查渠道列表
$GW GET /api/user/                                             # 查用户列表
$GW GET /api/user/303/quota                                    # 查指定用户余额
$GW PUT /api/user/303/quota -d '{"quota":100000}'              # 充值
$GW POST /api/user/303/token -d '{"name":"test"}'              # 代创建 token
$GW GET /api/log/                                              # 查调用日志
$GW GET '/api/log/request_body?request_id=<request_id>'        # 查请求/响应日志元信息
$GW GET '/api/log/request_body?request_id=<request_id>&include_body=true'  # 查请求/响应正文
```

凭证文件：`~/.config/her/gateway-admin.env`（已配置，包含 access_token + user_id）。

### 备选：裸 curl

```bash
source ~/.config/her/gateway-admin.env
curl -s -H "Authorization: $HER_GW_TOKEN" -H "New-Api-User: $HER_GW_USER" \
  "${HER_GW_BASE}/api/channel/"
```

### 备选：Session cookie（token 不可用时降级）

```bash
curl -s -c /tmp/her_cookies.txt -X POST "https://api.tokenic.cn/api/user/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"her","password":"HerAgent#2026"}'

curl -s -b /tmp/her_cookies.txt "https://api.tokenic.cn/api/channel/" \
  -H "New-Api-User: 1"
```

### 鉴权细节

- 两个 header 都要带：`Authorization` + `New-Api-User`，漏后者会被 `middleware/auth.go:97` 拦截
- access_token 是裸值，不加 `Bearer ` 前缀（代码会自动 strip，但历史文档多处写"不要加"，保持习惯）
- access_token 在 `users` 表 `access_token` 列，`char(32)`，用 `openssl rand -hex 16` 生成
- 面板地址：`https://api.tokenic.cn`，管理员：`her` / `HerAgent#2026`

## 主要端点

| 路径 | 用途 |
|------|------|
| `/api/user/` | 用户管理（创建、配额、状态） |
| `/api/token/` | Token/Key 管理（创建、额度、启停） |
| `/api/channel/` | 渠道管理（上游 AI 服务商配置、Key 池、代理、优先级） |
| `/api/option/` | 系统设置（ServerURL、渠道自动测试间隔等） |
| `/api/log/` | 调用日志（按用户/渠道/模型查用量） |
| `/api/log/request_body` | 请求/响应日志（按 request_id 查 inbound/upstream/upstream_response 快照；`include_body=true` 才返回正文） |
| `/api/group/` | 用户组（不同组可访问不同渠道和模型） |

`/api/log/request_body/<id>` 不存在；按 query string 过滤。`id=...` 当前不会按单条 ID 过滤，`keyword=...` 当前会被忽略并返回普通分页，排查时优先用 `request_id`。

常见 stage：
- `inbound`：客户端传入 gateway 的请求体。
- `upstream`：gateway 发给上游渠道的请求体。新日志中 JSON 请求会优先以 `body_encoding=json_diff` 存相对 `inbound` 的差异，`body_bytes` 仍是真实上游请求大小；旧日志或 diff 不省空间时仍是完整 text body。
- `upstream_response`：上游返回给 gateway 的可读响应体；仅记录文本、JSON、SSE 等可读 content-type，二进制响应会跳过。

### 请求/响应日志保留策略

生产 compose 显式配置：

```yaml
- REQUEST_LOG_RETENTION_DAYS=1
- REQUEST_LOG_CLEANUP_INTERVAL_MINUTES=60
```

含义：只保留最近 24 小时的 `request_body_logs`，每小时清理一次。代码默认值是 7 天；生产必须以 compose env 为准。

如果需要立刻释放 PostgreSQL 物理空间，只 `DELETE` 不够，Postgres 通常只会把空间留给表内复用。需要在删除旧行后执行：

```sql
VACUUM (FULL, VERBOSE, ANALYZE) request_body_logs;
```

`VACUUM FULL` 会拿表级排它锁。由于请求日志写入在请求路径上同步执行，生产回收空间前应临时设置 `REQUEST_LOG_ENABLED=false` 并 recreate `new-api`，回收完成后移除该临时 env 再 recreate。

### Admin 代户操作接口（2026-04-21 新增）

her-web 通过这些接口代替终端用户操作 gateway。全部需要 AdminAuth。

| 路径 | 方法 | 用途 |
|------|------|------|
| `/api/user/:id/quota` | GET | 查目标用户余额（绕过 Redis 缓存直读 DB） |
| `/api/user/:id/quota` | PUT | 给目标用户充值（支持 `Idempotency-Key` 幂等头） |
| `/api/user/:id/token` | POST | 代目标用户创建 token |
| `/api/user/:id/tokens` | GET | 列目标用户 token（分页） |
| `/api/user/:id/token/:token_id` | PUT | 代更新目标用户 token |
| `/api/user/:id/token/:token_id` | DELETE | 代删除目标用户 token |
| `/api/user/:id/group` | PUT | 改目标用户分组 |
| `/api/user/:id/logs` | GET | 查目标用户调用日志（分页+筛选） |
| `/api/user/:id/usage` | GET | 查目标用户用量统计（最长 1 个月跨度） |
| `/api/user/usage/token-totals` | POST | 批量查多个用户的 gateway token 全量累计 |

代码位置：`controller/user_admin_proxy.go`（handler）、`router/api-router.go`（路由定义）。

### 批量 Token Totals（2026-05-24 新增）

```bash
$GW POST /api/user/usage/token-totals -d '{"user_ids":[581],"usernames":["alice"],"start_timestamp":1710000000,"end_timestamp":1760000000}'
```

要点：
- 数据源只读 gateway `logs` 消费日志，不走 her-web telemetry。
- `user_ids` 和 `usernames` 至少传一个；`usernames` 是 gateway `users.username` 精确匹配。
- 时间范围可选；不传 `start_timestamp` / `end_timestamp` 就是全量累计。
- 返回 `input_tokens`、`output_tokens`、`cache_read`、`cache_creation`、`total_tokens`、`request_count`，以及 `missing_user_ids` / `missing_usernames`。

口径边界：
- gateway `token-totals` 是 gateway 计费日志口径，直接来自 `newapi.logs`。
- her-web 后台导航里的「API 日志」实际是 telemetry 页面，读 `telemetry_events` / `telemetry_sessions` / `telemetry_session_snapshots`，会解析客户端 JSONL 快照；它不是 gateway `logs` 的同步副本。
- 生产 `new-api` 当前未配置 `HER_WEB_AGENT_OPS_*`，gateway 消费日志不会自动导出到 her-web telemetry。不要用 her-web telemetry 的 token 数字校验 gateway 计费日志。

## 定价系统

### 计费公式

前端显示价格 = `model_ratio × 2 × group_ratio`（USD 模式下）

当前系统设置：`quota_display_type=USD`，`usd_exchange_rate=1`。
效果：`$6` 显示出来就是 `¥6`——借 USD 的壳直显人民币价格。

### 当前定价

| 模型 | model_ratio | completion_ratio | cache_ratio | 显示价（输入/输出/缓存命中） |
|------|------------|-----------------|-------------|---------------------------|
| glm-5 | 3.0 | 3.6667 | 0.25 | $6 / $22 / $1.5 |
| glm-5-turbo | 3.5 | 3.7143 | 0.2571 | $7 / $26 / $1.8 |
| glm-5.1 | 4.0 | 3.5 | 0.25 | $8 / $28 / $2.0 |

缓存创建（`create_cache_ratio`）全部为 0（免费）。

### 修改定价

定价数据存在 PostgreSQL 的 `options` 表，key 分别是 `ModelRatio`、`CompletionRatio`、`CacheRatio`、`CreateCacheRatio`，value 是 JSON 字符串。

通过 SSH + 数据库改（shell 多层转义会吃引号，用 base64 绕过）：

```bash
PG="dokploy-postgres.1.<TAB补全>"
DSN="postgresql://her:HerAgent%232026@172.17.255.75:5432/newapi"

# 构造 SQL 并 base64 编码
cat <<'EOF' | base64
UPDATE options SET value='{"glm-5": 3.0, "glm-5-turbo": 3.5, "glm-5.1": 4.0}' WHERE key='ModelRatio';
EOF

# 通过 base64 管道执行，避免引号被 shell 吃掉
$SSH "echo '<base64>' | base64 -d | sudo docker exec -i $PG psql '$DSN'"
```

**改完必须重启 new-api**（内存缓存不会自动刷新）：`$SSH "sudo docker restart new-api"`
