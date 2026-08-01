# 下载与安装

AutoMAA 当前面向 macOS 14 或更高版本的 Apple Silicon Mac。它不内置 MaaCore、`maa-cli` 或游戏包体。

## 下载正确的文件

前往 [GitHub Releases](https://github.com/Rememorio/AutoMAA/releases/latest)，下载同一版本的两个文件：

```text
AutoMAA-<版本>-macOS-arm64.dmg
AutoMAA-<版本>-macOS-arm64.dmg.sha256
```

只从 `github.com/Rememorio/AutoMAA` 下载公开版本。第三方转载的安装包可能已被修改，本项目无法验证其安全性。

### 可选：校验安装包

假设两个文件都在“下载”文件夹：

```bash
cd ~/Downloads
shasum -a 256 -c AutoMAA-<版本>-macOS-arm64.dmg.sha256
```

看到 `OK` 后再继续。如果校验失败，请删除这两个文件并从 Release 重新下载。

## 安装 App

1. 双击打开 DMG。
2. 将 `AutoMAA.app` 拖入窗口中的“应用程序”文件夹。
3. 在 Finder 打开“应用程序”，找到 AutoMAA。

## 处理“Apple 无法验证”提示

::: warning 为什么会出现这个提示？
当前公开版本使用临时代码签名，尚未使用 Apple Developer ID 签名和公证。macOS 因而无法向 Apple 验证开发者身份，会阻止第一次直接启动。这一提示本身不代表系统已经发现恶意软件，但你仍应确认下载来源和 SHA-256。
:::

优先尝试：

1. 在 Finder 中按住 Control 点击 AutoMAA，选择“打开”。
2. 在确认窗口中再次选择“打开”。

如果窗口只有“完成”按钮，或仍然提示无法验证：

1. 关闭提示窗口。
2. 打开“系统设置 → 隐私与安全性”。
3. 向下找到“已阻止‘AutoMAA.app’以保护 Mac”。
4. 点击右侧的“仍要打开”。
5. 在最后的系统确认窗口中选择“打开”；macOS 可能要求 Touch ID 或登录密码。

这会为当前这份 AutoMAA 建立本机安全例外。以后正常双击即可启动；重新下载的新版本可能需要再次确认。

::: danger 不要全局关闭 Gatekeeper
不要运行 `sudo spctl --master-disable`，也不建议使用递归删除隔离属性的命令。它们会削弱整个系统或一批文件的安全检查。使用 macOS 提供的“仍要打开”，只授权你已经核验的这个 App。
:::

## 更新 AutoMAA

`v0.1.1` 起，AutoMAA 会在启动时检查本项目最新的正式 GitHub Release。也可以选择 App 菜单中的“检查更新…”，或在“全局设置 → AutoMAA 更新”中手动检查。

发现新版本后：

1. 点击“下载并校验”；
2. 等待 DMG 通过附件大小、SHA-256、磁盘映像、Bundle ID、版本、arm64 架构和代码签名校验；
3. 点击“重启并立即更新”；
4. AutoMAA 退出后由独立辅助程序替换 App 并重新打开。

替换或重新启动失败时，更新器会恢复旧版本，并在 AutoMAA 再次打开后显示原因。自动更新要求 `AutoMAA.app` 位于可写磁盘中；如果正在 DMG 内运行或所在目录不可写，请按本页前面的步骤手动安装。

::: info 首次启用应用内更新
`v0.1.0` 尚未包含更新器，因此需要从 Releases 手动安装一次 `v0.1.1`。之后的版本可以使用上述应用内更新流程。
:::

## 安装 MAA 运行环境

AutoMAA 通过 `maa-cli` 调用 MaaCore。使用 Homebrew 安装：

```bash
brew install MaaAssistantArknights/tap/maa-cli
maa install
maa version
```

`maa install` 会安装 MaaCore 和资源。其他安装方式请参考 [maa-cli 官方安装文档](https://docs.maa.plus/zh-cn/manual/cli/install.html)。

接下来前往[首次配置](./getting-started)。
