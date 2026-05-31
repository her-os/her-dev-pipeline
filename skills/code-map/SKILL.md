---
name: code-map
description: |
  代码智能一键配置——检测并安装 LSP 语言服务器、Codex LSP MCP、CodeGraph 代码图谱、项目依赖，
  让 Claude Code 和 Codex 的代码智能从第一秒就能用。
  触发场景：lsp-setup、配置 LSP、装 LSP、LSP 不工作、LSP 报错、goToDefinition 不能用、
  findReferences 失败、hover 没反应、typescript-language-server、gopls、
  装 CodeGraph、codegraph、代码图谱、代码索引、
  新项目配环境、新同事 onboarding、开发环境初始化、dev setup。
---

# Code Map

让 AI coding agent（Claude Code / Codex）的代码智能从开箱就能用。

## 这个 skill 解决什么问题

Agent 在修改代码前需要两类代码智能：
- **LSP**：精确定位符号（goToDefinition、findReferences、hover）
- **CodeGraph**：调用链追踪、修改影响面评估、符号关系图谱

如果没配好，agent 只能退化成盲目 rg 和读文件——慢、费 token、还会漏。

## 执行流程

运行诊断脚本，根据输出决定操作：

```bash
bash ~/.claude/skills/code-map/scripts/lsp-doctor.sh --project-dir "$(pwd)"
```

看输出里有没有 `[MISSING]`。有的话加 `--fix` 自动修复：

```bash
bash ~/.claude/skills/code-map/scripts/lsp-doctor.sh --fix --project-dir "$(pwd)"
```

只验证 / 安装 Codex LSP MCP 时，用窄模式，避免修改 Claude Code 配置、CodeGraph、项目依赖和检索说明：

```bash
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}" bash ~/.claude/skills/code-map/scripts/lsp-doctor.sh --fix --codex-lsp-only --project-dir "$(pwd)"
```

脚本会检查并修复六个部分：

### 0. 配置 Claude Code LSP 插件

Claude Code 继续走 LSP 插件，不改这条安装路径。脚本只检测并补齐三步：

1. **ENABLE_LSP_TOOL** 环境变量 — 在 `~/.claude/settings.json` 里设 `"ENABLE_LSP_TOOL": "1"`
2. **注册 marketplace** — `Piebald-AI/claude-code-lsps`（第三方 LSP 插件仓库）
3. **启用具体语言插件** — `vtsls`/`gopls`/`pyright`/`rust-analyzer`

脚本会检测项目语言，自动把上述配置写入 `~/.claude/settings.json`。

### 1. 安装 LSP 语言服务器二进制

插件只是告诉 Claude Code 调用哪个命令，语言服务器本身还需要装在系统上：

| 项目标志文件 | LSP Server | 安装命令 |
|-------------|-----------|---------|
| `tsconfig.json` / `package.json` | `vtsls` | `npm i -g @vtsls/language-server` |
| `go.mod` | `gopls` | `go install golang.org/x/tools/gopls@latest` |
| `pyproject.toml` / `requirements.txt` | `pyright` | `pip3 install pyright` |
| `Cargo.toml` | `rust-analyzer` | `rustup component add rust-analyzer` |

### 2. 配置 Codex LSP MCP

Codex 不使用 Claude Code 的 LSP 插件。脚本会为 Codex 单独配置 repo-local `lsp-mcp`：

| 检查项 | 缺失时 `--fix` 行为 |
|--------|---------------------|
| `~/.codex/tools/lsp-mcp/target/release/lsp-mcp` | clone/build upstream `BumpyClock/lsp-mcp`，缺 `Cargo.lock` 时先 `cargo generate-lockfile`，再应用本 skill 自带的 Codex 兼容补丁并 build |
| `~/.codex/config.toml` 的 `[mcp_servers.lsp-mcp]` | 写入全局 MCP 配置，`command` 指向 release binary，不写固定 `--workspace-root` |
| 项目 `.lsp-mcp.json` | 按项目语言写入本地配置，`preset: minimal`、`enable: ["documentSymbol"]`、`initial_setup: disabled` |
| `.git/info/exclude` | 本地忽略 `.lsp-mcp/`、`.lsp-mcp.json` 等，不改 tracked `.gitignore` |

