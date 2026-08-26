import AppKit
import AutoMAAKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsBetaUpdateConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                applicationUpdatePanel
                notificationPanel
                maaPanel
                storagePanel
            }
            .padding(28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("全局设置")
        .confirmationDialog(
            "更新到 MAA Beta？",
            isPresented: $showsBetaUpdateConfirmation,
            titleVisibility: .visible
        ) {
            Button("更新 Beta 核心与基础资源") {
                model.updateMAACore(channel: .beta)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Beta 可适配最新热更新资源，但属于上游预发布版本。AutoMAA 不会自动切换；确认后仅执行这一次 Beta 更新。")
        }
    }

    private var applicationUpdatePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("软件更新", systemImage: "arrow.down.app.fill")
                        .font(.headline)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Toggle("自动下载并准备更新", isOn: Binding(
                        get: { model.configuration.applicationUpdates.automaticallyDownloadsUpdates },
                        set: { model.setAutomaticApplicationUpdatesEnabled($0) }
                    ))
                    .font(.subheadline.weight(.medium))
                    .toggleStyle(.switch)
                    .accessibilityHint("发现正式版本后，在 AutoMAA 空闲时下载并完成安全校验；安装前仍需确认重启")
                    Text("发现正式版本后，仅在 AutoMAA 空闲时下载并完成安全校验；安装前仍需确认重启。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch model.applicationUpdateState {
                case .idle:
                    updateRow(
                        message: "当前使用 v\(model.currentApplicationVersion)，启动时会自动检查正式版本。",
                        buttonTitle: "检查更新",
                        action: { model.checkForApplicationUpdate() }
                    )
                case .checking:
                    progressRow("正在为 v\(model.currentApplicationVersion) 检查更新…")
                case .upToDate:
                    updateRow(
                        message: "v\(model.currentApplicationVersion) 已是最新版本。",
                        symbol: "checkmark.circle.fill",
                        color: .green,
                        buttonTitle: "再次检查",
                        action: { model.checkForApplicationUpdate() }
                    )
                case let .available(release):
                    VStack(alignment: .leading, spacing: 10) {
                        Label(
                            "v\(release.version.description) 可用（当前 v\(model.currentApplicationVersion)）",
                            systemImage: "sparkles"
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.maaAccent)
                        if !release.releaseNotes.isEmpty {
                            Text(releaseSummary(release.releaseNotes))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        HStack {
                            Link("查看发布说明", destination: release.pageURL)
                            Spacer()
                            Button("下载并校验") { model.downloadApplicationUpdate(release) }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isWorkflowRunning)
                        }
                    }
                case let .downloading(release):
                    HStack(spacing: 10) {
                        progressRow("正在下载并校验 v\(release.version)…")
                        Spacer()
                        Button("停止下载") { model.cancelApplicationUpdateDownload() }
                    }
                case let .ready(prepared):
                    VStack(alignment: .leading, spacing: 10) {
                        Label("v\(prepared.release.version.description) 已准备好", systemImage: "checkmark.shield.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.green)
                        Text("更新包已通过 SHA-256、Bundle ID、架构和代码签名校验。重启后会替换当前 App；失败时自动恢复旧版本。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Link("查看发布说明", destination: prepared.release.pageURL)
                            Spacer()
                            Button("重启并立即更新") { model.restartAndInstallApplicationUpdate(prepared) }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.isWorkflowRunning)
                        }
                    }
                case let .installing(release):
                    progressRow("正在退出并安装 v\(release.version)…")
                case let .failed(message):
                    VStack(alignment: .leading, spacing: 10) {
                        Label("更新未完成", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack {
                            Spacer()
                            Button("重新检查") { model.checkForApplicationUpdate() }
                        }
                    }
                }

                Text("仅从 \(model.applicationUpdateRepository) 的正式 Release 下载，不会更新游戏包体或 MAA 资源。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func updateRow(
        message: String,
        symbol: String? = nil,
        color: Color = .secondary,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(color)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(buttonTitle, action: action)
        }
    }

    private func progressRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func releaseSummary(_ notes: String) -> String {
        let lines = notes
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("本项目遵循") }
        return lines.prefix(3).joined(separator: " ")
    }

    private var notificationPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("重要通知", systemImage: "bell.badge.fill")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.configuration.notifications.importantEventsEnabled },
                        set: { model.setImportantNotificationsEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(model.isRequestingNotificationAuthorization)
                    .accessibilityLabel("启用重要通知")
                }

                Text("仅通知需要确认的公招稀有或保留标签、人工处理、流程中止与步骤失败；普通完成不会打扰你。通知只显示概括，账号名称、识别标签和错误详情仍留在活动记录中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                notificationAuthorizationRow
            }
        }
    }

    @ViewBuilder
    private var notificationAuthorizationRow: some View {
        if model.isRequestingNotificationAuthorization {
            progressRow("正在等待 macOS 通知权限…")
        } else if !model.configuration.notifications.importantEventsEnabled {
            Label("未开启", systemImage: "bell.slash")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 10) {
                switch model.notificationAuthorizationState {
                case .authorized:
                    Label("macOS 已允许横幅与声音", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button(model.isTestingImportantNotification ? "正在测试…" : "测试后台通知") {
                        model.testImportantNotification()
                    }
                    .disabled(model.isTestingImportantNotification)
                case .provisional:
                    Label("macOS 当前以静默方式投递", systemImage: "bell.and.waves.left.and.right")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.isTestingImportantNotification ? "正在测试…" : "测试后台通知") {
                        model.testImportantNotification()
                    }
                    .disabled(model.isTestingImportantNotification)
                case .notDetermined:
                    Label("尚未授予 macOS 通知权限", systemImage: "questionmark.circle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("继续授权") { model.requestNotificationAuthorization() }
                case .denied:
                    Label("macOS 已关闭 AutoMAA 通知", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("打开通知设置") { openNotificationSettings() }
                }
            }
            .font(.caption)
        }
    }

    private func openNotificationSettings() {
        var components = URLComponents(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            components?.queryItems = [URLQueryItem(name: "id", value: bundleIdentifier)]
        }
        if let url = components?.url, NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(filePath: "/System/Applications/System Settings.app", directoryHint: .isDirectory))
    }

    private var maaPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Label("MAA", systemImage: "terminal.fill")
                    .font(.headline)
                LabeledContent("maa-cli 路径") {
                    TextField("/opt/homebrew/bin/maa", text: $model.configuration.cliPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 390)
                }
                LabeledContent("环境版本") {
                    if model.isCheckingMAAEnvironment {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(model.maaVersionSummary)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("空闲时自动更新 MAA 核心与基础资源", isOn: Binding(
                        get: { model.configuration.maaUpdates.automaticallyUpdatesCoreAndResources },
                        set: { model.setAutomaticMAAUpdatesEnabled($0) }
                    ))
                    .font(.subheadline.weight(.medium))
                    .toggleStyle(.switch)
                    .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
                    .accessibilityHint("每天最多检查一次稳定通道，定时方案即将运行或其他流程忙碌时会自动推迟")
                    Text("AutoMAA 打开时每天最多检查一次稳定通道；仅在没有流程运行且近期没有定时任务时更新。临时网络错误会自动重试一次；最终失败会写入活动记录，可稍后手动重试。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("自动维护只使用稳定通道；Beta 仅在你手动确认时更新。热更新后若资源需要更新 Core，AutoMAA 会在启动游戏前停止并说明。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("检测环境") { model.refreshMAAStatus(showResult: true) }
                        .disabled(
                            model.isWorkflowRunning
                                || model.applicationUpdateState.blocksWorkflow
                                || model.isCheckingMAAEnvironment
                        )
                    Menu {
                        Button("更新稳定版核心与基础资源") { model.updateMAACore() }
                        Button("更新 Beta 核心与基础资源…") {
                            showsBetaUpdateConfirmation = true
                        }
                    } label: {
                        Text("更新核心与基础资源")
                    }
                        .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
                    Button {
                        model.hotUpdate()
                    } label: {
                        Label("热更新识别资源", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
                }
            }
        }
    }

    private var storagePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Label("数据与恢复", systemImage: "externaldrive.fill")
                    .font(.headline)
                LabeledContent("配置目录") {
                    Text(model.directories.root.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
                HStack {
                    Button("打开配置目录") { NSWorkspace.shared.open(model.directories.root) }
                    Button("重置今日完成记录") { model.resetToday() }
                        .disabled(model.isWorkflowRunning)
                    Spacer()
                    Button("立即保存") { model.saveNow() }
                }
            }
        }
    }
}
