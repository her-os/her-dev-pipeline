# 生产问题修复（Hotfix / follow-up fix）

> **🗄️ 部署方式已更新（2026-06-12）**：合 main 后 K8s 自动发布，不再手动跑 release.sh（已归档）。紧急止血优先考虑 K8s 秒级回滚而非快速发新代码，见 `context/k8s-deploy-pipeline.md` 紧急通道。

## 触发条件

代码已合入 main 或已部署生产后发现问题，需要继续修复。

## 核心判断

**默认从最新 main 新拉分支修，不继续旧工作分支。**

原因：
- 旧 PR 已 merged/closed，不能在原 PR 里继续追加有效变更
- 旧分支代表上一轮工作，继续复用会污染审查记录和 changelog
- 问题代码已经在 main 里，从 main 新拉分支 diff 最干净
- 生产 release 成功后 dev 会自动 resync 到 main，后续修复可以重新走 dev 测试

只有一种例外：main PR 尚未合并、生产尚未部署时，继续在原分支上修，然后 push 更新原 PR。

## 路径选择

### A. 普通 follow-up fix（推荐）

适合：生产发现问题，但可以先走 test 环境验证。

流程：

```bash
git checkout main
git pull origin main
git checkout -b fix/describe-the-issue
```

然后按正常流程：
1. 修复 + 自测
2. `ops/merge-to-dev.md`：PR → dev，部署 test 验证
3. `ops/merge-to-main.md`：PR → main，确认生产部署（自动 tag + release）

### B. 紧急 hotfix

适合：生产问题影响用户，不能等 test 环境完整回归。

流程：

```bash
git checkout main
git pull origin main
git checkout -b hotfix/describe-the-issue
```

1. 只改必要代码，不顺手加功能
2. 本地自测
3. PR → main
4. 合入 main 后按 `ops/merge-to-main.md` 确认生产部署（自动打 patch tag + release）
5. 验证生产

`release.sh` 成功后会 best-effort 自动 resync dev 到 main；不需要额外手动把 hotfix 合 dev。

## 不要做

- 不要在已 merged/closed 的旧 PR 里继续提交
- 不要复用旧分支做下一轮生产修复，除非旧 PR 还没合并
- 不要为了修生产问题直接改 dev；生产修复的基线是 main
- 不要等待 GitHub Actions Docker build；生产部署走服务器本地 build，CI 只做备份镜像/draft Release

## 分支清理

main 部署完成并验证后，按 `merge-to-main.md` 清理修复分支：

```bash
git push origin --delete <branch-name> || true
git fetch --prune origin
git branch -d <branch-name>
```