# 环境隔离

## 三层环境

```
本地开发（feat/xxx）  →  本地库（SQLite / Docker PG）
测试环境（dev 分支）  →  克隆库（test 测试栈，从生产 pg_dump）
生产环境（main + tag）→  正式库（172.17.255.75:5432）
```

**核心规则：只有 main 分支（含 hotfix）部署的服务才连正式库。dev 一律连克隆库。**

## 各项目本地开发环境

| 项目 | 本地开发 | 说明 |
|------|---------|------|
| Her-Web | 本地 SQLite | `pnpm db:setup` 初始化 |
| her-gateway | 本地 Docker PG 或 SQLite fallback | 代码支持 `SQL_DSN` 为空时回退 SQLite |
| her-salon | 本地 SQLite | 独立于服务端 |
| herclub | Vite proxy → localhost | 已合并到 Her-Web |

## Test 测试栈

入口：`http://192.144.187.174:80`（IP 直访，不依赖域名）

### 服务架构

```
her-web-test（Swarm）
  → her-web-test-db-clone（从生产 pg_dump 恢复）

her-gateway-test（Swarm）
  → her-gateway-test-db（独立库）
  → her-gateway-test-redis（独立 Redis）
```

> 容器名从 roome → test 的重命名在第二步（拆 her-ops）中执行，见 handoff-cicd-redesign-0521.md §6。

测试 DSN 和生产 DSN 完全不同（不同主机、库名、用户）。

### 管理脚本

`deploy-test.sh`（第二步迁入 her-cicd skill 后可用）支持：

| 命令 | 作用 |
|------|------|
| `deploy-web` | 部署 Her-Web 到测试栈 |
| `deploy-gateway` | 部署 her-gateway 到测试栈 |
| `refresh-web-db` | 从生产同步 Her-Web 数据快照 |
| `refresh-gateway-db` | 从生产同步 gateway 数据快照 |
| `refresh-all` | 全部刷新 |
| `verify-web-gateway` | 检查 web ↔ gateway token 绑定 |
| `audit-env` | 对比生产/测试环境变量差异 |

### 非开发同事测试

- **Web 功能**：直接访问 `http://192.144.187.174:80`
- **salon 独有功能**：需开发者打一个测试版（`HER_API_BASE_URL=http://192.144.187.174:80 cargo tauri build`），安装包发给测试同事

## 分支与数据库对应

| 阶段 | 分支 | 数据库 |
|------|------|--------|
| 本地开发 | feat/xxx（本地） | 本地库（SQLite / Docker PG） |
| 测试 | dev | 克隆库（her-web-test-db-clone 等） |
| 正式上线 | main | 正式库（172.17.255.75:5432） |
| 紧急热修 | hotfix/xxx | 本地 → 正式库 |

## 克隆库使用规则

| 规则 | 说明 |
|------|------|
| 手动触发 | 需要新数据时手动跑，不每次部署都刷新 |
| refresh 后跑 migration | dump 是旧 schema，恢复后要重跑 dev 分支的 migration |
| 脱敏（建议） | 清理真实用户邮箱、支付记录、API Key |
| 可随时重置 | 跑乱了重新 refresh |

## Migration 策略

| 项目 | migration 方式 | 命令 |
|------|---------------|------|
| Her-Web | Drizzle ORM，手动触发 | `pnpm db:migrate` 或 `pnpm db:push` |
| her-gateway | GORM AutoMigrate，启动时自动执行 | 重启容器即可 |

执行顺序：本地库先跑 → 克隆库验证 → 正式库执行。

破坏性变更分两版完成（v0.3.0 加新字段兼容，v0.4.0 清理旧格式）。

migration 只做加法。失败处理：克隆库失败在 feat 上修；正式库失败立刻回滚走 hotfix。
