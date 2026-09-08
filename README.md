<div align="center">

<img src="./Assets/AutoMAA-icon.png" width="128" alt="AutoMAA 图标">

# AutoMAA

把多客户端、多账号的 MAA 日常，变成一次运行。

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![GitHub Release](https://img.shields.io/github/v/release/Rememorio/AutoMAA)](https://github.com/Rememorio/AutoMAA/releases/latest)
[![Continuous integration](https://github.com/Rememorio/AutoMAA/actions/workflows/ci.yml/badge.svg)](https://github.com/Rememorio/AutoMAA/actions/workflows/ci.yml)

**[下载](https://github.com/Rememorio/AutoMAA/releases/latest) · [使用文档](https://rememorio.github.io/AutoMAA/) · [问题反馈](https://github.com/Rememorio/AutoMAA/issues/new/choose)**

</div>

AutoMAA 是原生 macOS 的 [MAA](https://github.com/MaaAssistantArknights/MaaAssistantArknights) 工作流编排器。把客户端、账号和任务配置好后，它会依次启动游戏、执行日常、关闭客户端，再处理下一项；画面识别和游戏操作由 `maa-cli` 与 MaaCore 完成。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="./docs/assets/screenshots/overview-dark.webp">
  <img src="./docs/assets/screenshots/overview-light.webp" width="1180" alt="AutoMAA 今日总览：两套日常方案、多个客户端与账号，以及运行前检查">
</picture>

## 能做什么

- **一份账号配置，多套日常方案。** 为同一批账号安排轻量收菜或完整换班，分别选择任务、参数和执行对象。方案可从指定游戏日起优先剿灭，跨方案共享本周完成状态。
- **按结果续跑。** 一键补跑未完成任务，保留已完成步骤；理智不足的剿灭留待后续运行补打，作战中断或战果不明时等待确认。
- **按顺序处理客户端与账号。** 当前客户端关闭、连接释放后，才启动下一个；支持自动切换账号的服务器可配置账号队列。
- **失败后接着跑。** 成功步骤按方案和日期记录，再次运行会跳过已完成内容；活动记录可查看结果与失败原因。
- **手动运行，也能按周定时。** 每个方案独立设置星期和时间；主 App 退出后仍可由后台 Runner 执行，需要处理时可发送系统通知。

支持[理智作战、公开招募、基建、信用购物和奖励领取](https://rememorio.github.io/AutoMAA/tasks/)。任务可使用 MAA 推荐参数，也可在界面中自定义；基建提供仅收菜、完整换班和自定义排班。

当前配置协议为 schema v7；旧配置升级时先备份再恢复空配置，需要重新设置方案与定时，见[配置版本说明](https://rememorio.github.io/AutoMAA/reference/configuration#配置版本不兼容时)。

## 使用前确认

- **Apple Silicon Mac，macOS 14 或更高版本。**
- **已安装 `maa-cli`、MaaCore 和识别资源。** AutoMAA 不内置这些组件。
- **已配置 PlayCover + MaaTools 的游戏客户端。** 这是 AutoMAA 当前支持的连接与客户端管理环境，其他 MAA 连接方式尚未接入。

官服、Bilibili、繁中服和韩服支持多账号切换；韩服需要 MaaCore v6.16.8 或更高版本。国际服、日服使用游戏当前已登录的单个账号。具体配置见[首次配置](https://rememorio.github.io/AutoMAA/guide/getting-started#添加账号)。

AutoMAA 仍处于 `0.x` 阶段，首次运行请有人值守。它不保存游戏密码，也不处理验证码、协议确认或游戏包体更新；遇到需要人工处理的情况会停止或跳过对应客户端。定时运行需要用户保持登录、Mac 唤醒，详见[定时条件](https://rememorio.github.io/AutoMAA/guide/scheduling)。

## 开始使用

1. 按[安装指南](https://rememorio.github.io/AutoMAA/guide/installation)准备 MAA 与游戏连接环境，从 [Releases](https://github.com/Rememorio/AutoMAA/releases/latest) 下载 DMG，将 AutoMAA 拖入“应用程序”。
2. 在“全局设置”检测 MAA 环境，添加客户端与账号。
3. 选择“轻量日常”或“完整日常”模板，确认执行对象、任务和参数。回到总览处理运行检查，再手动跑通一次。
4. 在“活动记录”确认结果，稳定后按需启用方案定时。

当前安装包使用临时代码签名，尚未经过 Apple 公证。如首次打开被拦截，确认下载来源和校验值后，在 Finder 中右键选择“打开”；仍被拦截时使用“系统设置 → 隐私与安全性 → 仍要打开”。[详细步骤与校验方法](https://rememorio.github.io/AutoMAA/guide/installation#处理-apple-无法验证-提示)。

## 按需查阅

| 你想做什么 | 文档 |
| --- | --- |
| 配好第一个客户端和方案 | [首次配置](https://rememorio.github.io/AutoMAA/guide/getting-started) |
| 调整任务、安排定时、理解续跑 | [任务配置](https://rememorio.github.io/AutoMAA/tasks/) · [每周定时](https://rememorio.github.io/AutoMAA/guide/scheduling) · [执行流程](https://rememorio.github.io/AutoMAA/guide/workflow) |
| 处理连接、账号或更新问题 | [常见问题](https://rememorio.github.io/AutoMAA/troubleshooting/common) |
| 备份配置或了解数据使用 | [数据与配置](https://rememorio.github.io/AutoMAA/reference/configuration) · [安全与隐私](https://rememorio.github.io/AutoMAA/reference/safety) |

## 参与贡献

欢迎报告问题、改进文档和提交代码。Bug 报告请附复现步骤、“关于 AutoMAA”中的诊断信息，以及已脱敏的相关日志；安全漏洞请使用[私密报告](./SECURITY.md)。

从源码构建见[开发指南](https://rememorio.github.io/AutoMAA/development/)，提交 Pull Request 前请阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。版本变化记录在 [CHANGELOG.md](./CHANGELOG.md)。

## 致谢与许可证

- [MAA / MaaCore](https://github.com/MaaAssistantArknights/MaaAssistantArknights)：任务协议、识别资源与游戏自动化能力。
- [maa-cli](https://github.com/MaaAssistantArknights/maa-cli)：命令行入口、Core 与资源管理。
- [MaaMacGui](https://github.com/MaaAssistantArknights/MaaMacGui)：macOS 交互设计与部分推荐值的参考。
- [PlayCover](https://github.com/PlayCover/PlayCover) 与 MaaTools 贡献者：当前游戏连接环境的基础。

AutoMAA 是独立社区项目，与 MAA 官方、鹰角网络、Hypergryph、Yostar 或《明日方舟》运营方均无隶属、合作或背书关系。上述第三方项目各自的许可证和用户协议仍然适用。

源代码与文档采用 [MIT License](./LICENSE)。**应用图标与宣传视觉资产不属于 MIT 授权范围**：图标为艾雅法拉的非官方二次创作，并非 MAA 官方 Logo；角色名称、形象及相关知识产权归原权利人所有。视觉资产仅用于识别和介绍本项目，完整说明见 [Assets/README.md](./Assets/README.md)。
