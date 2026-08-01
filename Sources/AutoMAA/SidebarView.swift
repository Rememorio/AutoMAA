import AppKit
import AutoMAAKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            brand
            List(selection: $model.selection) {
                Section {
                    Label("今日总览", systemImage: "square.grid.2x2.fill")
                        .tag(SidebarSelection.overview)
                }

                Section {
                    ForEach(model.configuration.clients) { client in
                        DisclosureGroup {
                            ForEach(client.accounts) { account in
                                HStack(spacing: 9) {
                                    StatusDot(color: account.enabled ? .maaAccent : .secondary.opacity(0.5))
                                    Text(account.name)
                                        .lineLimit(1)
                                }
                                .tag(SidebarSelection.account(client.id, account.id))
                            }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: client.kind.symbol)
                                    .foregroundStyle(client.enabled ? Color.maaAccent : Color.secondary)
                                Text(client.kind.title)
                                Spacer()
                                Text("\(client.accounts.filter(\.enabled).count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { model.selection = .client(client.id) }
                        }
                    }
                } header: {
                    HStack {
                        Text("工作流")
                        Spacer()
                        Button {
                            model.addClient()
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .help("添加客户端")
                    }
                }

                Section("工具") {
                    Label("运行日志", systemImage: "list.bullet.rectangle")
                        .tag(SidebarSelection.logs)
                    Label("全局设置", systemImage: "gearshape.fill")
                        .tag(SidebarSelection.settings)
                }
            }
            .listStyle(.sidebar)

            statusFooter
        }
        .background(.thinMaterial)
    }

    private var brand: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("AutoMAA")
                    .font(.headline)
                Text("MAA 日常自动化")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 11) {
            workflowStatus

            if model.isRunning {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)

                Button {
                    model.cancelRun()
                } label: {
                    Label("安全停止", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .help("停止当前 MAA 命令，关闭客户端并释放连接")
            } else {
                Button {
                    model.runAll()
                } label: {
                    Label("开始今日任务", systemImage: "play.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.maaAccent)
                .disabled(!model.canRun)
                .help(model.canRun ? "按照侧边栏顺序执行所有客户端和账号" : "请先处理总览中的配置问题")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var workflowStatus: some View {
        HStack(spacing: 9) {
            Image(systemName: statusSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 26, height: 26)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("运行状态：\(statusTitle)，\(statusDetail)")
    }

    private var statusColor: Color {
        if model.isRunning { return model.phase.statusTint }
        if hasReadinessErrors { return .red }
        return model.readinessIssues.isEmpty ? .green : .orange
    }

    private var statusSymbol: String {
        if model.isRunning { return model.phase.statusSymbol }
        if hasReadinessErrors { return "exclamationmark.triangle.fill" }
        return model.readinessIssues.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var statusTitle: String {
        if model.isRunning { return model.phase.displayName }
        if !model.canRun { return "需要完善配置" }
        return model.readinessIssues.isEmpty ? "已准备就绪" : "可以运行"
    }

    private var statusDetail: String {
        if model.isRunning { return model.statusMessage }
        if model.readinessIssues.isEmpty { return "\(model.activeAccountCount) 个账号 · \(model.activeTaskCount) 个步骤" }
        return model.canRun
            ? "\(model.readinessIssues.count) 项提醒"
            : "\(model.readinessIssues.count) 项问题待处理"
    }

    private var hasReadinessErrors: Bool {
        model.readinessIssues.contains { $0.severity == .error }
    }
}
