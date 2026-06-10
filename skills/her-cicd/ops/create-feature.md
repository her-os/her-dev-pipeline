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
