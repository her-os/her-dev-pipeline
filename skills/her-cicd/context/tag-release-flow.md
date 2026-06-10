# Tag 发版与部署

## 核心规则

```
push main ≠ 上线          代码准备好不等于正式上线
打 tag = 人工决定上线      tag 把「准备好」和「上线」解耦
CI 只做 GHCR 备份          不做部署（仅 Her-Web / gateway 有 CI，salon 无）
部署走手动脚本              release.sh / deploy.sh / build-macos-local.sh
```

## CI 与部署的对应关系

### Her-Web / her-gateway（有 CI，构建 Docker 镜像）

| 触发条件 | CI 做什么 | 镜像 tag | 实际部署 |
|---------|----------|---------|---------|
| push to dev | 构建 GHCR 备份镜像 | dev | 手动跑 deploy-test.sh |
| push to main | 构建 GHCR 备份镜像 | main + SHA | 不部署 |
| tag v*（在 main） | 构建 GHCR/TCR 备份镜像 + 创建 draft Release（非阻塞） | v0.x.y + latest | Her-Web: release.sh / gateway: deploy.sh（不等 CI） |

### her-salon（无 CI，本地构建）

| 触发条件 | 做什么 | 实际部署 |
|---------|--------|---------|
| main 打 tag | 无自动行为 | 本地 `build-macos-local.sh` 签名构建 → SSH 上传 |

## Tag 发版步骤

```bash
# 1. 确认 main 上的最新提交都测过了
git checkout main && git pull

# 2. 打 tag
git tag v0.2.0

# 3. push tag → Her-Web/gateway: CI 构建 GHCR + draft Release；salon: 无 CI
git push origin v0.2.0

# 4. 手动部署
bash release.sh /path/to/Her-Web v0.2.0   # Her-Web（仓库路径 + tag）
bash deploy.sh                             # her-gateway（部署 main HEAD）

# 5. GitHub Release 补 release notes 后发布
```

## 发版策略

```
正常节奏：功能测完就发，不攒
可以攒：同一天测完两个 feat，打一个 tag 包含两个 feat
兜底规则：超过 2 周没发版，review 一下
紧急热修：随时发，tag 为 patch 版本（v0.2.1）
```

## 各项目部署方式对比

| 项目 | 部署入口 | 容器编排 | 构建位置 | 部署链条 |
|------|---------|---------|---------|---------|
| Her-Web | `release.sh`（唯一入口） | Docker Swarm | 服务器本地 build | git archive → scp → docker build → Swarm start-first |
| her-gateway | `deploy.sh` | Dokploy compose | 服务器本地 build | scp → docker build → compose recreate |
| her-salon | `build-macos-local.sh` | 无 | 本地签名构建 | tauri build → 签名公证 → SSH 上传 |
| herclub | 随 Her-Web | Docker Swarm | 服务器本地 build | deploy.sh → Swarm update |

> GHCR 镜像仅作备份和回滚用，不是部署路径。原因：腾讯云 pull ghcr 经常超时。

## Her-Web release.sh 流程

```
release.sh（唯一入口）
  → preflight 检查
  → 创建临时干净 worktree
  → git archive → scp
  → 服务器 docker build → Swarm start-first update
  → 写入 release metadata（current.json）
  → postflight 验证
```

关键规则：
- schema 变更默认阻断部署，需 migration report 放行
- 生产事实以 `current.json` 为准，不以分支状态为准

## 脚本与 Tag 方案的关系

```
改前：合到 main → 人工跑 release.sh
改后：合到 main → 确认就绪 → 打 tag → release.sh 读取 tag commit 部署
```

现状（已确认 2026-05-19）：
- `release.sh` 原生支持 tag 参数：`release.sh <repo> v0.2.0`，无需改动
- `deploy.sh` 部署 main HEAD（打完 tag 后 HEAD 即为 tag commit），无需 tag 参数
- CI 在 tag 时推 GHCR + 创建 draft Release（Her-Web 已配置 ✅）

## 回滚

- Her-Web：`rollback.sh` 从 `previous.json` 回滚，或 GHCR digest 回滚
- her-gateway：旧代码备份重新 build，或 ghcr pull 旧镜像

## 版本号规范

统一 semver `major.minor.patch`：
- major：不兼容的 API 变更或重大重构
- minor：新增功能（向后兼容）
- patch：bug 修复、小改动

继续使用 0.x.y，等 HER Engine 跑通后再定 1.0 节点。
