# 部署到生产环境

> **红灯操作**：Agent 不可自行执行，必须用户确认。

## 前置条件

- 工作分支（feat/fix/hotfix 等）已合入 main
- 已打 tag（`bash ~/.claude/skills/her-cicd/scripts/tag-release.sh vX.Y.Z $REPO`，或 merge-to-main 流程内自动打）
- **不需要等 CI**：Her-Web / gateway 的 GitHub Actions 只构建 GHCR/TCR 备份镜像和 draft Release，不是生产部署路径

---

## Her-Web 部署

### 唯一入口：release.sh

```bash
QUIET=1 bash ~/.claude/skills/her-cicd/scripts/her-web/release.sh <Her-Web 仓库路径> vX.Y.Z
```

release.sh 做的事：
1. 创建本地和服务器 release lock，避免并发部署
2. 用实时远端 `origin/main` SHA 判断目标版本，不信本地缓存
3. 创建临时干净 worktree，不部署当前目录
4. 生成 release report，检查 production/main 是否对齐
5. 阻断 schema/migration、未知生产 commit、缺回滚目标等风险
6. 需要时要求 `ACCEPT_RELEASE_REPORT=<id>:<hash>` 和 `CONFIRM_SMOKE=...`
7. 调用底层执行器 `deploy.sh`（git archive HEAD → scp → 服务器 docker build → Swarm update）
8. 写入 release metadata，输出 postflight / smoke / rollback 信息

生产 her-web 发布会固定保留不限流配置：
- `AUTH_RATE_LIMIT_ENABLED=false`：关闭 better-auth 登录/注册限流。
- `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN`：her-web → gateway 内部调用绕过 gateway 限流。

`deploy.sh` 会把这两个 env 固化到 `/home/ubuntu/.her-web-env-production`，并在 `docker service update` 时显式 `--env-add`。postflight 会检查生产 service env；缺任意一个都算发布失败。

如果传给 `release.sh` 的仓库路径是临时/新建 worktree，先在该路径跑 `pnpm install --frozen-lockfile`。`release.sh` 会把传入仓库的 `node_modules` symlink 到临时 release worktree；传入仓库没有 `node_modules` 时，TypeScript preflight 会阻断。

### 关键规则

- `main` 合并不等于自动上线
- 不部署未提交代码，不从 `suyuan` 整体直接上线生产
- 低层脚本 `deploy.sh` / `deploy-main-digest.sh` 不是日常入口，只作为 release 内部执行器
- 单节点前提：`docker node ls` 只看到一个节点，多节点 Swarm 时方案需重做

### Schema 变更阻断

如果目标版本改了 `src/config/db/schema*.ts`、`drizzle/**`、`drizzle.config.ts`，默认阻断。
通过 `--migration-report <path>` 走正常发布：

- migration report 必须是 JSON，`targetSha` 等于发布目标
- `databaseProvider` 必须是 `postgres`
- 必须包含 `backupPath`、`backupSha256`、`appliedAt`、`appliedBy`
- `beforeChecks` / `afterChecks` 至少覆盖：user.real_name、user.wechat_id、invite_code.balance_cents 等核心字段
- 生产备份固定放 `/home/ubuntu/her-web-release/dumps/`

### 紧急止血例外

```
已提交的任务分支 / suyuan
  → 用户当前会话明确授权
  → 显式开启 ALLOW_NON_MAIN_DEPLOY=1
  → release.sh 紧急模式部署止血
  → 线上验证
  → 立刻补干净 PR 到 main
```

### 验证

```bash
curl -s https://hersoul.cn | head -5
```

标准验证门槛：
1. 代码来源是目标 commit，不是脏工作区
2. Swarm service running task 真的换了
3. running container 指向目标 image id
4. hersoul.cn 返回 200
5. auth 不是 403
6. env 驱动改动：关键 env / 页面行为也验证通过
7. schema/migration：先停，不上线
8. 不限流 env：`AUTH_RATE_LIMIT_ENABLED=false` + `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN` 存在

