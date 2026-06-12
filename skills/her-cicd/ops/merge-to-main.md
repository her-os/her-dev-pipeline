# 合入 main + 部署生产

> **部署方式已更新（2026-06-12）**：合 main 即触发 K8s 自动发布（构建 ~8-10min + 轮询），release.sh 手动部署已归档（仅过渡期/应急用，见 `ops/deploy-prod.md` 头部说明）。

## 前置条件

- 工作分支（feat/fix/hotfix 等）已在 dev/测试环境验证通过
- Codex review 无 blocking issue（工作分支→dev PR 上的 review，与测试并行完成）

## 步骤

### 1. 确认远端分支存在

dev PR 合入后远端分支可能已被删除（GitHub auto-delete 已关闭，但历史 PR 或手动删除仍可能发生）。

```bash
git ls-remote origin <branch-name>
```

无输出 → 重新推送：`git push origin <branch-name>`

### 2. 创建 PR → main

在 GitHub 创建 Pull Request：
- Base: `main`
- Compare: `<branch-name>`
- 标题描述清楚改了什么

**Codex review 自动触发**（CI workflow 监听 main 分支 PR）。push 修复后自动重审（`synchronize` 触发）。

### 3. 合入 main

**Admin 直接合 + Codex 兜底**（D7）：
- 不强制等人工 review。Admin 可 bypass review requirement 直接合入。
- Codex 已在工作分支→dev 阶段审过一次；工作分支→main PR 上的 Codex review 是上线前兜底。
- 如果 Codex 在 main PR 上报了 blocking issue，先修再合。

### 4. 确认部署生产

> **红灯操作**：向用户确认一次，确认后 Agent 自动完成打 tag + 部署。

确认时告知用户：
- 版本号（按下方策略确定）
- 涉及的项目（Her-Web / gateway / salon）

```
版本号策略（patch-heavy）：
bug 修复 / 新功能  → bump patch（0.1.15 → 0.1.16）
重大新功能         → bump minor（0.1.16 → 0.2.0）
不兼容变更         → bump major（0.2.0 → 1.0.0）
```

如果同一天测完多个分支，可以合一起打一个 tag。

用户确认后，**不再二次确认**，直接执行以下步骤：

#### 4a. 打 Tag

```bash
git checkout main
git pull origin main
git tag vX.Y.Z
git push origin vX.Y.Z
```

- **Her-Web / gateway**：CI 会并行构建 GHCR/TCR 备份镜像 + draft Release，但**不阻塞部署**，不要等待 CI 完成
- **salon**：无 CI，直接进入下一步本地构建

#### 4b. 部署

```bash
# Her-Web（两个参数：仓库路径 + tag）
QUIET=1 bash ~/.claude/skills/her-cicd/scripts/her-web/release.sh <Her-Web 仓库路径> vX.Y.Z

# her-gateway（接受版本参数）
QUIET=1 bash ~/.claude/skills/her-cicd/scripts/gateway/deploy.sh vX.Y.Z

# her-salon（本地构建，按 ops/release-salon.md 执行）
```

> salon 的构建签名分发见 `ops/release-salon.md`，her-cicd 只管到"打 tag"为止。
> 详细部署步骤见 `ops/deploy-prod.md`。

**release.sh 完成后自动重置 dev = main**（`resync-dev.sh`，best-effort）。
DRY_RUN 模式不触发重置。重置失败不影响已成功的 release。

### 5. 验证生产

```bash
# Her-Web
curl -s https://hersoul.cn | head -5

# Gateway
curl -s -o /dev/null -w "%{http_code}" https://api.tokenic.cn/api/status
```

### 6. 补 Release Notes

GitHub Releases → 找到 draft → 补充 release notes → 发布

### 7. 清理分支

```bash
git push origin --delete <branch-name> || true
git fetch --prune origin
git branch -d <branch-name>
```

## 客户端 + 服务端联合发版

如果本次发版涉及 salon + Her-Web：

```
1. 先部署 Her-Web 到生产（release.sh）
2. 验证生产 API 正常
3. 再发 salon 新版本（本地构建 + 上传）
```

**服务端先上，客户端后发。** 详见 `context/collaboration-scenarios.md` 场景 A。

## 注意

- 生产事实以 `current.json` 为准，不以分支状态为准
- schema 变更会阻断部署，需 migration report 放行
- release 后 dev 自动重置为纯 main；若有在测分支，手动 `merge <branch>→dev` 继续
