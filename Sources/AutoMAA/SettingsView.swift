import AppKit
import AutoMAAKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selectedSection: SettingsSection
    @State private var showsBetaUpdateConfirmation = false
    @State private var updateDetailsRequest: UpdateDetailsRequest?
    @State private var preferredContentHeight: CGFloat = 360

    var body: some View {
        SettingsPresentation(selectedSection: $selectedSection, onPreferredHeight: { height, isNewPage in
            preferredContentHeight = isNewPage || selectedSection == .general ? height : max(preferredContentHeight, height)
        }) { section in
            VStack(alignment: .leading, spacing: 18) {
                switch section {
                case .general:
                    notificationSection
                    Divider()
                    applicationUpdatePreferences
                    Divider()
                    dataAndPrivacy
                case .environment:
                    maaSections
                case .about:
                    AboutView(embedded: true) {
                        updateDetailsRequest = model.applicationNotesRequest(currentVersion: true)
                    }
                }
            }
        }
        .applicationFeedback(model, destination: .settings(selectedSection))
        .frame(width: 560)
        .frame(minHeight: 220, idealHeight: 360, maxHeight: .infinity)
        .tint(.maaAccent)
        .disclosureGroupStyle(FullWidthDisclosureStyle())
        .navigationTitle("设置")
        .background(SettingsWindowSizing(contentHeight: preferredContentHeight, reduceMotion: reduceMotion)
            .frame(width: 0, height: 0))
        .sheet(item: $updateDetailsRequest) { request in
            UpdateDetailsView(model: model, request: request)
                .focusedSceneValue(\.operationCommandScope, .unavailable)
        }
        .sheet(isPresented: $model.showsMaintenanceHistory) {
            MaintenanceHistoryView()
                .environmentObject(model)
                .focusedSceneValue(\.operationCommandScope, .unavailable)
        }
        .onChange(of: model.configuration) { _, _ in
            model.scheduleSave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshNotificationAuthorization()
                model.reloadActivityHistory()
            }
        }
        .onAppear { model.refreshNotificationAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: .autoMAAOpenSettings)) { _ in
            updateDetailsRequest = nil
            showsBetaUpdateConfirmation = false
        }
        .confirmationDialog(
            "更新到 MAA Beta？",
            isPresented: $showsBetaUpdateConfirmation,
            titleVisibility: .visible
        ) {
            Button("更新 MAA Beta") {
                model.updateMAACore(channel: .beta)
            }
            .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
            Button("取消", role: .cancel) {}
        } message: {
            Text("Beta 版本可能不稳定。本次更新引擎与识别数据，后续自动更新仍使用稳定版。")
        }
    }

    private var applicationUpdatePreferences: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("软件更新").font(.headline)
                Spacer()
                ActionTextButton(title: model.applicationUpdateEntryTitle, symbol: "arrow.down.circle") {
                    model.openApplicationUpdate()
                    openWindow(id: ApplicationUpdateView.windowID)
                }
            }
            SettingsToggleRow(
                title: "接收预发布更新",
                detail: "Beta 和 RC 版本可能不稳定。",
                showsDetail: true,
                isOn: Binding(
                    get: { model.configuration.applicationUpdates.receivesPrereleaseUpdates },
                    set: { model.setPrereleaseApplicationUpdatesEnabled($0) }
                )
            )
            .disabled(!model.canChangeApplicationUpdateChannel)
            SettingsToggleRow(
                title: "自动下载并准备更新",
                detail: "空闲时下载并校验，准备好后手动重启安装。",
                isOn: Binding(
                    get: { model.configuration.applicationUpdates.automaticallyDownloadsUpdates },
                    set: { model.setAutomaticApplicationUpdatesEnabled($0) }
                )
            )
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

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("通知").font(.headline)
                Spacer()
                if model.configuration.notifications.importantEventsEnabled,
                   model.notificationAuthorizationState == .authorized || model.notificationAuthorizationState == .provisional {
                    ActionTextButton(title: model.isTestingImportantNotification ? "正在测试…" : "测试通知", symbol: "bell.badge",
                                     help: "测试后台通知", reservedTitles: ["测试通知", "正在测试…"]) {
                        model.testImportantNotification()
                    }
                    .disabled(model.isTestingImportantNotification || model.isRequestingNotificationAuthorization)
                }
            }
            SettingsToggleRow(
                title: "通知失败和待处理事项",
                detail: "通知中隐藏账号和识别标签。",
                isOn: Binding(
                    get: { model.configuration.notifications.importantEventsEnabled },
                    set: { model.setImportantNotificationsEnabled($0) }
                )
            )
            .disabled(model.isRequestingNotificationAuthorization)
            notificationAuthorizationRow
        }
    }

    @ViewBuilder
    private var notificationAuthorizationRow: some View {
        if model.isRequestingNotificationAuthorization {
            progressRow("正在等待 macOS 通知权限…")
        } else if model.configuration.notifications.importantEventsEnabled {
            HStack(spacing: 10) {
                switch model.notificationAuthorizationState {
                case .authorized:
                    EmptyView()
                case .provisional:
                    Label("macOS 将静默投递通知", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                case .notDetermined:
                    Label("尚未授予 macOS 通知权限", systemImage: "questionmark.circle")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("继续授权") { model.requestNotificationAuthorization() }
                case .denied:
                    Label("macOS 已关闭 AutoMAA 通知", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    ActionTextButton(title: "通知设置", symbol: "arrow.up.right.square", help: "打开系统通知设置") { openNotificationSettings() }
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

    private var maaSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("连接").font(.headline)
                Spacer()
                ActionTextMenu(title: "更新内容", symbol: "doc.text", help: "MAA 发布说明与更新详情") {
                    Button("MAA 稳定版发布说明") { updateDetailsRequest = .maaLatest(.stable) }
                    Button("MAA Beta 发布说明") { updateDetailsRequest = .maaLatest(.beta) }
                    if let information = model.latestMAAUpdateInformation {
                        Divider()
                        Button("最近启用的更新详情") {
                            updateDetailsRequest = .maa(information)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Text("maa-cli").frame(width: 62, alignment: .leading)
                TextField("/opt/homebrew/bin/maa", text: $model.configuration.cliPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                    .accessibilityLabel("maa-cli 路径")
                    .help(model.configuration.cliPath)
                    .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
                if model.isCheckingMAAEnvironment {
                    progressRow("正在检测…")
                } else {
                    ActionTextButton(title: "检测环境", symbol: "arrow.clockwise") { model.refreshMAAStatus() }
                        .fixedSize()
                        .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("版本").frame(width: 62, alignment: .leading)
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.maaVersionSummary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    if let details = model.maaEnvironmentDiagnostic {
                        DetailDisclosure(details: details).id(details)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("维护").font(.headline)
                Spacer()
                ActionTextButton(title: "维护记录", symbol: "clock.arrow.circlepath", help: "浏览 MAA 环境维护记录") {
                    model.showMaintenanceHistory()
                }
                ActionTextMenu(title: "更新 MAA", symbol: "arrow.down.circle", help: "选择 MAA 更新内容") {
                    Button("更新 MAA 稳定版") { model.updateMAACore() }
                    Button("仅更新识别数据") { model.hotUpdate() }
                    Divider()
                    Button("更新 MAA Beta…") { showsBetaUpdateConfirmation = true }
                }
                .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
            }
            SettingsToggleRow(
                title: "空闲时自动更新 MAA",
                detail: "每天最多检查一次稳定版，并避开即将运行的定时任务。",
                isOn: Binding(
                    get: { model.configuration.maaUpdates.automaticallyUpdatesCoreAndResources },
                    set: { model.setAutomaticMAAUpdatesEnabled($0) }
                )
            )
            if model.isWorkflowRunning, model.maaUpdateActivity?.isFinished != false {
                Text("当前运行结束后可维护环境。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if model.applicationUpdateState.blocksWorkflow {
                Text("本体更新结束后可维护环境。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let activity = model.maaUpdateActivity {
                if activity.isFinished {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(activity.message, systemImage: activity.phase == .failed
                              ? "exclamationmark.triangle.fill"
                              : activity.phase == .cancelled ? "stop.circle" : "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(activity.phase == .failed ? Color.orange : .secondary)
                        HStack(spacing: 14) {
                            if activity.phase == .failed {
                                ActionTextButton(title: "重试", symbol: "arrow.clockwise",
                                                 help: "重新更新\(activity.component.title)") {
                                    switch activity.component {
                                    case .resources: model.hotUpdate()
                                    case .core(.stable): model.updateMAACore()
                                    case .core(.beta): showsBetaUpdateConfirmation = true
                                    }
                                }
                                .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow)
                            }
                            if let runID = activity.runID,
                               let session = model.maintenanceSessions.first(where: { $0.runID == runID }) {
                                ActionTextButton(title: "本次记录", symbol: "clock.arrow.circlepath", help: "查看本次维护记录") {
                                    model.showMaintenanceHistory(sessionID: session.id)
                                }
                            }
                        }
                        .font(.caption)
                        if let details = activity.details, !details.isEmpty {
                            DetailDisclosure(details: details).id(details)
                        }
                    }
                } else {
                    UpdateProgressRow(
                        message: (activity.automatic ? "自动更新 · " : "") + (activity.progress?.message ?? activity.message),
                        progress: activity.progress?.download,
                        startedAt: activity.startedAt,
                        isCancelling: activity.isCancelling,
                        showsTransferRate: true,
                        cancel: { model.cancelRun() }
                    )
                }
            }
        }
    }

    private var dataAndPrivacy: some View {
        DisclosureGroup("数据与隐私") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("配置目录")
                    Text(model.directories.root.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(model.directories.root.path)
                    ClipboardCopyButton(subject: "配置目录路径") { model.directories.root.path }
                    ActionIconButton(title: "打开配置目录", symbol: "folder") { NSWorkspace.shared.open(model.directories.root) }
                }
                HStack {
                    Text("更新来源")
                    Text("\(model.applicationUpdateRepository) · \(model.applicationUpdateChannelDescription)")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                ActionTextButton(title: "打开日志目录", symbol: "doc.text.magnifyingglass") { NSWorkspace.shared.open(model.directories.logs) }
                Text("配置、断点和运行记录保存在本机。AutoMAA 不保存游戏密码或验证码。应用联网用于更新和读取说明。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }
}
