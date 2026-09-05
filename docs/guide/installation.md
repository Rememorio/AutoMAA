# 下载与安装

本页帮助你准备运行环境并打开 AutoMAA。完成后，前往[首次配置](./getting-started)跑通第一个方案。

## 系统与运行环境

| 项目 | 要求 |
| --- | --- |
| Mac | Apple Silicon，macOS 14 或更高版本 |
| MAA | 单独安装 `maa-cli`、MaaCore 和识别资源 |
| 游戏连接 | PlayCover + MaaTools，客户端可手动启动并进入游戏 |

AutoMAA 负责客户端管理与任务编排，不包含 MAA 或游戏包体。MAA 支持的其他模拟器与连接方式，目前尚未接入 AutoMAA。

### 安装 MAA

使用 Homebrew：

```bash
brew install MaaAssistantArknights/tap/maa-cli
maa install
maa version
```

`maa install` 安装 MaaCore 和资源；`maa version` 应能显示 maa-cli 与 MaaCore 版本。已有安装时直接检测即可，其他方式见 [maa-cli 安装文档](https://docs.maa.plus/zh-cn/manual/cli/install.html)。

### 准备游戏客户端

按照 [MAA 的 macOS 连接指南](https://docs.maa.plus/zh-cn/manual/device/macos.html)配置支持 MaaTools 的 PlayCover 环境。确认游戏窗口显示连接地址，并完成游戏数据下载、登录和必要确认。

记录每个客户端的游戏 `.app` 与 MaaTools 地址，稍后填入 AutoMAA。不要仅凭安装了 PlayCover 就假定已启用 MaaTools。

## 下载并安装 AutoMAA

1. 前往 [GitHub Releases](https://github.com/Rememorio/AutoMAA/releases/latest)，下载 `AutoMAA-<版本>-macOS-arm64.dmg`。
2. 打开 DMG，将 `AutoMAA.app` 拖入“应用程序”。
3. 从 Finder 的“应用程序”中启动 AutoMAA。

### 校验安装包

如需确认下载完整，同时下载同版本的 `.dmg.sha256` 文件。将两个文件放在同一目录，在终端执行以下命令；把 `<版本>` 替换为下载文件中的实际版本号：

```bash
cd ~/Downloads
shasum -a 256 -c AutoMAA-<版本>-macOS-arm64.dmg.sha256
```

结果应为 `OK`。校验失败时重新从本仓库 Release 下载，不要继续安装该文件。

## 处理“Apple 无法验证”提示

当前公开版本使用临时代码签名，尚未使用 Apple Developer ID 签名和公证，因此首次启动可能被 macOS 拦截。

确认安装包来自本仓库并核验 SHA-256 后：

1. 在 Finder 中按住 Control 点击 AutoMAA，选择“打开”，再在确认窗口中选择“打开”。
2. 若仍被拦截，打开“系统设置 → 隐私与安全性”，找到 AutoMAA 的阻止提示，点击“仍要打开”。
3. 按系统提示确认，可能需要 Touch ID 或登录密码。

这是对当前这份 App 的单独授权。不要全局关闭 Gatekeeper，也不要使用来源不明的命令移除系统保护。关于提示含义与系统流程，可参阅 [Apple 的说明](https://support.apple.com/zh-cn/102445)。

## 确认安装完成

打开 AutoMAA 的“全局设置”，确认 `maa-cli` 路径正确，点击“检测环境”能看到版本信息。然后进入[首次配置](./getting-started)。若检测失败，先查看[常见问题](../troubleshooting/common#找不到-maa-cli)。

后续维护见[更新应用与 MAA](./updates)；不需要为每次更新重新配置账号和方案。
