# 数据与配置

在“全局设置 → 数据与恢复”中点击“打开配置目录”，即可找到 AutoMAA 的本机数据。默认位置：

```text
~/Library/Application Support/AutoMAA
```

## 备份与恢复

1. 暂停相关方案的定时，结束正在运行的流程并退出 AutoMAA。
2. 复制整个数据目录，妥善保存；备份完成后可重新打开 App 并按需恢复定时。
3. 恢复时也先暂停定时、结束运行并退出 App，另行保留现有数据，再将备份放回原位置。
4. 使用兼容版本打开 AutoMAA，检查客户端路径、连接和方案配置。手动验证后再启用定时。

换到另一台 Mac 时，游戏应用、自定义排班文件和 maa-cli 的路径可能不同，不能只复制配置就直接运行。

### 配置版本不兼容时

当前使用 schema v7（自 AutoMAA v0.13.0 起），每周剿灭默认关闭，开始日默认周一。schema v6 及更早版本、缺少必要字段或损坏的配置不自动迁移：图形界面会先创建 `config-schema-v*.backup.json`，再恢复空配置；后台 Runner 只报告错误并退出。升级前请备份配置，并在重新配置后确认账号范围、任务参数和定时。

遇到恢复提示时先保留备份，根据提示重新配置，不要删除唯一副本。备份仍包含账号片段和本机路径，分享前需要脱敏。

## 文件用途

| 文件或目录 | 内容 |
| --- | --- |
| `config.json` | 客户端、账号、方案和全局设置 |
| `execution-state.json` | 各方案当天的成功断点、作战结果与剿灭／常规分阶段进度 |
| `fight-stage-memory.json` | 每个账号记录的常规关卡与恢复状态 |
| `weekly-annihilation.json` | 按客户端、账号、服务器与游戏周保存的剿灭状态；参与方案共享，独立于每日断点 |
| `history.json` | 活动记录，包括运行结果与 MAA 更新详情 |
| `release-notes.json` | 更新说明缓存和阅读状态 |
| `maa-maintenance.json` | 最近一次完整 MAA 更新尝试时间 |
| `Logs/` | 最近 30 次 maa-cli 诊断输出，以及 Runner 与定时运行输出 |
| `Updates/` | 已下载、待安装的 AutoMAA 更新 |
| `update-result.json` | App 读取后即删除的一次性更新结果 |
| `MAA/profiles/`、`MAA/tasks/` | AutoMAA 生成的 MAA 配置与任务文件 |

日常修改优先使用界面。`MAA/` 下的文件会重新生成，不应手工编辑；删除方案或账号时，只清理能够确认由 AutoMAA 生成的文件。

## 检查配置字段

以下用于排查配置或参与开发，完整结构以 [Models.swift](https://github.com/Rememorio/AutoMAA/blob/main/Sources/AutoMAAKit/Models.swift)为准。

| 字段 | 含义 |
| --- | --- |
| `notifications.importantEventsEnabled` | 希望接收重要通知；macOS 是否授权仍由系统单独控制 |
| `applicationUpdates.automaticallyDownloadsUpdates` | 空闲时自动准备 AutoMAA 更新，不代表允许静默重启 |
| `maaUpdates.automaticallyUpdatesCoreAndResources` | 空闲时自动维护 MAA；具体时机见[更新指南](../guide/updates#自动更新-maa) |
| `schedule.rules` | 方案的星期集合、小时和分钟；同一个星期不能出现在多条规则中 |
| `stageStrategy` | `gameCurrentOrLast` 跟随游戏、`rememberedRegular` 剿灭后恢复、`fixed` 固定关卡 |
| `fallbackStage` | 可选常规兜底关卡，留空关闭；仅在确认选关失败且尚未开战时尝试一次，不覆盖恢复记录 |
| `weeklyAnnihilation.enabled` | 开启本方案的每周优先剿灭；独立于 MAA 参数模式，默认关闭 |
| `weeklyAnnihilation.startDay` | 本游戏周开始尝试剿灭的星期，取 `monday` 至 `sunday`，默认 `monday`；未满时后续运行继续补打 |

关卡恢复状态独立于方案保存，行为见[理智作战](../tasks/fight)。方案使用自己的任务参数，账号不保存另一份任务配置。

## 分享配置前

AutoMAA 不保存游戏密码或验证码，但账号匹配片段、显示名称和路径仍可能识别个人。不要直接上传整个目录；问题报告通常只需要相关日志和已脱敏的配置片段，见[安全与隐私](./safety)。
