# 参与贡献

感谢你愿意改进 AutoMAA。这个项目会直接操作游戏客户端和账号，因此我们既重视功能体验，也把“不会跑错账号、不会连接错客户端、可以安全停止”放在首位。

## 在开始之前

- 小型修复、文档和测试改进可以直接提交 Pull Request。
- 新任务类型、配置协议变化、客户端生命周期调整或较大的界面重构，建议先创建 Issue 说明使用场景与方案，避免做出无法合并的实现。
- 安全问题或可能泄露账号信息的问题请不要在公开 Issue 中附带敏感细节；先使用 GitHub 的私密漏洞报告渠道联系维护者。
- 请阅读仓库根目录的 [`AGENTS.md`](./AGENTS.md)，其中记录了架构、安全边界和测试隔离要求。

## 开发环境

需要：

- macOS 14 或更高版本；
- Apple Silicon Mac；
- Xcode 26 或兼容 Swift 6.2 的工具链。

克隆自己的 fork 并验证环境：

```bash
git clone git@github.com:<your-name>/AutoMAA.git
cd AutoMAA
git remote add upstream https://github.com/Rememorio/AutoMAA.git
swift test --parallel
./scripts/build-app.sh
open .build/AutoMAA.app --args --data-directory /tmp/automaa-development
```

大多数代码改动不需要真实游戏、PlayCover 或 MAA。单元测试必须保持完全隔离且可重复运行。

## 分支与提交

外部贡献者不能直接推送本仓库的 `main`。请 fork 仓库，从最新 `main` 创建短期分支：

```bash
git fetch upstream
git switch main
git merge --ff-only upstream/main
git switch -c feat/short-description
```

推荐分支前缀：

- `feat/`：新功能；
- `fix/`：错误修复；
- `docs/`：文档；
- `test/`：测试；
- `refactor/`：不改变行为的重构；
- `build/` 或 `ci/`：构建和持续集成。

Commit 使用 Conventional Commits 风格：

```text
feat: add configurable task ordering
fix: release MaaTools port after cancellation
docs: clarify unnotarized app installation
test: isolate unavailable client workflow
```

要求：

- 一个 commit 只解决一个明确问题；
- 标题简短、使用祈使语气，不写模糊的 `update`、`changes` 或 `fix stuff`；
- 需要解释权衡时在正文说明“为什么”，不重复代码本身；
- 不提交 `.build/`、`dist/`、DMG、用户配置、运行日志、账号片段、手机号、密码或访问令牌；
- 不要在普通功能 PR 中修改版本号、创建 tag 或编辑历史 Release。

仓库维护者可以在紧急修复、文档维护和正式发版时直接推送 `main`；这项权限不改变外部贡献必须通过 PR 的规则。

## 编码要求

- 保持 macOS 14 与 Swift 6.2 兼容。
- UI 使用原生 SwiftUI 组件、动态颜色和 SF Symbols，并兼顾深浅色、VoiceOver 与“减少动态效果”。
- 可测试的配置、MAA 参数生成和工作流逻辑放在 `AutoMAAKit`，不要堆进 SwiftUI 视图。
- 任何外部进程都必须处理超时、取消和非零退出码。
- MAA 参数必须与上游当前集成文档和 MaaCore 接口一致；MaaMacGui 只作为交互与推荐值参考。请在 PR 中注明依据的协议、源码或版本。
- 不生成上游已弃用字段，也不为掩盖协议漂移增加兼容层；协议变化应同步模型、生成器、UI、测试和文档。
- 保持客户端严格串行、端口释放确认、成功后才写断点和取消时完整清理等安全约束。
- 配置协议不兼容变化需要递增 schema，并同步默认值、Codable、任务生成、UI、测试和 README。
- 除非经过讨论并能说明分发与维护成本，不新增第三方依赖。

## 测试与隐私

提交前至少运行：

```bash
swift test --parallel
git diff --check
```

涉及 SwiftUI、应用入口或系统集成时再运行：

```bash
./scripts/build-app.sh
```

涉及打包脚本或 Release 结构时还需运行：

```bash
./scripts/verify-release.sh
```

涉及 README 或 `docs/` 时还需运行：

```bash
npm ci
npm run docs:build
```

测试要求：

- 使用临时 `AppDirectories(root:)`；
- 使用假 Bundle Identifier、测试端口和无副作用的命令；
- 不连接默认 MaaTools 地址或端口，不启动真实游戏，不读取用户的 AutoMAA 数据目录；
- LaunchAgent 测试必须注入临时目录并关闭系统集成；SwiftUI 冒烟测试必须使用 Debug `--data-directory <临时目录>`，或仅在独立 QA Bundle 中注入 `AUTOMAA_DEVELOPMENT_DATA_DIRECTORY`；
- 错误修复应包含能在修复前失败、修复后通过的回归测试；
- UI 改动在 PR 中提供深色和浅色模式截图，涉及状态变化时说明动画和无障碍表现。

如果确实需要真实游戏验证，只能使用你有权操作的账号，并在 PR 中描述测试范围。截图、日志和配置必须移除完整账号、手机号、账号片段、设备路径及其他可识别信息。

## 提交 Pull Request

PR 应合并到 `main`。请保持范围聚焦，并在描述中包含：

1. 改了什么；
2. 为什么需要；
3. 对用户、配置协议和安全边界的影响；
4. 运行过的测试；
5. 尚未验证或需要维护者真机确认的部分；
6. 关联 Issue，以及 UI 改动的前后截图。

PR 标题同样使用 Conventional Commits，例如 `fix: avoid connecting to an occupied MaaTools port`。未完成的工作请先创建 Draft PR；准备好审查后再转为 Ready for review。

维护者通常会重点检查：

- 是否可能操作错误账号或错误客户端；
- 失败、取消和超时后是否完整清理；
- MAA 参数与服务端资源映射是否准确；
- 测试是否真正隔离；
- 是否引入用户专属配置、敏感信息或未授权资产；
- 用户文档和错误提示是否足够明确。

请根据 review 继续向同一分支推送修复，不要为同一个改动重复创建 PR，也不要强推覆盖审查者正在查看的历史，除非维护者明确要求整理 commits。

## 许可证与署名

提交代码即表示你同意该贡献按仓库的 [MIT License](./LICENSE) 发布。第三方代码与视觉资产必须保留原许可证和署名，并确保与本项目分发方式兼容。

AutoMAA 应用图标及角色相关视觉资产不属于 MIT License。请勿在 PR 中加入来源或授权不明的游戏角色图片、Logo、字体、音频或其他素材。
