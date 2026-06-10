# 客户端与服务端版本兼容

## 核心难点

服务端一更新所有用户立刻受影响，但客户端更新取决于用户自己。

## 版本协商接口（待实现）

salon 启动时调用：

```
GET /api/v1/client/compatibility
Header: X-Client-Version: 0.0.4

响应：
{
  "server_version": "0.2.0",
  "min_client_version": "0.0.4",
  "recommended_version": "0.0.5",
  "deprecated_before": "0.0.3"
}
```

salon 侧处理逻辑：

```
我的版本 < deprecated_before   → 禁止使用，引导更新
我的版本 < min_client_version  → 强制更新（触发 Tauri updater）
我的版本 < recommended_version → 提示有新版本
否则                           → 正常使用
```

服务端在管理后台可调整三个阈值，不需要重新部署。

> 接口文档：`Her-Web/docs/client-integration.md`（约 500 行），修改这些接口时必须判断是否为破坏性变更。

## 请求头带版本号

salon 每个请求携带：

```
X-Client-Version: 0.0.4
X-Client-Platform: darwin-aarch64
```

用途：兼容适配（过渡期对不同版本返回不同格式）+ 监控决策（统计各版本占比）。

## 部署顺序规则

| 场景 | 部署顺序 | 原因 |
|------|---------|------|
| 服务端加新接口 | 先服务端，再客户端 | 旧客户端不调新接口 |
| 服务端改/删旧接口 | 分两步走 | 直接删会破坏旧客户端 |
| 紧急不兼容变更 | 服务端部署 + 提高 min_client_version | 旧客户端被强制更新 |

## 两步走下线旧接口

```
第一步：服务端同时支持新旧格式 + 发新版客户端 + 提高 recommended_version
第二步（确认旧版 < 5%）：提高 min_client_version + 服务端删旧格式
```

**一句话：服务端永远向后兼容至少一个客户端版本。先推更新，确认旧版没人用了再删。**

## API 路径版本化

```
Her-Web:      /api/v1/user/*
              /api/v1/chat/completions
              /api/v1/client/compatibility

her-gateway:  /v1/*（OpenAI 兼容格式）
```

不兼容变更时 bump 到 v2，v1 和 v2 可以共存。

## Tauri Updater

salon 已有 Tauri updater 基础设施。配合版本协商：

```
salon 启动 → 调 compatibility 接口 → 发现需要更新
→ 调 Tauri updater → 有更新 → 下载安装重启
→ 无更新 → 显示维护提示
```

updater 的 `latest.json` 由发版流程自动生成。

## 常见误解

**Q：兼容两个版本 = 跑两套服务端？**
不是。一台机器、一个容器，同一份代码里新旧格式同时保留。

**Q：客户端要判断调哪个接口？**
不需要。每个版本的 salon 编译时就确定了调什么接口。

**Q：大多数迭代需要三步走？**
不需要。大多数只是加字段、加新路由，不会破坏旧格式。真正需要三步走的很少。现阶段用户量小，甚至可以微信群通知更新。
