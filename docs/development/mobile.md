# 移动端开发

`Mobile/` 是独立 Flutter 工程，面向 iOS 和 Android。Mac 仍使用 SwiftUI 和 AutoMAAKit；手机没有游戏自动化引擎，不复制 MAA 参数生成与工作流逻辑。

## 工具与构建

开发基线为 Flutter 3.47.6 / Dart 3.13.5。使用 Xcode 和 iOS Simulator 构建 iOS；Android 需要另行安装 Android SDK、接受其许可并准备模拟器或真机。Xcode 模拟器不能验证 Android。第三方依赖与版本由 `Mobile/pubspec.lock` 固定。

```sh
cd Mobile
flutter pub get
flutter analyze
flutter test test/mobile_client_test.dart
flutter build ios --simulator --debug
flutter build apk --debug
```

iOS 插件通过 Swift Package Manager 集成。真机安装需在 `Mobile/ios/Runner.xcworkspace` 选择开发团队和设备，并配置代码签名；不要把个人团队、证书或 provisioning profile 提交到仓库。Android debug APK 仅用于测试，正式分发需独立配置签名。

`flutter_secure_storage` 将凭据保存在系统安全存储；iOS 使用设备限定且解锁后可读的 Keychain 项，Android 关闭应用备份。`mobile_scanner` 负责原生相机与二维码识别，`uuid` 生成请求标识。它们减少自行实现硬件桥接与安全存储的成本，但升级时必须重测权限、后台生命周期和原生平台构建；不向 Mac 新增第三方运行依赖。

## 分层与协议

移动图标复用现有项目 Logo。在仓库根目录执行 `swift scripts/build-mobile-icons.swift` 可重新生成平台所需尺寸；衍生图标沿用 `Assets/README.md` 的授权边界。

| 位置 | 责任 |
| --- | --- |
| `AutoMAAKit/MobileProtocol.swift` | v1 JSON 请求、白名单响应 DTO、日期编码、凭据摘要与安全地址校验 |
| `AutoMAAKit/MobileAccessStore.swift` | 五分钟单次配对、授权存储、撤销、会话内命令回执 |
| `AutoMAAKit/MobileWebSocketServer.swift` | Network.framework WebSocket；仅 IPv4 loopback，系统协议解析，消息与连接限额 |
| `AutoMAA/MobileAccessController.swift` | Mac 审批、鉴权路由、连接管理与状态推送 |
| `AutoMAA/MobilePresentation.swift` | 复用现有运行校验、脱敏、历史与精确停止接口 |
| `AutoMAA/MobileTailscaleService.swift` | 自有前台 Serve 进程的启动、健康检查及有界清理 |
| `Mobile/lib/mobile_client.dart` | 安全存储、连接、未决操作持久化、回执恢复；允许测试注入 transport/store |

传输地址为 `wss://设备.私人网络.ts.net:43827/mobile`。Tailscale Serve 负责 HTTPS 证书，转发到随机本机端口。应用不关闭证书校验、不支持普通 HTTP 配对、不启用 Funnel。停止或退出只终止自有前台 Serve 进程，不调用全局 `serve reset`。

请求包含 `version: 1`、UUID `id` 和 `operation`。日期使用 ISO 8601。操作包括 `pair`、`authenticate`、`snapshot`、`history`、`historyDetails`、`run`、`stop`、`receipt`。鉴权凭据在消息体中，不进入 URL、日志或普通偏好设置。

`run` 需要 `sessionID`、`planID` 和确认时的 `revision`；revision 包含配置、断点、每周记录、关卡记忆和日期，集合规范化且忽略无语义的执行状态更新时间。`stop` 需要 `sessionID` 和完整 `WorkflowRunIdentity`，只停止目标运行。两者必须先通过设备授权，再由 Mac 执行；手机禁用按钮不是安全边界。

同一服务会话按请求 UUID 和完整载荷去重，并隔离设备。接受和拒绝回执均保留到 App 重启；达到 4096 个后拒绝新操作，不能淘汰旧回执使旧请求重新生效。`receipt` 返回 `type: receipt`、`outcome: accepted/rejected`；查不到或服务会话变化属于结果未知，不表示未执行。手机在发出命令前持久化未决意图，得到明确结果后才清除；重新配对不清除旧未决操作。

授权目录权限为 `0700`，文件为 `0600`，仅保存随机凭据的 SHA-256 摘要。默认初始化不创建授权文件。最多授权 20 台手机、同时接受 12 个连接；未认证连接 30 秒超时，每连接每秒最多 10 个请求。输入最大 16 KiB，输出最大 1 MiB，慢客户端有发送队列上限。正在等待 Mac 审批的连接仅存活至配对过期。

## 隔离验证

```sh
swift test --parallel
./scripts/build-app.sh
cd Mobile
flutter test integration_test/mobile_flow_test.dart -d <模拟器ID>
flutter drive --driver=test_driver/integration_driver.dart --target=integration_test/mobile_ui_test.dart -d <模拟器ID>
```

模拟器集成测试使用临时 loopback 假服务和假任务，不接触真实游戏。测试连接注入只存在于测试构造路径，生产入口没有明文地址或跳过授权的开关。原生 Keychain 测试只写测试应用的假凭据并清除。

跨语言协议测试启动真实 Swift WebSocket 服务并调用 Dart 客户端，控制动作仍为无副作用的假实现。在仓库根目录执行 `AUTOMAA_INTEROP_DART="$(command -v dart)" swift test --filter MobileInteropTests`；未提供 Dart 路径时该项明确跳过。

Mac GUI QA 必须同时使用独立 QA Bundle 的 `LSEnvironment/AUTOMAA_DEVELOPMENT_DATA_DIRECTORY` 和 `--data-directory`。固定 Bundle 隔离可保证 GUI 检查工具无参数重启 App 时仍不读取默认用户目录。不得用这些入口指定默认用户数据目录。

模拟器通过不能代替真机：发布前必须验证摄像头权限、扫码、Tailscale 网络、Wi-Fi/蜂窝切换、锁屏与后台恢复，以及最终签名构建。实际游戏测试需另行授权并确认清理完成。
