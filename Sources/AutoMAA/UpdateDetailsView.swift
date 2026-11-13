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
    private var resolvedRequest: UpdateDetailsRequest { model.resolvedUpdateDetails(request) }

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
                    ReleaseNotesContent(model: model, request: resolvedRequest)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .frame(minHeight: 28)
            .padding(16)
        }
        .frame(width: 560, height: 520)
        .focusedSceneValue(\.workspaceActive, false)
        .environment(\.openURL, OpenURLAction { url in
            ReleaseNotes.safePageURL(url) == nil ? .discarded : .systemAction
        })
        .onExitCommand { dismiss() }
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

}
