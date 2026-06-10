# 上游渠道接入 runbook

> 最后更新：2026-05-25

建一条新的上游 AI 渠道（智谱、mimo、moonshot、OpenRouter 等），从代码到 DB 完整流程。

## 环境分流

| 场景 | 入口 |
|------|------|
| **生产加渠道**（已有渠道类型，只加新 channel/定价） | `gw-admin.sh` 或 SSH + psql，详见 `gateway-admin-api.md` |
| **本地搭建开发环境** | **her-cicd** skill → `ops/local-dev-setup.md` |
| **首次接入新渠道类型**（改代码 + 建渠道 + 配定价） | 本文的字段清单、定价公式、坑清单仍有效；Admin API 调用和 DB 操作按当前环境用 psql，不要用下方过时的 MySQL 命令 |

> **注意**：下方 Admin 鉴权、建渠道 curl、端到端验证段的 `her-mysql-local`（MySQL）命令已过时——本地和生产都已切到 PostgreSQL。这些段落保留的价值是字段语义和流程顺序，具体命令需要按 her-cicd 本地环境或生产环境适配。

---

## 前置：确认代码层已接入

建渠道前，确保 her-gateway 后端代码已经认识这个渠道类型（`channel_type`）。检查清单：

| 位置 | 需要什么 |
|------|---------|
| `constant/channel.go` | `ChannelTypeXxx = N` 常量 + `ChannelBaseURLs[N]` + `ChannelTypeNames[N]`；如走 Claude 格式的 Coding Plan，还要加 `ChannelSpecialBases["xxx-coding-plan"]` |
| `constant/api_type.go` | `APITypeXxx` 常量 |
| `common/api_type.go` | `case constant.ChannelTypeXxx: apiType = constant.APITypeXxx` |
| `relay/relay_adaptor.go` | `case constant.APITypeXxx: return &xxx.Adaptor{}` |
| `relay/channel/xxx/` | 实现 `channel.Adaptor` 接口（核心方法：`GetRequestURL` / `SetupRequestHeader` / `ConvertClaudeRequest` / `DoRequest` / `DoResponse`） |
| `web/src/constants/channel.constants.js` | 前端渠道选项 `{value: N, color: 'xxx', label: 'xxx'}` |
| `common/anthropic_only_channel.go` | **如果渠道只支持 Anthropic 原生 `/v1/messages`**（比如 MiMo），必须把 `ChannelTypeXxx` 加进 `anthropicOnlyChannelTypes` 白名单。漏了会导致后台「测试渠道」按钮假失败（testChannel 默认走 OpenAI 格式），如果 `auto_ban=1` 还可能触发定时巡检误禁用。moonshot **不**加（它同时支持 OpenAI 格式）。**2026-04-17 新增集成点** |

跑完单测 + `go build` 成功，才能往下走建渠道。

### Anthropic-only 场景：testChannel 假失败识别

症状：渠道建完后，真实流量（`/v1/messages`）能正常拿到流式响应 + 日志记账正确，**但后台点「测试渠道」按钮返回失败**。

根因：`controller/channel-test.go::buildTestRequest` 和 `normalizeChannelTestEndpoint` 会按渠道类型决定构造 `ClaudeRequest` 还是 `GeneralOpenAIRequest`。如果 `IsAnthropicOnlyChannel(channelType) == false`（白名单漏注册），测试链路就默认走 OpenAI 端点 → `ConvertOpenAIRequest` → adaptor 返回 `not implemented` → 失败。

修复：见上面表格的 `common/anthropic_only_channel.go` 那一行。

---

## Admin 鉴权

两种方式任选：

**方式 A：用户名密码登录拿 session cookie**（适合手动操作）
```bash
curl -c /tmp/cookies.txt -X POST "http://localhost:3001/api/user/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"<admin-password>"}'
```

**方式 B：直接 DB 写 access_token**（适合脚本化）

⚠️ **`users.access_token` 是 `char(32)`，token 长度必须正好 32**。用 `openssl rand -hex 16` 生成（32 个 hex 字符）。长度不对会 `ERROR 1406 Data too long`。

```bash
ADMIN_TOKEN=$(openssl rand -hex 16)
docker exec her-mysql-local mysql -uroot -pher_dev_local her_gateway \
  -e "UPDATE users SET access_token='$ADMIN_TOKEN' WHERE id=1;"
```

