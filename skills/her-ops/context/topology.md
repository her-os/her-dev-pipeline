# Her Gateway 服务器拓扑

> 最后更新：2026-04-18

---

## 服务器

| 项目 | 值 |
|------|-----|
| 提供商 | （待补充） |
| IP | 192.144.187.174（入站/SSH） |
| 出口 IP | 81.70.184.21（2026-06-09 起，疑 K8s 迁移期 VPC 变更；外部 IP 白名单需放行此 IP，见 SKILL.md 坑 #17） |
| 用户名 | ubuntu |
| 认证 | SSH 公钥（ed25519），已配置免密 |
| 系统 | （待确认，大概率 Ubuntu） |
| Docker | 已安装，需 sudo |
| Dokploy | v0.28.8，端口 3000 |

---

## Docker 网络

| 网络 | 用途 | 连接的容器 |
|------|------|-----------|
| `dokploy-network` | Traefik ↔ 所有服务 | dokploy-traefik, new-api, dokploy, dokploy-redis, dokploy-postgres |
| `new-api-network` | new-api ↔ Redis 内部通信 | new-api, redis |

**关键**：new-api 同时在两个网络上。`dokploy-network` 是 Traefik 路由的必要条件，`new-api-network` 是 redis 通信的内部网络。

---

## 容器清单

| 容器 | 镜像 | 端口 | 网络 | 重启策略 |
|------|------|------|------|---------|
| `new-api` | `ghcr.io/her-os/her-gateway:main`（GHCR 远程镜像，CI 自动构建） | 3000/tcp（内部） | dokploy-network + new-api-network | always |
| `redis` | `redis:7-alpine` | 6379/tcp（内部） | new-api-network | always |
| `dokploy-traefik` | `traefik:v3.6.7` | 80→80, 443→443 | dokploy-network | — |
| `dokploy` | `dokploy/dokploy:v0.28.8` | 3000→3000 | dokploy-network | — |
| `dokploy-redis` | `redis:7` | 6379（内部） | dokploy-network | — |

**⚠️ Port 3000 碰撞**：`new-api` 和 `dokploy` 面板都监听 3000。服务器上 `curl localhost:3000` 默认走 IPv6（`::1`）会打到 Dokploy 面板（返回 HTML / 401），不是 gateway。验证 gateway 要用 `curl http://127.0.0.1:3000` 或 `docker exec new-api wget -qO- http://localhost:3000/api/status`。
| `dokploy-postgres` | `postgres:16` | 5432（内部） | dokploy-network | — |

---

## 数据库

| 项目 | 值 |
|------|-----|
| 类型 | PostgreSQL |
| 地址 | 172.17.255.75:5432 |
| 数据库名 | newapi |
| 用户名 | her |
| 密码 | HerAgent#2026 |
| DSN | `postgresql://her:HerAgent%232026@172.17.255.75:5432/newapi` |

**注意**：密码里有 `#`，DSN 里必须 URL 编码为 `%23`。这个坑踩过一次（docker-compose 的 .env 文件会把 `#` 后面的内容当注释截断），现在 DSN 直接硬编码在 docker-compose.yml 的 environment 里。

---

## 域名与 DNS

| 域名 | DNS 提供商 | A 记录指向 | 用途 |
|------|-----------|-----------|------|
| `api.tokenic.cn` | DNSPod/腾讯云 | 192.144.187.174 | API 端点（对外） |
| `api.roome.cn` | DNSPod/腾讯云 | 192.144.187.174 | 管理面板（对内） |
| `dok.tokenic.cn` | DNSPod/腾讯云 | 192.144.187.174 | Dokploy 面板 |
| `dok.roome.cn` | DNSPod/腾讯云 | 192.144.187.174 | Dokploy 面板（备） |
| `relay.tokenic.cn` | DNSPod/腾讯云 | 104.194.94.116 (bwg-la) | imarouter 反向代理加速节点（nginx on BandwagonHost LA CN2） |
| `relay-pl.tokenic.cn` | DNSPod/腾讯云 | 104.194.94.116 (bwg-la) | pipellm 反向代理加速节点 |
| `relay-cr.tokenic.cn` | DNSPod/腾讯云 | 104.194.94.116 (bwg-la) | CodingRouter 反向代理加速节点 |

