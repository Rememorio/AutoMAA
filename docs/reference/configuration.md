# 数据与配置

AutoMAA 的用户数据保存在：

```text
~/Library/Application Support/AutoMAA
├── config.json
├── execution-state.json
├── history.json
├── update-result.json       # 仅在更新后短暂存在
├── Logs/
├── Updates/
└── MAA/
    ├── profiles/
    └── tasks/
```

## 文件用途

| 路径 | 用途 |
| --- | --- |
| `config.json` | 客户端、账号、自动化方案和全局设置 |
| `execution-state.json` | 按方案隔离的当天成功任务断点 |
| `history.json` | 图形界面中的结构化活动记录；新记录按每次运行分组 |
| `Logs/` | 最近 30 次 maa-cli 诊断输出，以及 LaunchAgent 与 Runner 输出 |
| `Updates/` | 已下载并通过校验、等待安装的 AutoMAA 更新及准备清单；App 重启后会再次校验 |
| `update-result.json` | 更新辅助程序写入的一次性结果；App 读取提示后删除 |
| `MAA/profiles/` | AutoMAA 生成的独立 MAA Profile |
| `MAA/tasks/` | AutoMAA 按方案、客户端和账号生成的任务文件 |

`config.json` 中的 `notifications.importantEventsEnabled` 记录用户是否希望接收重要通知。它不代表 macOS 已经授权；系统权限仍由“系统设置 → 通知 → AutoMAA”独立控制。

`applicationUpdates.automaticallyDownloadsUpdates` 记录是否在 AutoMAA 打开且空闲时自动下载并准备正式版本。它不允许 App 静默重启，也不会让后台定时 Runner 下载或安装更新。

每个方案的 `schedule.rules` 保存周计划。每条规则包含一组语义化星期值（例如 `monday`、`sunday`）以及 `hour`、`minute`；同一方案不能在同一个星期出现两条规则。LaunchAgent 安装时才会把这些值转换为系统使用的 `Weekday` 数字，配置文件不依赖 Foundation 或 launchd 的星期编号。

## 哪些文件可以编辑

优先在 AutoMAA 界面修改配置。`MAA/` 中的文件会在保存配置时重新生成，不应手工编辑。

删除方案、客户端或账号时，AutoMAA 只会清理由自身生成清单或严格命名规则确认归属的文件，不会清空整个 MAA 目录。

## 备份与恢复

备份前先停止正在运行的工作流，然后复制整个 AutoMAA 数据目录。恢复时确保 App 和配置协议版本兼容。

当前配置协议以 v0.6.0 生成的完整 schema v5 为唯一基线。schema v4 及更早版本、缺少必要字段、仍使用旧版每日时间结构或无法解码的配置都不自动迁移。图形界面会先在同一目录创建 `config-schema-v*.backup.json`，再恢复通用空配置；无界面 Runner 只报告无法处理的配置并退出。备份仍可能含账号片段和本机路径，分享前同样需要脱敏。

## 配置中不包含什么

AutoMAA 不保存：

- 游戏密码；
- 短信或邮箱验证码；
- Apple ID 或其他系统凭据；
- MaaTools 的远程访问凭据。

账号匹配片段仍可能属于隐私信息。分享 `config.json` 前必须删除或替换它们，并检查本机路径和自定义账号名称。
