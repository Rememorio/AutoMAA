import AppKit
import AutoMAAKit
import SwiftUI

private struct WorkspaceActiveKey: FocusedValueKey { typealias Value = Bool }

extension FocusedValues {
    var workspaceActive: Bool? {
        get { self[WorkspaceActiveKey.self] }
        set { self[WorkspaceActiveKey.self] = newValue }
    }
}

extension Notification.Name {
    static let autoMAAOpenSettings = Notification.Name("AutoMAA.OpenSettings")
}

struct WorkspaceColumns<Content: View, Detail: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        HSplitView {
            content()
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 320, maxHeight: .infinity)
            detail()
                .frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WorkspaceWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }

    func updateNSView(_ view: AppearanceView, context: Context) { view.applyAppearance() }

    final class AppearanceView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyAppearance()
        }

        func applyAppearance() {
            window?.titlebarAppearsTransparent = false
            window?.titlebarSeparatorStyle = .none
        }
    }
}

struct WorkspaceRunControl: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.isWorkflowRunning {
            Button { model.cancelCurrentOperation() } label: {
                Label(model.activePlanID == nil ? "取消更新" : "安全停止", systemImage: model.isCancellingRun ? "hourglass" : "stop.fill")
            }
            .labelStyle(.iconOnly)
            .disabled(!model.canCancelRun || model.isCancellingRun)
            .help(model.isCancellingRun ? "正在安全停止" : model.activePlanID == nil ? "取消更新" : "安全停止当前流程")
        } else if let planID = model.currentPlanID {
            PlanRunControl(planID: planID)
                .accessibilityHint(model.configuration.plans.first(where: { $0.id == planID })?.displayName ?? "当前方案")
        }
    }
}

struct WorkspaceActivityStatus: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button { model.showCurrentActivity() } label: {
            HStack(spacing: 8) {
                Image(systemName: model.activePhase.statusSymbol)
                    .foregroundStyle(model.activePhase.statusTint)
                Text(model.activePhase.displayName).lineLimit(1)
                if model.activeProgress > 0, model.activeProgress.isFinite {
                    Text(min(model.activeProgress, 1), format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(model.activeStatusMessage + " · 查看运行记录")
        .accessibilityLabel("\(model.activePhase.displayName)，查看运行记录")
    }
}
