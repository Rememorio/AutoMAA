import AutoMAAKit
import SwiftUI

enum UpdateDetailsRequest: Identifiable, Equatable {
    case application(String)
    case maa(MAAUpdateInformation)
    case maaLatest(MAAUpdateChannel)

    var id: String {
        switch self {
        case let .application(version): "application-\(version)"
        case let .maa(information): information.id.uuidString
        case let .maaLatest(channel): "maa-\(channel.rawValue)"
        }
    }
    var title: String {
        switch self {
        case .application: "AutoMAA 更新内容"
        case .maa: "MAA 更新详情"
        case .maaLatest(.stable): "MAA 稳定版发布说明"
        case .maaLatest(.beta): "MAA Beta 发布说明"
        }
    }
}

struct UpdateDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: AppModel
    let request: UpdateDetailsRequest
    @State private var releases: [ReleaseNotes] = []
    @State private var notice: String?
    @State private var error: String?
    @State private var isLoading = true
    @State private var reloadID = 0

    private var resolvedRequest: UpdateDetailsRequest { model.resolvedUpdateDetails(request) }
    private struct LoadID: Equatable {
        let request: UpdateDetailsRequest
        let reload: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(request.title).font(.title2.weight(.semibold))
                if case let .application(version) = request {
                    Text(version == model.currentApplicationVersion
                         ? "当前版本 v\(version)"
                         : "当前 v\(model.currentApplicationVersion) → v\(version)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("上游说明可能包含 Windows 界面、MaaMacGui 等专属变化；AutoMAA 支持的功能以本应用为准。")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if case let .maa(information) = resolvedRequest { installedVersions(information) }
                    ForEach(releases) { release in releaseSection(release) }
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("正在读取更新说明…").foregroundStyle(.secondary)
                        }
                    } else if releases.isEmpty, error == nil, notice == nil {
                        Text("上游未提供可读取的详细变更说明。已知版本与修订信息显示在上方。")
                            .foregroundStyle(.secondary)
                    }
                    if let notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack {
                if error != nil || notice != nil {
                    Button("重新读取说明") { reloadID += 1 }.disabled(isLoading)
                }
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 620, idealWidth: 720, maxWidth: 820, minHeight: 460, idealHeight: 640, maxHeight: 760)
        .environment(\.openURL, OpenURLAction { url in
            ReleaseNotes.safePageURL(url) == nil ? .discarded : .systemAction
        })
        .onExitCommand { dismiss() }
        .task(id: LoadID(request: resolvedRequest, reload: reloadID)) { await load(resolvedRequest) }
    }

    private func installedVersions(_ information: MAAUpdateInformation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(information.title).font(.headline)
                Spacer()
                Text(information.date, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 9) {
                GridRow {
                    Text("组件")
                    Text(information.after == nil ? "当前安装" : "更新前")
                    if information.after != nil { Text("已启用") }
                }.font(.caption).foregroundStyle(.secondary)
                versionRow("MAA 引擎", before: information.before.core.map { "v\($0)" } ?? "未取得版本号",
                           after: information.after.map { $0.core.map { "v\($0)" } ?? "未取得版本号" })
                versionRow("基础识别数据", before: information.before.baseResources.label,
                           after: information.after?.baseResources.label)
                versionRow("识别数据补丁", before: information.before.recognitionData.label,
                           after: information.after?.recognitionData.label)
            }.textSelection(.enabled)
            if let after = information.after {
                if let revision = after.recognitionData.revision, revision == information.before.recognitionData.revision {
                    Text("识别数据仓库修订未变化，已重新通过兼容性校验。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let date = after.recognitionData.updatedAt {
                    Text("识别数据标注时间：\(date)").font(.caption).foregroundStyle(.secondary)
                }
                if let activity = after.recognitionData.activity {
                    Text("资源标注活动：\(activity)").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("尚无新组件启用记录；版本信息及发布说明对应更新开始时的安装。成功启用后会显示实际变化。")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if let url = information.resourceComparisonURL {
                Link("查看识别数据的完整上游差异", destination: url)
            }
            Divider()
        }
    }

    private func versionRow(_ title: String, before: String, after: String?) -> some View {
        GridRow {
            Text(title).font(.callout)
            Text(before).font(.callout.monospaced())
            if let after { Text(after).font(.callout.monospaced()) }
        }
    }

    private func releaseSection(_ release: ReleaseNotes) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(release.pageURL?.path.contains("/compare/") == true ? "识别数据 \(release.version)" : "v\(release.version)")
                    .font(.headline)
                if let date = release.publishedAt {
                    Text(date, format: .dateTime.year().month().day()).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let url = release.pageURL.flatMap(ReleaseNotes.safePageURL) {
                    Link("上游页面", destination: url).font(.callout)
                }
            }
            if release.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(isLoading ? "正在获取此版本的说明…" : "此版本未提供详细更新说明，可前往上游页面查看。")
                    .foregroundStyle(.secondary)
            } else {
                ReleaseNotesBody(markdown: release.body)
            }
        }
    }

    private func load(_ request: UpdateDetailsRequest) async {
        isLoading = true
        error = nil
        notice = nil
        releases = model.initialReleaseNotes(for: request)
        do {
            let result = try await model.loadReleaseNotes(for: request)
            try Task.checkCancellation()
            let ids = Set(result.releases.map(\.id))
            releases = result.releases + releases.filter { !ids.contains($0.id) }
            notice = result.notice
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "更新说明暂时无法读取：\(ReleaseNotesError.message(for: error))\n可重试读取；更新操作不受影响。"
        }
        isLoading = false
    }
}

private struct ReleaseNotesBody: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(ReleaseNotesMarkdown.blocks(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(text, level):
                    Text(.init(text)).font(level <= 2 ? .title3.weight(.semibold) : .headline)
                        .padding(.top, 6).accessibilityAddTraits(.isHeader)
                case let .paragraph(text):
                    Text(.init(text)).font(.callout)
                case let .bullet(text):
                    HStack(alignment: .top, spacing: 8) {
                        Text("•").accessibilityHidden(true)
                        Text(.init(text)).frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.callout)
                case let .code(text):
                    Text(text).font(.caption.monospaced()).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                case .divider:
                    Divider()
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
}
