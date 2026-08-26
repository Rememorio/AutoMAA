# AutoMAA Agent Guide

本文件适用于整个仓库，供 Codex、其他编码代理以及自动化维护工具使用。目标是让改动保持通用、可验证，并优先保护用户的账号、游戏客户端和本机环境。

## 项目定位

AutoMAA 是原生 macOS MAA 工作流编排器。它管理客户端、账号、可复用自动化方案、任务顺序、重试、断点、定时和客户端生命周期；画面识别与实际游戏操作由 `maa-cli` 和 MaaCore 完成。

不要把 AutoMAA 描述或实现成：

- 某个特定用户的日常脚本；
- PlayCover 专用账号助手；
- MAA 或 MaaCore 的替代品；
- 保存游戏密码、验证码或登录凭据的工具。

所有功能必须能够由新用户从空配置开始自行配置。仓库内不得出现维护者的账号、手机号、账号片段、密码、本机应用路径或用户数据。

## 开始工作

修改前先确认工作区与改动范围：

```bash
git status --short --branch
git diff
swift test --parallel
```

保留不属于当前任务的本地改动。除非用户明确要求，不要提交、推送、创建 Release，也不要操作真实游戏客户端。

常用验证命令：

```bash
swift test --parallel
./scripts/build-app.sh
./scripts/test-updater.sh
./scripts/package-dmg.sh
npm run docs:build
```

构建产物位于 `.build/` 和 `dist/`，不得提交。

## 代码结构

| 路径 | 职责 |
| --- | --- |
| `Sources/AutoMAA/` | SwiftUI 应用、界面状态和用户交互 |
| `Sources/AutoMAAKit/Models.swift` | 配置协议、任务枚举和工作流数据模型 |
| `Sources/AutoMAAKit/ConfigurationValidation.swift` | 结构校验、运行前检查和 Profile 名称规范化 |
| `Sources/AutoMAAKit/MAAConfigurationWriter.swift` | 将 AutoMAA 配置转换为独立的 MAA Profile 与 Task 文件 |
| `Sources/AutoMAAKit/WorkflowRunner.swift` | 串行调度、重试、断点、清理和事件输出 |
| `Sources/AutoMAAKit/RuntimeSupport.swift` | 进程锁、端口、游戏生命周期和人工处理分类 |
| `Sources/AutoMAAKit/Stores.swift` | 配置、历史与当日执行状态的持久化 |
| `Sources/AutoMAAKit/LaunchAgentManager.swift` | macOS LaunchAgent 定时任务 |
| `Sources/AutoMAARunner/` | 无界面定时运行入口 |
| `Sources/AutoMAAResourceProbe/` | 在独立进程中调用 MaaCore 验证基础与增量资源组合 |
| `Sources/AutoMAAUpdater/` | 等待主 App 退出、原子替换、失败回滚和重新启动 |
| `Tests/AutoMAAKitTests/` | 核心配置与工作流测试 |
| `scripts/` | App、图标和 DMG 构建脚本 |
| `docs/` | VitePress 用户与开发文档 |
| `.github/workflows/ci.yml` | Swift 测试、App 构建、签名和更新器隔离验证 |
| `.github/workflows/docs.yml` | GitHub Pages 构建与部署 |

界面层不应重新实现工作流或 MAA 参数语义。可测试的配置、生成和调度逻辑应放在 `AutoMAAKit`。

## 核心安全约束

涉及工作流的改动必须保持以下不变量：

1. 客户端严格串行运行；只有当前客户端关闭且 MaaTools 端口确认释放后，才能启动下一个客户端。
2. 只有当前 MAA 支持自动切换账号的服务器才能在同一客户端启用多个账号，这些账号必须使用非空且互不重复的匹配片段；不支持切换的服务器只能启用一个账号并使用游戏当前登录状态。
3. 账号匹配失败只能跳过该账号；客户端更新、维护或无法进入游戏时应跳过该客户端；连接到错误进程、端口无法释放等安全问题必须停止整个流程。
4. 只有成功完成的任务才能写入当日断点。断点必须按方案隔离；失败、超时和取消不得伪装成成功。
5. “安全停止”必须终止当前 MAA 命令、关闭当前客户端并清理连接。
6. 不绕过登录、验证码、用户协议、维护、强制更新或未知弹窗，也不自动下载或安装游戏包体。
7. 日志与错误信息应足以定位问题，但必须通过统一脱敏层隐藏配置中的账号片段、完整手机号、邮箱和其他凭据。
8. 每个客户端使用独立的 MAA Profile；生成文件只能清理由 AutoMAA 清单或命名规则确认归属的文件。
9. AutoMAA 本体更新只接受构建时配置仓库中固定命名的正式 Release；替换前必须校验大小、SHA-256、Bundle ID、版本、架构和代码签名，失败时保留或恢复旧 App。
10. 图形界面、定时 Runner 和直接调用 `WorkflowRunner` 必须使用同一套运行前校验；不能只在按钮层阻止危险配置。
11. MaaCore、基础资源和热更新资源必须先写入隔离候选目录，并由候选 Core 在独立进程中按实际顺序加载；只有验证通过后才能启用，失败时不得破坏当前安装或启动游戏。

