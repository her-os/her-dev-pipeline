---
name: her-dev-teammate
description: |
  Her 项目团队成员开发工作流：分支规范、PR 提交、Codex Review 处理、本地测试、test 环境部署。
  触发场景：创建分支、提 PR、代码审查、Codex review、本地测试、部署测试、
  开发流程、feat 分支、fix 分支、review 怎么看、怎么部署、我要开发、新功能、
  合并代码、创建 pull request、部署到测试环境、跑测试。
---

# Her 团队成员开发工作流

面向团队成员的 Claude Code agent，指导从建分支到部署测试的完整开发周期。

---

## 工作流总览

```
创建分支 → 本地开发 → 本地测试 → 推分支 → PR 到 dev → 合 dev → 部署 test 验证 → PR 到 main → Codex Review → 合 main
(branch.md)              (local-test.md)        (pr.md)      (pr.md)  (deploy-test.md)    (pr.md)      (pr.md)       (pr.md)
```

> **硬规则：所有分支（feat/fix/hotfix）都必须先合 dev 测试通过，再提 PR 到 main。不存在跳过 dev 直接进 main 的情况。**

收到开发请求时：① 读本 SKILL.md 定位场景 → ② 读对应 ops/ 文件 → ③ 执行。

---

## 路径定义

```bash
SKILL_DIR=~/.claude/skills/her-dev-teammate
OPS=$SKILL_DIR/ops
```

---

## 场景路由表

| 场景 | 文档 |
|------|------|
| 开一个新功能/修复分支 | `ops/branch.md` |
| 提交 PR + 处理 Codex Review | `ops/pr.md` |
| 本地测试 | `ops/local-test.md` |
| 部署到 test 环境 | `ops/deploy-test.md` |

---

## 权限边界

权限由机制保障，不是约定：

| 操作 | 能力 | 机制 |
|------|------|------|
| 创建 feat/fix 分支 | ✅ | git 本地操作 |
| 推分支到远端 | ✅ | git push |
| 创建 PR | ✅ | gh CLI |
| 合入 dev | ✅ | CI 通过即可，无额外 review |
| 部署 test 环境 | ✅ | `gh workflow run deploy-test-dispatch.yml` |
| 合入 main | ⏳ 创建 PR 后等 review | branch protection 强制至少 1 人 review |
| 部署生产 | ❌ | 无对应 workflow，物理不可达 |
| SSH 到服务器 | ❌ | 无密钥 |
| 操作数据库 | ❌ | 无连接凭证 |
| 修改 CI workflow | ❌ | 需 repo admin 权限 |

---

## Codex Review 注意事项

PR 创建后 1-2 分钟，Codex AI 自动提交代码审查。**Codex 有系统性局限，agent 必须独立审视每条建议：**

1. **过度防御**：标记"可能为 null / undefined"但框架已保证非空 → 检查调用链，有保障则忽略
2. **业务逻辑盲区**：不了解 Her 的权益模型、邀请机制、订阅状态机等 → 涉及业务逻辑的建议标记"需人工确认"
3. **风格偏好**：建议重命名、提取函数、加注释 → 保持和现有代码一致 > 遵从 Codex 偏好

详细处理流程见 `ops/pr.md`。

---

## 仓库信息

| 仓库 | 用途 | GitHub |
|------|------|--------|
| her-web | 产品前端+后端 | her-os/Her-Web |
| her-gateway | API 网关 | her-os/her-gateway |

---

## 基础规则

- 分支从 `main` 拉，不从 `dev` 拉
- 一个分支做一件事，不混合功能
- `dev` 是测试分支，`main` 是生产分支
- **所有分支先合 dev 测试，测完再合 main 上线**——feat、fix、hotfix 概不例外
- PR 标题描述改了什么，不写 "update" / "fix"
- 不提交 `.env*`、`node_modules`、`.next`、`.claude/`、`.trellis/`

---

## 初始配置清单（夙愿一次性操作）

以下配置由项目管理员完成，agent 不执行：

- [ ] GitHub Secrets（her-web 仓库）：`TEST_SSH_KEY`、`TEST_SSH_HOST`、`TEST_SSH_USER`
- [ ] 服务器 `/opt/her-ci/her-web`：`git clone` + deploy key（只读）
- [ ] 服务器 `/opt/her-ci/her-gateway`：`git clone` + deploy key（只读）
- [ ] test 环境基础设施已就绪（Docker Swarm services、DB、Redis）
- [ ] 同事有 GitHub 仓库 collaborator 权限（需要能触发 workflow_dispatch）
