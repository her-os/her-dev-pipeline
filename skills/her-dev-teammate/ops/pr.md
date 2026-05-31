# 提交 PR + Codex Review 处理

> **硬规则：所有分支（feat/fix/hotfix）都必须先提 PR 到 dev 测试通过，再提 PR 到 main。不存在跳过 dev 直接进 main 的情况。**

## 1. 推分支到远端

```bash
git push -u origin feat/your-feature-name
```

## 2. 创建 PR

PR 分两步提交，**顺序强制**：

| 步骤 | base | 说明 | 前置条件 |
|------|------|------|---------|
| ① 送测 | `dev` | CI 通过即可自行合入 | 本地测试通过 |
| ② 上线 | `main` | 需至少 1 人 review | test 环境验证通过 |

```bash
# 送测：PR 到 dev
gh pr create --base dev \
  --title "feat: 简短描述改了什么" \
  --body "## 改动说明
- 改了什么
- 为什么改

## 测试要点
- 需要验证的功能点"

# 上线：PR 到 main
gh pr create --base main \
  --title "feat: 简短描述改了什么" \
  --body "## 改动说明
- 改了什么
- 为什么改

## 测试结果
- 本地测试 ✅
- test 环境验证 ✅"
```

PR 标题规范：
- `feat: xxx` — 新功能
- `fix: xxx` — bug 修复
- `hotfix: xxx` — 紧急修复
- 描述改了什么，不要写 "update" / "fix bug"

## 3. Codex Review（仅 PR 到 main 时触发）

PR 创建到 main 后，`codex-auto-review.yml` 自动触发 Codex AI 代码审查，1-2 分钟出结果。

### 读取 Codex Review

**必须用 reviews API，不是 comments API**（Codex 提交的是 PR review，不是普通评论）：

```bash
# 获取 Codex review 内容
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --jq '.[] | select(.user.login | test("codex")) | {state, body}'
```

如果 body 被截断：
```bash
# 获取完整 body
gh api repos/{owner}/{repo}/pulls/{number}/reviews \
  --jq '[.[] | select(.user.login | test("codex"))] | last | .body'
```

### 审视 Codex Review（核心流程）

Codex review 是外部 AI 的代码审查，有系统性局限。**不盲从，逐条独立判断。**

**已知局限：**

1. **过度防御**：Codex 标记"可能为 null / undefined / 未处理的异常"，但实际上框架或上游调用已保证安全。遇到这类建议 → 检查调用链是否已有保障，有则忽略。

2. **业务逻辑盲区**：Codex 不了解 Her 的业务规则（权益模型、邀请机制、订阅状态机、HerClub 会员体系、试用额度计算等）。涉及业务逻辑的建议 → 标记"需人工确认"，不自动采纳。

3. **风格偏好**：Codex 可能建议重命名变量、提取函数、添加注释、调整代码结构等风格改动。保持和现有代码一致 > 遵从 Codex 偏好 → 除非明显提升可读性，否则忽略。

**处理流程：**

逐条过 Codex 的每个建议，分三类：

- **🔴 明确的 bug / 安全问题** → 必须修。例：SQL 注入、未转义用户输入、死循环、类型错误导致运行时崩溃。
- **🟡 业务逻辑相关** → 标记给用户确认，不自动改。例："这里是否应该检查用户订阅状态？""权限校验是否完整？"
- **⚪ 风格/防御性建议** → 默认忽略。例："建议添加 null check""变量名不够语义化""建议提取为独立函数"。

**输出格式**（给用户看的表格）：

```
| # | Codex 建议摘要 | 分类 | 判断理由 | 建议动作 |
|---|---------------|------|---------|---------|
| 1 | "xxx 可能为 null" | ⚪ 防御性 | 上游 getUser() 已保证非 null | 忽略 |
| 2 | "缺少权限校验" | 🟡 业务逻辑 | 不确定此路由是否需要 admin 权限 | 请确认 |
| 3 | "SQL 拼接有注入风险" | 🔴 安全 | 用户输入未参数化 | 必须修 |
```

### 处理完 Review 后

- 🔴 的全部修完 → commit + push → Codex 会重新 review
- 🟡 的等用户确认后决定
- 所有 🔴 处理完且无阻塞 🟡 → PR 可以进入合入流程

## 4. 合入

### feat → dev（送测）

CI 通过即可自行合入，不需要额外 review：

```bash
gh pr merge {number} --squash --delete-branch
```

合入后 → 部署到 test 环境（见 `ops/deploy-test.md`）。

### feat → main（上线）

需要至少 1 人 review 通过（branch protection 强制），agent **不能自行合入**。

```bash
# 检查 PR 状态
gh pr view {number} --json reviews,statusCheckRollup,mergeable

# review 通过 + CI 通过 + mergeable → 提示用户合入
# review 未通过 → 提示用户等待或找 reviewer
```

合入后 GitHub 自动删除源分支。

## 异常处理

| 问题 | 解决 |
|------|------|
| Codex review 迟迟不出现 | 检查 `gh api repos/.../issues/{number}/comments` 看 @codex 评论是否存在，不存在则手动评论 `@codex` |
| CI 构建失败 | `gh pr checks {number}` 查看失败原因，在本地修复后 push |
| PR 有冲突 | `git fetch origin main && git rebase origin/main` 解决冲突后 force push |
| Codex review 全是 ⚪ | 正常，直接告诉用户"Codex 无实质性问题，可以合入" |
