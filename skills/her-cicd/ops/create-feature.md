# 创建功能分支

## 前置条件

- 清楚要做什么功能
- 确认分支名符合命名规范

## 步骤

### 1. 从 main 拉分支

```bash
git checkout main
git pull origin main
git checkout -b feat/your-feature-name
```

命名规范：
- `feat/xxx` — 新功能
- `fix/xxx` — bug 修复
- `engine/xxx` — HER Engine 专项

不用个人名前缀。

### 2. 确认本地开发环境

| 项目 | 本地环境 |
|------|---------|
| Her-Web | `pnpm install && pnpm db:setup`（SQLite） |
| her-gateway | `docker-compose up`（本地 PG）或 SQLite fallback |
| her-salon | `cargo tauri dev`（本地 SQLite） |

### 2.5 worktree 场景必做 bootstrap（B1/B2 决策固化）

任务在独立 worktree 进行时（原仓库被占用），创建后**必须**依次执行，否则 LSP 和测试都跑不了：

1. `pnpm install --frozen-lockfile`——共享 pnpm store，通常分钟级。**不要**软链主仓库的 node_modules（只允许一次性试验）
2. `lsp-doctor --fix --project-dir <worktree>`——生成 worktree 本地 `.lsp-mcp.json`
3. 同一 AI 会话从主目录切到 worktree → 先调用 LSP `setWorkspaceRoot {"path":"<worktree>"}`
4. 端口用 `~/.config/her/dev-envs.json` 里预分配的值，不自选
5. 不复制 `.claude` / `.codex` / `AGENTS.md` 进 worktree

### 3. 开发自测

本地连本地库，不碰测试/生产环境。

### 4. 下一步

功能开发到可以测试时 → `merge-to-dev.md`

## 注意

- feat 分支**从 main 拉**，不从 dev 拉
- 一个 feat 分支做一件事，不要在一个分支里混多个功能
- 也可以用脚本创建：`bash ~/.claude/skills/her-cicd/scripts/create-feat.sh feat/xxx [仓库路径]`
- 如果是基础改动（影响 10+ 文件、改地基），看 `context/collaboration-scenarios.md` 场景 C

## 排障

- 分支命名不符合规范 → `create-feat.sh` 会直接报错，按提示修改
- `git pull --ff-only` 失败 → 先 `git fetch`，再检查本地 main 是否有未推送提交
