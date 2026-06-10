# Worktree 卫生方案设计

> 状态：设计稿，未实施
> 日期：2026-05-28
> 前置文档：[agent-session-worktree-hygiene.md](./agent-session-worktree-hygiene.md)

## 问题回顾

AI 长会话中连续处理多个任务，导致：
- 原仓库停在已完成的分支上，残留其他任务的未提交改动
- `git status` 混杂代码修复、handoff 文档、prototype 等不同性质的文件
- 远端分支被 auto-delete 后本地变成 `[gone]`，分支生命周期断裂
- Worktree 在非标准路径（/private/tmp/）创建且未清理

根因：**CLAUDE.md 的"写代码前检查"只覆盖会话开始场景，没有覆盖会话中途切换任务的场景。纯规则不可靠——AI 有时连会话开始的检查也不执行。**

## 设计目标

> 核心约束：**在每一个任务边界，工作区状态必须是确定性的。**

即：任何时刻看 `git status`，5 秒内能判断"这个仓库在做什么任务、哪些文件属于这个任务"。

## 决策总览

| # | 决策 | 结论 |
|---|------|------|
| D1 | 方案深度 | Hook（PreToolUse）+ 辅助脚本。纯 CLAUDE.md 规则不可靠 |
| D2 | GitHub auto-delete | **关闭**。改为 main PR 合并后由流程清理远端分支 |
| D3 | 分支生命周期终点 | main PR 合并后才结束。dev PR 合并后分支保留 |
| D4 | 任务切换检测 | PreToolUse hook 在 Edit/Write 时检查工作区状态 |
| D5 | 文件分类（代码 vs 文档） | `src/` + 配置 + CI = 必须走 feat 分支；`.md` 文档 = 允许在 main 上改 |
| D6 | 拦截强度 | 代码文件在 main/dev 上：硬拦截 + 具体修复指令 |
| D7 | 会话产物管理 | 分类 gitignore（handoff-*、checklist、prototype 等模式） |
| D8 | Worktree 路径 | 统一走标准路径 `~/Documents/her-source/worktrees/`，禁止 /tmp |
| D9 | 任务注册 | 不需要额外注册机制，分支名 = 任务标识 |
| D10 | 远端分支清理 | main PR 合并时由 her-cicd merge-to-main 流程执行 |

---

## 方案详设

### 1. 关闭 GitHub auto-delete branch on merge

**变更**：Her-Web repo 设置 `delete_branch_on_merge: false`

**原因**：

auto-delete 在"所有 PR 直接合 main"的旧流程下是合理的。但两阶段流程（feat→dev 测试 → feat→main 上线）要求 feat 分支在 dev PR 合并后继续存在。GitHub 不支持按 base branch 区分 auto-delete 行为，因此只能全局关闭。

**替代清理机制**：见下方"分支清理流程"。

### 2. PreToolUse Hook：代码修改前检查

在 `.claude/settings.json`（项目级）添加 PreToolUse hook，拦截 `Edit` 和 `Write` 工具调用。

#### 触发条件

仅当目标文件匹配"代码文件"模式时触发检查：

```
代码文件（必须走 feat 分支）：
  src/**
  package.json, package-lock.json
  tsconfig*.json
  *.config.ts, *.config.js, *.config.mjs
  .github/**
  Dockerfile, docker-compose*
  prisma/**

文档文件（允许在 main 上直接改）：
  *.md（包括 CONTEXT.md、docs/adr/*.md、docs/specs/*.md）
  .gitignore
```

#### 检查项

| 检查 | 条件 | 动作 |
|------|------|------|
| 在 main/dev 上改代码 | `git branch --show-current` 是 `main` 或 `dev`，且文件匹配代码模式 | **硬拦截**。输出："当前在 {branch} 上，不能直接修改代码文件。请先创建 feat 分支：`git switch -c feat/<topic>`" |
| 分支远端已删 | `git branch -vv` 显示 `[gone]` | **警告**。输出："当前分支 {branch} 的远端已被删除。如果还需要此分支，请 re-push：`git push -u origin {branch}`。如果任务已完成，请切换到新分支。" |
| detached HEAD | `git branch --show-current` 为空 | **硬拦截**。输出："当前处于 detached HEAD 状态，不能修改代码。请先 checkout 到工作分支。" |

#### 实现方式

Hook 脚本 `workspace-guard.sh`，放在 `~/.claude/skills/her-cicd/scripts/` 下。

