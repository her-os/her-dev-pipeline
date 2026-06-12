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

## 已查实（2026-06-12 集群只读权限实查）

1. **轮询机制 = keel**（集群内工具），`trigger: poll`，**间隔 1 分钟**，policy force。
2. **盯 `main` tag**（her-web 和 gateway 都是 `her-tcr.../xxx:main`）→ **合并 main 即发布生产**，打 tag 与发布无关（仅留档/回滚锚点）。如要"打 tag 才发布"需让 idoubi 把镜像改 `latest`。
3. **探针**：gateway 配置完善（readiness+liveness `/api/status`，maxUnavailable=0，真零停机）；**her-web 无任何探针** → 换容器瞬间有数秒断流风险。需 idoubi 给 her-web 加 readinessProbe（GET /zh 或健康端点，port 3000）+ `maxUnavailable: 0`。
4. **环境变量已齐**：K8s her-web 的 env 通过 ConfigMap `her-web-env` 挂载，FEISHU_*、CRON_SECRET、HER_INTERNAL_RATE_LIMIT_BYPASS_TOKEN、AUTH_RATE_LIMIT_ENABLED 等全在（6/8 缺配置问题已修复）。
5. 查"线上跑哪个 commit"：`kubectl describe pod -n her -l app=her-web | grep Image:`（image digest 对应 `sha-<commit>` tag）。集群访问方法 → her-ops `ops/k8s-cluster-access.md`。

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
