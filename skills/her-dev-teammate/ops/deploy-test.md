# 部署到 Test 环境

通过 GitHub Actions `workflow_dispatch` 自助部署，无需 SSH。

## 前置条件

- 分支已推送到远端（`git push -u origin feat/xxx`）
- 本地测试已通过

## 部署步骤

### 1. 确认没有正在运行的部署

```bash
gh run list --workflow=deploy-test-dispatch.yml --limit 3 \
  --json databaseId,status,headBranch,startedAt
```

如果有 `in_progress` 或 `queued` 的 run → 等它完成再部署。

### 2. 触发部署

```bash
# 部署 her-web
gh workflow run deploy-test-dispatch.yml \
  -f target=web \
  --ref feat/your-branch-name

# 部署 her-gateway
gh workflow run deploy-test-dispatch.yml \
  -f target=gateway \
  -f gateway_branch=feat/gateway-branch \
  --ref main

# 同时部署 web + gateway
gh workflow run deploy-test-dispatch.yml \
  -f target=all \
  -f gateway_branch=feat/gateway-branch \
  --ref feat/web-branch
```

`--ref` 控制 her-web 用哪个分支。`gateway_branch` 控制 her-gateway 用哪个分支（默认 `main`）。

### 3. 等待完成

```bash
# 获取最新 run ID
RUN_ID=$(gh run list --workflow=deploy-test-dispatch.yml --limit 1 \
  --json databaseId -q '.[0].databaseId')

# 实时跟踪
gh run watch $RUN_ID
```

正常耗时 3-8 分钟（docker build 占主要时间）。

### 4. 验证

```bash
# HTTP 状态码
curl -s -o /dev/null -w "%{http_code}" http://192.144.187.174:80/zh/pricing
# 期望：200

# 查看部署信息（从 Docker label 读取）
# 需要夙愿协助，agent 无 SSH 权限
```

## 自动数据刷新

部署完成后会自动从生产环境刷新数据（refresh-all），包括：
1. 生产 gateway DB → test gateway DB（pg_dump + restore）
2. 生产 web DB → test web DB clone（pg_dump + restore）
3. 修复 web ↔ gateway token binding（确保登录和 API 调用正常）
4. 验证 binding 一致性

数据刷新大约需要 3-5 分钟。如果只想部署代码不刷数据，加 `skip_refresh=true`：

```bash
gh workflow run deploy-test-dispatch.yml \
  -f target=web \
  -f skip_refresh=true \
  --ref feat/your-branch
```

## 注意事项

- **test 环境是共享的**：你的部署会覆盖当前版本。部署前在群里说一声。
- **只有远端分支能部署**：本地未 push 的提交不会被包含。
- **不可回滚**：test 不需要回滚，重新部署正确的分支就行。
- **构建失败**：`gh run view $RUN_ID --log-failed` 查看错误日志。

## test 环境信息

| 入口 | 地址 |
|------|------|
| her-web 测试版 | `http://192.144.187.174:80` |
| gateway 测试版 | `http://192.144.187.174:80/test-gateway` |

## 异常处理

| 问题 | 解决 |
|------|------|
| workflow 没出现在列表 | 确认 `deploy-test-dispatch.yml` 已合入 main |
| 触发后一直 queued | GitHub Actions runner 排队，等几分钟 |
| SSH 连接失败 | GitHub Secrets 配置问题，联系夙愿 |
| docker build 失败 | `gh run view $RUN_ID --log-failed` 看错误，通常是代码构建问题 |
| 部署成功但页面不对 | 确认部署的分支是对的：`gh run view $RUN_ID` 查看触发参数 |

## 下一步

test 环境验证通过 → `ops/pr.md`（创建 PR 到 main，准备上线）