**ICP 备案状态**：
- `tokenic.cn`：有备案（京ICP备2026006105号）→ SSL 正常
- `roome.cn`：无备案 → Let's Encrypt HTTP-01 验证被 DNSPod 拦截

---

## SSL 证书

| 域名 | 颁发者 | 状态 | 到期时间 |
|------|--------|------|---------|
| `api.tokenic.cn` | Let's Encrypt (R13) | 有效 ✅ | 2026-07-08 |
| `api.roome.cn` | TRAEFIK DEFAULT CERT | 自签名 ❌ | — |
| `test.hersoul.cn` | Let's Encrypt (YR2) | 有效 ✅ | 2026-09-09 |
| `dok.tokenic.cn` | Let's Encrypt | 有效 ✅ | （待确认） |
| `dok.roome.cn` | Let's Encrypt | 有效 ✅ | （待确认） |
| `relay.tokenic.cn` | Let's Encrypt | 有效 ✅ | （待确认） |
| `relay-pl.tokenic.cn` | Let's Encrypt | 有效 ✅ | 2026-08-14 |
| `relay-cr.tokenic.cn` | Let's Encrypt | 有效 ✅ | 2026-08-14 |

**验证命令**：
```bash
echo | openssl s_client -connect api.tokenic.cn:443 -servername api.tokenic.cn 2>/dev/null | openssl x509 -noout -issuer -subject -dates
```

---

## Traefik 配置

**主配置**（`/etc/dokploy/traefik/traefik.yml`）：
```yaml
providers:
  docker:
    exposedByDefault: false
    network: dokploy-network
entryPoints:
  web:
    address: :80
  websecure:
    address: :443
    http3:
      advertisedPort: 443
    http:
      tls:
        certResolver: letsencrypt
certificatesResolvers:
  letsencrypt:
    acme:
      email: admin@roome.cn
      storage: /etc/dokploy/traefik/dynamic/acme.json
      httpChallenge:
        entryPoint: web
```

**Dokploy 注入的 Traefik Labels**（在 new-api 容器上）：

路由 1 — api.roome.cn：
- `traefik.http.routers.her-newapi-e91gqn-1-web.rule = Host(api.roome.cn)`
- `traefik.http.routers.her-newapi-e91gqn-1-websecure.tls.certresolver = letsencrypt`

路由 2 — api.tokenic.cn：
- `traefik.http.routers.her-newapi-e91gqn-2-web.rule = Host(api.tokenic.cn)`
- `traefik.http.routers.her-newapi-e91gqn-2-websecure.tls.certresolver = letsencrypt`

两个域名都有 HTTP → HTTPS 重定向（`redirect-to-https@file`）。

---

## Dokploy 配置

| 项目 | 值 |
|------|-----|
| 面板地址 | https://dok.tokenic.cn |
| 应用 slug | her-newapi-e91gqn |
| composeId | bNFluKYYc6Jq-I9K4XuxM |
| sourceType | `raw`（04-17 后切换，YAML 直接存 DB `compose.composeFile`） |
| 镜像来源 | `ghcr.io/her-os/her-gateway:main`（不再 git clone 源码） |
| webhook refreshToken | `qpfrEdx5Cf-fTe-ZTb0I-`（同时存在 GitHub Secret `DOKPLOY_WEBHOOK_TOKEN`） |
| Ghcr 登录凭证 | Dokploy 容器 `/root/.docker/config.json` 内有（艾逗笔给 her-web 配的 PAT，her-gateway package 继承可用） |

**重要陷阱**：改 docker-compose.yml 要**双写**——仓库里的 compose 文件 + Dokploy DB 的 `composeFile` 字段。raw 模式下 Dokploy 不读仓库，只读 DB。详细同步流程见 **her-cicd** skill `ops/deploy-prod.md`。

---

## GitHub 仓库与分支策略

| 项目 | 值 |
|------|-----|
| 仓库 | her-os/her-gateway（私有，2026-04-17 从 suyuan2022 转入 her-os 组织） |
| 生产分支 | main（push → Actions 构建镜像推 ghcr，**不自动部署**。部署要手动） |
| 开发分支 | feat/xxx 从 main 创建，完成后 PR 合回 main。分支模型详见 **her-cicd** skill |
| CI workflow | `.github/workflows/docker-image-main.yml`（push to main 触发） |
| 镜像地址 | `ghcr.io/her-os/her-gateway:main` + `:sha-<短哈希>` |
| 上线流程 | feat → PR → merge main → 手动部署。详见 **her-cicd** skill `ops/deploy-prod.md` |
| 回滚 | 见 **her-cicd** skill `ops/rollback.md` |

