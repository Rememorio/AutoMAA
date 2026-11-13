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
            preferredContentHeight = isNewPage ? height : max(preferredContentHeight, height)
        }) { section in
            VStack(alignment: .leading, spacing: 18) {
                switch section {
                case .general:
                    notificationSection
                    Divider()
                    applicationUpdatePreferences
                    Divider()
                    storageSection
                    Divider()
                    privacySection
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
        }
        .onChange(of: model.configuration) { _, _ in
            model.scheduleSave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshNotificationAuthorization() }
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
            Text("Beta 是预发布版本，可能包含尚未进入稳定版的修复，也可能出现新问题。本次将更新引擎与识别数据，兼容性校验通过后才启用；自动更新仍使用稳定通道。")
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
                detail: "包含 Beta、RC 等预发布版本，可能出现新问题。关闭后保留当前版本，等待更新的正式版。",
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
            Text("来源：\(model.applicationUpdateRepository) · \(model.applicationUpdateChannelDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help("从 \(model.applicationUpdateRepository) 下载所选通道的更新。MAA 与游戏包体分别维护。")
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
            Text("通知").font(.headline)
            SettingsToggleRow(
                title: "启用重要通知",
                detail: "提醒需要处理的事件与失败，不展示账号或识别标签；普通完成不通知。",
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
                    ActionTextButton(title: model.isTestingImportantNotification ? "正在测试…" : "测试通知", symbol: "bell.badge",
                                     help: "测试后台通知", reservedTitles: ["测试通知", "正在测试…"]) {
                        model.testImportantNotification()
                    }
                    .disabled(model.isTestingImportantNotification)
                case .provisional:
                    Label("macOS 当前以静默方式投递", systemImage: "bell.and.waves.left.and.right")
                        .foregroundStyle(.secondary)
                    Spacer()
                    ActionTextButton(title: model.isTestingImportantNotification ? "正在测试…" : "测试通知", symbol: "bell.badge",
                                     help: "测试后台通知", reservedTitles: ["测试通知", "正在测试…"]) {
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
                        Button(model.maaUpdateActivity == nil ? "最近更新详情" : "本次更新详情") {
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
                ActionTextButton(title: "检测环境", symbol: "arrow.clockwise", help: "检测 MAA 环境") { model.refreshMAAStatus() }
                    .fixedSize()
                    .disabled(model.isWorkflowRunning || model.applicationUpdateState.blocksWorkflow
                              || model.isCheckingMAAEnvironment)
                    .help("检测 MAA 环境")
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("版本").frame(width: 62, alignment: .leading)
                if model.isCheckingMAAEnvironment {
                    progressRow("正在检测…")
                } else {
                    Text(model.maaVersionSummary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("维护").font(.headline)
                Spacer()
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
                detail: "每 24 小时最多一次稳定版；避开 90 分钟内的定时任务，关闭仅影响后续更新。",
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
                        if let details = activity.details, !details.isEmpty {
                            DetailDisclosure(details: details)
                                .id(details)
                        }
                        if let runID = activity.runID {
                            ActionTextButton(title: "本次记录", symbol: "clock.arrow.circlepath", help: "查看本次更新记录") {
                                model.showActivity(runID: runID)
                                openWindow(id: "main")
                                NSApp.activate(ignoringOtherApps: true)
                            }
                            .font(.caption)
                        }
                    }
                } else {
                    UpdateProgressRow(
                        message: (activity.automatic ? "自动更新 · " : "") + (activity.progress?.message ?? activity.message),
                        progress: activity.progress?.download,
                        startedAt: activity.startedAt,
                        limit: "上限 \(UpdatePolicy.durationDescription(activity.timeout))，含重试与校验",
                        isCancelling: activity.isCancelling,
                        showsTransferRate: true,
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
            Text("校验通过后启用；失败或取消保留当前安装。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help("最多重试一次，计入当前操作的总时限。")
        }
    }

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("数据与恢复").font(.headline)
                Spacer()
                Label(model.configurationSaveError == nil ? "自动保存" : "尚未保存", systemImage: model.configurationSaveError == nil ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                ActionIconButton(title: "打开日志目录", symbol: "doc.text.magnifyingglass") {
                    NSWorkspace.shared.open(model.directories.logs)
                }
            }
            HStack(spacing: 8) {
                Text("配置目录").fixedSize()
                Text(model.directories.root.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(model.directories.root.path)
                ClipboardCopyButton(subject: "配置目录路径") { model.directories.root.path }
                ActionIconButton(title: "打开配置目录", symbol: "folder") {
                    NSWorkspace.shared.open(model.directories.root)
                }
            }
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("本地数据").font(.headline)
            Text("配置、断点和运行历史保存在本机。AutoMAA 不读取或保存游戏密码、验证码。")
            Text("应用联网用于更新和读取说明；任务联网由游戏、maa-cli 与 MaaCore 管理。")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

}
