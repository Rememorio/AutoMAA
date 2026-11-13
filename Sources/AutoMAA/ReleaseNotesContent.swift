import AutoMAAKit
import SwiftUI

struct ReleaseNotesContent: View {
    @ObservedObject var model: AppModel
    let request: UpdateDetailsRequest
    @State private var releases: [ReleaseNotes] = []
    @State private var notice: String?
    @State private var error: String?
    @State private var isLoading = true
    @State private var reloadID = 0

    private struct LoadID: Equatable {
        let request: UpdateDetailsRequest
        let reload: Int
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let notice { Text(notice).font(.callout).foregroundStyle(.secondary) }
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary)
            }
            if let cacheError = model.releaseNotesCacheError {
                Text(cacheError).font(.caption).foregroundStyle(.secondary)
            }
            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在读取更新说明…").font(.caption).foregroundStyle(.secondary)
                }
            } else if error != nil || notice != nil || model.releaseNotesCacheError != nil {
                ActionTextButton(title: "重新读取说明", symbol: "arrow.clockwise") { reloadID += 1 }
            }
            ForEach(releases) { release in releaseSection(release) }
            if !isLoading, releases.isEmpty, error == nil, notice == nil {
                Text("此版本未提供详细更新说明。").foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .task(id: LoadID(request: request, reload: reloadID)) { await load(request) }
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
        if case let .application(version) = request, version == model.currentApplicationVersion {
            _ = model.applicationNotesRequest(currentVersion: true)
        }
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
