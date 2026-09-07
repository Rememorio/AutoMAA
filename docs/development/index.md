# 参与开发

AutoMAA 是 Swift Package Manager 项目，界面使用 SwiftUI，最低支持 macOS 14。构建需要 Apple Silicon Mac 和 Xcode 26（Swift 6.2）或兼容工具链；单元测试不需要安装游戏、PlayCover 或 MAA。

## 从源码运行

```bash
git clone https://github.com/Rememorio/AutoMAA.git
cd AutoMAA
swift test --parallel
./scripts/build-app.sh
open .build/AutoMAA.app --args --data-directory /tmp/automaa-development
```

构建产物位于 `.build/AutoMAA.app`。上面的启动命令使用独立数据目录，同时隔离配置、日志和 LaunchAgent，并关闭系统 LaunchAgent 集成与自动更新检查。界面测试始终使用这一入口，不读取或覆盖日常使用的配置。

## 代码从哪里看

| 目录 | 职责 |
| --- | --- |
| `Sources/AutoMAA/` | SwiftUI 界面、状态与交互；共享视觉组件位于 `Theme.swift` |
| `Sources/AutoMAAKit/` | 配置模型、校验、MAA 文件生成、工作流、存储与系统集成 |
| `Sources/AutoMAARunner/` | 定时任务使用的无界面入口 |
| `Sources/AutoMAAResourceProbe/` | 在独立进程中验证 MaaCore 与识别资源组合 |
| `Sources/AutoMAAUpdater/` | App 替换、失败回滚与重新启动 |
| `Tests/AutoMAAKitTests/` | 核心逻辑与隔离测试 |
| `scripts/` | 构建、打包与验证脚本 |
| `docs/` | 用户指南和文档站 |

修改配置通常从 `Models.swift` 与 `ConfigurationValidation.swift` 开始，任务参数转换位于 `MAAConfigurationWriter.swift`，运行顺序、重试和断点位于 `WorkflowRunner.swift`。可测试逻辑应留在 `AutoMAAKit`，避免在界面层重复实现。

作战结果判定与续跑状态位于 `FightExecution.swift`，关卡记忆位于 `FightStageMemory.swift`。当前实现对照 MaaCore v6.17.2 和 maa-cli v0.7.5：每次作战命令通过 `MAA_STATE_DIR` 使用独立 Core 日志，结算依据 `StageDrops` 回调，`cur_times` 按每次结算累加。maa-cli 摘要的次数在开打时增加，不能单独证明完成；剿灭导航失败也不能证明周奖励已满。

作战类型与显示名称分开保存。`ProcessTask` 开始处理 `EndOfAction` 或 `EndOfActionAnnihilation` 时记录结算类型，再与对应的掉落结果关联；有效周奖励进度也能证明是剿灭，不要求达到上限。Core 先运行掉落插件，再转发 `SubTaskCompleted`，因此不能等待完成事件再判断前面的掉落。未知类型、无效编号和不完整结果不会覆盖常规关卡记忆。上游依据见 [StageDropsTaskPlugin](https://github.com/MaaAssistantArknights/MaaAssistantArknights/blob/v6.17.2/src/MaaCore/Task/Fight/StageDropsTaskPlugin.cpp)、[AbstractTask 回调顺序](https://github.com/MaaAssistantArknights/MaaAssistantArknights/blob/v6.17.2/src/MaaCore/Task/AbstractTask.cpp#L123-L151)、[StageNavigationTask](https://github.com/MaaAssistantArknights/MaaAssistantArknights/blob/v6.17.2/src/MaaCore/Task/Fight/StageNavigationTask.cpp) 和 [maa-cli 作战摘要](https://github.com/MaaAssistantArknights/maa-cli/blob/v0.7.5/crates/maa-cli/src/run/callback/summary.rs)。对应行为使用隔离回调样例与工作流测试覆盖。

## 修改与验证

提交方式、编码要求和测试隔离规范见 [CONTRIBUTING.md](https://github.com/Rememorio/AutoMAA/blob/main/CONTRIBUTING.md)。外部贡献者通过 fork、分支和 Pull Request 合入 `main`。

按改动范围运行相应检查：

| 改动范围 | 验证命令 |
| --- | --- |
| 所有改动 | `git diff --check` |
| Swift 代码 | `swift test --parallel` |
| SwiftUI、应用入口或系统集成 | 另运行 `./scripts/build-app.sh`，使用独立数据目录检查界面 |
| README 或文档 | `npm ci`、`npm run docs:build`、`./scripts/check-public-content.sh` |
| 打包脚本或发行结构 | `./scripts/verify-release.sh` |

账号切换、端口释放、断点、取消和 MAA 参数的修改需要相应回归测试。测试不得连接真实游戏、默认 MaaTools 地址或用户数据；LaunchAgent 测试还需注入临时目录并关闭系统集成。

文档修改见[文档站维护](./docs)。维护者发版流程集中在 [RELEASE.md](https://github.com/Rememorio/AutoMAA/blob/main/RELEASE.md)；编码代理还应遵循 [AGENTS.md](https://github.com/Rememorio/AutoMAA/blob/main/AGENTS.md)。
