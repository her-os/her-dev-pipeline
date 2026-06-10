---
name: her-cicd
description: |
  Her 项目群版本管理、发布流程与部署：分支模型、Tag 发版、CI workflow、环境隔离、协作场景、部署脚本。
  **触发场景**：创建分支、合并 PR、打 tag、发版本、部署测试环境、部署生产、
  feature branch、dev 分支、main 分支、fix/hotfix、版本号、semver、
  生产发现问题、线上 bug、上线后继续修、已合 main 后继续改、follow-up fix、
  CI workflow、GitHub Actions、GHCR、test 测试栈、环境隔离、
  客户端服务端兼容、edition 配置、Feature Flag、HER Engine 分支、
  release.sh、deploy.sh、deploy-test.sh、rollback、协作流程、API 版本化、
  分支保护、dev 清理、克隆库刷新、migration、回滚、本地开发环境。
---

# Her 版本管理与发布

版本管理方案原文：`2026-05-13_版本管理方案.md`（在坚果云共享盘 或 本地 Doc 目录）
重设计决策记录：`her-web/docs/handoff-cicd-redesign-0521.md`

---

## 工作流（强制）

收到版本/分支/发布/部署相关请求：① 读本 SKILL.md 定位场景 → ② 读对应 ops/ 或 context/ 文件 → ③ 执行 → ④ 完成后更新 changelog。**不凭记忆直接动手。**

---

## 路径定义

```bash
SKILL_DIR=/Users/suyuan/.claude/skills/her-cicd
OPS=$SKILL_DIR/ops          # 操作文件（一个任务读一个）
CTX=$SKILL_DIR/context      # 背景知识（正常不读）
CICD=$SKILL_DIR/scripts     # ops/ 文件里的 $CICD 指向这里
```

---

## 项目地图

| 项目 | 仓库 | 部署入口 |
|------|------|---------|
| Her-Web | GitHub: Her-Web | `release.sh`（生产）/ `deploy-test.sh`（测试） |
| her-gateway | GitHub: her-gateway | `deploy.sh`（生产）/ `deploy-test.sh`（测试） |
| her-salon | GitHub: her-salon | `ops/release-salon.md`（构建签名分发） |
| HER Engine | GitHub: 独立仓库（待建） | 待定 |
| herclub | GitHub: herclub（archived） | 随 Her-Web |

依赖链：`her-salon →(API)→ Her-Web /api/v1/* →(proxy)→ her-gateway /v1/*`
Engine 独立仓库开发，功能成熟后通过 SDK 接口接入 salon。

---

## 系统概述

```
分支模型    dev + main，工作分支（feat/fix/hotfix 等）从 main 拉；dev 是测试池，release 后自动回到 main
合并方向    工作分支 → dev（测试）→ 工作分支 → main（上线）；test 部署只从 dev 取代码
发版触发    main 打 tag → 人工跑部署脚本
CI 职责     Her-Web / gateway 构建 GHCR 备份镜像，不做部署；salon 无 CI
部署方式    全部手动脚本（release.sh / deploy.sh / build-macos-local.sh）
版本号      统一 semver，各项目独立，patch-heavy（不轻易升 minor）
内部 vs 用户  edition 配置（internal / beta），不分仓库
```

---

## Agent 权限边界

| 可自动执行 | 执行后通知 | 需人类确认 |
|-----------|-----------|-----------|
| 创建 feat/fix/hotfix 分支 | 克隆库 refresh | 部署生产（确认后自动打 tag + 部署） |
| 推送分支到远端 | | 修改 CI workflow 文件 |
| 创建 PR（feat → dev / feat → main） | | 配置分支保护规则 |
| 合入 dev（CI 通过后） | | 修改 GitHub repo settings |
| 合入 main（admin 可 bypass review） | | 删除远端分支 |
| 部署 test 环境（deploy-test） | | 服务器上的 Docker 操作（生产容器） |
| dev 重置（resync-dev.sh，release 后自动） | | 修改生产数据库 |
| 运行测试 | | |
| 本地 Docker DB 创建/销毁 | | |
| 读生产日志（只读） | | |
| 读生产数据库（只读查询） | | |

