# 创建分支

## 步骤

### 1. 同步 main

```bash
git fetch origin
git switch main
git pull --ff-only
```

`pull --ff-only` 失败 → 说明本地 main 有未推送提交，不正常。先 `git log --oneline main..origin/main` 排查。

### 2. 创建分支

```bash
git switch -c feat/your-feature-name
```

命名规范：
- `feat/xxx` — 新功能
- `fix/xxx` — bug 修复
- `hotfix/xxx` — 紧急线上修复

不用个人名前缀（`gaogao-*` 等），Git 有 author 信息。

### 3. 确认本地环境

```bash
pnpm install
pnpm db:setup    # 初始化本地 SQLite（首次）
pnpm dev         # 启动开发服务器
```

详见 `ops/local-test.md`。

## 硬规则

- 分支**从 main 拉**，不从 dev 拉
- 一个分支做一件事，不混合多个功能
- 分支名用英文小写 + 短横线，简短描述功能（如 `feat/invite-email-template`）

## 异常处理

| 问题 | 解决 |
|------|------|
| `pull --ff-only` 失败 | `git fetch origin` → `git reset --hard origin/main`（确认本地无重要改动） |
| 分支名写错了 | `git branch -m feat/old-name feat/new-name` |
| 想基于别人的分支开发 | 先确认对方分支已推远端，`git fetch origin` → `git switch -c feat/mine origin/feat/theirs` |

## 下一步

本地开发完成后 → `ops/local-test.md`（本地测试）→ `ops/pr.md`（先 PR 到 dev 送测）→ `ops/deploy-test.md`（部署 test 验证）→ `ops/pr.md`（再 PR 到 main 上线）
