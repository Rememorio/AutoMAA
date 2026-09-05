import AppKit
import AutoMAAKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsBetaUpdateConfirmation = false
    @State private var showsResetConfirmation = false

    var body: some View {
        AppPage(width: PageLayout.readingWidth) {
            applicationUpdatePanel
            maaPanel
            notificationPanel
            storagePanel
        }
        .navigationTitle("全局设置")
        .confirmationDialog("重置今日完成记录？", isPresented: $showsResetConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重置完成记录", role: .destructive) { model.resetToday() }
        } message: {
            Text("所有方案今天的成功步骤会被清空；再次运行时，这些步骤会重新执行。配置和活动记录会保留。")
        }
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
                SectionHeading(title: "AutoMAA 更新", symbol: "arrow.down.app.fill", detail: "更新界面与工作流功能。")

                SettingsToggleRow(
                    title: "自动下载并准备更新",
                    detail: "空闲时下载正式版并完成校验，安装前仍需确认重启。",
                    isOn: Binding(
                        get: { model.configuration.applicationUpdates.automaticallyDownloadsUpdates },
                        set: { model.setAutomaticApplicationUpdatesEnabled($0) }
                    )
                )
                Divider()

                applicationUpdateInformation

                switch model.applicationUpdateState {
                case .idle:
                    updateRow(
                        message: "启动时会自动检查正式版本。",
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
                        message: "已是最新版本。",
                        symbol: "checkmark.circle.fill",
                        color: .green,
                        buttonTitle: "再次检查",
                        action: { model.checkForApplicationUpdate() }
                    )
                case let .available(release):
                    HStack {
                        Text("新版本可下载").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("下载并校验") { model.downloadApplicationUpdate(release) }
                            .buttonStyle(.borderedProminent)
                            .tint(.maaAction)
                            .disabled(model.isWorkflowRunning)
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
                        Text("更新包已通过校验，重启后生效；安装失败时自动恢复旧版本。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            DetailDisclosure(details: "更新包已通过 SHA-256、Bundle ID、版本、架构和代码签名校验。")
                            Spacer()
                            Button("重启并立即更新") { model.restartAndInstallApplicationUpdate(prepared) }
                                .buttonStyle(.borderedProminent)
                                .tint(.maaAction)
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
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button("重新检查") { model.checkForApplicationUpdate() }
                        }
                    }
                }

                Text("仅从 \(model.applicationUpdateRepository) 的正式 Release 下载。MAA 与游戏包体分别维护。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var applicationUpdateInformation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let release = model.applicationUpdateRelease {
                    Text("当前 v\(model.currentApplicationVersion) → v\(release.version.description)")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("当前版本 v\(model.currentApplicationVersion)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Button(model.applicationUpdateRelease == nil ? "本版本更新内容" : "更新内容") {
                    model.showApplicationNotes()
                }
            }
            if let release = model.applicationUpdateRelease {
                HStack(spacing: 10) {
                    if let date = release.publishedAt {
                        Text(date, format: .dateTime.year().month().day())
                    }
                    Text(ByteCountFormatter.string(fromByteCount: Int64(release.diskImage.size), countStyle: .file))
                }.font(.caption).foregroundStyle(.secondary)
                if release.notes.highlights.isEmpty {
                    Text(release.releaseNotes.isEmpty ? "此版本尚未提供详细更新说明。" : "打开“更新内容”查看此版本的完整说明。")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(release.notes.highlights.enumerated()), id: \.offset) { _, text in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•").accessibilityHidden(true)
                            Text(.init(text))
                        }.font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if model.releaseNotesState.unreadVersion == model.currentApplicationVersion {
                HStack {
                    Label("已更新到 v\(model.currentApplicationVersion)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("查看本次变化") { model.showApplicationNotes(currentVersion: true) }
                }.font(.callout)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            ReleaseNotes.safePageURL(url) == nil ? .discarded : .systemAction
        })
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

    private var notificationPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "重要通知", symbol: "bell.badge.fill")
                SettingsToggleRow(
                    title: "启用重要通知",
                    detail: "提醒公招确认、人工处理、流程中止与步骤失败。普通完成不会打扰你，通知不展示账号或识别标签。",
                    isOn: Binding(
                        get: { model.configuration.notifications.importantEventsEnabled },
                        set: { model.setImportantNotificationsEnabled($0) }
                    )
                )
                .disabled(model.isRequestingNotificationAuthorization)
                Divider()

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
                SectionHeading(title: "MAA 更新", symbol: "cpu", detail: "MAA 引擎（MaaCore）执行任务，识别数据提供界面、关卡和活动的规则与图片。")
                LabeledContent("maa-cli 路径") {
                    TextField("/opt/homebrew/bin/maa", text: $model.configuration.cliPath)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 200, maxWidth: 480)
                        .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
                }
                LabeledContent("环境版本") {
                    if model.isCheckingMAAEnvironment {
                        ProgressView()
                            .controlSize(.small)
                            .frame(height: 28)
                            .accessibilityLabel("正在检测 MAA 环境")
                    } else {
                        Text(model.maaVersionSummary)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                            .frame(minHeight: 28)
                    }
                }
                HStack {
                    Button("查看 MAA 稳定版发布说明") { model.updateDetailsRequest = .maaLatest(.stable) }
                    Spacer()
                    if let information = model.latestMAAUpdateInformation {
                        Button(model.maaUpdateActivity == nil ? "最近更新详情" : "本次更新详情") {
                            model.updateDetailsRequest = .maa(information)
                        }
                    }
                }.font(.callout)
                Divider()
                SettingsToggleRow(
                    title: "空闲时自动更新 MAA",
                    detail: "每 24 小时最多尝试一次稳定版，避让运行中的方案和 90 分钟内的定时任务。关闭开关只影响后续更新，当前更新可单独取消。",
                    isOn: Binding(
                        get: { model.configuration.maaUpdates.automaticallyUpdatesCoreAndResources },
                        set: { model.setAutomaticMAAUpdatesEnabled($0) }
                    )
                )
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
                        Divider()
                        Button("查看 Beta 发布说明") { model.updateDetailsRequest = .maaLatest(.beta) }
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
                            if let details = activity.details, !details.isEmpty {
                                DetailDisclosure(details: details)
                                    .id(details)
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
                if let information = model.latestMAAUpdateInformation, let after = information.after {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("最近启用 · \(information.date.formatted(date: .abbreviated, time: .shortened))")
                        if let old = information.before.core, let current = after.core {
                            Text(old == current ? "MAA 引擎 v\(current) · 版本未变" : "MAA 引擎 v\(old) → v\(current)")
                        }
                        if let summary = information.recognitionSummary { Text(summary) }
                    }.font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text("“更新 MAA”包含引擎及配套识别数据，上限 \(UpdatePolicy.durationDescription(UpdatePolicy.packageTimeout))；仅更新识别数据获取增量，不更换引擎，上限 \(UpdatePolicy.durationDescription(UpdatePolicy.resourceTimeout))。最多重试一次，计入总时限；校验通过后才启用，失败或取消保留当前安装。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            }
        }
    }

    private var storagePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "数据与恢复", symbol: "externaldrive.fill")
                LabeledContent("配置目录") {
                    Text(model.directories.root.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(model.directories.root.path)
                }
                HStack {
                    Button("打开配置目录") { NSWorkspace.shared.open(model.directories.root) }
                    Spacer()
                    Button("立即保存") { model.saveNow() }
                }
                Text("配置修改会自动保存。重置完成记录后，今天已成功的步骤也会重新执行。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                HStack {
                    Spacer()
                    Button("重置今日完成记录…", role: .destructive) { showsResetConfirmation = true }
                        .disabled(model.isWorkflowRunning)
                }
            }
        }
    }
}
