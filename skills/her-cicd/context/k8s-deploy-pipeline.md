# K8s 生产部署管线（新轨道）

> 状态（2026-06-12）：**DNS 未切换，生产流量仍在老 CVM**。本文档描述切换后的生产部署方式。
> dev / test 环境不受影响，继续走老方式（`ops/deploy-test.md`）。

## 双轨概览

| 环境 | 部署方式 | 触发动作 |
|------|---------|---------|
| test（test.hersoul.cn） | 老方式：CVM Swarm，`deploy-test.sh` / workflow dispatch | 手动 |
| 生产 | K8s 自动发布，无人工步骤（release.sh 旧方式已归档 → `ops/deploy-prod.md`） | 合并 main（待确认，见下） |

## 链路（已实测验证）

```
合并 main → GitHub Actions 构建（正常 ~8-10min；无变更 ~2min）
         → 同一镜像推 GHCR + TCR（main tag 更新）
         → K8s 定时轮询 TCR 发现新 digest（无 webhook，实测 TCR 触发器=0）
         → 滚动更新（1-2min）
```

- 等待期间线上跑旧版本，**不中断**；唯一风险窗口是换容器瞬间（取决于 readiness probe，待确认）。
- 构建缓存 2026-06-12 已迁 GHCR registry（`her-web:buildcache`），消除缓存驱逐导致的 ~18min 全量构建（PR #260）。

## 镜像 tag 语义（TCR `her-tcr` / GHCR 相同）

| tag | 何时更新 |
|-----|---------|
| `main` / `dev` | 对应分支每次 push |
| `sha-<commit>` | 每次构建（回滚锚点，全部保留） |
| `vX.Y.Z` + `latest` | 打 tag 时 |

## ⚠️ 待 idoubi 确认（切换前必问）

1. **K8s 轮询盯 `main` 还是 `latest`**：盯 main = 合并即发布生产（无发版把关）；盯 latest = 打 tag 才发布。建议盯 latest。
2. **readiness probe 配了没有**：决定换容器瞬间是否丢请求。
3. **轮询间隔**多久；如何查"当前线上跑的是哪个 commit"。

## 紧急通道

| 场景 | 动作 | 耗时 |
|------|------|------|
| 线上坏了止血 | K8s 指回上一个 `sha-*` 镜像（目前仅 idoubi 可操作，RBAC 授权后可自助） | 秒级 |
| 终极回滚 | DNS 切回老 CVM（老生产栈完整保留） | 分钟级 |
| 必须发新代码 | CVM 当构建机直推 TCR `main` tag（原生 x86 + 本机有生产 env；脚本待写）。**不要用 Apple Silicon 本地构建**（QEMU 转译极慢） | ~5-8min |

## 基础设施事实

- TCR：`her-tcr.tencentcloudcr.com`（企业版基础版，北京，664/月；计划迁广州个人版省此费用）
- 数据层与部署无关：云 PG `172.17.255.75`（her_web + newapi 两库），CVM 与 K8s 共用，已实测验证同库
- K8s 集群访问方式 → her-ops `ops/k8s-cluster-access.md`