---

## 环境变量（docker-compose.yml 中硬编码）

```yaml
environment:
  - SQL_DSN=postgresql://her:HerAgent%232026@172.17.255.75:5432/newapi
  - REDIS_CONN_STRING=redis://redis
  - SESSION_SECRET=a7f3e9b2c1d4056789abcdef0123456789abcdef0123456789abcdef01234567
  - TZ=Asia/Shanghai
  - GIN_MODE=release
  - ERROR_LOG_ENABLED=true
  - BATCH_UPDATE_ENABLED=true
  - HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN=<same as her-web>
```

---

## 凭证索引

| 凭证 | 位置 | 说明 |
|------|------|------|
| SSH 密钥 | `~/.ssh/id_ed25519` | Mac 本地，已配置到服务器 |
| Gateway 面板 | admin-api.md | 用户名 `her`，密码 `HerAgent#2026` |
| PostgreSQL DSN | docker-compose.yml | 包含密码，已 URL 编码 |
| SESSION_SECRET | docker-compose.yml | 用于 JWT 签名 |
| 腾讯云 API Key（子账号 `cli`） | `~/.tccli/default.configure` | tccli DNS 管理 / CVM 安全组；权限 `QcloudDNSPodFullAccess` + `QcloudCVMFullAccess` |
| 智谱 API Key | （在 gateway Dashboard 渠道配置中管理） | Coding Plan 账号池 |

---

## 财务

| 项目 | 费用 | 周期 | 到期日 |
|------|------|------|--------|
| 服务器 | （待补充） | （待补充） | （待补充） |
| tokenic.cn 域名 | （待补充） | 年付 | （待补充） |
| roome.cn 域名 | （待补充） | 年付 | （待补充） |
| 智谱 Z.AI Max | $200/账号/月 × 3 | 月付 | （待补充） |

---

## 域名与 SSL

> 合并自原 domains-and-ssl.md，最后更新：2026-05-09

| 域名 | 用途 | SSL | 备注 |
|------|------|-----|------|
| `api.tokenic.cn` | API 端点（对外） | Let's Encrypt ✅ (R13, 到期 2026-07-08) | tokenic.cn 有 ICP 备案（京ICP备2026006105号） |
| `api.roome.cn` | 管理面板（对内） | 自签名 ❌ | roome.cn 无 ICP 备案 |
| `dok.tokenic.cn` | Dokploy 面板 | Let's Encrypt ✅ | — |
| `dok.roome.cn` | Dokploy 面板（备） | Let's Encrypt ✅ | — |
| `relay.tokenic.cn` | imarouter 反代加速（bwg-la） | Let's Encrypt ✅ (到期 2026-08-07) | A 记录指向 104.194.94.116（BandwagonHost LA），certbot 自动续期 |

DNS 全在 DNSPod/腾讯云。大部分 A 记录指向 `192.144.187.174`，`relay.tokenic.cn` 例外指向 `104.194.94.116`。

### api.roome.cn SSL 失败根因

`roome.cn` 无 ICP 备案，DNSPod 拦截 HTTP-01 验证请求。`tokenic.cn` 有备案所以能拿到证书。目前选择维持现状，API 走 `api.tokenic.cn`。

### SSL 验证命令

```bash
# 看证书颁发者和有效期
echo | openssl s_client -connect <域名>:443 -servername <域名> 2>/dev/null | openssl x509 -noout -issuer -subject -dates

# Traefik 证书失败排查
$SSH "sudo docker logs dokploy-traefik --tail 50 2>&1 | grep -i 'acme\|certif\|unable'"

# 查 acme.json 已签发的证书列表
$SSH "sudo cat /etc/dokploy/traefik/dynamic/acme.json" | python3 -c 'import json,sys; [print(c["domain"]["main"]) for c in json.load(sys.stdin).get("letsencrypt",{}).get("Certificates",[]) or []]'
```