调 admin API 时两个 header 都要带（缺一个被 `middleware/auth.go` 拒）：
```
Authorization: <access_token>       # 注意：不是 Bearer <token>，直接裸 token
New-Api-User: 1
```

---

## 建渠道（Admin API）

路径：`POST /api/channel/`，body 结构：
```json
{
  "mode": "single",
  "channel": { ... }
}
```

### 完整字段清单

`channel` 对象字段按重要性排序：

| 字段 | 类型 | 说明 | 典型值 |
|------|------|------|--------|
| `type` | int | 渠道类型常量（`constant/channel.go` 里的 `ChannelTypeXxx`） | 58（mimo） |
| `name` | string | 显示名（会在 admin UI 和日志里看到） | "小米 MiMo Coding Plan #1" |
| `key` | string | API Key；多 key 池用 `\n` 换行分隔 | `tp-xxx...`（**从 env var 读，别硬编码**） |
| `base_url` | string | 上游端点 URL；或 `ChannelSpecialBases` 注册的标识符 | `https://token-plan-cn.xiaomimimo.com/anthropic` |
| `models` | string | 逗号分隔的模型 ID 列表 | `mimo-v2-pro` |
| `group` | string | 用户组（`default` 让所有 token 都能用） | `default` |
| `status` | int | `1`=启用，`2`=禁用，`3`=自动禁用 | 1 |
| `priority` | int | 同一 model 多渠道时的优先级（大的先用） | 0 |
| `weight` | int | 同优先级渠道的加权轮询权重 | 1 |
| `auto_ban` | int | 上游连续报错时是否自动禁用（`1`=是） | **0**（业务决策：本项目统一不开，见下方说明） |
| `setting` | string（JSON） | 渠道级高级设置，最常用的子字段： | 见下 |
| `header_override` | string（JSON） | 请求头替换/清空规则 | `{"*":"","User-Agent":"claude-code/2.1.94"}` |
| `model_mapping` | string（JSON） | 客户端 model 名映射到上游 model 名 | `{"claude-3-5-sonnet":"mimo-v2-pro"}` |
| `param_override` | string（JSON） | 请求体参数覆盖 | `{"temperature":0.2}` |

### DeepSeek Anthropic thinking 冲突

DeepSeek 的 Anthropic 接口会把 `output_config.effort` 当成 reasoning effort。请求如果同时带：

- `thinking={"type":"disabled"}`
- `output_config={"effort":"high"}` 或 `reasoning_effort`

上游会返回 `400 thinking options type cannot be disabled when reasoning_effort is set`。

VIP `mimo-v2.5-pro -> deepseek-v4-pro` 的 channel 18 已用 `param_override` 处理：当 `thinking.type=disabled` 时删除 `output_config` 和 `reasoning_effort`。新增 DeepSeek Anthropic 映射渠道时，如保留客户端的 `thinking.disabled`，要同步加同类规则。

### 业务决策：`auto_ban` 统一设 0（不开）

**2026-04-18 夙愿拍板**：新建所有渠道统一 `auto_ban=0`。

原因：
- her-gateway 目前只给自己的 her-web 做上游，不是对外多租户，流量可控，没必要靠自动禁用兜底
- 定时巡检调的是 `controller/channel-test.go::testChannel`，任何测试链路的误判（典型：Anthropic-only 渠道白名单漏注册、上游短暂 5xx、本地 ratio 配置没对齐）都会把一条正常渠道强制禁掉，运维反而要手动 re-enable
- 04-17 MiMo 渠道就是因为 `auto_ban=1` + testChannel 对 Anthropic-only 假失败，被巡检误禁过一次

如果未来对外开放 + 流量大时再考虑打开。目前新建渠道 curl body 里把 `auto_ban` 设 0。

已在线上的渠道如果发现 auto_ban=1，走 admin API `PUT /api/channel/` 改回 0。

### `setting` 字段的关键子字段

这是一个 JSON 字符串（再套一层），常用 key：

| key | 类型 | 用途 |
|-----|------|------|
| `system_prompt_rewrite` | `map<string,string>` | 渠道级系统提示词文本替换。智谱/mimo Coding Plan 用它把 "Claude Agent SDK" 身份改写成 "Claude Code CLI" 身份，通过上游对官方客户端的识别 |
| `zhipu_quota_jwt` | string | 智谱专用，浏览器控制台 localStorage 拷来的 JWT，用于额度监控 |
| `max_concurrency_per_key` | int | 每个 Key 的并发上限（智谱 Max 建议 2-3） |

