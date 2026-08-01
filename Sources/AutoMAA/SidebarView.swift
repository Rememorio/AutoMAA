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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusDot(color: model.isRunning ? .orange : (model.readinessIssues.contains { $0.severity == .error } ? .red : .green))
                Text(model.isRunning ? model.phase.displayName : "\(model.activeAccountCount) 个账号已配置")
                    .font(.caption.weight(.medium))
            }
            if model.isRunning {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.025))
    }
}
