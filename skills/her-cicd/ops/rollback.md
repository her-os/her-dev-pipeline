# 生产回滚

> **红灯操作**：Agent 不可自行执行，必须用户确认。

## 触发条件

生产部署后发现严重问题，需要立刻回到上一个版本。

---

## Her-Web 回滚

### 方式 A：rollback.sh（推荐）

```bash
bash ~/.claude/skills/her-cicd/scripts/her-web/rollback.sh
```

从 `previous.json` 或 release report 回滚到上一个已知版本。

验证：`curl -s https://hersoul.cn | head -5`

### 方式 B：GHCR digest 回滚（保底）

当 rollback.sh 不可用或需要回到更早版本时：

```bash
# 查看可用的 GHCR digest
bash ~/.claude/skills/her-cicd/scripts/her-web/deploy-main-digest.sh

# 指定 digest 回滚
bash ~/.claude/skills/her-cicd/scripts/her-web/deploy-main-digest.sh sha256:<digest>
```

需要用户显式授权。

---

## her-gateway 回滚

### 方式 A：旧代码备份恢复

旧代码自动保留在服务器 `code.bak.*` 目录：

```bash
# 找到旧备份
/usr/bin/ssh -n ubuntu@192.144.187.174 "ls -lt /etc/dokploy/compose/her-newapi-e91gqn/ | head -5"

# 用旧代码重新 build
/usr/bin/ssh -n ubuntu@192.144.187.174 "nohup sudo docker build -t her-newapi-e91gqn-new-api /etc/dokploy/compose/her-newapi-e91gqn/code.bak.<timestamp> > /tmp/gateway-build.log 2>&1 &"

# build 完成后重启
/usr/bin/ssh -n ubuntu@192.144.187.174 "sudo docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api"

# 验证
curl -s -o /dev/null -w "%{http_code}" https://api.tokenic.cn/api/status
```

### 方式 B：GHCR 旧镜像（依赖网络）

```bash
# 查可用的 sha tag
gh run list --repo her-os/her-gateway --workflow=docker-image-main.yml --limit 5

# pull + tag + restart
/usr/bin/ssh -n ubuntu@192.144.187.174 "sudo docker pull ghcr.io/her-os/her-gateway:sha-<commit>"
/usr/bin/ssh -n ubuntu@192.144.187.174 "sudo docker tag ghcr.io/her-os/her-gateway:sha-<commit> her-newapi-e91gqn-new-api:latest && sudo docker compose -p her-newapi-e91gqn up -d --force-recreate --no-deps new-api"
```

---

## HerClub 回滚

HerClub 是纯静态站，回滚 = 用旧代码重新 build + deploy：

```bash
# 回到旧版本 commit
cd /Users/suyuan/Documents/her-source/herclub
git checkout <旧版本 tag 或 commit>
bash ~/.claude/skills/her-cicd/scripts/herclub/deploy.sh
```

紧急下线：
```bash
/usr/bin/ssh -n ubuntu@192.144.187.174 'sudo docker service scale herclub=0'
# 恢复：
/usr/bin/ssh -n ubuntu@192.144.187.174 'sudo docker service scale herclub=1'
```

---

## 回滚后

1. 在 feat 分支上修复问题
2. 走正常 hotfix 流程重新发版（见 `ops/hotfix.md`）
3. changelog.md 记录回滚原因

## 注意

- SSH 必须用绝对路径 `/usr/bin/ssh`
- 回滚不等于问题解决，必须跟进 hotfix
- Gateway build 必须用 nohup（防 SSH 断连）
