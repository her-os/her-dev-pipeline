# CI/CD Skill 安装指引

> 一次性配置，2 分钟。

## 安装

```bash
mkdir -p ~/.claude/skills/her-cicd
cp -r SKILL.md changelog.md ops/ context/ scripts/ \
      ~/.claude/skills/her-cicd/
```

### 验证

重启 Claude Code，输入「帮我创建一个 feat/test-cicd 分支」，Claude 应路由到 her-cicd skill。

## 前置条件

- Claude Code 已安装
- GitHub CLI 已登录（`gh auth status`）
- 本地有 Her-Web / her-gateway / her-salon 仓库

## 文件结构

```
her-cicd/
├── SKILL.md              ← 入口 + 路由表
├── changelog.md          ← 操作记录（3 行封顶）
├── ops/                  ← 操作文件（一个任务一个文件，自包含）
├── context/              ← 背景知识（正常不读）
├── scripts/              ← 可执行脚本
└── changelog-archive/    ← 存量归档
```
