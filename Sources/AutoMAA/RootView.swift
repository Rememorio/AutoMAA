import AutoMAAKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var statusPulse = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    LinearGradient(
                        colors: [Color.maaAccent.opacity(0.035), Color.clear, Color.maaBlue.opacity(0.025)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
                .toolbar { toolbar }
        }
        .navigationSplitViewStyle(.balanced)
        .tint(.maaAccent)
        .overlay(alignment: .top) {
            if let message = model.bannerMessage {
                banner(message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 10)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.bannerMessage)
        .onChange(of: model.configuration) { _, _ in
            model.scheduleSave()
        }
        .task {
            model.prepareApplication()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .overview:
            DashboardView()
        case let .client(id):
            if let binding = model.clientBinding(id) {
                ClientEditorView(client: binding)
            } else {
                ContentUnavailableView("客户端不存在", systemImage: "rectangle.slash")
            }
        case let .account(clientID, accountID):
            if let account = model.accountBinding(clientID: clientID, accountID: accountID),
               let client = model.configuration.clients.first(where: { $0.id == clientID }) {
                AccountEditorView(client: client, account: account)
            } else {
                ContentUnavailableView("账号不存在", systemImage: "person.crop.circle.badge.exclamationmark")
            }
        case .logs:
            LogsView()
        case .settings:
            SettingsView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isRunning {
                runningStatus
                Button {
                    model.cancelRun()
                } label: {
                    Label("安全停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("停止当前 MAA 命令，关闭客户端并释放连接")
            } else {
                Button {
                    model.runAll()
                } label: {
                    Label("运行全部", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canRun)
                .help(model.canRun ? "按照侧边栏顺序执行所有客户端和账号" : "请先处理总览中的配置问题")
            }
        }
    }

    private var runningStatus: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(model.phase.statusTint.opacity(0.13))
                    .scaleEffect(reduceMotion ? 1 : (statusPulse ? 1.12 : 0.88))
                    .opacity(reduceMotion ? 1 : (statusPulse ? 0.75 : 1))
                Image(systemName: model.phase.statusSymbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.phase.statusTint)
            }
            .frame(width: 20, height: 20)

            Text(model.phase.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
        }
        .frame(minWidth: 94, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(model.phase.statusTint.opacity(0.075), in: Capsule())
        .overlay {
            Capsule()
                .stroke(model.phase.statusTint.opacity(0.16), lineWidth: 1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("运行状态：\(model.phase.displayName)")
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                statusPulse = true
            }
        }
        .onDisappear {
            statusPulse = false
        }
    }

    private func banner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.maaAccent)
            Text(message)
                .font(.callout.weight(.medium))
            Button {
                model.bannerMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThickMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
    }
}
