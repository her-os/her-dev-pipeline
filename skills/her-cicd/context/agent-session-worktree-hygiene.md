# AI 长会话与 worktree 脏状态问题

## 背景

2026-05-28，Her-Web 在一个 AI 窗口里连续处理了多件事：

- 先做 `feat/auth-rate-limit-toggle`，合入 `dev` 后远端分支被删。
- 测试部署后发现 WeChat 优惠券支付金额问题。
- 继续在同一个对话里排查、修改、临时部署 test。
- 为了让 test 部署来源干净，AI 又使用干净的 `origin/dev` worktree 部署。
- WeChat 修复后来单独提交到 `fix/wechat-coupon-payment-amount`，PR #172 合入 `dev`。

结果：原仓库当前 worktree 仍停在旧分支 `feat/auth-rate-limit-toggle`，并残留了 WeChat 修复的未提交副本、文档、原型和本地记录文件。

## 这不是哪一处代码错了

问题更像是工作区卫生问题：

- 一个 AI 窗口长时间连续做多个任务。
- 用户在测试后继续反馈问题，AI 没有先收口当前分支和工作区。
- 为了部署干净，AI 创建了干净 worktree，但这只保证部署来源干净，不会自动清理原仓库。
- 修复被正确提交到新分支后，原仓库里的同样改动没有同步清掉。
- 多个任务的临时文件、handoff、prototype、bug 记录混在同一个仓库状态里，导致 `git status` 很难读。

## 典型症状

- 当前分支显示 `[gone]`，但本地还有未提交改动。
- 某个修复已经通过 PR 合入 `dev`，原仓库仍显示同样文件被修改。
- `git status` 同时出现代码修复、handoff 文档、prototype 文件、backup 文件。
- 用户很难判断哪些该 commit，哪些只是残留。

## 远端分支自动删除（已解决）

**2026-06-08 已关闭 auto-delete head branch**（Her-Web / her-gateway / her-salon 三个仓库）。

feat 分支需先合 dev 再合 main，自动删除会打断后续 main PR。现在 PR 合入后远端分支保留，由 `merge-to-main.md` 步骤 7 手动清理。

## 之后统一解决时要考虑

- 每次开始新问题前，先记录当前分支、PR、部署来源和未提交状态。
- 测试反馈导致继续修改时，优先继续同一个修复分支；确实要新建分支时，先解释为什么。
- test 部署使用干净 worktree 后，要回到原仓库检查是否留下重复改动。
- PR 合入后，提醒清理原仓库里的重复未提交副本。
- ~~PR 合入 `dev` 后，不要默认认为远端分支还在~~ → auto-delete 已关闭，远端分支不会被自动删除
- 临时文件分区：代码修复、部署记录、handoff、prototype、本地 bug 记录不要混在同一个提交判断里。

## 待解决

远端分支自动删除问题已通过关闭 auto-delete 解决。以下工作区卫生问题仍待统一设计自动检查或收口脚本。
