# 本地开发环境 + 测试

## 前置条件

```bash
# 检查 Node.js（需要 18+）
node -v

# 检查 pnpm
pnpm -v
# 没装：npm install -g pnpm

# 检查 gh CLI（用于 PR、Codex review、触发部署）
gh --version
# 没装：brew install gh && gh auth login
```

## 首次搭建

### 1. 克隆仓库

```bash
git clone git@github.com:her-os/Her-Web.git
cd Her-Web
```

### 2. 配置环境变量

```bash
cp .env.example .env
```

编辑 `.env`，设置 `AUTH_SECRET`（随意填一个长字符串即可，本地开发用）：

```
DATABASE_PROVIDER=sqlite
AUTH_SECRET=any-random-string-at-least-32-chars-long
```

其他字段（Feishu、Resend、Cron）本地开发可留空，对应功能不可用但不影响启动。

### 3. 安装依赖 + 初始化数据库

```bash
pnpm install
pnpm db:setup    # 选择 SQLite schema
pnpm db:push     # 创建 SQLite 数据库 + 建表
```

### 4. 启动

```bash
pnpm dev
```

默认地址：`http://localhost:3000`

## 日常开发

```bash
pnpm dev          # 开发服务器（热更新）
pnpm build        # 生产构建（提 PR 前跑一次确认不报错）
pnpm lint         # ESLint
pnpm db:studio    # Drizzle Studio 查看数据库
```

## SQLite vs PostgreSQL 差异

本地用 SQLite，线上用 PostgreSQL。大部分兼容，以下场景有差异：

| 场景 | SQLite | PostgreSQL |
|------|--------|-----------|
| JSON 字段 | `json_extract()` | `->>` / `jsonb` |
| 日期函数 | `datetime()` | `now()` |
| LIKE 大小写 | 默认不敏感 | 默认敏感 |
| 并发写入 | 受限 | 无问题 |

**涉及 SQL / 数据库的改动，本地测完后必须在 test 环境再验证一次**（见 `ops/deploy-test.md`）。

## 本地数据

本地 SQLite 是空库。注册一个测试账号即可进行基础功能开发。

需要生产数据验证的功能 → 部署到 test 环境（自动刷生产数据），在 test 环境验证。

## 下一步

本地测试通过 → `ops/pr.md`（先提 PR 到 dev 送测）→ `ops/deploy-test.md`（部署 test 验证）→ `ops/pr.md`（再提 PR 到 main 上线）
