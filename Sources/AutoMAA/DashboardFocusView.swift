import AppKit
import AutoMAAKit
import SwiftUI

struct DashboardFocusView: View {
    @EnvironmentObject private var model: AppModel
    let summary: DashboardPlanSummary?

    var body: some View {
        Panel {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    if model.isWorkflowRunning {
                        running
                    } else if let summary {
                        ready(summary)
                    } else {
                        Text("从一份日常方案开始").font(.headline)
                        Text("配置任务和账号，准备好后即可运行。")
                            .font(.callout).foregroundStyle(.secondary)
                        Button("使用轻量日常模板") { model.addPlan(.lightRoutine) }
                            .buttonStyle(.borderedProminent).tint(.maaAction)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DashboardIllustration().frame(width: 140, height: 118)
            }
            .padding(8)
        }
    }

    private func ready(_ summary: DashboardPlanSummary) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 6) {
                Text("当前方案").font(.caption).foregroundStyle(.secondary)
                if model.configuration.plans.count > 1 {
                    Menu {
                        Picker("当前方案", selection: Binding(get: { summary.id }, set: { model.selectCurrentPlan($0) })) {
                            ForEach(model.configuration.plans) { plan in Text(plan.displayName).tag(plan.id) }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(summary.plan.displayName).font(.title3.weight(.semibold))
                                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
                        }
                        .foregroundStyle(.primary)
                    }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("切换当前方案：\(summary.plan.displayName)")
                    .help("切换当前方案")
                } else {
                    Text(summary.plan.displayName).font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                }
                Text(summary.scope).font(.caption).foregroundStyle(.secondary)
            }
            Text(summary.plan.enabledTasks.isEmpty ? "尚未启用任务" : summary.plan.enabledTasks.map(\.title).joined(separator: "  →  "))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            PlanTodaySummary(progress: summary.progress, runState: summary.runState, showsGuidance: false)
            HStack(spacing: 12) {
                PlanRunControl(planID: summary.id, showsTitle: true)
                if case let .warnings(count) = summary.readiness.state {
                    ActionTextButton(title: "\(count) 项运行提醒", symbol: "exclamationmark.circle",
                                     tint: ActivityOutcome.awaitingReview.color, help: "查看本方案的运行前提醒") {
                        model.readinessRequest = .init(id: summary.id)
                    }
                }
                Spacer(minLength: 8)
            }
        }
    }

    private var running: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("当前运行").font(.caption).foregroundStyle(.secondary)
                Text(summary?.plan.displayName ?? (model.isExternalRunActive ? "后台任务" : "MAA 维护"))
                    .font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
            }
            Text(model.activeStatusMessage).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ActionTextButton(title: "查看运行", symbol: "arrow.right", help: "查看当前运行的过程与结果") {
                model.showCurrentActivity()
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