### `header_override` 的语法

特殊 key `"*"` 表示通配：
- `{"*": ""}` → 清空所有原始请求头（不透传任何客户端 header）
- `{"*": "", "User-Agent": "claude-code/2.1.94"}` → 清空所有，然后只加 UA
- `{"X-Foo": "bar"}` → 追加/覆盖这个 header（不清空其他）

### 典型 curl 建渠道（mimo 示例）

```bash
export MIMO_API_KEY="<从安全存储读>"
ADMIN_TOKEN=$(cat /tmp/her_admin_token.txt)

python3 <<'PY' > /tmp/channel_body.json
import json, os
body = {
  "mode": "single",
  "channel": {
    "type": 58,
    "name": "小米 MiMo Coding Plan #1",
    "key": os.environ["MIMO_API_KEY"],
    "base_url": "https://token-plan-cn.xiaomimimo.com/anthropic",
    "models": "mimo-v2-pro",
    "group": "default",
    "status": 1, "priority": 0, "weight": 1, "auto_ban": 0,
    "setting": json.dumps({"system_prompt_rewrite": {
      "You are a Claude agent, built on Anthropic's Claude Agent SDK.": "You are Claude Code, Anthropic's official CLI for Claude.",
      "You are Claude Code, Anthropic's official CLI for Claude, running within the Claude Agent SDK.": "You are Claude Code, Anthropic's official CLI for Claude.",
      "cc_entrypoint=sdk-cli": "cc_entrypoint=cli"
    }}, ensure_ascii=False),
    "header_override": json.dumps({"*": "", "User-Agent": "claude-code/2.1.94"}, ensure_ascii=False),
  },
}
print(json.dumps(body, ensure_ascii=False))
PY

curl -s -X POST "http://localhost:3001/api/channel/" \
  -H "Authorization: $ADMIN_TOKEN" \
  -H "New-Api-User: 1" \
  -H "Content-Type: application/json" \
  --data @/tmp/channel_body.json
```

⚠️ **别用 bash heredoc 拼 JSON**——shell 单双引号和 `$` 转义会把 API key 或 setting 吞掉。用 Python 生成 JSON 文件，curl `--data @file` 读。

---

## 定价配置（必做）

渠道建了但没配定价，请求会被定价中间件拦，返回 `模型 xxx 的价格未配置`。

### 定价基准

看 `setting/ratio_setting/model_ratio.go:14`：
```
USD = 500  // $0.002 = 1 -> $1 = 500
```
意思是 ratio 的基准单位 `1` 对应 `$0.002/1K tokens` = `$2/1M tokens`。

her-gateway 当前部署里 `USDExchangeRate=1`，借 USD 的壳直显人民币——所以**实际等价于 `1 ratio = ¥2/1M tokens`**。

### 四个 ratio 字段的语义

存在 `options` 表，四个独立 key，每个 value 是 `{modelName: number}` 格式的 JSON：

| Option key | 含义 | 计算公式 |
|-----------|------|---------|
| `ModelRatio` | input 单价倍率 | input ¥/1M = ratio × 2 |
| `CompletionRatio` | output 相对 input 的倍率 | output ¥/1M = ModelRatio × CompletionRatio × 2 |
| `CacheRatio` | cache 命中读取相对 input 的倍率 | cache read ¥/1M = ModelRatio × CacheRatio × 2 |
| `CreateCacheRatio` | cache 写入相对 input 的倍率 | cache write ¥/1M = ModelRatio × CreateCacheRatio × 2 |

### 从人民币单价反推 ratio

```
ModelRatio       = input 单价(¥/1M) / 2
CompletionRatio  = output 单价 / input 单价
CacheRatio       = cache read 单价 / input 单价
CreateCacheRatio = cache write 单价 / input 单价（免费则 0）
```

### 参照现有渠道

智谱 glm-5.1（input ¥8 / output ¥28 / cache ¥2 / create 免费）：
- ModelRatio=4, CompletionRatio=3.5, CacheRatio=0.25, CreateCacheRatio=0

mimo-v2-pro（input ¥7 / output ¥21 / cache 读 ¥1.4 / cache 写免费）：
- ModelRatio=3.5, CompletionRatio=3, CacheRatio=0.2, CreateCacheRatio=0

### 更新定价（本地 admin API，热生效）

