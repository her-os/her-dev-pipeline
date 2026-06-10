# CI Workflow 现状

## Her-Web

### docker-build.yaml ✅

触发：main/dev push + PR（只 build 不 push）+ v* tag（标 latest + draft Release）。

> `ENV_TEST` 不需要加。测试凭证由服务器脚本管理，不经过 CI。

| Secret 名 | 内容 | 状态 |
|-----------|------|------|
| `ENV_PRODUCTION` | 生产环境 `.env` 全文 | 已有 |

### codex-auto-review.yml ✅（2026-05-25 新增）

PR 打开到 main 时自动评论 `@codex` 触发 Codex code review。去重检查避免重复评论。

**agent 注意**：提 PR 后不需要手动 @codex，workflow 会自动触发。创建 PR 后等 1-2 分钟，Codex review 评论会自动出现。

### sync-close-to-reqflow.yml ✅（2026-05-25 合入）

issue 关闭时自动同步关闭上游 trivium-sys/reqflow issue。需要 `REQFLOW_TOKEN` secret（未配不报错）。

## her-gateway

### docker-image-main.yml ✅（2026-05-25 重写）

触发：main/dev push + PR（只 build 不 push）+ v* tag（标 latest）。
用 docker/metadata-action 管理 tag，VERSION 文件适配三种触发类型。

已有 release.yml 处理 Go 二进制构建（tag 触发），两者不冲突。

### codex-auto-review.yml ✅（2026-05-25 新增）

同 her-web，PR 打开到 main 时自动触发 Codex review。

### pr-check.yml（已有）

anti-slop 检查，拦截低质量外部 PR。

## her-salon

目前无 CI，完全靠本地构建脚本。短期不加。

## 仓库设置

三仓库均已开启「Automatically delete head branches」（2026-05-25），PR 合并后自动删除源分支。

## Workflow 实现要点

PR 行为的正确写法：在 job 里区分 PR 和 push/tag，而不是在 job 级别跳过 PR。

```yaml
# 触发条件包含 PR
on:
  push:
    branches: [main, dev]
    tags: ['v*']
  pull_request:
    branches: [main, dev]

jobs:
  build:
    # 不要在这里加 if: github.event_name != 'pull_request'
    steps:
      - name: Build（PR 和 push 都跑）
        run: docker build ...
        # PR 时加 --no-push 或 push: false

      - name: Push to GHCR（只有 push/tag 才推）
        if: github.event_name != 'pull_request'
        run: docker push ...

      - name: Create Release（只有 tag 才创建）
        if: startsWith(github.ref, 'refs/tags/v')
        run: gh release create ...
```
