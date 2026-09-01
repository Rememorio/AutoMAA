<div align="center">

<img src="./Assets/AutoMAA-icon.png" width="180" alt="AutoMAA 图标">

# AutoMAA

把多客户端、多账号的 MAA 日常组织成可复用、可定时、可恢复的 macOS 自动化方案。

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![Continuous integration](https://github.com/Rememorio/AutoMAA/actions/workflows/ci.yml/badge.svg)](https://github.com/Rememorio/AutoMAA/actions/workflows/ci.yml)
[![MIT License](https://img.shields.io/badge/License-MIT-2ea44f)](./LICENSE)
[![GitHub Release](https://img.shields.io/github/v/release/Rememorio/AutoMAA)](https://github.com/Rememorio/AutoMAA/releases/latest)
[![Documentation](https://img.shields.io/badge/文档-AutoMAA-0d9f9e)](https://rememorio.github.io/AutoMAA/)

</div>

AutoMAA 是一个面向 [MAA](https://github.com/MaaAssistantArknights/MaaAssistantArknights) 的自动化编排器。客户端和账号只需配置一次，再由任意数量的自动化方案决定执行对象、任务组合、参数与时间；游戏画面识别与实际操作仍由 MaaCore 完成。

完整的安装、配置、任务说明与故障排查请访问 **[AutoMAA 文档站](https://rememorio.github.io/AutoMAA/)**。

它不是 MAA 的替代品，也不是某个游戏运行器的附属助手。当前版本首先支持 macOS 上通过 PlayCover 与 MaaTools 连接的游戏客户端，但产品模型围绕 MAA 的“客户端—账号—任务”工作流设计，PlayCover 只是现阶段的连接实现。

> AutoMAA 仍处于早期开发阶段。首次使用请在有人值守的情况下完整运行一次，并确认账号匹配、任务参数和客户端切换均符合预期。

## 为什么需要 AutoMAA

MAA 很擅长完成单个客户端中的游戏任务；当日常扩展到多个服务器、多个账号和不同任务组合时，还需要一个更高层的调度器。AutoMAA 关注的正是这一层：

- 任意添加和排序客户端、账号，不预置与开发者有关的服务器、账号或本机路径。
- 客户端、账号和自动化方案都可使用自定义显示名称；重命名不会改变方案引用、当日断点或定时任务。
- 按配置串行启动客户端、切换账号、执行任务、关闭客户端并释放连接。
- 用可复用方案统一配置理智作战、公开招募、基建、信用购物和奖励领取；方案可作用于所有已启用账号或指定账号。
- 同一批账号可以拥有“轻量收菜”“完整换班”等不同方案，不需要复制客户端或账号配置。
- 按“方案 + 账号 + 步骤”记录当天完成状态，失败后可以续跑，多个方案互不串扰。
- 每个方案都能按星期配置一个或多个时间段，并独立使用 macOS LaunchAgent 定时运行；星期与时间完全重合的方案会被阻止，也可以随时从图形界面手动启动或安全停止。
- 自动化总览会为每个方案独立显示“已就绪”、提醒或问题摘要；选择任意状态即可查看对应执行路径和完整运行检查。
- 自动检查正式 GitHub Release；可选择在 App 空闲时自动下载并完成多重校验，再由用户确认重启更新 AutoMAA。

## AutoMAA 与 MAA 的关系

| 组件 | 职责 |
| --- | --- |
| AutoMAA | 自动化方案、账号顺序、任务参数、定时、重试、断点和客户端生命周期 |
| [`maa-cli`](https://github.com/MaaAssistantArknights/maa-cli) | 提供稳定的命令行入口，管理并调用 MaaCore 与资源 |
| [MaaCore / MAA](https://github.com/MaaAssistantArknights/MaaAssistantArknights) | 图像识别、游戏操作和任务执行 |
| 游戏连接环境 | 向 MaaCore 提供可连接的游戏客户端；当前 macOS 实现使用 PlayCover + MaaTools |

AutoMAA 不复制 MAA 的识别能力，也不把 MaaCore 打包进仓库。运行时需要用户自行安装 `maa-cli`、MaaCore 和资源。

## 功能

### 通用工作流

- 支持简中服 · 官服、简中服 · Bilibili、繁中服、国际服、日服和韩服。
- 客户端与账号按照用户配置的顺序串行执行；每个方案单独定义任务顺序。
- 官服、Bilibili、繁中服与 MaaCore v6.16.8 起的韩服支持同一客户端配置多个账号，通过登录页中的唯一账号片段安全匹配；MAA 暂不支持国际服和日服自动切换账号，这两个客户端只运行游戏当前已登录的单个账号。
- 每个客户端使用独立的 MAA Profile，避免服务器资源和连接配置互相污染。

### 日常任务

- **理智作战**：支持游戏当前/上次、平时跟随游戏并在 AutoMAA 剿灭后按账号恢复一次、长期资源关卡、固定剿灭、OF 关卡和自定义关卡；成功的常规作战会更新备用恢复关卡。支持普通理智药、指定天数内到期的理智药、源石、次数、1–10 次连战与博朗台模式。
- **公开招募**：刷新、次数、加急、星级自动确认、三星首选、额外标签策略和任意保留标签；5★/6★ 与保留标签会进入醒目的活动提醒，并在该次公招任务结束后立即通过可选的 macOS 通知提醒。
- **基建**：可选 `mode = 20000` 的仅收菜一键轮换、`mode = 0` 的完整换班或 `mode = 10000` 的 MAA 自定义排班；支持设施、无人机、上岗最低心情、宿舍信赖、会客室与训练室选项。每天一次完整换班的自定义参数默认使用 90% 最低心情。
- **信用与购物**：访问好友基建领取信用、信用商店购物、优先购买、黑名单、溢出策略与可选助战信用关。
- **领取奖励**：每日/每周任务、邮件、免费单抽、合成玉与限时活动奖励。

每张任务卡都有“自定义参数”开关：关闭时使用 AutoMAA 对齐当前 MAA 的推荐参数，再次开启会恢复此前保存的自定义值。未启用的可选理智参数不会写入 MAA 任务文件。

> MAA 的推荐基建参数会进行常规换班。若只想收菜而不常规换班，请开启自定义参数并明确选择“仅收菜”。

### 可靠性与安全边界

- 每个方案拥有独立的热更新、失败重试和继续策略，并按日期保存完成状态。
- 已完成的客户端或账号不会在当天再次启动或切换。
- 切换客户端前关闭当前游戏，并确认 MaaTools 连接已经释放。
- 使用单实例锁防止任务重复运行，使用 `caffeinate` 避免流程中途休眠。
- 图形界面和无界面定时运行使用同一套运行前校验；账号切换能力不匹配、账号片段不唯一、参数损坏或自定义排班缺失时不会开始流程。
- 活动记录按每次运行整理进度与结果；在定时任务运行期间打开 AutoMAA，界面会持续同步当前阶段和累计进度。自动恢复的重试会保留过程与结果，但只有重试耗尽或确实需要确认时才计为警告；部分完成会分别显示已完成、失败和未执行步骤。理智作战完成后会显示实际关卡、次数和总掉落，完整命令输出单独保存在最近 30 次诊断日志中。
- 全局设置可开启并测试后台重要通知，仅提醒需要确认的公招结果、人工处理、流程中止和步骤失败；普通完成不发送通知，未送达会进入活动记录，锁屏预览也不会显示账号名、识别标签或错误详情。
- 命令名称与输出写入活动记录或诊断日志前会遮盖账号片段、完整手机号、邮箱和本机用户目录前缀。
- “关于 AutoMAA”可以复制不含账号、路径或日志的版本与环境信息；App 与帮助菜单可直接打开关于、设置、更新检查、使用文档和问题反馈。
- 账号无法匹配时只跳过该账号；MAA 报告游戏连接离线、账号准备超时或任务执行超时时会安全重启当前客户端一次，仍未恢复或客户端需要其他人工处理时再关闭并跳过该客户端。同一客户端每次流程只自动重启一次，不会在未知界面反复尝试。
- 连接被其他已配置客户端占用时会指出冲突客户端；端口归属未知或客户端无法安全关闭时仍会停止流程，避免连接到错误实例，也不会自动关闭用户手动打开的游戏。
- “安全停止”会终止当前 MAA 命令、关闭当前客户端并清理连接；也可以按 `Command-.`。

AutoMAA 不会下载或安装游戏包体，也不会尝试绕过登录、验证码、用户协议、维护或强制大版本更新。遇到这些情况时会有限重试、给出提示并跳过对应客户端，交由用户手动处理。

## 系统要求

- macOS 14 或更高版本。
- Apple Silicon Mac。
- 已安装的 [`maa-cli`](https://github.com/MaaAssistantArknights/maa-cli) 及 MaaCore/资源。
- 一个 MAA 能够连接的游戏运行环境。当前 AutoMAA 客户端生命周期适配以 PlayCover + MaaTools 为准。

使用 Homebrew 安装 `maa-cli`：

```bash
brew install MaaAssistantArknights/tap/maa-cli
maa install
maa version
```

如果通过其他方式安装，请参考 [maa-cli 安装文档](https://docs.maa.plus/zh-cn/manual/cli/install.html)。macOS 游戏连接环境请参考 [MAA 的 macOS 文档](https://docs.maa.plus/zh-cn/manual/device/macos.html)。

## 下载与安装

1. 前往 [Releases](https://github.com/Rememorio/AutoMAA/releases/latest) 下载最新的 `AutoMAA-*-macOS-arm64.dmg`。
2. 打开 DMG，将 AutoMAA 拖入其中的“应用程序”文件夹。
3. 首次启动时，在 Finder 的“应用程序”中右键 AutoMAA，选择“打开”，再确认一次“打开”。

当前公开构建采用临时代码签名，尚未使用 Apple Developer ID 公证，因此直接双击可能被 Gatekeeper 拦截。如果右键打开仍被拦截，请前往“系统设置 → 隐私与安全性”，在安全性提示中选择“仍要打开”。请只从本仓库 Releases 下载，并使用 Release 中附带的 `.sha256` 文件校验安装包。

图文步骤、安全解释和校验命令见文档站的[下载与安装](https://rememorio.github.io/AutoMAA/guide/installation)；请勿全局关闭 Gatekeeper。

安装完成后，AutoMAA 的更新与游戏包体更新相互独立。AutoMAA 会检查本项目的正式 GitHub Release；可以在“全局设置”选择让 App 空闲时自动下载并准备更新。更新包通过附件大小、SHA-256、Bundle ID、版本、架构和代码签名校验后，仍需由用户确认“重启并立即更新”。后台定时 Runner 不会自行更新 App。“全局设置”还可以查看 maa-cli / MaaCore 版本、手动更新稳定版核心与基础资源、热更新识别资源，或选择在 AutoMAA 打开且空闲时每 24 小时最多自动尝试一次稳定版更新。手动维护和空闲自动维护遇到可识别的临时网络错误时会自动重试一次；自动维护会避让正在运行和 90 分钟内即将运行的方案。当前安装为尚未进入稳定通道的 MaaCore Beta 时，只检查稳定版清单并保留现有版本，不会下载较旧稳定包或覆盖其资源。每个方案的运行前热更新仍独立负责可热更新的识别资源。Core、基础资源和热更新资源会先写入隔离候选目录，再由对应的 MaaCore 实际加载基础、增量、服务器与 iOS 差异资源；全部通过后才启用。候选不兼容时当前安装保持不变并在活动记录中说明；可以手动确认更新 Beta Core，或等待兼容版本进入稳定通道。自动维护不会切换到 Beta，也不会自动回退资源。游戏大版本更新仍需在游戏运行环境中手动完成。

## 快速开始

1. 启动 AutoMAA，在“全局设置”中确认 `maa-cli` 路径。Apple Silicon Homebrew 的默认路径通常是 `/opt/homebrew/bin/maa`。
2. 添加一个客户端，选择服务器、游戏 `.app`、MaaTools 地址和唯一的 MAA Profile 名称。
3. 添加一个或多个账号。官服、Bilibili、繁中服与 MaaCore v6.16.8 起的韩服只有一个启用账号时，账号片段可以留空；存在多个启用账号时，每个账号必须填写不同的登录页匹配片段，例如手机号末四位或韩服 Email 中不含星号的唯一片段。国际服和日服只启用一个账号并将片段留空，运行前先在游戏中登录该账号。AutoMAA 不读取或保存游戏密码。
4. 打开“轻量日常”“完整日常”模板或新建方案，选择执行账号、任务顺序和参数。只收基建时选择“仅收菜”；完整换班时选择“完整换班”。
5. 回到“自动化总览”，先查看每张方案卡的检查摘要；选择有提醒或问题的状态可展开完整原因，处理后再在有人值守的情况下点击对应方案的“运行”。
6. 验证稳定后，在方案编辑页选择星期、设置时间并启用独立定时运行。AutoMAA 主窗口无需保持打开，但用户必须保持登录；若要准时执行，应让系统保持唤醒并避免停留在锁屏。显示器可以单独熄灭。详细条件见[每周定时运行](https://rememorio.github.io/AutoMAA/guide/scheduling)。

## 游戏更新与人工处理

AutoMAA 启动客户端后会等待 MaaTools 就绪，再交给 MAA 进入主界面。游戏大版本更新后，首次启动可能还会下载或解压数 GB 的游戏数据；这类流程可能超过自动启动的等待时间，也可能出现需要用户确认的提示。

建议在游戏更新后先手动启动一次对应客户端，等待数据下载完成并确认能够到达登录页或主界面，再运行 AutoMAA。若运行中遇到游戏版本不匹配、资源下载、维护、重新登录、验证码、用户协议或公告弹窗，AutoMAA 会有限重试、记录人工处理提示、关闭并跳过该客户端，不会自动下载游戏包体或反复操作未知界面。

## 数据与生成文件

AutoMAA 的用户数据保存在：

```text
~/Library/Application Support/AutoMAA
├── config.json             # 用户配置
├── execution-state.json    # 当日断点
├── fight-stage-memory.json # 按客户端与账号保存备用常规关卡和剿灭恢复状态
├── history.json            # 界面中的活动记录
├── Logs/                   # 经过脱敏的诊断日志与定时运行输出
├── Updates/                # 已下载、待安装的 AutoMAA 更新
└── MAA/                    # 自动生成的 Profile 与任务文件
```

`MAA/` 下的文件由 AutoMAA 管理，不建议手动编辑。删除方案、客户端或账号时，AutoMAA 只会清理由自身清单或严格命名规则确认归属的生成文件。

当前配置协议以 v0.10.0 生成的完整 schema v6 为唯一基线。schema v5 及更早配置、缺少必要字段或损坏的配置不再迁移：图形界面会先备份原文件再恢复通用空配置，后台 Runner 只报告无法处理的配置并退出。

## 开发

从源码构建需要 Xcode 26 或兼容 Swift 6.2 的工具链：

```bash
git clone https://github.com/Rememorio/AutoMAA.git
cd AutoMAA
swift test --parallel
./scripts/build-app.sh
open .build/AutoMAA.app --args --data-directory /tmp/automaa-development
```

`--data-directory` 在 Debug 与 Release 构建中都会隔离配置、日志和 LaunchAgent，并关闭系统定时任务集成；开发和界面验收不得省略该参数。

快速制作与 Release 相同结构的 DMG：

```bash
./scripts/package-dmg.sh
```

正式发版前执行唯一的完整验收入口：

```bash
./scripts/verify-release.sh
```

产物位于 `dist/`，并同时生成 SHA-256 校验文件。完整验收会覆盖隔离测试、文档、更新器、DMG、挂载结构、版本、架构与签名。若修改了图标母图，可运行 `./scripts/build-icon.sh` 重新生成 `.icns`。

在临时目录中验证更新辅助程序的替换、校验和结果回写：

```bash
./scripts/test-updater.sh
```

本地预览文档站：

```bash
npm ci
npm run docs:dev
```

生产构建使用 `npm run docs:build`。`main` 上的文档改动由 GitHub Actions 自动发布到 GitHub Pages。

项目结构：

```text
Sources/
├── AutoMAA/        # SwiftUI 图形界面
├── AutoMAAKit/     # 配置、任务生成、执行器和系统集成
└── AutoMAARunner/  # LaunchAgent 使用的无界面入口
docs/               # VitePress 中文文档站
Tests/
└── AutoMAAKitTests/
```

欢迎通过 [Issues](https://github.com/Rememorio/AutoMAA/issues) 报告能够复现的问题，也欢迎提交 Pull Request。涉及账号切换、客户端生命周期或任务参数的改动，请同时补充相应测试，并优先保证“不会跑错账号、不会连接错客户端”。

提交代码前请阅读 [`CONTRIBUTING.md`](./CONTRIBUTING.md)。仓库的架构、安全边界和编码代理约束记录在 [`AGENTS.md`](./AGENTS.md)，维护者发版流程记录在 [`RELEASE.md`](./RELEASE.md)。外部贡献者通过分支和 Pull Request 合入 `main`；维护者可按项目需要直接维护 `main`。

## 致谢

AutoMAA 建立在 MAA 社区长期积累的成果之上，谨向以下项目及其所有贡献者致谢：

- [MaaAssistantArknights](https://github.com/MaaAssistantArknights/MaaAssistantArknights)：提供 MaaCore、任务协议、资源和完整的自动化能力。没有 MAA，就没有 AutoMAA。
- [maa-cli](https://github.com/MaaAssistantArknights/maa-cli)：提供 macOS 上可靠的命令行工作流、Core/资源管理和 Profile/Task 配置机制。
- [MaaMacGui](https://github.com/MaaAssistantArknights/MaaMacGui)：AutoMAA 的部分任务参数语义与 macOS 交互设计参考了其开源实现。
- [PlayCover](https://github.com/PlayCover/PlayCover) 与 MaaTools 相关贡献者：为当前 macOS 原生游戏连接方案提供基础能力。

AutoMAA 是独立的社区项目，与 MAA 官方、鹰角网络、Hypergryph、Yostar 或《明日方舟》的运营方均无隶属、合作或背书关系。项目名称中的 “MAA” 用于说明其依赖和服务对象；MAA 的名称、Logo、代码与其他资产仍归各自权利人所有，并遵循 [MAA 的许可证与用户协议](https://github.com/MaaAssistantArknights/MaaAssistantArknights#声明)。

## 许可证与视觉资产

AutoMAA 的源代码与文档使用 [MIT License](./LICENSE) 开源。

MAA、MaaCore 与 `maa-cli` 是独立安装的第三方项目，分别遵循其各自的许可证和用户协议，不因使用 AutoMAA 而改变。

AutoMAA 应用图标与宣传视觉资产不属于 MIT License 的授权范围。图标为面向《明日方舟》角色艾雅法拉的非官方二次创作，设计上向 MAA 社区熟悉的视觉语言致意，但并非 MAA 官方 Logo。角色名称、形象及相关知识产权归其权利人所有；宣传字图是独立制作的非官方项目视觉，不包含官方 Logo、角色形象或原始活动素材。这些资产仅用于识别和介绍 AutoMAA，不得据此主张任何官方关系、合作或授权。
