import AutoMAAKit
import SwiftUI

struct ApplicationUpdateView: View {
    static let windowID = "software-update"
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissWindow) private var dismissWindow

    private var notesRequest: UpdateDetailsRequest {
        .application(model.applicationUpdateRelease?.version.description ?? model.currentApplicationVersion)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                BrandLogo().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Text(model.applicationUpdateRelease.map {
                        "当前 v\(model.currentApplicationVersion) → v\($0.version.description)"
                    } ?? "当前版本 v\(model.currentApplicationVersion)")
                    .font(.callout).foregroundStyle(.secondary)
                    if let release = model.applicationUpdateRelease {
                        HStack(spacing: 10) {
                            if let date = release.publishedAt { Text(date, format: .dateTime.year().month().day()) }
                            Text(ByteCountFormatter.string(fromByteCount: Int64(release.diskImage.size), countStyle: .file))
                        }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if case let .failed(message) = model.applicationUpdateState {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let notice = model.applicationUpdateNotice {
                        Text(notice).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ReleaseNotesContent(model: model, request: notesRequest)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                operation
                if model.isWorkflowRunning {
                    Text("当前任务结束后可下载或安装更新。").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(16)
        }
        .applicationFeedback(model, destination: .applicationUpdate)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440, idealHeight: 540)
        .tint(.maaAccent)
        .disclosureGroupStyle(FullWidthDisclosureStyle())
        .focusedSceneValue(\.workspaceActive, false)
        .environment(\.openURL, OpenURLAction { url in
            ReleaseNotes.safePageURL(url) == nil ? .discarded : .systemAction
        })
        .onAppear {
            model.isApplicationUpdateWindowVisible = true
            if let notice = model.feedback.notice(for: .workspace, style: .toast), notice.action == .applicationUpdate {
                model.feedback.dismiss(id: notice.id)
            }
        }
        .onDisappear { model.isApplicationUpdateWindowVisible = false }
    }

    private var title: String {
        switch model.applicationUpdateState {
        case .idle, .restoring, .checking: "检查 AutoMAA 更新"
        case .upToDate: model.applicationUpdateCurrentStatus
        case .available: "发现 AutoMAA 新版本"
        case .downloading: "正在准备 AutoMAA 更新"
        case .cancelling: "正在取消更新"
        case .ready: "更新已准备好"
        case .installing: "正在安装 AutoMAA 更新"
        case .failed: "更新未完成"
        }
    }

    @ViewBuilder
    private var operation: some View {
        switch model.applicationUpdateState {
        case .idle, .upToDate:
            HStack {
                if let date = model.applicationUpdateCheckedAt {
                    Text("\(date.formatted(date: .omitted, time: .standard)) 检查").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismissWindow() }.keyboardShortcut(.cancelAction)
                Button("再次检查") { model.checkForApplicationUpdate() }.keyboardShortcut(.defaultAction)
            }
        case .restoring, .checking:
            UpdateProgressRow(
                message: model.applicationUpdateState.isRestoring ? "正在校验已下载的更新…" : "正在检查新版本…",
                startedAt: model.applicationUpdateStartedAt,
                limit: "上限 \(UpdatePolicy.durationDescription(UpdatePolicy.checkTimeout))，含重试",
                cancel: { model.cancelApplicationUpdate() }
            )
        case let .available(release):
            HStack {
                Text("下载后将校验更新，安装前仍需确认重启。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("稍后") { dismissWindow() }.keyboardShortcut(.cancelAction)
                Button("下载更新") { model.downloadApplicationUpdate(release) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(model.isWorkflowRunning)
            }
        case let .downloading(release):
            UpdateProgressRow(
                message: model.applicationUpdateProgress?.message ?? "正在准备下载 v\(release.version)…",
                progress: model.applicationUpdateProgress?.download,
                startedAt: model.applicationUpdateStartedAt,
                limit: "上限 \(UpdatePolicy.durationDescription(UpdatePolicy.packageTimeout))，含重试与校验",
                cancel: { model.cancelApplicationUpdate() }
            )
        case .cancelling:
            UpdateProgressRow(message: "", startedAt: model.applicationUpdateStartedAt,
                              limit: "清理完成后即可重新操作", isCancelling: true, cancel: {})
        case let .ready(prepared):
            HStack {
                Text("更新已校验，保存配置后重启安装。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("稍后") { dismissWindow() }.keyboardShortcut(.cancelAction)
                Button("重启并安装") { model.restartAndInstallApplicationUpdate(prepared) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(model.isWorkflowRunning || model.configurationSaveError != nil)
            }
        case .installing:
            HStack {
                ProgressView().controlSize(.small)
                Text("正在退出并安装更新…").font(.callout)
            }
        case .failed:
            HStack {
                Text("当前版本仍可使用。").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismissWindow() }.keyboardShortcut(.cancelAction)
                Button("重新检查") { model.checkForApplicationUpdate() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}

private extension ApplicationUpdateState {
    var isRestoring: Bool {
        if case .restoring = self { return true }
        return false
    }
}
