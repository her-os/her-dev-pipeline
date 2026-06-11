# 合入 dev（测试环境）

## 前置条件

- 工作分支（feat/fix/hotfix 等）本地开发自测通过
- 确认是**普通功能**（不是基础改动；基础改动跳过 dev，见场景 C）
- 如果本次是在同事 PR 上补充改动，补充分支必须从同事 PR 分支拉出，PR 描述写明"包含 PR #xxx + 本次补充"。

> **dev 不需要手动同步 main。** 每次 release 后 `release.sh` 自动把 dev 重置为纯 main（`resync-dev.sh`）。
> 如果 dev 意外偏离 main，手动跑 `bash $CICD/resync-dev.sh <仓库路径>` 即可。**不要用旧的 `sync-dev.sh`。**

## 核心规则

- test 部署来源必须是 `dev` merge commit，不从本地脏工作区、单独工作分支或临时叠 PR 直接部署。
- 热更新也是同一流程：继续在当前测试分支修改 → commit/push → PR 合入 `dev` → 从 `dev` 重跑 `deploy-web`。
- 合入 `dev` 默认不刷新测试 DB。只有用户明确要求"同步生产数据"或"重置测试数据"时才跑 `refresh-all`。
- **不等 CI**：`deploy-test` 在服务器自建镜像（`her-web:test-latest`），不依赖 dev 的 CI（CI 只负责 GHCR 备份镜像）。合入 dev 后可立即部署 test。

## 步骤

### 1. 推送工作分支

```bash
git push origin <branch-name>
```

### 2. 创建 PR → dev

在 GitHub 创建 Pull Request：
- Base: `dev`
- Compare: `<branch-name>`
- 标题描述清楚改了什么
- 如果 compare 分支基于同事 PR，PR body 必须写明：
  - 上游 PR 编号和分支，例如 `PR #166 fix/subscription-page`
  - 本分支额外 commit 做了什么
  - 本次只是进 `dev/test`，不是绕过上游 PR 直接进 `main`

**Codex review 自动触发**（CI workflow `codex-auto-review.yml` 监听 dev 分支 PR），与测试并行进行。无需手动 @codex。

### 3. 合入 dev

CI 通过后合入。dev 分支可以自行合入，不需要额外 review。**不需要等 Codex review 完成。**

### 4. 部署到 test 测试栈

合入 dev 后，从干净的 `origin/dev` worktree 手动部署到测试环境：

```bash
# Her-Web
git fetch origin dev
# 若 /tmp/her-web-dev-test 已存在（上轮残留），worktree add 会失败或停在旧 commit、
# 被 deploy 脚本拒绝（source must be origin/dev）。先 git worktree remove --force 再 add。
git worktree add -B deploy/dev-test /tmp/her-web-dev-test origin/dev
QUIET=1 bash ~/.claude/skills/her-cicd/scripts/her-web/deploy-test.sh deploy-web /tmp/her-web-dev-test
git worktree remove /tmp/her-web-dev-test

# her-gateway（传入 worktree 路径）
QUIET=1 bash ~/.claude/skills/her-cicd/scripts/her-web/deploy-test.sh deploy-gateway /path/to/her-gateway
```

详细步骤见 `ops/deploy-test.md`。

### 5. 通知测试

在群里发一条消息：

```
dev 现在包含了 <branch-name>，测试环境已部署。
测试入口：https://test.hersoul.cn
主要测试点：[简述新功能]
```

### 6. 处理反馈

- 有问题 → 在工作分支上修，push 后重新合 dev，重新部署
- 没问题 → 进入下一步 `merge-to-main.md`

## dev 偏离 main 时

dev 是测试池，不是长期集成分支。清理策略是**按条件**，不是定时、不是按次数：

- **自动清理**：每次生产 `release.sh` 真实部署成功后，自动 `resync-dev.sh`，让 dev 的代码内容重新等于 main
- **不清理**：合 dev 测试期间，即使 dev 包含多个工作分支，也不要为了“干净”重置；这是测试池的正常状态
- **手动清理**：只有 dev 上的残留改动影响当前测试、导致冲突/误判，或自动清理失败时，才手动 resync

判断 dev 是否已经和最新 main 一致，看 tree，不看 commit SHA：

```bash
git fetch origin main dev --prune
git diff --quiet origin/main^{tree} origin/dev^{tree}
```

`diff` 为空 → dev 与 main 代码内容一致，无需重置。
`diff` 非空但当前就是在测多个分支 → 不重置。
`diff` 非空且污染/冲突影响当前测试 → 手动重置：

```bash
bash $CICD/resync-dev.sh <仓库路径>
```

该脚本自动：备份旧 dev → 清理 7 天前备份 → commit-tree 重置 → PR → admin merge。
**不要 force push `dev`**（受保护分支，GH006 拒绝）。

## 注意

- 合 dev **不代表上线**，dev 只是测试
- 分支不要删，后续还要合 main
- 多个工作分支可以同时在 dev 里，互不影响
- 如果 dev 上冲突导致测试环境不可用，优先修复
- 工作分支→dev PR 可能显示不属于本分支的 commit（main 上有但 dev 没有的），这是正常现象，不影响合入
- **stacked 分支（同一分支多轮 PR 到 dev）不要用 squash 合入**：squash 会让 dev 与分支历史分叉，下一轮 PR 对同一文件（尤其双方都新增的文件）报 add/add 冲突。解法：分支先 `git merge origin/dev` 解冲突，PR 用 merge commit（`gh pr merge --merge`）合入
- `gh pr list` 只拉 `number,title,headRefName,mergeable,statusCheckRollup`，详情用 `gh pr diff` / `gh pr view` 按需补，避免撑爆上下文