Postflight HTTP 规则：`curl -L`，`/ → 307 → /zh → 200` 视为正常。

---

## her-gateway 部署

### 一键脚本

```bash
bash ~/.claude/skills/her-cicd/scripts/gateway/deploy.sh vX.Y.Z
```

脚本做的事：
1. `git archive HEAD` 打包 → scp 上传（~3s）
2. 服务器 `DOCKER_BUILDKIT=1 docker build`（nohup 防 SSH 断连，有缓存时 ~1min）
3. `docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api`（~30s 不可用）
4. 验证镜像切换 + 双网络 + healthy + 外部 HTTP 200
5. 部署前检查 `docker-compose.yml` 必须有 `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN`，缺失时拒绝重建 new-api

**build 必须用 nohup**。腾讯云 SSH 不稳定，裸跑 `docker build` 会因 SSH 断开中断。

### 手动步骤（脚本不可用时）

```bash
cd /Users/suyuan/Documents/her-source/her-gateway

# 1. 打包 + 上传
git archive --format=tar.gz main -o /tmp/her-gateway.tar.gz
/usr/bin/scp /tmp/her-gateway.tar.gz ubuntu@192.144.187.174:/tmp/
/usr/bin/ssh -n ubuntu@192.144.187.174 "sudo mv /etc/dokploy/compose/her-newapi-e91gqn/code /etc/dokploy/compose/her-newapi-e91gqn/code.bak.\$(date +%s) && sudo mkdir -p /etc/dokploy/compose/her-newapi-e91gqn/code && sudo tar -xzf /tmp/her-gateway.tar.gz -C /etc/dokploy/compose/her-newapi-e91gqn/code"

# 2. 服务器 build（nohup 防断连）
/usr/bin/ssh -n ubuntu@192.144.187.174 "nohup sudo docker build -t her-newapi-e91gqn-new-api /etc/dokploy/compose/her-newapi-e91gqn/code > /tmp/gateway-build.log 2>&1 &"

# 3. build 完成后 compose recreate
/usr/bin/ssh -n ubuntu@192.144.187.174 "cd /etc/dokploy/compose/her-newapi-e91gqn/code && sudo sed -i.bak -e 's|image: ghcr.io/her-os/her-gateway:main|image: her-newapi-e91gqn-new-api:latest|' -e 's|pull_policy: always|pull_policy: never|' docker-compose.yml && sudo docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api"

# 4. 验证
curl -s -o /dev/null -w "http=%{http_code} time=%{time_total}s\n" https://api.tokenic.cn/api/status
```

### 实测时间线

| 阶段 | 耗时 |
|------|------|
| git archive + scp | ~3s |
| 服务器 docker build | 3-5 min |
| recreate + healthy | ~30-40s |
| **总计** | **4-6 分钟** |

### Dokploy compose 双写陷阱

Dokploy `sourceType=raw` 从**自己 DB 的 `composeFile` 字段**读 YAML，不读仓库里的 `docker-compose.yml`。改 compose YAML 必须同步两处（仓库 + Dokploy DB）。同步命令见 `context/` 下 gateway 相关文档或用 her-ops skill。

当前 raw compose 必须保留 `HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN`。如果从 Dokploy UI 直接 redeploy gateway，先确认 DB 里的 `compose.composeFile` 也包含这个 env。

### 固定值

| 项 | 值 |
|----|-----|
| SSH 命令 | `/usr/bin/ssh -n ubuntu@192.144.187.174` |
| Dokploy 应用 slug | `her-newapi-e91gqn` |
| 镜像名（本地 build） | `her-newapi-e91gqn-new-api` |
| 代码目录 | `/etc/dokploy/compose/her-newapi-e91gqn/code/` |

---

## HerClub 部署

HerClub 是纯静态 Vite + React SPA，调 her-web API（`https://hersoul.cn`），没有自己的后端。

### 一键脚本

```bash
bash ~/.claude/skills/her-cicd/scripts/herclub/deploy.sh
```

her-web API 上线不代表 `club.hersoul.cn` 页面已更新；HerClub 前端改动必须再跑一次这个脚本。

