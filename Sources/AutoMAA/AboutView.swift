import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    var embedded = false
    var onShowCurrentVersionNotes: (() -> Void)?

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                AppPage(width: PageLayout.readingWidth) {
                    content
                }
                .navigationTitle("关于 AutoMAA")
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: PageLayout.sectionSpacing) {
            identity
            sloganArtwork
            Divider()
            openSourceSection
            Divider()
            supportSection
        }
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 14) {
            BrandLogo()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("AutoMAA").font(.title2.weight(.semibold))
                    Text("v\(model.currentApplicationVersion)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel("AutoMAA 版本 \(model.currentApplicationVersion)")
                    ActionTextButton(title: "更新内容", symbol: "doc.text", help: "本版本更新内容") {
                        if let onShowCurrentVersionNotes {
                            onShowCurrentVersionNotes()
                        } else {
                            model.showApplicationNotes(currentVersion: true)
                        }
                    }
                }
                Text("把重复的 MAA 日常，整理成可靠的自动化方案。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Link("使用文档", destination: model.documentationURL)
                    Link("GitHub 仓库", destination: model.repositoryURL)
                }
                .font(.caption)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var sloganArtwork: some View {
        if let url = Bundle.main.url(forResource: "AutoMAA-slogan", withExtension: "png"),
           let image = NSImage(contentsOf: url)
        {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 380)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("直到日常变成一次运行")
                .accessibilityHint("AutoMAA 装饰标语")
        }
    }

    private var supportSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("反馈与支持").font(.subheadline.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                ClipboardCopyButton(subject: "诊断信息", feedback: model.feedback) { model.supportDiagnostics.text }
            }
            Link("前往问题反馈", destination: model.issueReportURL).font(.callout)
            Text("诊断信息不包含账号、匹配片段、本机路径或运行日志。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var openSourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开源与致谢").font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text("AutoMAA 编排客户端、账号、任务与定时；画面识别和游戏操作由 MAA、MaaCore 与 maa-cli 完成。界面交互参考 MaaMacGui，是独立的非官方社区项目。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("源代码与文档采用 MIT License；Logo、应用图标及宣传视觉资产不在该许可范围内。")
                .font(.caption)
                .foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) { creditLinks }
                VStack(alignment: .leading, spacing: 8) { creditLinks }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private var creditLinks: some View {
        Link("查看许可证", destination: model.repositoryURL.appending(path: "blob/main/LICENSE"))
        Link("完整致谢", destination: model.documentationURL.appending(path: "about/credits"))
        Link("MAA 项目", destination: URL(string: "https://github.com/MaaAssistantArknights/MaaAssistantArknights")!)
    }
}
