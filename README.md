# Her AI 开发管线

15 个 skill 组成的完整 AI 辅助开发流程，适用于 Claude Code 和 Codex。

## 安装

```bash
git clone https://github.com/her-os/her-dev-pipeline.git
cd her-dev-pipeline

# 链接到 Claude Code
for d in skills/*/; do ln -sf "$(pwd)/$d" ~/.claude/skills/$(basename "$d"); done

# 链接到 Codex（指向 Claude Code 的同一份，更新只需一处）
for d in ~/.claude/skills/*/; do ln -sf "$d" ~/.codex/skills/$(basename "$d"); done
```

更新时 `git pull` 即可，两边同时生效。

## 项目初始化

在每个代码仓库里首次使用前，跑这两个 skill：

```
/setup-matt-pocock-skills    ← 配置 Issue Tracker、Triage 标签、Domain 文档路径
/lsp-setup                   ← 安装 LSP 语言服务器 + 会话 hook
```

然后把管线路由规则写入项目的 CLAUDE.md / AGENTS.md（模板见下方）。

## 管线流程

```
想法 → /standup → /grill-with-docs → /prototype(可选) → /to-prd
                                                           ↓
                              /bugfix ← FAIL ← /e2e-verify ← /mp-review ← TDD 编码
                                                                              ↓
                                          /functional-test ← Codex Review ← 提交 PR
                                                  ↓
                                            /her-dev-teammate → 部署上线
```

完整图文版见 [`docs/pipeline.html`](docs/pipeline.html)（浏览器打开，29 页翻页式）。

## Skill 一览

### 环境安装（跑一次）

| Skill | 作用 |
|-------|------|
| `/setup-matt-pocock-skills` | 配置 Issue Tracker、Triage 标签、CONTEXT.md 路径 |
| `/lsp-setup` | 安装 LSP + Codex lsp-mcp + 会话 hook |

### 开发管线（日常使用）

| Skill | 作用 | 人参与？ |
|-------|------|---------|
| `/standup` | 分诊 Issue、推荐下一个任务 | |
| `/grill-with-docs` | 拷问想法，挖出所有细节 | ◆ |
| `/prototype` | 快速原型验证（可选） | |
| `/to-prd` | 对话 → PRD → 写入 GitHub Issue | ◆ 确认 |
| `/tdd` | 测试驱动开发 | |
| `/mp-review` | 双轴并行代码审查 | |
| `/thermo-nuclear-code-quality-review` | 热核级代码质量审查 | |
| `/e2e-verify` | 按验收标准自动验证 | |
| `/bugfix` | 7 阶段诊断循环 | |
| `/functional-test` | 分组手测，AI 陪测查 DB | ◆ |
| `/her-dev-teammate` | 分支、PR、部署 | ◆ 确认 |
| `/handoff` | 上下文快满时断点续传 | |
| `/improve-codebase-architecture` | 架构深化，沉淀编码规范 | |

> ◆ = 需要人参与。15 个 skill 中只有 5 个需要你动脑。

## CLAUDE.md / AGENTS.md 路由模板

将以下内容复制到项目的 `CLAUDE.md` 或 `.codex/AGENTS.md` 中。agent 每次 session 启动时读取，知道什么情况该用什么 skill。

```markdown
## 开发管线

按场景路由到对应 skill，不要跳步：

| 场景 | 做什么 |
|------|--------|
| 选任务 / 开始工作 | `/standup` |
| 新功能 / 新想法 | `/grill-with-docs` → `/to-prd` → TDD 编码 |
| 想先看看效果 | `/prototype`（grill 之后、to-prd 之前） |
| 代码写完了 | `/mp-review` → `/e2e-verify` |
| 验证不通过 | `/bugfix`，修完回 `/e2e-verify` |
| 要求极严格审查 | `/thermo-nuclear-code-quality-review` |
| 提交 PR 后 | 等 Codex Auto-Review，处理评论 |
| 上线前手测 | `/functional-test` |
| 分支 / PR / 部署 | `/her-dev-teammate` |
| Bug / 报错 / 性能退化 | `/bugfix` |
| 上下文快满 | `/handoff` |
| 想改善代码结构 | `/improve-codebase-architecture` |
```

## 知识沉淀

管线运行过程中持续积累三类文档：

- **CONTEXT.md** — 业务术语表
- **docs/adr/** — 技术决策记录
- **docs/specs/** — 已知陷阱

## License

MIT
