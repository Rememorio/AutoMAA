import AutoMAAKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reloadActivityHistory()
                model.refreshNotificationAuthorization()
            }
        }
        .onChange(of: model.selection) { _, selection in
            if selection == .overview || selection == .activity {
                model.reloadActivityHistory()
            }
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
        case let .plan(id):
            if let binding = model.planBinding(id) {
                PlanEditorView(plan: binding)
            } else {
                ContentUnavailableView("方案不存在", systemImage: "clock.badge.exclamationmark")
            }
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
        case .activity:
            ActivityView()
        case .settings:
            SettingsView()
        case .about:
            AboutView()
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
