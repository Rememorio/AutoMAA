import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identity
                purposePanel
                privacyPanel
                openSourcePanel
            }
            .padding(28)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("关于 AutoMAA")
    }

    private var identity: some View {
        HStack(spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 92, height: 92)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text("AutoMAA")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("把重复的 MAA 日常，整理成可靠的自动化方案。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("版本 \(model.currentApplicationVersion)（\(model.currentApplicationBuild)）")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    private var purposePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                Label("项目定位", systemImage: "square.stack.3d.up.fill")
                    .font(.headline)
                Text("AutoMAA 是原生 macOS MAA 日常工作流编排器，负责组织客户端、账号、任务顺序、定时、重试和断点；图像识别与游戏操作由 maa-cli 和 MaaCore 完成。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Link("使用文档", destination: documentationURL)
                    Link("GitHub 仓库", destination: repositoryURL)
                    Link("问题反馈", destination: repositoryURL.appending(path: "issues"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var privacyPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                Label("本地优先", systemImage: "hand.raised.fill")
                    .font(.headline)
                Label("配置、断点和运行历史保存在本机", systemImage: "checkmark.circle.fill")
                Label("不读取或保存游戏密码、验证码", systemImage: "checkmark.circle.fill")
                Label("任务串行执行，并在切换客户端前确认连接释放", systemImage: "checkmark.circle.fill")
                Text("应用只会为检查更新与 MAA 自身的资源更新访问网络；实际任务的网络行为由游戏、maa-cli 和 MaaCore 决定。")
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
                Label("开源与致谢", systemImage: "heart.fill")
                    .font(.headline)
                Text("AutoMAA 源代码与文档采用 MIT License；应用图标及角色视觉资产不在该许可范围内。项目建立在 MAA、MaaCore、maa-cli 及其社区长期积累的成果之上，是独立的非官方社区项目。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Link("查看许可证", destination: repositoryURL.appending(path: "blob/main/LICENSE"))
                    Link("完整致谢", destination: documentationURL.appending(path: "about/credits"))
                    Link("MAA 项目", destination: URL(string: "https://github.com/MaaAssistantArknights/MaaAssistantArknights")!)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var repositoryURL: URL {
        URL(string: "https://github.com/\(model.applicationUpdateRepository)")!
    }

    private var documentationURL: URL {
        URL(string: "https://rememorio.github.io/AutoMAA/")!
    }
}
