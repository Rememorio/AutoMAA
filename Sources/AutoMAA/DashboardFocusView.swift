import AppKit
import AutoMAAKit
import SwiftUI

struct DashboardFocusView: View {
    @EnvironmentObject private var model: AppModel
    let summary: DashboardPlanSummary?
    let blocker: String?

    var body: some View {
        if model.isWorkflowRunning {
            running
        } else if model.configuration.clients.isEmpty {
            HStack(spacing: 18) {
                DashboardIllustration().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择要运行的游戏客户端").font(.title3.weight(.semibold))
                    Button("添加客户端…") {
                        model.selection = .clients
                        model.entityEditor = .newClient
                    }
                }
                Spacer()
            }
        } else if let summary {
            HStack(alignment: .center, spacing: 16) {
                DashboardIllustration().frame(width: 68, height: 68)
                VStack(alignment: .leading, spacing: 7) {
                    planPicker(summary)
                    Text(summary.scope).font(.callout).foregroundStyle(.secondary)
                    if let blocker {
                        Text(blocker).font(.callout).foregroundStyle(ActivityOutcome.blocked.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if case let .warnings(count) = summary.readiness.state {
                    ActionTextButton(title: "\(count) 项运行提醒", symbol: "exclamationmark.circle",
                                     tint: ActivityOutcome.awaitingReview.color, help: "查看运行前提醒") {
                        model.readinessRequest = .init(id: summary.id)
                    }
                }
                PlanRunControl(summary: summary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("创建日常方案").font(.title3.weight(.semibold))
                Button("使用轻量日常模板") { model.addPlan(.lightRoutine) }
            }
        }
    }

    @ViewBuilder
    private func planPicker(_ summary: DashboardPlanSummary) -> some View {
        if model.configuration.plans.count > 1 {
            Menu {
                Picker("当前方案", selection: Binding(get: { summary.id }, set: { model.selectCurrentPlan($0) })) {
                    ForEach(model.configuration.plans) { plan in Text(plan.displayName).tag(plan.id) }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    Text(summary.plan.displayName).font(.title2.weight(.semibold)).lineLimit(2)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                }
                .foregroundStyle(.primary)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("切换当前方案：\(summary.plan.displayName)")
            .help("切换当前方案")
        } else {
            Text(summary.plan.displayName).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
        }
    }

    private var running: some View {
        let maintenance = model.isMAAMaintenanceRunning
        let controls = WorkspaceRunControlState(model: model)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                if maintenance {
                    Text(model.maaUpdateActivity?.automatic == true ? "自动维护" : "环境维护")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(maintenance ? (model.maaUpdateActivity?.component.title ?? "MAA 维护") : (summary?.plan.displayName ?? "后台任务"))
                    .font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            }
            Text(model.activeStatusMessage).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                if maintenance {
                    ActionTextButton(title: "查看维护", symbol: "arrow.right", help: "打开 MAA 环境设置，查看维护进度或取消更新") {
                        controls.openOperation(in: model)
                    }
                } else {
                    ActionTextButton(title: "查看运行", symbol: "arrow.right", help: "查看当前运行的过程与结果") {
                        controls.openOperation(in: model)
                    }
                    ActionTextButton(title: "安全停止", symbol: "stop.fill", help: controls.stopHelp) {
                        controls.stopWorkflow(in: model)
                    }
                    .disabled(!controls.canStop)
                    .accessibilityLabel(controls.stopHelp)
                }
            }
        }
    }
}

private struct DashboardIllustration: View {
    private static let image: NSImage? = Bundle.main.url(forResource: "AutoMAA-overview", withExtension: "png")
        .flatMap(NSImage.init(contentsOf:))

    var body: some View {
        Group {
            if let image = Self.image { Image(nsImage: image).resizable().scaledToFit() }
            else { BrandLogo() }
        }
        .accessibilityHidden(true).allowsHitTesting(false)
    }
}
