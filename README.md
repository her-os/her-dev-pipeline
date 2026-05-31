# Her AI 开发管线

15 个 Claude Code skill 组成的完整 AI 辅助开发流程。

不是教你写代码，是教你怎么**驾驭 AI** 帮你写代码。

## 管线总览

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

## 15 个 Skill

### 零 · 环境安装（新同事先跑这两个）

| Skill | 作用 |
|-------|------|
| [`/setup-matt-pocock-skills`](skills/setup-matt-pocock-skills/) | 一键安装 Issue Tracker、Triage 标签、Domain 文档等基础 skill |
| [`/code-map`](skills/code-map/) | 一键安装 LSP 语言服务器，让 AI 精准定位代码 |

### 壹 · 对齐需求

| Skill | 作用 | 人参与？ |
|-------|------|---------|
| [`/standup`](skills/standup/) | 分诊 Issue、推荐下一个任务 | |
| [`/grill-with-docs`](skills/grill-with-docs/) | 扮演严格产品经理，拷问想法直到对齐 | ◆ |
| [`/prototype`](skills/prototype/) | 快速原型验证（逻辑 or UI），用完即丢 | |
| [`/to-prd`](skills/to-prd/) | 对话 → 15 节 PRD → 写入 GitHub Issue | ◆ 确认 |

### 贰 · 配好工具

| Skill | 作用 | 人参与？ |
|-------|------|---------|
| [`/handoff`](skills/handoff/) | 上下文快满时压缩交接，新会话断点续传 | |

### 叁 · 管好质量

| Skill | 作用 | 人参与？ |
|-------|------|---------|
| [`/tdd`](skills/tdd/) | 测试驱动开发，红→绿→重构循环 | |
| [`/mp-review`](skills/mp-review/) | 双轴并行代码审查（Standards + Spec） | |
| [`/thermo-nuclear-code-quality-review`](skills/thermo-nuclear-code-quality-review/) | 热核级代码质量审查，极严格可维护性审计 | |
| [`/e2e-verify`](skills/e2e-verify/) | 按 PRD 验收标准逐条自动验证 | |
| [`/bugfix`](skills/bugfix/) | 7 阶段诊断循环，像医生问诊 | |
| [`/functional-test`](skills/functional-test/) | 分组手工测试，AI 陪测查 DB | ◆ |

### 辅助

| Skill | 作用 | 人参与？ |
|-------|------|---------|
| [`/her-dev-teammate`](skills/her-dev-teammate/) | 分支创建、PR 提交、部署上线 | ◆ 确认 |
| [`/improve-codebase-architecture`](skills/improve-codebase-architecture/) | 架构深化，发现重构机会，沉淀编码规范 | |

> ◆ = 需要人参与的步骤。15 个 skill 中只有 5 个需要你动脑。

## 安装

```bash
# 克隆到本地
git clone https://github.com/her-os/her-dev-pipeline.git

# 将 skills 目录链接到 Claude Code
# 方式一：全部链接
ln -s $(pwd)/her-dev-pipeline/skills/* ~/.claude/skills/

# 方式二：按需链接单个
ln -s $(pwd)/her-dev-pipeline/skills/tdd ~/.claude/skills/tdd
```

## 知识沉淀

管线运行过程中持续积累三类知识文档：

- **CONTEXT.md** — 业务术语表，AI 不再反复确认已知事实
- **docs/adr/** — 技术决策记录，防止 AI 做出相反决策
- **docs/specs/** — 已知陷阱，修相关代码前自动读取

## License

MIT
