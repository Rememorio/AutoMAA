# AutoMAA 发版指南

本文档面向仓库维护者，定义从 `main` 发布 AutoMAA 的标准流程。外部贡献者不应创建版本 tag 或 Release。

## 版本策略

AutoMAA 使用[语义化版本](https://semver.org/lang/zh-CN/)：

- `PATCH`：向后兼容的错误修复和小型文档修正；
- `MINOR`：向后兼容的新功能；在 `0.x` 阶段，不兼容的配置或行为调整也递增 `MINOR`，并在更新日志中醒目标注；
- `MAJOR`：稳定协议后的不兼容变化。

Git tag 使用 `vX.Y.Z`，App 版本使用 `X.Y.Z`。公开发布后不得移动或覆盖 tag；发现问题时发布新的补丁版本。

## 1. 确认发布范围

开始前确认：

- 所有计划合入的 PR 已完成 review 并进入 `main`；
- 本地 `main` 与 `origin/main` 一致，工作区干净；
- 没有未公开的账号、手机号、账号片段、本机路径、日志或凭据；
- 已对照当前 MAA 集成文档、MaaCore 参数接口和稳定版更新日志审计参数；
- 任务生成逻辑不存在 `expiring_medicine`、`skip_robot` 等已弃用字段；测试可以保留显式“不生成”断言；
- Release 不包含 MaaCore、`maa-cli`、游戏包体或用户配置。

```bash
git switch main
git fetch origin --tags
git merge --ff-only origin/main
git status --short --branch
```

检查 GitHub 上不存在目标 tag 或 Release：

```bash
git ls-remote origin "refs/tags/vX.Y.Z"
gh release view "vX.Y.Z"
```

## 2. 更新版本与文档

在 `scripts/Info.plist` 中更新：

- `CFBundleShortVersionString` 为 `X.Y.Z`；
- `CFBundleVersion` 由构建脚本生成，不需要手动修改。

在 `CHANGELOG.md` 顶部增加本次版本、发布日期和用户可见变化。优先使用以下分类：

- 新功能；
- 修复；
- 可靠性；
- 分发；
- 已知限制或不兼容变化。

同步检查 `README.md` 的系统要求、安装方式、支持功能、已知限制和截图。版本提交使用：

```bash
git add scripts/Info.plist CHANGELOG.md README.md <其他发布改动>
git diff --cached --check
git commit -m "release: vX.Y.Z"
```

如果用户行为、安装说明或兼容性发生变化，同步更新 `docs/` 并执行：

```bash
npm ci
npm run docs:build
```

## 3. 完整发布验证

`verify-release.sh` 是正式发版的唯一完整验收入口。它只使用临时目录和伪对象，不连接真实游戏：

```bash
./scripts/verify-release.sh
```

脚本会依次验证 Swift 测试、Release App 构建、更新器替换、文档站、DMG、SHA-256、只读挂载结构、版本、Bundle ID、arm64 架构和代码签名。还需人工确认：

- 测试使用临时目录、假 Bundle Identifier 和测试专用高位端口；
- 不存在连接默认 MaaTools 地址、调用系统 LaunchAgent 或启动真实游戏的测试；
- 配置 Codable 往返、MAA 参数生成、服务端映射、端口安全、断点、取消和人工处理分类均有覆盖；
- App 版本、图标、Bundle Identifier 和最低系统版本正确。

## 4. 隔离界面验收

使用 Debug App、独立 QA Bundle Identifier 和 `--data-directory <临时目录>` 验收界面。不得指向用户默认数据目录，也不得选择或启动真实游戏 App。至少覆盖：

1. 全新空配置、首次引导、配置恢复提示和关于页；
2. 客户端、任意数量账号、方案增删改排、账号范围和开关反复切换；
3. 关闭任务后仍能重新开启，关闭自定义参数后仅使用 MAA 推荐参数；
4. `Infrast` 三种模式、自定义排班文件选择与缺失文件阻断；
5. 运行检查、禁用按钮、维护状态、安全停止和错误提示文案；
6. 定时开关只在临时 LaunchAgents 目录生成 plist，不调用系统 `launchctl`；
7. 深浅色、较窄窗口、键盘导航、VoiceOver 标签和“减少动态效果”；
8. 文档截图使用通用假数据，不含维护者路径或账号信息。

真实游戏验证不是自动化 Release 门禁。只有维护者主动授权时才能在自有账号上执行，并且必须在 Release Notes 中精确记录范围；未执行时明确写“未进行真实游戏测试”，不能把生成配置或隔离 UI 验收描述成真机通过。

隔离验收结束后退出 QA App、删除临时数据，并确认没有游戏客户端被测试过程启动。

## 5. 构建 DMG

当前公开包为 Apple Silicon、临时代码签名且未公证。完整验证已生成产物时不应再次打包；仅在定位打包问题时单独运行：

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist
./scripts/package-dmg.sh
```

脚本会生成：

```text
dist/AutoMAA-X.Y.Z-macOS-arm64.dmg
dist/AutoMAA-X.Y.Z-macOS-arm64.dmg.sha256
```

打包脚本从 `CFBundleShortVersionString` 读取版本；如果手动传入版本参数，它也必须与 App 版本一致。构建后执行：

```bash
hdiutil verify "dist/AutoMAA-X.Y.Z-macOS-arm64.dmg"
(cd dist && shasum -a 256 -c "AutoMAA-X.Y.Z-macOS-arm64.dmg.sha256")
```

只读挂载镜像并确认：

- 根目录包含 `AutoMAA.app`；
- `Applications` 是指向 `/Applications` 的符号链接；
- `codesign --verify --deep --strict` 通过；
- App 和 `AutoMAARunner` 都是 arm64；
- App 内包含可执行的 `AutoMAAUpdater`，并已通过隔离临时目录中的替换冒烟测试；
- Info.plist 版本正确；
- 从 DMG 中能够实际启动 App，退出后能够正常卸载镜像。

由于当前没有 Developer ID 与公证，`spctl --assess` 预期会拒绝。README 和 Release Notes 必须明确说明 Finder 右键“打开”以及“系统设置 → 隐私与安全性 → 仍要打开”的正常流程，不提供绕过 Gatekeeper 的破坏性命令。

获得 Developer ID 后，应在本节补充 hardened runtime、Developer ID Application 签名、notarytool 提交、staple 和 `spctl` 接受验证，并删除临时签名说明。

## 6. 推送发布提交

再次确认差异和测试结果，然后推送维护者的 `main`：

```bash
git status --short --branch
git log -1 --oneline
git push origin main
```

确认远端 `main` 指向发布提交：

```bash
git ls-remote origin refs/heads/main
```

## 7. 创建 GitHub Release

从 `CHANGELOG.md` 复制当前版本章节到一个临时 Release Notes 文件，内容应包含用户影响、已知限制、签名状态和安装提示。不要把整个历史更新日志重复粘贴到每个 Release。

```bash
gh release create "vX.Y.Z" \
  "dist/AutoMAA-X.Y.Z-macOS-arm64.dmg" \
  "dist/AutoMAA-X.Y.Z-macOS-arm64.dmg.sha256" \
  --repo Rememorio/AutoMAA \
  --target main \
  --title "AutoMAA vX.Y.Z" \
  --notes-file /tmp/automaa-release-notes.md \
  --latest
```

`--target` 使用远端分支名或完整 commit SHA；不要使用缩写 SHA。

发布后验证：

```bash
gh release view "vX.Y.Z" --repo Rememorio/AutoMAA
git ls-remote origin "refs/tags/vX.Y.Z"
```

重新下载两个附件，在独立临时目录中执行 `.sha256` 校验，并与本地已验证的 DMG 做字节比较。最后从未登录状态打开 Release 页面，确认 README 徽章、下载链接、说明和附件均可访问。

应用内更新依赖 Release 附件的固定命名和公开元数据。发布后还要确认 `releases/latest` 指向本次版本，DMG 与 `.sha256` 的名称、大小和下载地址均正确；不要静默替换已经公开的附件。

## 8. 发布后处理

- 在支持的 macOS 版本上从 Release 下载并安装一次；
- 观察 Issue 和崩溃反馈，确认没有普遍的启动、配置或连接回归；
- 将下一版本的计划改动记录到 `CHANGELOG.md` 的未发布部分或 Issue；
- 如发现严重问题，立即在 Release 描述中标注，不移动既有 tag，也不静默替换附件；修复后发布新的补丁版本；
- 只有确认附件不可用且 Release 尚未被公开消费时，才能删除失败的草稿并重新创建。已公开版本按不可变发布物处理。

## 发布检查表

- [ ] `main` 与远端同步，工作区干净
- [ ] 版本号和 `CHANGELOG.md` 已更新
- [ ] README 与实际能力、限制和签名状态一致
- [ ] 文档站构建通过，安装与常见问题页面已同步
- [ ] 仓库不含用户配置、敏感信息或构建产物
- [ ] `./scripts/verify-release.sh` 完整通过
- [ ] 更新器替换冒烟测试通过
- [ ] Release App 构建和代码签名校验通过
- [ ] 隔离界面验收范围与未验证项已记录
- [ ] DMG、挂载结构和 SHA-256 校验通过
- [ ] 发布提交已推送到 `main`
- [ ] tag 指向正确提交
- [ ] Release 附件上传完成并重新下载验证
- [ ] Release 页面、下载链接和安装说明可公开访问
- [ ] GitHub Pages 部署成功且线上关键页面可访问
