import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        AppPage(width: PageLayout.readingWidth) {
            identity
            supportPanel
            privacyPanel
            openSourcePanel
            sloganArtwork
        }
        .navigationTitle("关于 AutoMAA")
    }

    private var identity: some View {
        HStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text("AutoMAA")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("把重复的 MAA 日常，整理成可靠的自动化方案。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    StatusBadge(title: "v\(model.currentApplicationVersion)", color: .maaAccent)
                        .accessibilityLabel("AutoMAA 版本 \(model.currentApplicationVersion)")
                    Button("管理更新") { model.selection = .settings }
                        .buttonStyle(.link)
                    Button("本版本更新内容") { model.showApplicationNotes(currentVersion: true) }
                        .buttonStyle(.link)
                }
                HStack(spacing: 14) {
                    Link("使用文档", destination: model.documentationURL)
                    Link("GitHub 仓库", destination: model.repositoryURL)
                }
                .font(.callout)
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
                .frame(maxWidth: 420)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .accessibilityLabel("直到日常变成一次运行")
                .accessibilityHint("AutoMAA 装饰标语")
        }
    }

    private var supportPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "反馈与支持", symbol: "lifepreserver.fill",
                               detail: "提交问题时，附上版本与运行环境，便于定位。")
                HStack(spacing: 12) {
                    Button { model.copySupportDiagnostics() } label: {
                        Label("复制诊断信息", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    Link("前往问题反馈", destination: model.issueReportURL)
                }
                Text("诊断信息不包含账号、匹配片段、本机路径或运行日志。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacyPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading(title: "本地优先", symbol: "hand.raised.fill",
                               detail: "AutoMAA 编排客户端、账号、任务、定时与断点；画面识别和游戏操作由 maa-cli 与 MaaCore 完成。")
                Label("配置、断点和运行历史保存在本机", systemImage: "checkmark.circle.fill")
                Label("不读取或保存游戏密码、验证码", systemImage: "checkmark.circle.fill")
                Label("任务串行执行，并在切换客户端前确认连接释放", systemImage: "checkmark.circle.fill")
                Text("应用会为检查更新、读取更新说明与同步 MAA 资源访问网络；实际任务的网络行为由游戏、maa-cli 和 MaaCore 决定。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var openSourcePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                SectionHeading(title: "开源与致谢", symbol: "heart.fill")
                Text("AutoMAA 源代码与文档采用 MIT License；应用图标及宣传视觉资产不在该许可范围内。项目建立在 MAA、MaaCore、maa-cli 及其社区长期积累的成果之上，是独立的非官方社区项目。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { creditLinks }
                    VStack(alignment: .leading, spacing: 10) { creditLinks }
                }
            }
        }
    }

    @ViewBuilder
    private var creditLinks: some View {
        Link("查看许可证", destination: model.repositoryURL.appending(path: "blob/main/LICENSE"))
        Link("完整致谢", destination: model.documentationURL.appending(path: "about/credits"))
        Link("MAA 项目", destination: URL(string: "https://github.com/MaaAssistantArknights/MaaAssistantArknights")!)
    }
}