Codex 的 `lsp-mcp` **不写固定仓库路径**：新窗口在哪个仓库启动，MCP 就以那个 cwd 作为 workspace。跨仓查询返回 `outside workspace` 是正确隔离。

补丁只改 `~/.codex/tools/lsp-mcp` 这个工具本体，不会改业务仓库代码。当前补丁包含：

- 过滤已删除文件的 stale diagnostics。
- `documentSymbol` 默认不取 snippet，避免结构概览变成读源码。
- `documentSymbol(include_children=true)` 不再对每个嵌套符号逐个 hover，避免大文件超时。
- 修复带中文等多字节字符的 snippet range 切片 panic。

### 3. 安装项目依赖

| 锁文件 | 命令 |
|--------|------|
| `pnpm-lock.yaml` | `pnpm install --frozen-lockfile` |
| `package-lock.json` | `npm ci` |
| `go.mod` | `go mod download` |

### 4. CodeGraph（代码图谱）

CodeGraph 用 tree-sitter 解析代码生成符号关系图谱（SQLite），让 agent 一次查询拿到完整调用链，
替代多轮 rg → 小范围读文件。脚本会检查这些项：

| 检查项 | 缺失时 `--fix` 行为 |
|--------|---------------------|
| `.codegraph/codegraph.db` | `npx -y @colbymchenry/codegraph init -i`（全量建索引） |
| `.mcp.json` 里的 codegraph 配置 | 写入 Claude Code 用的 MCP server 配置 |
| `.mcp.json` 里遗留的 `lsp-mcp` 配置 | 删除；Claude Code 走 LSP 插件，Codex 走全局 `~/.codex/config.toml` |
| `~/.codex/config.toml` 的 `[mcp_servers.codegraph]` | 写入 Codex 用的全局启动器，`command = "npx"`，不写固定 `cwd` |
| `.git/info/exclude` 里的本地索引/MCP 配置 | 追加 `.codegraph/`、`.mcp.json` 等本地忽略规则，不改 tracked `.gitignore` |

CodeGraph 内置文件监听，保存文件后 2 秒自动增量更新索引，无需手动维护。

Codex 的 CodeGraph MCP 和 LSP MCP 一样，只注册**全局启动器**：新窗口在哪个仓库启动，就使用哪个仓库的 `.codegraph/` 索引。不要把某个仓库路径写死进全局配置。

### 5. 检索规则（CLAUDE.md / AGENTS.md）

`--fix` 时自动检测项目的 `CLAUDE.md` 和 `.codex/AGENTS.md`，如果没有"代码检索"部分就追加。
如果 `CLAUDE.md` 已经被 Git 跟踪，脚本不会自动改它，避免把本地 AI 检索说明带进团队 PR。
这些本地说明文件通过 `.git/info/exclude` 忽略，不要求项目改 `.gitignore`。
模板根据安装情况自动适配：有 CodeGraph → 四层（CodeGraph→LSP→rg→小范围读文件），没有 → 三层（LSP→rg→小范围读文件）。

Codex 版规则只写当前最小 LSP 工具集：`documentSymbol`、`goToDefinition`、`findReferences`、`hover`、`getDiagnostics`。不要写 `incomingCalls`、`outgoingCalls` 这类当前 Codex 会话未暴露的工具。

## 如果脚本修不了

某些情况需要手动介入：

- **gopls 缓存过期**：`pkill -f gopls`，重开会话让 gopls 重新索引
- **LSP 首次冷启动慢**：等 3-5 秒再重试，不要立刻降级到 rg
- **node_modules 存在但过期**：删掉 `node_modules` 再跑 `--fix`
- **Codex 新会话没暴露 LSP / CodeGraph MCP**：确认 `~/.codex/config.toml` 有 `[mcp_servers.lsp-mcp]` 和 `[mcp_servers.codegraph]`，然后完全新开一个 Codex 窗口；旧窗口不会热加载 MCP server

## 不再配置 SessionStart hook

这个 skill 不创建 `scripts/ensure-deps.sh`，也不写 `.claude/settings.json` / `.codex/hooks.json` 的 SessionStart hook。依赖安装由 `lsp-doctor.sh --fix` 当场处理，避免每次开窗口自动跑脚本。