### 手动步骤

```bash
cd /Users/suyuan/Documents/her-source/herclub

# 1. 本地 build
npm run build

# 2. rsync 到服务器
/usr/bin/ssh -n ubuntu@192.144.187.174 'mkdir -p /tmp/herclub-deploy/dist'
rsync -avz --delete dist/ ubuntu@192.144.187.174:/tmp/herclub-deploy/dist/
scp Dockerfile nginx.conf ubuntu@192.144.187.174:/tmp/herclub-deploy/

# 3. 服务器 build + Swarm update
/usr/bin/ssh -n ubuntu@192.144.187.174 'cd /tmp/herclub-deploy && sudo docker build -t herclub:latest .'
/usr/bin/ssh -n ubuntu@192.144.187.174 'sudo docker service update --image herclub:latest --no-resolve-image --force herclub'

# 4. 验证
curl -sI https://club.hersoul.cn
```

### 联合改动检查清单

HerClub 支付、邀请码、会员卡等功能通常同时动两个服务：

1. 先部署 her-web API，确认 `https://hersoul.cn/api/herclub/*` 新接口在线
2. 再部署 herclub 静态站
3. Swarm 更新期间可能短暂 502，持续不恢复才查 `docker service ps herclub`
4. 用命令验证，不靠浏览器感觉判断

---

## 联合发版顺序

涉及 salon + Her-Web 时：**服务端先上，客户端后发。**

```
1. 先部署 Her-Web 到生产（release.sh）
2. 验证生产 API 正常
3. 再发 salon 新版本（本地构建 + 上传）
```

---

## 排障

### Lock 文件残留

release.sh 被中途杀死时，lock 不会自动清理：

```bash
# 本地 lock
rm -rf /tmp/her-web-release.lock

# 服务器 lock
ssh ubuntu@192.144.187.174 "sudo rm -rf /home/ubuntu/her-web-release/release.lock.d"

# worktree 残留
rm -rf /tmp/her-web-release
```

### Release report token 确认：两步调用

`release-check.sh` 每次运行生成新 report（ID 含 `NOW_EPOCH`）。`ACCEPT_RELEASE_REPORT` 必须匹配同一次 report。

```bash
# 第一步：固定 epoch，获取 token
NOW_EP=$(date +%s)
NOW_EPOCH=$NOW_EP bash scripts/her-web/release.sh <repo> origin/main 2>&1 | grep "ACCEPT_RELEASE_REPORT="

# 第二步：同一 epoch + token 再跑
NOW_EPOCH=$NOW_EP ACCEPT_RELEASE_REPORT="<上一步的值>" CONFIRM_SMOKE="<ids>" \
  bash scripts/her-web/release.sh <repo> origin/main
```

**常见错误**：不固定 `NOW_EPOCH` → 每次重跑 epoch 变 → token 永远不匹配 → 死循环。

### SSH keepalive 必需

`~/.ssh/config` 必须包含：

```
Host 192.144.187.174
    ServerAliveInterval 30
    ServerAliveCountMax 5
    ConnectTimeout 15
```

没配会导致 `[2/5] 传输已提交代码到服务器` 超时。

### nonMainOverride 生产 commit 处理

上次部署用了 `nonMainOverride` 时，新一轮正常部署会 BLOCK `TARGET_REMOVES_PRODUCTION_COMMITS`：

1. 确认 nonMainOverride commit 的改动已全部进入新 main（`git diff` 验证 zero diff）
2. 备份 `current.json`：`ssh ... "sudo cp current.json current.json.bak-$(date +%s)"`
3. 更新 `current.json`：commit 改为最后一个 main commit，`nonMainOverride: false`，`branch: "main"`
4. 清理 lock/worktree 后重跑 release.sh

### Gateway 回滚（紧急）

见 `ops/rollback.md`。

### 构建耗时

Her-Web: npmmirror + BuildKit cache 上线后，首次 ~91s，后续 ~57s。Bash 默认 120s 超时足够。
Gateway: 3-5 分钟，需设 `timeout: 300000`。
