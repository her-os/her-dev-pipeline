# 协作场景

## 场景 A：新功能开发（客户端 + 服务端联调）

涉及 Her-Web 后端 API 新增 + her-salon 客户端界面改动。

```
阶段一：本地开发（各自独立）
├── Her-Web:  feat/new-feature 从 main 拉出，本地 SQLite 自测 API
├── salon:    feat/new-feature 从 main 拉出，本地指向 localhost:3000 联调
└── 目标：各端功能可运行

阶段二：测试环境联调（test 测试栈）
├── Her-Web feat → dev → deploy-test.sh deploy-web 部署
├── salon API 地址切到 https://test.hersoul.cn 联调
├── 非开发同事在测试环境体验新功能
└── 有问题回 feat 修，重新部署 dev

阶段三：上线生产（服务端先行）
├── 1. Her-Web feat → main（PR review）
├── 2. main 打 tag（v0.2.0）
├── 3. release.sh 部署生产
├── 4. 验证生产 API 正常
├── 5. salon feat → main，打 tag（v0.0.5）
├── 6. 本地构建签名包，上传
└── 关键：服务端先上，客户端后发
```

**为什么服务端先上**：新 API 上线后旧版 salon 不调用它，不受影响；反过来新版 salon 会请求还不存在的接口。

## 场景 B：已有 API 接口修改

### 非破坏性变更（常见）

新增字段、新增可选参数 —— 旧客户端忽略不认识的字段，走普通流程。

### 破坏性变更（改字段名、改格式、删字段）

三步迁移：

```
第一步：服务端兼容期
├── 同时返回新旧两种格式
├── 部署到生产，旧版 salon 继续用旧格式
└── 打 tag 上线（v0.2.1）

第二步：发布新客户端
├── salon 新版本改为读取新格式
├── 打 tag 构建发布（v0.0.6）
├── Tauri updater 推送更新
└── 等待用户逐步升级

第三步：清理旧格式
├── 确认旧版本占比 < 5%
├── 服务端移除旧格式兼容代码
└── 打 tag 上线（v0.3.0）
```

时间线：第一步到第三步通常 2-4 周。兼容代码放着不碍事。

## 场景 C：基础改动（地基变更）

鉴权重构、DB schema 迁移、构建工具升级、公共组件重写等。

**核心区别：先 main 再同步 dev。** 原因：基础改动进 dev 后其他 feat 会不知不觉依赖新地基，之后合到 main（旧地基）会出问题。

```
第一步：从 main 拉分支，本地开发自测
第二步：跳过 dev，直接 PR 到 main（review 更严格）
第三步：打 tag，release.sh 部署生产
第四步：同步 dev（git checkout dev && git merge main && git push）
第五步：通知其他人 rebase main
```

**怎么判断**：改了 2-3 个文件当普通 feat；改了 10+ 个文件、影响别人正在写的代码当基础改动。

**现阶段简化**：3 人团队群里说一声"我要改地基，这两天先别往 dev 合"，改完通知 rebase。

## 场景 D：HER Engine 长期开发

Engine 是 salon 的新运行时基座，与现有 salon **独立仓库**开发（2026-05-18 会议决定）。改动量接近重做整个软件，不与现有代码混放。

**仓库关系**：
- engine 独立仓库，自己的 `dev` + `main`，走标准两分支模型
- salon 现有仓库继续日常迭代（bug 修复、小功能）
- salon 预留通用 SDK 接口，engine 功能成熟后逐步迁移接入

### Engine 仓库内的开发流程

和其他项目一致：`feat/xxx → dev → main → 打 tag`。没有特殊分支规则。

**关键：拆小分支，频繁合入。** 每个分支一两周合一次，不要一个分支干三个月。

### 与 salon 的集成

engine 功能需要接入 salon 时：

```
1. engine 仓库先完成功能，打 tag 发版
2. salon 仓库开 feat/integrate-xxx，引入 engine 产物（SDK / crate / npm 包）
3. salon feat 走普通流程：dev 测试 → main 上线
```

引入 engine 产物属于 salon 的正常功能开发，不需要特殊流程。如果引入后需要替换 salon 的旧模块（大面积改动），走基础改动流程（场景 C）。

### edition 灰度切换

engine 功能接入 salon 后，用 edition 开关控制灰度：
- `internal`：启用新模块，内部先验证
- `beta`：仍走旧路径，用户不受影响
- 确认没问题后 beta 也切到新模块 → 打 tag 发版

## 对比总结

```
普通功能：  feat → dev（测试）→ main（上线）      先 dev 再 main
基础改动：  feat → main（上线）→ 同步到 dev       先 main 再 dev
接口修改：  非破坏性走普通流程，破坏性走三步迁移
Engine：    独立仓库开发，接入 salon 时走普通或基础改动流程
```
