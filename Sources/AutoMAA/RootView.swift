import AutoMAAKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingReadinessDestination: PlanReadinessDestination?
    @State private var showsSidebar = true

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 200)
                .frame(maxHeight: .infinity)
                .background(.regularMaterial)
                .frame(width: showsSidebar ? 200 : 0, alignment: .leading)
                .clipped()
                .allowsHitTesting(showsSidebar)
                .accessibilityHidden(!showsSidebar)
            if showsSidebar { Divider() }
            detail
                .disclosureGroupStyle(FullWidthDisclosureStyle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let error = model.configurationSaveError {
                        ConfigurationSaveFeedback(error: error) { model.saveNow() }
                    } else {
                        ApplicationFeedbackRegion(center: model.feedback, window: .workspace)
                    }
                }
        }
        .background(WorkspaceWindowAppearance().frame(width: 0, height: 0))
        .background(ApplicationWindowContext(feedback: model.feedback, destination: .workspace).frame(width: 0, height: 0))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        showsSidebar.toggle()
                    }
                } label: {
                    Label(showsSidebar ? "隐藏边栏" : "显示边栏", systemImage: "sidebar.left")
                }
                .help(showsSidebar ? "隐藏边栏" : "显示边栏")
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            if model.isWorkflowRunning {
                ToolbarItem(placement: .primaryAction) { WorkspaceActivityStatus() }
            }
            if !isPlanSelected && model.isWorkflowRunning {
                ToolbarItem(placement: .primaryAction) { WorkspaceRunControl() }
            }
        }
        .focusedSceneValue(\.workspaceActive, true)
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

    private var isPlanSelected: Bool {
        if case .plan = model.selection { return true }
        return false
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