### Agent 端口和进程规则
- Agent 不许自行选择端口，必须使用 `.env.local` 中预分配的端口
- Agent 不许杀不属于自己 worktree 的进程
- Agent 不许删除注册表（`~/.config/her/dev-envs.json`）中其他 worktree 的条目

---

## 场景路由表

| 场景 | 文档 |
|------|------|
| 开一个新功能分支 | `ops/create-feature.md` |
| 功能合到 dev 测试 | `ops/merge-to-dev.md` |
| 功能测完上线生产 | `ops/merge-to-main.md` |
| 生产/上线后发现问题、已合 main 后继续修、紧急线上修复 | `ops/hotfix.md` |
| 部署到 test 环境 | `ops/deploy-test.md` |
| 部署到生产（her-web + gateway + herclub） | `ops/deploy-prod.md` |
| 生产回滚 | `ops/rollback.md` |
| 本地开发环境搭建 | `ops/local-dev-setup.md` |
| salon 构建签名分发（Edition / Feature Flag） | `ops/release-salon.md`（profile: `context/release-profiles/her-salon.toml`） |
| dev 偏离 main / 手动重置 dev | `resync-dev.sh`（自动：release.sh 末尾调用；手动：直接执行） |
| 分支模型细节 / 保护规则 / dev 重置机制 | `context/branching-model.md` |
| Tag 发版流程 / CI 与部署关系 / 各项目部署对比 | `context/tag-release-flow.md` |
| CI workflow（Her-Web / gateway / salon） | `context/ci-workflows.md` |
| 三层环境 / test 测试栈 / 克隆库 / migration | `context/environment-guide.md` |
| 协作场景（新功能联调 / API 修改 / 基础改动 / Engine） | `context/collaboration-scenarios.md` |
| 客户端服务端兼容 / 版本协商 / 部署顺序 | `context/client-server-compat.md` |
| AI 长会话 / worktree 脏状态问题 | `context/agent-session-worktree-hygiene.md` |

---

## 脚本

| 脚本 | 用途 | Claude 可执行？ |
|------|------|---------------|
| `$CICD/create-feat.sh feat/xxx [仓库]` | 从 main 创建功能分支并推远程 | ✅ |
| `$CICD/resync-dev.sh [仓库]` | commit-tree 重置 dev=main（备份+清理+PR+merge） | ✅ |
| `$CICD/tag-release.sh v0.2.0 [仓库]` | main 打 tag 并推送 | ✅ |
| `$CICD/her-web/release.sh <仓库> <tag>` | 生产部署（含自动 resync-dev） | ⚠️ 需确认 |
| ~~`$CICD/sync-dev.sh`~~ | ❌ 已废弃，用 `resync-dev.sh` 替代 | — |

部署脚本见 ops/ 文件。不传仓库路径时默认用当前目录。

---

## 操作完成后（强制）

1. **changelog.md** 追加一条，格式见下方
2. **经验捕获**（3 个 yes/no）：
   - 踩了坑？→ 对应 ops/ 文件里补注意事项
   - 走了路由表没有的路径？→ 补一行到路由表
   - 没有新增事实时明说"her-cicd 无需更新"

### Skill 内容增删改规则

- 操作手册 → `ops/`，一个操作一个文件，自包含
- 背景知识（跨操作共享、正常不读）→ `context/`
- 新增/删除文件后必须同步更新路由表
- 信息只写一处。ops/ 文件已有的内容，SKILL.md 和 changelog 不重复

### Changelog 格式

每条 3 行封顶，只记事实不记过程：

```
### YYYY-MM-DD 一句话标题

> 改了什么 → 结果/影响。回滚：`一行命令`。
```

操作步骤、SSH 命令 → 不写（ops/ 文件里有）。commit/PR 链接 → 只在有代码变更时写。
