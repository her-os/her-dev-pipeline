# salon 后端切换

> 最后更新：2026-04-25

salon 是 her-beta 客户端仓库：

```bash
/Users/suyuan/Documents/her-source/salon
```

客户端访问 her-web 由 `VITE_HER_*` 环境变量控制。切换后必须重启
`pnpm tauri dev`，Vite/Tauri 不会热更新 `.env.local`。

## 快速命令

```bash
cd /Users/suyuan/Documents/her-source/salon

# 本地联调：本机 her-web + 本机 dev callback
./scripts/switch-her-backend.sh local

# 云端联调：线上 hersoul.cn + 本机 dev callback
./scripts/switch-her-backend.sh cloud

# 生产默认：线上 hersoul.cn + her:// deep-link callback
./scripts/switch-her-backend.sh prod

# 查看当前模式
./scripts/switch-her-backend.sh status
```

## 三种模式

| 模式 | `VITE_HER_WEB_BASE_URL` | auth callback | 用途 |
|------|--------------------------|---------------|------|
| `local` | `http://localhost:3000` | `http://127.0.0.1:17693/auth/callback` | her-web 本地联调 |
| `cloud` | `https://hersoul.cn` | `http://127.0.0.1:17693/auth/callback` | dev 客户端打线上 her-web |
| `prod` | unset（默认 `https://hersoul.cn`） | unset（默认 `her://auth/callback`） | 正式打包 / 安装包行为 |

## 为什么 cloud 不是 her://

macOS dev 模式下，`her://` deep-link 往往会打开已安装的 Her，而不是当前
`pnpm tauri dev` 进程。

所以 cloud 模式仍然使用本机 HTTP callback：

```env
VITE_HER_AUTH_CALLBACK_URL=http://127.0.0.1:17693/auth/callback
VITE_HER_PAYMENT_CALLBACK_URL=http://127.0.0.1:17693/payment/callback
```

Tauri dev 进程里的本地 listener 会接住回调并写入 token/cookie。

## 修改范围

`switch-her-backend.sh` 只管理三行：

```env
VITE_HER_WEB_BASE_URL=
VITE_HER_AUTH_CALLBACK_URL=
VITE_HER_PAYMENT_CALLBACK_URL=
```

它不会覆盖 Apple 签名、Tauri updater、feature flags 等其它 `.env.local`
配置。

## 常见坑

- 切换后没重启 `pnpm tauri dev`：旧环境变量仍在生效。
- 云端联调用 `prod`：登录后可能打开已安装 Her，而不是 dev 窗口。
- 本地联调用 `cloud`：余额和账号会走线上 her-web，不会复现本地 her-web 改动。