官方构建的更新仓库由 `scripts/Info.plist` 中的 `AutoMAAUpdateRepository` 指定。下游发行版可以在构建时改为自己的仓库，不要在界面或业务代码中另行写死维护者信息。

任何削弱这些约束的改动都需要明确设计说明、相应测试和维护者审查。

## MAA 配置规则

- MAA 参数名称、默认值和服务端映射以当前 MAA 集成文档与 MaaCore 接口为准；MaaMacGui 只用于交互和推荐值参考。上游 GUI 仍在使用弃用字段时，不得把弃用字段带入 AutoMAA。
- “MAA 推荐参数”和“AutoMAA 自定义参数”是两个明确模式。关闭自定义参数不能丢失用户先前输入的值；推荐参数应集中生成并尽量省略有稳定 Core 默认值的可选字段，避免复制一份会漂移的默认配置。
- 基建常规换班使用 `Infrast mode = 0`，自定义排班使用 `mode = 10000`，仅收菜的一键轮换使用 `mode = 20000`；文案必须准确说明 mode 20000 仍保留无人机和会客室等基本操作。
- 不得生成上游已弃用参数。当前临期理智药使用 `medicine_expire_days`，公招保留标签使用 `preserve_tags`。
- 任务参数属于自动化方案，不属于账号；不要重新把相同任务配置复制回每个账号。
- 未启用的可选参数不应写入任务文件。
- Profile 名称和生成文件名必须经过安全规范化，禁止目录穿越或覆盖用户手写配置。
- 修改配置字段时同步检查默认值、Codable 往返、UI、任务生成和测试。
- 项目处于 `0.x` 阶段，配置协议发生不兼容变化时递增 `AppConfiguration.currentSchemaVersion`，并更新测试、README 和配置参考。除非任务明确要求，不增加旧实验配置的迁移层；不兼容配置必须先备份再重置，后台 Runner 不得静默改写它。

## Swift 与 SwiftUI 规范

- 使用 Swift 6.2，并保持 macOS 14 为最低系统版本。
- 遵循现有命名和文件组织；类型使用清晰的完整名称，局部变量保持简洁但不含糊。
- 保持严格并发安全：UI 状态和工作流入口使用 `@MainActor`，跨并发边界的数据模型应满足 `Sendable`。
- 优先使用 Foundation、AppKit 和 SwiftUI；新增第三方依赖前必须说明收益、维护成本和分发影响。
- 文件写入使用原子操作；外部进程必须有超时、取消和退出码处理。
- 不吞掉会影响用户决策的错误。可以降级的错误要进入日志或人工处理提示。
- SwiftUI 视图保持职责单一；重复且可复用的视觉语言放入 `Theme.swift` 或小型组件。
- 用户界面以简体中文为主，文案应简短、具体，并说明用户下一步可以做什么。
- 使用系统控件、动态颜色和 SF Symbols，支持深浅色、VoiceOver 和“减少动态效果”。避免无意义的持续动画或会导致布局跳动的状态控件。

提交 Swift 改动前至少运行：

```bash
swift test --parallel
```

涉及应用入口、SwiftUI 或打包的改动还需运行：

```bash
./scripts/build-app.sh
```

## 测试隔离

自动化测试不得接触真实游戏或用户数据。

- 所有存储测试使用 `AppDirectories(root:)` 指向独立临时目录。
- LaunchAgent 测试必须同时注入临时 `launchAgentsDirectory` 并关闭系统集成；只替换 `AppDirectories` 仍可能触碰用户的 `~/Library/LaunchAgents` 或调用真实 `launchctl`。
- 流程测试使用假 Bundle Identifier、测试专用高位端口和无副作用的可执行文件，例如 `/usr/bin/true`。
- 不得在测试中使用生产服务器的 Bundle Identifier、真实 `.app` 路径、默认 MaaTools 地址或用户的 `~/Library/Application Support/AutoMAA`。
- 不得依赖已经安装的账号、密码、PlayCover 状态、MAA Profile 或网络。
- 修改账号切换、端口释放、断点、取消、任务参数和人工处理分类时必须补充回归测试。
- 真机或真实账号测试只在用户明确授权时进行；开始前说明范围，结束后确认客户端关闭和端口释放，并在结果中隐去敏感信息。
- 所有 SwiftUI 冒烟测试，无论 Debug 还是 Release 构建，都必须使用 `--data-directory <临时目录>`，或仅在独立 QA Bundle 中注入 `AUTOMAA_DEVELOPMENT_DATA_DIRECTORY`；该入口同时隔离配置、日志和 LaunchAgent，禁止用它指向默认用户目录。