```
# settings.json 中的 hook 配置（伪代码）
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "command": "bash ~/.claude/skills/her-cicd/scripts/workspace-guard.sh"
      }
    ]
  }
}
```

hook 脚本接收 tool 参数（文件路径），判断：
1. 文件是否匹配代码模式
2. 如果是代码文件，当前分支是否合规
3. 输出对应的拦截/警告信息

### 3. 分支清理流程

#### 场景 A：main PR 合并后（正常生命周期终点）

在 her-cicd 的 `merge-to-main` 操作流程中增加步骤：

```bash
# main PR 合并后执行
BRANCH=feat/xxx

# 1. 删除远端分支
git push origin --delete $BRANCH 2>/dev/null

# 2. 清理本地 [gone] 分支
git fetch --prune
git branch -vv | grep ': gone]' | awk '{print $1}' | xargs git branch -D 2>/dev/null

# 3. 如果有对应的 worktree，提醒清理
git worktree list | grep $BRANCH && echo "⚠️ 该分支有关联 worktree，请运行 destroy-dev-env.sh 清理"
```

#### 场景 B：定期清理废弃分支

可选的辅助脚本 `prune-stale-branches.sh`：列出所有已合入 main 的远端分支，提示删除。

### 4. 会话产物分类 gitignore

在 `.gitignore` 中增加以下模式：

```gitignore
# AI 会话产物（handoff、checklist、prototype）
docs/handoff-*
docs/*-checklist.md
docs/prototype-*
docs/test-*-bugs.md
docs/test-*-checklist.md
docs/*-test-prompt.md
docs/*-test-status.md

# AI 工作目录
.her/

# 备份文件
*.backup
```

**不排除的文件**（应正常 commit）：
- `CONTEXT.md`
- `docs/adr/*.md`
- `docs/specs/*.md`
- `docs/agents/*.md`

### 5. Worktree 路径标准化

**硬性规则**：所有 worktree 必须通过 `create-dev-env.sh` 创建，路径统一为：

```
~/Documents/her-source/worktrees/<repo>-<session>
```

`workspace-guard.sh` 可选择额外检查：如果当前 repo 路径在 `/private/tmp/` 或其他非标准位置，输出警告。

### 6. CLAUDE.md 更新（配合 hook 的规则层）

虽然 hook 做了硬性保障，CLAUDE.md 仍需更新以下内容：

#### 新增："会话中途切换任务"检查点

```markdown
### 会话中途切换任务

当用户提出的新请求不属于当前分支的范围时（例如从 feat/A 切到修 bug B）：

1. **收口当前任务**：
   - 未提交的代码改动：commit 或 stash
   - 确认当前分支的 PR 状态
   - 记录当前任务状态（一句话即可）

2. **创建新分支**：
   - `git switch main && git pull --ff-only`
   - `git switch -c fix/xxx`（或 feat/xxx）

3. **如果原仓库被占用**（另一个 AI 窗口在用）：
   - 走 `create-dev-env.sh` 创建 worktree
```

#### 更新："写代码前检查"补充

在现有检查之后追加：

```markdown
**第三步：确认分支状态**

- 当前分支不是 `[gone]`（远端已删）→ 如果是，`git push -u origin <branch>` 恢复
- 当前分支不是 main/dev → 如果是，先创建 feat 分支
- `git status` 的脏文件都属于当前任务 → 如果混有其他任务的文件，先 stash/commit
```

---

## 实施清单

> 以下为后续实施时的 TODO，本次只设计不实施。

- [ ] GitHub 设置：关闭 Her-Web 的 `delete_branch_on_merge`
- [ ] 编写 `workspace-guard.sh` 脚本
- [ ] 配置 `.claude/settings.json` 的 PreToolUse hook
- [ ] 更新 `.gitignore` 增加会话产物模式
- [ ] 更新 `her-source/CLAUDE.md`："会话中途切换任务"检查点 + "写代码前检查"补充
- [ ] 更新 `her-cicd/ops/merge-to-main.md`：增加分支清理步骤
- [ ] 清理当前脏状态：处理原仓库的 20+ untracked 文件 + 清理 /private/tmp worktree
- [ ] 清理 4 个 `[gone]` 本地分支

## 风险与注意

- Hook 在每次 Edit/Write 时都会执行，需要确保 `workspace-guard.sh` 执行速度 <200ms
- 文档文件放行规则可能需要根据实际使用调整（比如未来新增的配置文件类型）
- her-gateway、her-salon 等其他仓库如果也开了 auto-delete，需要同步关闭
