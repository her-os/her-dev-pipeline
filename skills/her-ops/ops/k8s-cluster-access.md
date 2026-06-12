# K8s 集群访问（TKE her-cluster）

> 集群归 idoubi 管。我们的定位：只读观察（看 pod 状态/日志/配置），操作权限待 CVM 退役前升级。

## 集群事实

- 集群：`cls-4n0yzaz7`（her-cluster），TKE v1.34.1，北京，创建 2026-06-03
- API server **仅内网**：`https://172.17.255.76`（K8s 自动建的内网 CLB），公网不可达
- 算力：按量节点池（无 CVM 整机节点）；出网走 NAT `her_nat`
- 数据：云 PG `172.17.255.75`（与 CVM 共用，见 `ops/production-db-ops.md`）；云 Redis `her-cache`（仅 K8s gateway 用）

## 连接方法

```bash
# 1. 隧道（经老 CVM 跳板进 VPC）
/usr/bin/ssh -f -N -o ExitOnForwardFailure=yes -L 16443:172.17.255.76:443 ubuntu@192.144.187.174

# 2. kubectl（kubeconfig 已配 tls-server-name 走隧道）
kubectl --kubeconfig ~/.config/her/k8s-her-cluster.yaml get pods -A
```

kubeconfig 重新生成（证书失效/换账号时）：

```bash
tccli tke DescribeClusterKubeconfig --region ap-beijing --ClusterId cls-4n0yzaz7
# 取 Kubeconfig 字段，把 server 改为 https://127.0.0.1:16443 并加一行 tls-server-name: 172.17.255.76
# 存 ~/.config/her/k8s-her-cluster.yaml，chmod 600
```

## 权限状态（2026-06-12）

| 层 | 状态 |
|----|------|
| CAM（腾讯云侧） | ✅ 子账号 UIN 100046064896 已有 TKE/TCR/billing/CLB/CVM/VPC 只读 |
| 集群内 RBAC | ❌ 未授权（kubectl 报 Forbidden）。管理员操作：TKE 控制台 → her-cluster → 授权管理 → RBAC 策略生成器 → 子账号 → 集群维度只读（ro） |

## 部署链路 / 紧急通道

镜像构建、轮询发布、回滚路径 → her-cicd `context/k8s-deploy-pipeline.md`（信息只写一处）。

## 已知待确认项

- K8s 轮询盯 `main` 还是 `latest` tag（问 idoubi）
- readiness probe 是否配置（拿到 RBAC 后 `kubectl get deploy -o yaml` 自查）
- K8s her-web 环境变量完整性（FEISHU_* 等，6/8 事故根因之一）