```bash
python3 <<'PY'
import json, urllib.request
token = open('/tmp/her_admin_token.txt').read().strip()
updates = [
    ("ModelRatio",       {"glm-5.1":4,    "mimo-v2-pro":3.5}),
    ("CompletionRatio",  {"glm-5.1":3.5,  "mimo-v2-pro":3}),
    ("CacheRatio",       {"glm-5.1":0.25, "mimo-v2-pro":0.2}),
    ("CreateCacheRatio", {"glm-5.1":0,    "mimo-v2-pro":0}),
]
for key, value in updates:
    body = json.dumps({"key": key, "value": json.dumps(value, ensure_ascii=False)}).encode()
    req = urllib.request.Request("http://localhost:3001/api/option/", data=body, method="PUT",
        headers={"Authorization": token, "New-Api-User": "1", "Content-Type": "application/json"})
    urllib.request.urlopen(req).read()
PY
```

⚠️ 合并时**保留旧条目**——直接 PUT 整个 map 会覆盖掉其它模型的定价。先 SELECT 读出来再加新条目。

### 生产环境改定价

线上走 SSH + `sudo docker exec` 改 PostgreSQL 的 options 表，改完**必须重启 new-api**（内存缓存不热更新）。细节见 `gateway-admin-api.md`。

### 绕过定价（本地调试用）

把 options 表 `SelfUseModeEnabled` 设 `true`——所有未配价的模型都放行不扣费。**生产绝对别开**。

---

## Cache 同步延迟

建完渠道立刻发请求会报 `No available channel for model xxx under group default (distributor)`——**不是 bug**。

原因：`common/init.go:83` 的 `MEMORY_CACHE_ENABLED` 默认开启，渠道 cache 按 `SYNC_FREQUENCY`（默认 60s）轮询刷新。新渠道要等下一轮 sync 才能被路由。

观察 `docker logs new-api | grep "channels synced"` 确认同步频率。等到下一条 "channels synced from database" 出来后再发请求。

（生产环境同理——新建渠道后 60s 内的请求可能拿不到。）

---

## 端到端验证

对着**本地 gateway** 而不是上游直连发一次请求，确认链路通：

```bash
USER_TOKEN=$(docker exec her-mysql-local mysql -uroot -pher_dev_local -sN \
  -e "USE her_gateway; SELECT \`key\` FROM tokens WHERE id=1;")

curl -sS -N -X POST "http://localhost:3001/v1/messages" \
  -H "Authorization: Bearer $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  -d '{"model":"mimo-v2-pro","max_tokens":200,"stream":true,
       "messages":[{"role":"user","content":"hi"}]}'
```

验收看三件事：
1. 流式 SSE 输出 `event: message_start` 到 `event: message_stop` 完整
2. `docker exec her-mysql-local mysql ... -e "SELECT id, model_name, channel_id, prompt_tokens, completion_tokens, quota FROM logs ORDER BY id DESC LIMIT 1"` 有新记录
3. 手算验证：`quota = prompt × ModelRatio + completion × ModelRatio × CompletionRatio` 对得上

三个都对才算 **Rule 5 绿灯**。

---

## 常见坑清单

| 症状 | 根因 | 修复 |
|------|------|------|
| `Unauthorized, invalid access token` | token 不是 char(32) 或漏了 `New-Api-User` 头 | `openssl rand -hex 16` 生成；两个 header 都带 |
| `channel cannot be empty` | body 里 `channel` 是空对象或字段没透传 | Python 生成 JSON 而不是 bash heredoc |
| `No available channel for model xxx` | cache 还没同步 | 等 60s，或重启 new-api |
| `模型 xxx 的价格未配置` | 四个 ratio 里没这个 model key | 按上面公式算好配齐四个 |
| 渠道建了但日志里 `channel_id=0` | abilities 表 INSERT 失败 | 查 `abilities WHERE channel_id=N enabled=1` 确认行在 |
| 上游识别出"你不是 Claude Code" | `system_prompt_rewrite` 没配或映射没命中 | 从智谱渠道抄映射，注意引号转义 |
| 建了渠道但列表里看不见 | 缓存/分页 | `?p=0&page_size=999` 或查 DB |

---

## 相关文档

- `gateway-admin-api.md` — Admin API 端点清单、鉴权、定价系统通用公式
- `context/zhipu-coding-plan.md` — 智谱专有的额度监控、错误码、并发控制
