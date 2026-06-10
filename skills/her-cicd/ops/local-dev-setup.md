# 本地开发环境搭建

## Her-Web

```bash
cd <Her-Web 仓库路径>
pnpm install
pnpm db:setup       # 初始化本地 SQLite
pnpm dev             # 启动开发服务器
```

日常开发默认用 `local-prod-snapshot`（生产数据镜像）。SQLite/dev 降级为备用（空库初始化、极轻 UI sandbox）。

## her-gateway

```bash
cd <her-gateway 仓库路径>
docker-compose up    # 本地 PG
```

或 SQLite fallback。

## her-salon

```bash
cd <her-salon 仓库路径>
pnpm install
cargo tauri dev      # 本地 SQLite
```

---

## 隔离开发环境（多人并行 / 多 worktree）

每个开发分支使用独立的 Docker 化 PostgreSQL 容器，通过端口注册表隔离。

### 快速开始

```bash
# 创建 her-web 开发环境
bash ~/.claude/skills/her-cicd/scripts/create-dev-env.sh --repo her-web --session feat-auth

# 进入 worktree 开发
cd ~/Documents/her-source/worktrees/her-web-feat-auth
pnpm dev

# 完成后销毁
bash ~/.claude/skills/her-cicd/scripts/destroy-dev-env.sh --session feat-auth
```

### 单仓库开发

```bash
create-dev-env.sh --repo her-web --session feat-auth
```

脚本自动：从 `origin/main` 创建 worktree → 启动 PostgreSQL 容器（分配端口如 5433） → 生成 `.env.local` → 写入端口注册表。

### 跨仓库开发（her-web + her-gateway）

```bash
create-dev-env.sh --repo her-web --session feat-payment
create-dev-env.sh --repo her-gateway --session feat-payment
```

创建 gateway 时自动更新同 session 的 her-web `.env.local` 中的 `API_GATEWAY_BASE_URL`。

---

## 端口注册表

路径：`~/.config/her/dev-envs.json`

| 仓库 | 用途 | 端口范围 |
|------|------|---------|
| her-web | web_port（Next.js dev server） | 3001~3099 |
| her-web | db_port（PostgreSQL） | 5433~5499 |
| her-gateway | api_port（gateway API） | 3301~3399 |

`create-dev-env.sh` 使用 `flock` 文件锁（`~/.config/her/dev-envs.lock`）保证并发安全。锁定范围：读注册表 → 找可用端口 → 写注册表。锁释放后再做耗时操作。

---

## 注意

- Agent 可自动创建/销毁本地 Docker DB（绿灯）
- Agent 不许自行选端口，必须用 `.env.local` 预分配的端口
- Agent 不许杀其他 worktree 的进程
- Agent 不许删除注册表中其他 session 的条目
- 不许手动编辑注册表文件，不许在脚本外分配端口

## 排障

- 端口冲突：查注册表 `cat ~/.config/her/dev-envs.json`，用 `destroy-dev-env.sh` 释放
- flock 死锁：手动删 `~/.config/her/dev-envs.lock`
- DB 容器残留：`destroy-dev-env.sh --session <name>` 清理
- worktree 已存在：`git worktree remove <path>` 后重新创建
