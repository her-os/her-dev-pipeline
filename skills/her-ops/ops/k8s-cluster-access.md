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
| 集群内 RBAC | ✅ `her` 命名空间开发人员权限（2026-06-12，可读写 Deployment/exec），集群级仍只读 |

## 部署链路 / 紧急通道

镜像构建、轮询发布、回滚路径 → her-cicd `context/k8s-deploy-pipeline.md`（信息只写一处）。

## 已查实（2026-06-12）

- 轮询 = keel（ns `keel`），1 分钟一查，盯 `main` tag，policy force
- 零中断发布已配齐：her-web readinessProbe + 两服务 preStop sleep 15（2026-06-12 实测滚动 0 失败；改 Deployment 前先 `kubectl get deploy -o yaml` 备份到 `~/.config/her/`）
- her-web env 走 ConfigMap `her-web-env`，FEISHU_* 等全齐
