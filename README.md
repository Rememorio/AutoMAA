<div align="center">

<img src="./Assets/AutoMAA-icon.png" width="180" alt="AutoMAA 图标">

# AutoMAA

把多客户端、多账号的 MAA 日常串成一条可靠、可配置、可恢复的 macOS 工作流。

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![MIT License](https://img.shields.io/badge/License-MIT-2ea44f)](./LICENSE)

</div>

AutoMAA 是一个面向 [MAA](https://github.com/MaaAssistantArknights/MaaAssistantArknights) 的自动化编排器。它负责安排客户端和账号顺序、生成任务参数、调用 `maa-cli`、处理重试与断点，并在合适的时间安全切换到下一项；游戏画面识别与实际操作仍由 MaaCore 完成。

它不是 MAA 的替代品，也不是某个游戏运行器的附属助手。当前版本首先支持 macOS 上通过 PlayCover 与 MaaTools 连接的游戏客户端，但产品模型围绕 MAA 的“客户端—账号—任务”工作流设计，PlayCover 只是现阶段的连接实现。

> AutoMAA 仍处于早期开发阶段。首次使用请在有人值守的情况下完整运行一次，并确认账号匹配、任务参数和客户端切换均符合预期。

## 为什么需要 AutoMAA

MAA 很擅长完成单个客户端中的游戏任务；当日常扩展到多个服务器、多个账号和不同任务组合时，还需要一个更高层的调度器。AutoMAA 关注的正是这一层：

- 任意添加和排序客户端、账号，不预置与开发者有关的服务器、账号或本机路径。
- 按配置串行启动客户端、切换账号、执行任务、关闭客户端并释放连接。
- 为每个账号独立配置理智作战、公开招募、基建和奖励领取。
- 记录当天已经完成的步骤，失败后可以续跑，不重复消耗已完成任务。
- 通过 macOS LaunchAgent 定时运行，也可以随时从图形界面手动启动或安全停止。

## AutoMAA 与 MAA 的关系

| 组件 | 职责 |
| --- | --- |
| AutoMAA | 工作流、账号顺序、任务参数、定时、重试、断点和客户端生命周期 |
| [`maa-cli`](https://github.com/MaaAssistantArknights/maa-cli) | 提供稳定的命令行入口，管理并调用 MaaCore 与资源 |
| [MaaCore / MAA](https://github.com/MaaAssistantArknights/MaaAssistantArknights) | 图像识别、游戏操作和任务执行 |
| 游戏连接环境 | 向 MaaCore 提供可连接的游戏客户端；当前 macOS 实现使用 PlayCover + MaaTools |

AutoMAA 不复制 MAA 的识别能力，也不把 MaaCore 打包进仓库。运行时需要用户自行安装 `maa-cli`、MaaCore 和资源。

## 功能

### 通用工作流

- 支持中国大陆官服、Bilibili 服、繁中服、国际服、日服和韩服。
- 客户端、账号与账号内任务均按照用户配置的顺序串行执行。
- 同一客户端支持多个账号，通过登录页中的唯一账号片段安全匹配。
- 每个客户端使用独立的 MAA Profile，避免服务器资源和连接配置互相污染。

### 日常任务

- **理智作战**：当前/上次、1-7、龙门币、红票、技能、经验、剿灭和自定义关卡；支持理智药、48 小时过期理智药、源石、次数、连战与博朗台模式。
- **公开招募**：刷新、次数、加急、星级自动确认和小车词条保留。
- **基建**：使用 MAA `Infrast mode = 20000` 实现不换班收菜，可选择制造站、贸易站、会客室和无人机用途。
- **领取奖励**：每日/每周任务、邮件、免费单抽、合成玉与限时活动奖励。

每张任务卡都有“自定义参数”开关：关闭时使用 MAA 的出厂默认参数，再次开启会恢复此前保存的 AutoMAA 参数。未启用的理智参数不会写入 MAA 任务文件。

> MAA 的基建出厂参数会进行常规换班。若只想收菜而不换班，请保持基建的“自定义参数”开启。

### 可靠性与安全边界

- 每个步骤独立重试，并按日期保存完成状态。
- 已完成的客户端或账号不会在当天再次启动或切换。
- 切换客户端前关闭当前游戏，并确认 MaaTools 连接已经释放。
- 使用单实例锁防止任务重复运行，使用 `caffeinate` 避免流程中途休眠。
- 账号无法匹配时只跳过该账号；客户端需要人工处理时关闭并跳过该客户端。
- 连接被未知进程占用或客户端无法安全关闭时停止流程，避免连接到错误实例。
- “安全停止”会终止当前 MAA 命令、关闭当前客户端并清理连接；也可以按 `Command-.`。

AutoMAA 不会下载或安装游戏包体，也不会尝试绕过登录、验证码、用户协议、维护或强制大版本更新。遇到这些情况时会有限重试、给出提示并跳过对应客户端，交由用户手动处理。

## 系统要求

- macOS 14 或更高版本。
- Apple Silicon Mac；当前主要在 Apple Silicon 环境开发和验证。
- Xcode 26 或兼容 Swift 6.2 的开发工具链（从源码构建时需要）。
- 已安装的 [`maa-cli`](https://github.com/MaaAssistantArknights/maa-cli) 及 MaaCore/资源。
- 一个 MAA 能够连接的游戏运行环境。当前 AutoMAA 客户端生命周期适配以 PlayCover + MaaTools 为准。

使用 Homebrew 安装 `maa-cli`：

```bash
brew install MaaAssistantArknights/tap/maa-cli
maa install
maa version
```

如果通过其他方式安装，请参考 [maa-cli 安装文档](https://docs.maa.plus/zh-cn/manual/cli/install.html)。macOS 游戏连接环境请参考 [MAA 的 macOS 文档](https://docs.maa.plus/zh-cn/manual/device/macos.html)。

## 构建与运行

```bash
git clone https://github.com/Rememorio/AutoMAA.git
cd AutoMAA
./scripts/build-app.sh
open .build/AutoMAA.app
```

构建脚本会生成经过本地临时签名的 `.build/AutoMAA.app`，其中包含图形应用和用于定时任务的无界面运行器。

如果修改了图标母图，可重新生成 `.icns`：

```bash
./scripts/build-icon.sh
```

## 快速开始

1. 启动 AutoMAA，在“全局设置”中确认 `maa-cli` 路径。Apple Silicon Homebrew 的默认路径通常是 `/opt/homebrew/bin/maa`。
2. 添加一个客户端，选择服务器、游戏 `.app`、MaaTools 地址和唯一的 MAA Profile 名称。
3. 添加一个或多个账号。同一客户端只有一个启用账号时，账号片段可以留空；存在多个启用账号时，每个账号必须填写不同的登录页匹配片段。
4. 为每个账号启用任务并调整执行顺序。只收基建时，保持基建自定义参数开启并选择需要收取的设施和无人机用途。
5. 回到“今日总览”，处理所有运行检查提示，然后在有人值守的情况下执行一次完整工作流。
6. 验证稳定后，可在“全局设置”中启用每日自动运行。

## 数据与生成文件

AutoMAA 的用户数据保存在：

```text
~/Library/Application Support/AutoMAA
├── config.json             # 用户配置
├── execution-state.json    # 当日断点
├── history.json            # 运行历史
├── Logs/                   # 日志
└── MAA/                    # 自动生成的 Profile 与任务文件
```

`MAA/` 下的文件由 AutoMAA 管理，不建议手动编辑。删除客户端或账号时，AutoMAA 只会清理由自身清单记录的生成文件。

当前配置协议为 schema v2。项目仍在 `0.x` 阶段，不承诺对实验阶段的旧配置进行迁移；重要配置请自行备份。

## 开发

```bash
swift test
swift run AutoMAA
```

项目结构：

```text
Sources/
├── AutoMAA/        # SwiftUI 图形界面
├── AutoMAAKit/     # 配置、任务生成、执行器和系统集成
└── AutoMAARunner/  # LaunchAgent 使用的无界面入口
Tests/
└── AutoMAAKitTests/
```

欢迎通过 [Issues](https://github.com/Rememorio/AutoMAA/issues) 报告能够复现的问题，也欢迎提交 Pull Request。涉及账号切换、客户端生命周期或任务参数的改动，请同时补充相应测试，并优先保证“不会跑错账号、不会连接错客户端”。

## 致谢

AutoMAA 建立在 MAA 社区长期积累的成果之上，谨向以下项目及其所有贡献者致谢：

- [MaaAssistantArknights](https://github.com/MaaAssistantArknights/MaaAssistantArknights)：提供 MaaCore、任务协议、资源和完整的自动化能力。没有 MAA，就没有 AutoMAA。
- [maa-cli](https://github.com/MaaAssistantArknights/maa-cli)：提供 macOS 上可靠的命令行工作流、Core/资源管理和 Profile/Task 配置机制。
- [MaaMacGui](https://github.com/MaaAssistantArknights/MaaAssistantArknights/tree/dev-v2/src/MaaMacGui)：AutoMAA 的部分任务参数语义与 macOS 交互设计参考了其开源实现。
- [PlayCover](https://github.com/PlayCover/PlayCover) 与 MaaTools 相关贡献者：为当前 macOS 原生游戏连接方案提供基础能力。

AutoMAA 是独立的社区项目，与 MAA 官方、鹰角网络、Hypergryph、Yostar 或《明日方舟》的运营方均无隶属、合作或背书关系。项目名称中的 “MAA” 用于说明其依赖和服务对象；MAA 的名称、Logo、代码与其他资产仍归各自权利人所有，并遵循 [MAA 的许可证与用户协议](https://github.com/MaaAssistantArknights/MaaAssistantArknights#声明)。

## 许可证与视觉资产

AutoMAA 的源代码与文档使用 [MIT License](./LICENSE) 开源。

MAA、MaaCore 与 `maa-cli` 是独立安装的第三方项目，分别遵循其各自的许可证和用户协议，不因使用 AutoMAA 而改变。

AutoMAA 应用图标不属于 MIT License 的授权范围。图标为面向《明日方舟》角色艾雅法拉的非官方二次创作，设计上向 MAA 社区熟悉的视觉语言致意，但并非 MAA 官方 Logo。角色名称、形象及相关知识产权归其权利人所有；该图标仅用于识别本项目，不得据此主张任何官方关系或授权。
