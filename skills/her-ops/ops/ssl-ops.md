# SSL 证书检查与续签

## Part 1: 检查

决策级别: 绿灯
触发条件: 定期巡检（由 health-patrol 调用），或怀疑证书即将到期 / 出现 Traefik 自签名证书警告

### 前置检查
- 确认网络可达（能从本机访问目标域名的 443 端口）
- api.roome.cn 使用自签名证书（预期行为），不计入 Let's Encrypt 检查范围

### 需检查的域名

| 域名 | 预期颁发者 | 说明 |
|------|-----------|------|
| `api.tokenic.cn` | Let's Encrypt (R13) | gateway API 端点 |
| `hersoul.cn` | Let's Encrypt | her-web 产品前端 |
| `club.hersoul.cn` | Let's Encrypt | herclub 会员页 |

### 步骤

1. 检查 api.tokenic.cn 证书
   ```bash
   echo | openssl s_client -connect api.tokenic.cn:443 -servername api.tokenic.cn 2>/dev/null | openssl x509 -noout -dates
   ```
   验证: 输出 `notAfter=...`，计算距今天数。>= 14 天为正常

2. 检查 hersoul.cn 证书
   ```bash
   echo | openssl s_client -connect hersoul.cn:443 -servername hersoul.cn 2>/dev/null | openssl x509 -noout -dates
   ```
   验证: 同上

3. 检查 club.hersoul.cn 证书
   ```bash
   echo | openssl s_client -connect club.hersoul.cn:443 -servername club.hersoul.cn 2>/dev/null | openssl x509 -noout -dates
   ```
   验证: 同上

4. （可选）查看颁发者，确认是 Let's Encrypt 而非 Traefik 自签名
   ```bash
   echo | openssl s_client -connect api.tokenic.cn:443 -servername api.tokenic.cn 2>/dev/null | openssl x509 -noout -issuer
   ```
   验证: 输出包含 `Let's Encrypt` 或 `R13`。如果输出包含 `TRAEFIK DEFAULT` → 说明 ACME 失败，立即执行下方续签步骤

### 到期天数快速计算（Python 一行）

```bash
echo | openssl s_client -connect api.tokenic.cn:443 -servername api.tokenic.cn 2>/dev/null \
  | openssl x509 -noout -enddate \
  | python3 -c "
import sys, datetime
line = sys.stdin.read().strip()
exp = datetime.datetime.strptime(line.replace('notAfter=',''), '%b %d %H:%M:%S %Y %Z')
days = (exp - datetime.datetime.utcnow()).days
print(f'到期: {exp.date()}，剩余 {days} 天')
"
```

### 升级条件
- 任意 Let's Encrypt 域名剩余天数 < 14 天 → 执行下方 Part 2 续签
- 任意域名颁发者变成 `TRAEFIK DEFAULT`（自签名）→ 执行下方 Part 2 续签
- openssl 连接失败（返回空或报错）→ 检查域名 DNS 和服务器网络，必要时通知负责人

---

## Part 2: 续签

决策级别: 黄灯
触发条件: 上方检查发现任意 Let's Encrypt 域名剩余 < 14 天，或颁发者变成 `TRAEFIK DEFAULT`

### 前置检查
- 确认是 Let's Encrypt 域名（不是 api.roome.cn，它用自签名是预期行为）
- 确认域名有 ICP 备案（无备案的 .cn 域名 Let's Encrypt HTTP-01 验证会被 DNSPod 拦截）
  - `tokenic.cn`：有备案（京ICP备2026006105号）→ 可以续签
  - `roome.cn`：无备案 → HTTP-01 验证会失败，维持自签名是当前已知状态
- 确认当前 Traefik 在运行（`sudo docker ps | grep traefik`）

### 背景

Traefik 通过 ACME（自动证书管理环境）自动管理 Let's Encrypt 证书，配置使用 httpChallenge（HTTP-01 验证）。证书存储在 `/etc/dokploy/traefik/dynamic/acme.json`。

正常情况下 Traefik 会在证书到期前 30 天自动续签，无需手动干预。手动触发方式是重启 Traefik，让它立即检查并尝试续签。

### 步骤

1. 记录当前证书到期日（续签前基线）
   ```bash
   echo | openssl s_client -connect api.tokenic.cn:443 -servername api.tokenic.cn 2>/dev/null | openssl x509 -noout -dates
   echo | openssl s_client -connect hersoul.cn:443 -servername hersoul.cn 2>/dev/null | openssl x509 -noout -dates
   echo | openssl s_client -connect club.hersoul.cn:443 -servername club.hersoul.cn 2>/dev/null | openssl x509 -noout -dates
   ```
   验证: 记录每个域名的 `notAfter` 日期

2. 重启 Traefik 触发 ACME 刷新
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker restart dokploy-traefik'
   ```
   验证: 命令返回 `dokploy-traefik`，无报错

   **注意**: Traefik 重启期间（通常 < 10 秒）所有域名会短暂不可达。这是预期行为。

3. 等待 2 分钟，让 Traefik 完成 ACME 握手

4. 检查 Traefik 日志确认续签状态
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo docker logs dokploy-traefik --tail 50 2>&1 | grep -i "acme\|certif\|renew\|obtain"'
   ```
   验证:
   - 成功: 看到 `Certificate obtained successfully` 或 `Renewing certificate`
   - 失败: 看到 `Unable to obtain ACME certificate` 或 `invalid authorization`

5. 重新检查证书到期日
   ```bash
   echo | openssl s_client -connect api.tokenic.cn:443 -servername api.tokenic.cn 2>/dev/null | openssl x509 -noout -dates
   echo | openssl s_client -connect hersoul.cn:443 -servername hersoul.cn 2>/dev/null | openssl x509 -noout -dates
   echo | openssl s_client -connect club.hersoul.cn:443 -servername club.hersoul.cn 2>/dev/null | openssl x509 -noout -dates
   ```
   验证: `notAfter` 已更新，剩余天数 > 60 天（Let's Encrypt 证书有效期 90 天）

6. 核查 acme.json 中的证书列表（可选，用于确认续签确实写入）
   ```bash
   /usr/bin/ssh ubuntu@192.144.187.174 'sudo cat /etc/dokploy/traefik/dynamic/acme.json' \
     | python3 -c 'import json,sys; [print(c["domain"]["main"]) for c in json.load(sys.stdin).get("letsencrypt",{}).get("Certificates",[]) or []]'
   ```
   验证: 列出的域名包含需要续签的域名

### 回滚
重启 Traefik 是可逆操作（再次重启即可）。如果重启后服务不可达超过 1 分钟：
```bash
/usr/bin/ssh ubuntu@192.144.187.174 'sudo docker restart dokploy-traefik'
```
如仍不恢复，检查 Traefik 日志排查原因，通知负责人。

### 续签失败处理

**已知失败原因**：`roome.cn` 无 ICP 备案，DNSPod 会拦截 HTTP-01 验证请求，Traefik 日志会显示 `Invalid response from https://dnspod.qcloud.com/static/webblock.html`。这是已知现状，不需要修复。

**其他失败情况**：
1. 截图或保存 Traefik 日志中的 ACME 错误信息
2. 记录受影响域名和当前到期日
3. 写入 changelog.md
4. 通知负责人（当前阶段：在会话中告知）

### 升级条件
- 续签失败 + 证书到期日 < 7 天 → 升级为红灯，立即通知负责人
- 重启 Traefik 后所有域名不可达超过 5 分钟 → 立即通知负责人
- 怀疑 acme.json 文件损坏 → 不要动，立即通知负责人（直接编辑 acme.json 是黑灯操作）