## 文档与视觉资产

- 用户行为、系统要求或配置语义变化时同步更新 `README.md`。
- 完整用户指南位于 `docs/`；新增页面时同步更新 VitePress 导航，并运行 `npm run docs:build` 检查站内链接。
- 产品截图必须直接保留原生 Retina 背板像素，禁止把 1× 截图放大伪装成 2×；使用无损 WebP 和透明窗口圆角，提交前运行 `npm run docs:check-screenshots`，并在 100% 缩放下确认正文与控件文字清晰。
- 面向贡献者的流程更新在 `CONTRIBUTING.md`，发版流程更新在 `RELEASE.md`。
- 用户可见的重要变化记录在 `CHANGELOG.md`；README、文档、更新日志与 Release Notes 必须只表达产品事实、用户影响和已知限制，不能依赖维护协作背景才能成立。
- 保留并准确表达 MAA、MaaCore、`maa-cli`、MaaMacGui 和当前连接环境的 credit。
- 不提交来源或授权不明的角色图片、Logo、字体和其他资产。AutoMAA 图标不属于 MIT License，相关声明不得删除或弱化。

## Git 与 GitHub

- 外部贡献者必须从分支提交 Pull Request，不得直接推送 `main`。具体规范见 `CONTRIBUTING.md`。
- 维护者可以直接推送 `main`，但编码代理只有在用户明确要求时才能这样做。
- Commit 使用 Conventional Commits 风格，例如 `feat: ...`、`fix: ...`、`docs: ...`、`test: ...`、`refactor: ...`、`build: ...`、`chore: ...` 和 `release: vX.Y.Z`。
- 每个 commit 保持单一目的，不提交用户配置、日志、构建目录、DMG 或凭据。
- 不重写已经公开的 tag 或 Release。发版步骤见 `RELEASE.md`。

## 维护记忆与自进化

代理应把一次性发现转化为最小、可验证且不会过期的项目知识，让后续改动更安全，而不是在文档末尾不断堆叠经验记录。

1. **先取证再立规则。** 上游行为以公开协议、当前源码或可重复测试为证据；不要把推测、单次本机现象或个人偏好写成全局约束。
2. **错误先变成回归测试。** 修复缺陷时先找到能稳定复现的最小输入，再把安全不变量放进 `AutoMAAKit`，最后更新文案。测试名称描述行为，不记录事件经过。
3. **知识放在最窄的正确层级。** 代码不变量写成类型和校验，用户选择写入文档，贡献流程写入 `CONTRIBUTING.md`，发版检查写入 `RELEASE.md`；只有跨任务长期有效的代理约束才进入本文件。
4. **有机改写而非追加补丁。** 新结论与旧规则冲突时，直接重写或删除旧内容；不要同时保留两个时代的参数、命名或流程。定期搜索已弃用字段、过期版本、旧截图和重复说明。
5. **审计上游漂移。** 每个 MINOR Release 至少对照一次 MAA 集成文档、MaaCore 参数解析、maa-cli 配置 schema 和最新稳定版更新日志。发现差异时同步模型、生成器、UI、测试和文档，不用兼容层掩盖错误。
6. **只学习项目知识。** 公开内容应脱离当前协作上下文独立成立，不保留请求来源、批准过程、代理或工具名称、本机验收经过；也不把用户账号、手机号、路径、日志内容或私人运行习惯沉淀进仓库。通用场景要抽象成产品规则、空白模板、假数据和可配置能力。
7. **让规则能够被删除。** 新增规则时优先说明要保护的不变量；一旦代码结构或自动化检查已经完整承载该约束，就精简重复文字，保持本文件可读。

## 完成标准

交付前确认：

- 改动是通用配置能力，没有维护者专属内容；
- 核心安全约束仍成立；
- MAA 上游协议审计没有遗留弃用字段或未经说明的能力差异；
- 新行为有足够的自动化测试；
- `swift test` 和 CI 等价验证通过，必要时 App、更新器、文档和 DMG 构建也通过；
- README、贡献指南、发版文档和更新日志与实现一致，公开文案只包含产品事实、用户影响与已知限制；
- `git diff --check` 无错误，工作区中没有敏感信息或意外产物；
- 最终说明列出验证范围、未验证项和已知限制。
