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
| `config.json` | 客户端、账号、任务和全局设置 |
| `execution-state.json` | 当天已成功任务的断点 |
| `history.json` | 图形界面最近运行记录 |
| `Logs/` | LaunchAgent 与 Runner 输出 |
| `Updates/` | 已下载并通过校验、等待安装的 AutoMAA 更新；下次准备更新时自动清理旧内容 |
| `update-result.json` | 更新辅助程序写入的一次性结果；App 读取提示后删除 |
| `MAA/profiles/` | AutoMAA 生成的独立 MAA Profile |
| `MAA/tasks/` | AutoMAA 生成的账号任务文件 |

## 哪些文件可以编辑

优先在 AutoMAA 界面修改配置。`MAA/` 中的文件会在保存配置时重新生成，不应手工编辑。

删除客户端或账号时，AutoMAA 只会清理由自身生成清单或严格命名规则确认归属的文件，不会清空整个 MAA 目录。

## 备份与恢复

备份前先停止正在运行的工作流，然后复制整个 AutoMAA 数据目录。恢复时确保 App 和配置协议版本兼容。

当前配置协议是 schema v2。项目处于 `0.x` 阶段，实验版本之间不承诺自动迁移旧配置；不兼容变化会在更新日志中说明。

## 配置中不包含什么

AutoMAA 不保存：

- 游戏密码；
- 短信或邮箱验证码；
- Apple ID 或其他系统凭据；
- MaaTools 的远程访问凭据。

账号匹配片段仍可能属于隐私信息。分享 `config.json` 前必须删除或替换它们，并检查本机路径和自定义账号名称。
