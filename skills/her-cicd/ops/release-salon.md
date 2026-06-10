# 软件发布（her-salon）

> 五阶段流水线。每阶段可中断，说「继续发布」从断点恢复。
> 项目特有逻辑由 `context/release-profiles/` 配置驱动。
> 详细签名验证、错误处理见下方排障段。

---

## Phase 0: 项目识别

1. **检测项目类型**：`Cargo.toml` → Rust | `tauri.conf.json` → Tauri（附加标记）
2. **检测签名模式**：profile `signing_mode` → `local`（本地构建+签名）| `ci`（CI 构建）| `none`
3. **本地构建预检**（仅 local 模式）：
   - `security find-identity -v -p codesigning` 检查证书
   - `secret/{project}/updater-key` 检查 updater 私钥
   - `cargo-xwin` / 交叉编译工具链检查
4. **加载 profile**：读取 `context/release-profiles/{project}.toml`
5. **确认**：「检测到 {类型} 项目，版本 {X.Y.Z}，{local/CI} 构建模式。准备开始。」

---

## Phase 1: 预检

| 检查项 | 阻断 | 说明 |
|--------|------|------|
| Git 工作区干净 | 软 | 不干净则询问是否先提交 |
| 版本号已更新 | 硬 | 未更新则智能推荐 semver bump |
| 多处版本号一致 | 硬 | package.json / Cargo.toml / tauri.conf.json |
| 依赖无高危漏洞 | 软 | `cargo audit` |
| 无硬编码密钥 | 硬 | 扫描源码 + 敏感文件检测 |
| 签名就绪 | 软 | 钥匙串证书 + updater 私钥 |

**版本号推荐**：扫描 `git log {last_tag}..HEAD`，识别 conventional commits → breaking=Major / feat=Minor / fix=Patch。

### 预检命令

```bash
# 敏感文件检测
git ls-files | grep -iE '\.(env|pem|key|p12|pfx|jks|keystore|mobileprovision)$|\.env\.|credentials|secret'

# 源码硬编码密钥
git grep -nE '(password|passwd|secret|api_key|token|credential)\s*=\s*"[^"]{8,}"' -- '*.sh' '*.ts' '*.js' '*.rs' '*.toml'

# 钥匙串证书
security find-identity -v -p codesigning

# Updater 私钥
ls -la secret/{project}/updater-key

# 交叉编译工具链
cargo xwin --version 2>/dev/null || echo "需要安装: cargo install cargo-xwin"
rustup target list --installed | grep -E 'x86_64-(pc-windows-msvc|apple-darwin)'
```

---

## Phase 2: 质量门（构建）

### 本地构建模式（Tauri）

```bash
# macOS Apple Silicon（原生，最快）
pnpm tauri build --target aarch64-apple-darwin

# macOS Intel（交叉编译）
pnpm tauri build --target x86_64-apple-darwin

# Windows x64（交叉编译）
# 不要用 --runner cargo-xwin，用项目脚本：
./scripts/build-windows-local.sh
```

脚本内部做三件事：`cargo xwin env` 注入环境 + lld-link 完整路径 + `LC_ALL=en_US.UTF-8`（NSIS Unicode 修复）。

前置依赖：`brew install llvm makensis` + `cargo install cargo-xwin` + `rustup target add x86_64-pc-windows-msvc`

### 签名验证（macOS）

```bash
codesign --verify --deep --strict --verbose=2 [app_path]
spctl --assess --verbose=2 [app_path]
xcrun stapler validate [app_or_dmg_path]
```

---

## Phase 3: 文档

1. **CHANGELOG.md**：从 commits 整理，Keep a Changelog 格式
2. **软件内更新说明**：技术语言 → 大白话（3-5 条）
3. **软件内 changelog 同步**（**硬阻断**）：同步到 `src/**/changelog.*`，新版本用 `categories` 分类格式
4. **README / License**：版本号、badge、版权年份

---

## Phase 4: 发布 + 验证

1. 展示发布摘要 → 用户最终确认
2. `git tag -a v{X.Y.Z}` → push 到 profile 配置的所有 remotes
3. 创建 GitHub Release（draft）→ 上传产物 → Undraft
4. 镜像同步（如 profile 配了 `[mirror]`）：Release 产物 → 镜像服务器 → 生成 mirror 版 updater JSON
5. 验证：Release assets 完整 / Release Notes 非空 / 签名有效 / Updater endpoints 版本号一致（硬阻断）

---

## Edition 配置（发布时用到的开关）

同一份代码通过编译时配置打出不同的包：

```bash
VITE_EDITION=internal npm run build    # 内测包（全开）
VITE_EDITION=beta npm run build        # 用户包（只开测好的功能）
```

| Edition | 用途 |
|---------|------|
| internal | 内测版，给非开发同事和测试，功能全开 |
| beta | 用户版，只开测好的功能 |

her-salon 已有编译时开关：`VITE_DISABLE_VOICE`、`VITE_DISABLE_EAR`、`VITE_DISABLE_REMOTE_SESSION`、`VITE_DISABLE_SIDEBAR`、`VITE_LOCK_WORKSPACE` 等。

---

## 阻断级别

- **硬阻断**：必须解决（版本号、测试、密钥、updater 一致性、changelog 同步）
- **软阻断**：用户确认后可跳过（漏洞、签名、镜像失败）
- **提示**：仅通知（证书快过期、Draft Release）

## 中断恢复

任何阶段可中断，记录 `已完成 / 当前 / 待处理`，说「继续发布」恢复。

---

## 排障

### 签名问题速查

| 症状 | 原因 | 修复 |
|------|------|------|
| `0 valid identities found` | 证书未安装/过期 | 重新导入 .p12 到钥匙串 |
| `code signature invalid` | 签名后文件被修改 | 重新构建签名 |
| `not notarized` | 未提交/失败 | 检查 APPLE_ID + APPLE_PASSWORD |
| Gatekeeper 拦截 | 未 staple | `xcrun stapler staple` |

### Windows 交叉编译常见问题

- `lld-link` 冲突：Cargo 1.85+ 映射裸名 `lld-link` 到内置 rust-lld，需用完整路径 `~/Library/Caches/cargo-xwin/lld-link`
- NSIS `std::bad_alloc`：cargo-xwin 设 `LC_ALL=C`，makensis Unicode 模式需 UTF-8 → 设 `LC_ALL=en_US.UTF-8`
- SmartScreen 警告：可接受，Windows 代码签名证书成本高

### Updater endpoints 不一致

所有 endpoint 必须返回一致的新版本号。检查：
```bash
curl -sL {endpoint_url} | jq '.version'
```
