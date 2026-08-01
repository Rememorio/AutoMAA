# AutoMAA Agent Guide

本文件适用于整个仓库，供 Codex、其他编码代理以及自动化维护工具使用。目标是让改动保持通用、可验证，并优先保护用户的账号、游戏客户端和本机环境。

## 项目定位

AutoMAA 是原生 macOS MAA 工作流编排器。它管理客户端、账号、任务顺序、重试、断点、定时和客户端生命周期；画面识别与实际游戏操作由 `maa-cli` 和 MaaCore 完成。

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
swift test
```

保留不属于当前任务的本地改动。除非用户明确要求，不要提交、推送、创建 Release，也不要操作真实游戏客户端。

常用验证命令：

```bash
swift test
./scripts/build-app.sh
./scripts/package-dmg.sh
```

构建产物位于 `.build/` 和 `dist/`，不得提交。

## 代码结构

| 路径 | 职责 |
| --- | --- |
| `Sources/AutoMAA/` | SwiftUI 应用、界面状态和用户交互 |
| `Sources/AutoMAAKit/Models.swift` | 配置协议、任务枚举和工作流数据模型 |
| `Sources/AutoMAAKit/MAAConfigurationWriter.swift` | 将 AutoMAA 配置转换为独立的 MAA Profile 与 Task 文件 |
| `Sources/AutoMAAKit/WorkflowRunner.swift` | 串行调度、重试、断点、清理和事件输出 |
| `Sources/AutoMAAKit/RuntimeSupport.swift` | 进程锁、端口、游戏生命周期和人工处理分类 |
| `Sources/AutoMAAKit/Stores.swift` | 配置、历史与当日执行状态的持久化 |
| `Sources/AutoMAAKit/LaunchAgentManager.swift` | macOS LaunchAgent 定时任务 |
| `Sources/AutoMAARunner/` | 无界面定时运行入口 |
| `Tests/AutoMAAKitTests/` | 核心配置与工作流测试 |
| `scripts/` | App、图标和 DMG 构建脚本 |

界面层不应重新实现工作流或 MAA 参数语义。可测试的配置、生成和调度逻辑应放在 `AutoMAAKit`。

## 核心安全约束

涉及工作流的改动必须保持以下不变量：

1. 客户端严格串行运行；只有当前客户端关闭且 MaaTools 端口确认释放后，才能启动下一个客户端。
2. 同一客户端的多个启用账号必须使用非空且互不重复的账号匹配片段。
3. 账号匹配失败只能跳过该账号；客户端更新、维护或无法进入游戏时应跳过该客户端；连接到错误进程、端口无法释放等安全问题必须停止整个流程。
4. 只有成功完成的任务才能写入当日断点。失败、超时和取消不得伪装成成功。
5. “安全停止”必须终止当前 MAA 命令、关闭当前客户端并清理连接。
6. 不绕过登录、验证码、用户协议、维护、强制更新或未知弹窗，也不自动下载或安装游戏包体。
7. 日志与错误信息应足以定位问题，但不得记录密码、完整手机号或其他凭据。
8. 每个客户端使用独立的 MAA Profile；生成文件只能清理由 AutoMAA 清单或命名规则确认归属的文件。

任何削弱这些约束的改动都需要明确设计说明、相应测试和维护者审查。

## MAA 配置规则

- MAA 参数名称、默认值和服务端映射必须以当前 MAA/MaaMacGui 的公开协议为依据，不要凭印象新增参数。
- “MAA 默认参数”和“AutoMAA 自定义参数”是两个明确模式。关闭自定义参数不能丢失用户先前输入的值。
- 自定义基建收菜使用 `Infrast mode = 20000`；不要将它改为常规换班模式。
- 未启用的可选参数不应写入任务文件。
- Profile 名称和生成文件名必须经过安全规范化，禁止目录穿越或覆盖用户手写配置。
- 修改配置字段时同步检查默认值、Codable 往返、UI、任务生成和测试。
- 项目处于 `0.x` 阶段，配置协议发生不兼容变化时递增 `AppConfiguration.currentSchemaVersion`，并更新测试和 README。除非任务明确要求，不增加旧实验配置的迁移层。

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
swift test
```

涉及应用入口、SwiftUI 或打包的改动还需运行：

```bash
./scripts/build-app.sh
```

## 测试隔离

自动化测试不得接触真实游戏或用户数据。

- 所有存储测试使用 `AppDirectories(root:)` 指向独立临时目录。
- 流程测试使用假 Bundle Identifier、测试专用高位端口和无副作用的可执行文件，例如 `/usr/bin/true`。
- 不得在测试中使用默认官服/日服 Bundle Identifier、真实 `.app` 路径、`localhost:1717` 或用户的 `~/Library/Application Support/AutoMAA`。
- 不得依赖已经安装的账号、密码、PlayCover 状态、MAA Profile 或网络。
- 修改账号切换、端口释放、断点、取消、任务参数和人工处理分类时必须补充回归测试。
- 真机或真实账号测试只在用户明确授权时进行；开始前说明范围，结束后确认客户端关闭和端口释放，并在结果中隐去敏感信息。

## 文档与视觉资产

- 用户行为、系统要求或配置语义变化时同步更新 `README.md`。
- 面向贡献者的流程更新在 `CONTRIBUTING.md`，发版流程更新在 `RELEASE.md`。
- 用户可见的重要变化记录在 `CHANGELOG.md`。
- 保留并准确表达 MAA、MaaCore、`maa-cli`、MaaMacGui 和当前连接环境的 credit。
- 不提交来源或授权不明的角色图片、Logo、字体和其他资产。AutoMAA 图标不属于 MIT License，相关声明不得删除或弱化。

## Git 与 GitHub

- 外部贡献者必须从分支提交 Pull Request，不得直接推送 `main`。具体规范见 `CONTRIBUTING.md`。
- 维护者可以直接推送 `main`，但编码代理只有在用户明确要求时才能这样做。
- Commit 使用 Conventional Commits 风格，例如 `feat: ...`、`fix: ...`、`docs: ...`、`test: ...`、`refactor: ...`、`build: ...`、`chore: ...` 和 `release: vX.Y.Z`。
- 每个 commit 保持单一目的，不提交用户配置、日志、构建目录、DMG 或凭据。
- 不重写已经公开的 tag 或 Release。发版步骤见 `RELEASE.md`。

## 完成标准

交付前确认：

- 改动是通用配置能力，没有维护者专属内容；
- 核心安全约束仍成立；
- 新行为有足够的自动化测试；
- `swift test` 通过，必要时 App 和 DMG 构建也通过；
- README、贡献指南、发版文档和更新日志与实现一致；
- `git diff --check` 无错误，工作区中没有敏感信息或意外产物；
- 最终说明列出验证范围、未验证项和已知限制。
