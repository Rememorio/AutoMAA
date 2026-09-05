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
                maaPanel
                notificationPanel
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
            Button("更新 MAA Beta") {
                model.updateMAACore(channel: .beta)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Beta 是预发布版本，可能包含尚未进入稳定版的修复，也可能出现新问题。本次将更新引擎与识别数据，兼容性校验通过后才启用；自动更新仍使用稳定通道。")
        }
    }

    private var applicationUpdatePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("AutoMAA 更新", systemImage: "arrow.down.app.fill")
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
                case .restoring, .checking:
                    UpdateProgressRow(
                        message: applicationCheckMessage,
                        startedAt: model.applicationUpdateStartedAt,
                        limit: "上限 \(UpdatePolicy.durationDescription(UpdatePolicy.checkTimeout))，含重试",
                        cancel: { model.cancelApplicationUpdate() }
                    )
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
                    UpdateProgressRow(
                        message: "正在下载并校验 AutoMAA v\(release.version)…",
                        startedAt: model.applicationUpdateStartedAt,
                        limit: "上限 \(UpdatePolicy.durationDescription(UpdatePolicy.packageTimeout))，含重试与校验",
                        cancel: { model.cancelApplicationUpdate() }
                    )
                case .cancelling:
                    UpdateProgressRow(
                        message: "",
                        startedAt: model.applicationUpdateStartedAt,
                        limit: "清理完成后即可重新操作",
                        isCancelling: true,
                        cancel: {}
                    )
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

                Text("更新 AutoMAA 的界面与工作流功能，仅从 \(model.applicationUpdateRepository) 的正式 Release 下载。MAA 和游戏包体分别维护。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var applicationCheckMessage: String {
        if case .restoring = model.applicationUpdateState {
            "正在校验已下载的 AutoMAA 更新…"
        } else {
            "正在检查 AutoMAA 新版本…"
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
                Label("MAA 更新", systemImage: "cpu")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("MAA 引擎（MaaCore）执行自动化任务，随版本附带基础识别数据。")
                    Text("识别数据是识别界面、关卡和活动的规则与图片。完整更新会同步配套数据；仅更新识别数据通过热更新获取增量，不更换引擎。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                LabeledContent("maa-cli 路径") {
                    TextField("/opt/homebrew/bin/maa", text: $model.configuration.cliPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 390)
                        .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
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
                    Toggle("空闲时自动更新 MAA", isOn: Binding(
                        get: { model.configuration.maaUpdates.automaticallyUpdatesCoreAndResources },
                        set: { model.setAutomaticMAAUpdatesEnabled($0) }
                    ))
                    .font(.subheadline.weight(.medium))
                    .toggleStyle(.switch)
                    .accessibilityHint("每天最多检查一次稳定通道，定时方案即将运行或其他流程忙碌时会自动推迟")
                    Text("每 24 小时最多尝试一次稳定版，避让运行中的方案和 90 分钟内的定时任务。关闭开关只影响后续自动更新；进行中的更新可随时取消。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("检测环境") { model.refreshMAAStatus(showResult: true) }
                        .disabled(
                            model.isWorkflowRunning
                                || model.applicationUpdateState.blocksWorkflow
                                || model.isCheckingMAAEnvironment
                        )
                    Spacer()
                    Button("仅更新识别数据") { model.hotUpdate() }
                        .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
                    Menu {
                        Button("更新 MAA 稳定版") { model.updateMAACore() }
                        Button("更新 MAA Beta…") {
                            showsBetaUpdateConfirmation = true
                        }
                    } label: {
                        Text("更新 MAA")
                    } primaryAction: {
                        model.updateMAACore()
                    }
                        .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
                }
                if let activity = model.maaUpdateActivity {
                    if activity.isFinished {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(activity.message, systemImage: activity.phase == .failed
                                  ? "exclamationmark.triangle.fill"
                                  : activity.phase == .cancelled ? "stop.circle" : "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(activity.phase == .failed ? Color.orange : .secondary)
                            if let details = activity.details {
                                Text(details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Button("查看活动记录") { model.selection = .activity }
                                .font(.caption)
                        }
                    } else {
                        UpdateProgressRow(
                            message: (activity.automatic ? "自动更新 · " : "") + activity.message,
                            startedAt: activity.startedAt,
                            limit: "上限 \(UpdatePolicy.durationDescription(activity.component.timeout))，含重试与校验",
                            isCancelling: activity.isCancelling,
                            cancel: { model.cancelRun() }
                        )
                    }
                }
                Text("完整更新上限 \(UpdatePolicy.durationDescription(UpdatePolicy.packageTimeout))，仅更新识别数据上限 \(UpdatePolicy.durationDescription(UpdatePolicy.resourceTimeout))；临时网络错误最多重试一次，计入同一上限。下载与校验通过后才启用，失败或取消保留当前安装。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
