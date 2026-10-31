import AutoMAAKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openSettings) private var openSettings
    @State private var pendingReadinessDestination: PlanReadinessDestination?
    @State private var chrome = WorkspaceChromeController()

    var body: some View {
        WorkspaceShell(chrome: chrome, model: model) {
            SidebarView()
                .background(.regularMaterial)
        } content: {
            detail
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let error = model.configurationSaveError {
                        ConfigurationSaveFeedback(error: error) { model.saveNow() }
                    } else {
                        ApplicationFeedbackRegion(center: model.feedback, window: .workspace)
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ApplicationWindowContext(feedback: model.feedback, destination: .workspace).frame(width: 0, height: 0))
        .focusedSceneValue(\.workspaceActive, true)
        .focusedSceneValue(\.workspaceChromeController, chrome)
        .sheet(item: $model.entityEditor) { request in
            EntityEditorSheet(request: request).environmentObject(model)
        }
        .sheet(item: $model.updateDetailsRequest) { request in
            UpdateDetailsView(model: model, request: request)
                .focusedSceneValue(\.workspaceActive, false)
        }
        .sheet(item: $model.readinessRequest, onDismiss: navigateAfterReadinessDismissal) { request in
            PlanReadinessSheet(planID: request.id) { destination in
                pendingReadinessDestination = destination
                model.readinessRequest = nil
            }
                .environmentObject(model)
                .focusedSceneValue(\.workspaceActive, false)
        }
        .tint(.maaAccent)
        .onReceive(NotificationCenter.default.publisher(for: .autoMAAOpenSettings)) { _ in
            openSettings()
        }
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
                PlanEditorView(plan: binding).id(binding.wrappedValue.id)
            } else {
                ContentUnavailableView("方案不存在", systemImage: "clock.badge.exclamationmark")
                    .workspaceToolbar(title: "自动化方案")
            }
        case let .client(id):
            ClientsView().onAppear { model.entityEditor = .client(id); model.selection = .clients }
        case let .account(clientID, accountID):
            ClientsView().onAppear { model.entityEditor = .account(clientID, accountID); model.selection = .clients }
        case .clients: ClientsView()
        case .activity:
            ActivityView()
        }
    }

    private func navigateAfterReadinessDismissal() {
        guard let destination = pendingReadinessDestination else { return }
        pendingReadinessDestination = nil
        switch destination {
        case let .configuration(target):
            model.showConfigurationRepair(target)
        case .newClient:
            model.selection = .clients
            model.entityEditor = .newClient
        }
    }

}
