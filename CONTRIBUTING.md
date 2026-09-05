# 参与贡献

欢迎改进 AutoMAA 的功能、文档和测试。项目会直接操作游戏客户端，所有改动都应保证不会跑错账号、不会连接错客户端，并且可以安全停止。

## 报告问题与提出建议

从 [Issue 入口](https://github.com/Rememorio/AutoMAA/issues/new/choose)选择合适的表单：

- Bug：描述复现步骤、预期与实际行为，附上“关于 AutoMAA”的诊断信息和相关日志。
- 使用问题：说明卡在哪一步，以及已尝试的解决方法。
- 功能建议：先说明使用场景和希望解决的问题。新任务类型、配置协议、客户端生命周期或较大的界面调整，建议先讨论方案。

画面识别、关卡导航和游戏内操作属于 MAA / MaaCore，可向上游反馈。安全漏洞请按 [SECURITY.md](./SECURITY.md) 私密报告。公开截图、日志和附件应移除账号片段、手机号、邮箱、凭据和私人路径。

小型修复、文档和测试改进可以直接提交 Pull Request。

## 准备开发

应用开发需要 Apple Silicon Mac、macOS 14 和 Swift 6.2 工具链。源码运行、模块说明和构建命令见[开发指南](https://rememorio.github.io/AutoMAA/development/)；仅修改文档需要 Node.js 22 或更高版本，见[文档站维护](https://rememorio.github.io/AutoMAA/development/docs)。

外部贡献者请 fork 仓库，从最新 `main` 创建分支：

```bash
git clone git@github.com:<your-name>/AutoMAA.git
cd AutoMAA
git remote add upstream https://github.com/Rememorio/AutoMAA.git
git fetch upstream
git switch -c fix/short-description upstream/main
```

大多数代码改动不需要真实游戏、PlayCover 或 MAA。不要把日常使用的账号配置作为测试数据。

## 实现要求

- 保持 macOS 14 与 Swift 6.2 兼容；UI 使用原生 SwiftUI 组件、动态颜色和 SF Symbols，支持深浅色、VoiceOver 与“减少动态效果”。
- 配置、MAA 参数生成和工作流逻辑放在 `AutoMAAKit`；外部进程必须处理超时、取消和非零退出码。
- 保持客户端严格串行、端口释放确认、成功后才写断点和取消时完整清理等[安全边界](https://rememorio.github.io/AutoMAA/reference/safety)。
- MAA 参数以当前上游集成文档和 MaaCore 接口为准，在 PR 中注明依据。MaaMacGui 只作为交互和推荐值参考，不照搬已弃用字段或用兼容层掩盖协议差异。
- 配置字段修改需同步默认值、Codable、生成器、UI、测试和配置文档；不兼容变化递增 schema，并说明用户影响。
- 新增第三方依赖前先讨论收益、维护成本和分发影响。

文档应回答读者的实际问题。README 保留项目介绍、使用条件和上手入口；详细用法集中在对应指南，其他页面链接过去。重要的用户可见变化记录在 `CHANGELOG.md`，不把测试经过或维护讨论写进产品说明。

## 验证改动

| 改动范围 | 提交前检查 |
| --- | --- |
| 所有改动 | `git diff --check` |
| Swift 代码 | `swift test --parallel` |
| SwiftUI、应用入口或系统集成 | 另运行 `./scripts/build-app.sh` |
| README 或文档 | `npm ci`、`npm run docs:build`、`./scripts/check-public-content.sh` |
| 打包脚本或发行结构 | `./scripts/verify-release.sh` |

测试必须保持隔离：

- 存储使用临时 `AppDirectories(root:)`；进程使用假 Bundle Identifier、测试专用端口和无副作用的命令。
- 不连接默认 MaaTools 地址，不启动真实游戏，不读取用户的 AutoMAA 数据目录，也不依赖网络或已登录账号。
- LaunchAgent 测试必须注入临时 `launchAgentsDirectory` 并关闭系统集成。
- SwiftUI 冒烟测试无论 Debug 还是 Release，都使用 `--data-directory <临时目录>`，或仅在独立 QA Bundle 中注入 `AUTOMAA_DEVELOPMENT_DATA_DIRECTORY`。
- 错误修复提供能复现问题的回归测试，尤其是账号切换、端口、断点、取消、任务参数和人工处理分类。
- UI 改动检查深浅色与无障碍；文档页面检查桌面、窄屏、导航和中文搜索。

确需真实游戏验证时，只能使用你有权操作的账号，并在 PR 中说明范围与限制。所有公开记录都应脱敏。编码代理另需遵循 [AGENTS.md](./AGENTS.md)。

## 提交 Pull Request

一个 commit 解决一个明确问题，使用 Conventional Commits：

```text
feat: add configurable task ordering
fix: release MaaTools port after cancellation
docs: clarify first-run setup
```

不要提交构建产物、DMG、用户配置、日志、凭据或未授权资产。普通功能 PR 不修改版本号、不创建 tag，也不编辑历史 Release。

向 `main` 提交 PR，在描述中说明问题、修改后的行为和验证结果；涉及配置或安全边界时写清影响，并列出未验证部分。附上关联 Issue，UI 改动提供前后截图及深浅色效果。PR 标题同样使用 Conventional Commits，尚未完成时使用 Draft PR。

审查期间继续向同一分支推送修复，不重复创建 PR；未经维护者要求，不强推覆盖正在审查的历史。外部贡献通过 PR 合入，维护者可直接维护 `main`；发版步骤见 [RELEASE.md](./RELEASE.md)。

## 许可证与署名

提交代码即表示你同意该贡献按仓库的 [MIT License](./LICENSE) 发布。第三方代码与资产必须保留原许可证和署名，并与本项目分发方式兼容。

AutoMAA 图标及角色相关视觉资产不属于 MIT License，详见 [Assets/README.md](./Assets/README.md)。不要加入来源或授权不明的图片、Logo、字体、音频或其他素材。
