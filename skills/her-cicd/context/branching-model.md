# 分支模型

## 两分支模型

```
main           生产环境，受保护，PR 合入
  ↑ feat 单独合入（测完一个上一个）
dev            测试环境（test 测试栈），一次性分支，release 后自动重置为 main
  ↑ feat PR 合入（CI 验证构建通过）
feat/xxx       从 main 拉出
```

**main 上合入的永远是单个测好的 feat，不是 dev 的大杂烩。** 可以精确控制哪些功能上线。

## 分支命名

```
feat/xxx       新功能（feat/herclub-payment）
fix/xxx        bug 修复（fix/session-crash）
hotfix/xxx     紧急线上修复
engine/xxx     HER Engine 专项（engine/event-store）
```

不使用个人名前缀（suyuan-*、codex/* 等），Git 有 author 信息。

## 功能完整生命周期

```
1. 从 main 拉 feat/new-feature
2. 本地开发自测
3. feat/new-feature → dev（PR，Codex review 自动触发，与测试并行）
4. 部署到 test 测试栈（不等 CI，deploy-test 自建镜像），通知非开发同事在测什么
5. 非开发同事在测试环境测试 + Codex review 并行
6. 测完 + Codex 无 block → feat/new-feature → main（PR，admin 直接合 + Codex 兜底）
7. 打 tag → release.sh 部署生产 → dev 自动重置为纯 main
8. 有问题 → 在 feat 上修，重走 3-5
```

## 保护规则

| 分支 | 规则 |
|------|------|
| main | 禁止直接 push，必须 PR，admin 可 bypass review requirement |
| dev | 禁止直接 push，禁止 force-push，PR 合入，CI 通过即可自行合入 |

**核心原则**：main = 用户在用的东西，没测完的代码不许碰 main。

**两种合并模式**：
- 普通功能：feat → dev（测试）→ feat → main（上线）
- 基础改动：feat → main（上线）→ 同步 dev（见 `collaboration-scenarios.md` 场景 C）

## dev 分支：测试池，release 后回到 main（D1）

**dev 是测试池，不是长期集成分支。** 允许在测试窗口里暂时包含多个工作分支；清理策略是按条件触发，不定时、不按次数。

### 重置时机

- **自动**：每次 `release.sh` 真实部署成功后（DRY_RUN 不触发），把 dev 的代码内容重置为最新 main
- **手动**：只有 dev 残留改动影响当前测试、导致冲突/误判，或自动重置失败时，运行 `bash $CICD/resync-dev.sh <仓库路径>`
- **不重置**：当前就是在 dev 上测多个工作分支时，不为了“干净”重置

判断 dev 是否等于最新 main 看 tree，不看 commit SHA：`git diff --quiet origin/main^{tree} origin/dev^{tree}`。

### 重置机制（commit-tree）

dev 受保护不能 force-push（实测 GH006 拒绝），所以用 commit-tree 造重置 commit + PR 方式：

```bash
git fetch origin
MAIN_TREE=$(git rev-parse origin/main^{tree})
RESET=$(git commit-tree $MAIN_TREE -p origin/dev -p origin/main -m "chore: resync dev to main")
# 重置 commit 第一父节点 = origin/dev → 合入 dev 是 fast-forward
# 验证：git diff --stat $RESET origin/main 必须为空
git push origin $RESET:refs/heads/chore/resync-dev-<ts>
gh pr create --base dev --head chore/resync-dev-<ts> ...
gh pr merge --admin --merge --delete-branch
```

### 重置后有在测 feat

重置成纯 main，**不自动重合在测 feat**（D3）。用户通常一个个测。
重置后打印提示："若有在测 feat，`merge feat→dev` 一条命令继续测"。

### 备份与清理

- 每次重置前自动备份：`backup/dev-<YYYYMMDD-HHMMSS>` 推远端（D4）
- 每次重置自动清理 7 天前的 `backup/dev-*` 远端分支（D4）

### 回滚不影响

回滚是镜像级（`rollback.sh` 退 `previous.json`），**从不动 git main**。回滚后向前修(hotfix)，`dev=main` 永远是正确基线（D2a）。

### Gating

只在**真实部署成功**后跑（`DRY_RUN=1` / BLOCKED 不跑）；**best-effort**，重置失败绝不能影响已成功的 release（D2b）。

## 基础设施变更状态

| 变更 | 状态 | 说明 |
|------|------|------|
| Her-Web 创建 `dev` 分支 | ✅ 已完成 | 2026-05-19 从 main 创建 |
| her-gateway 创建 `dev` 分支 | ✅ 已完成 | 2026-05-19 从 main 创建 |
| her-salon 创建 `dev` 分支 | ✅ 已完成 | 2026-05-19 从 main 创建 |
| her-gateway 默认分支 `her` → `main` | ✅ 已完成 | 2026-05-24 确认已切换 |
| 分支保护规则（3 仓库 × 2 分支） | ✅ 已完成 | admin 可 bypass review + CI |
| 关闭 auto-delete head branch（3 仓库） | ✅ 已完成 | 2026-06-08，feat 分支需先合 dev 再合 main，不能自动删 |
