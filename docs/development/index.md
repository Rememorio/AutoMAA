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

作战结果判定与续跑状态位于 `FightExecution.swift`，关卡记忆位于 `FightStageMemory.swift`。当前实现对照 MaaCore v6.17.2 和 maa-cli v0.7.5：每次作战命令通过 `MAA_STATE_DIR` 使用独立 Core 日志，结算依据 `StageDrops` 回调，`cur_times` 按每次结算累加；缺少该值时使用由 `FightTimes.series` 绑定到对应开战与结算的批次倍率，两者均未知时显示次数下限。`SanityBeforeStage` 与紧随其后的消耗、倍率共同判断单局理智不足，不以整批连战消耗代替单局消耗。maa-cli 摘要的次数在开打时增加，不能单独证明完成；剿灭导航失败也不能证明周奖励已满。

作战类型与显示名称分开保存。`ProcessTask` 开始处理 `EndOfAction` 或 `EndOfActionAnnihilation` 时记录结算类型，再与对应的掉落结果关联；有效周奖励进度也能证明是剿灭，不要求达到上限。Core 先运行掉落插件，再转发 `SubTaskCompleted`，因此不能等待完成事件再判断前面的掉落。未知类型、无效编号和不完整结果不会覆盖常规关卡记忆。上游依据见 [StageDropsTaskPlugin](https://github.com/MaaAssistantArknights/MaaAssistantArknights/blob/v6.17.2/src/MaaCore/Task/Fight/StageDropsTaskPlugin.cpp)、[AbstractTask 回调顺序](https://github.com/MaaAssistantArknights/MaaAssistantArknights/blob/v6.17.2/src/MaaCore/Task/AbstractTask.cpp#L123-L151)、[StageNavigationTask](https://github.com/MaaAssistantArknights/MaaAssistantArknights/blob/v6.17.2/src/MaaCore/Task/Fight/StageNavigationTask.cpp) 和 [maa-cli 作战摘要](https://github.com/MaaAssistantArknights/maa-cli/blob/v0.7.5/crates/maa-cli/src/run/callback/summary.rs)。对应行为使用隔离回调样例与工作流测试覆盖。

常规兜底只接受作战前的 `StageNavigationTask` 失败，或已点击上次作战入口后的导航失败；进入 `FightBegin`、发现战斗画面、超时或掉线都会阻止自动换关。选关与各次尝试在 `WorkflowRunner` 中串行执行，已选兜底在派发前持久化。兜底结果与原目标分开保存，不能更新恢复记录；所有服务器共享这套判断。

每周剿灭策略与状态位于 `WeeklyAnnihilation.swift`。策略属于方案，周状态按客户端、账号与服务器区分；只以明确周奖励上限或手动确认为本周完成，单次成功与理智不足均不能替代。游戏周使用 [maa-cli v0.7.5 的服务器时间偏移](https://github.com/MaaAssistantArknights/maa-cli/blob/v0.7.5/crates/maa-cli/src/config/task/client_type.rs)：官服、Bilibili、繁中服为 UTC+4，日服、韩服为 UTC+5，国际服为 UTC−11；这些偏移已包含游戏日 04:00 的边界，不是当地民用时区。每周从游戏日周一开始；派发时固定周标识，跨周结果不会误记为新周完成。未确认结果跨周仍阻止自动补打。

`ExecutionState.prepareWeeklyAnnihilation` 统一供 Runner 与界面续跑状态使用，恢复剿灭可执行性时保留每日常规阶段与其他步骤。派发前分别原子保存每日目标和共享周状态；任何写入失败均停止派发，未完成的保存不能伪装成成功。`PlanContinuation.fightRecoveryItems` 提供独立于历史日志的当前处理项，方案页和活动记录共用 `FightRecoveryActions`。`WeeklyAnnihilationStore.confirmComplete` 在进程锁内重新读取并校验当前游戏周记录，仅更新周状态，不启动工作流。入口不可用只有在完整任务回调证明尚未进入作战时才可安全跳过，证据不足仍保留待确认。

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
