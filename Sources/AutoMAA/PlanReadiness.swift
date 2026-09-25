import AutoMAAKit
import Foundation
import SwiftUI

struct PlanReadinessRequest: Identifiable {
    let id: UUID
}

struct PlanReadinessSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let planID: UUID

    var body: some View {
        let readiness = model.planReadiness(for: planID)
        VStack(alignment: .leading, spacing: 20) {
            Text("运行检查").font(.title2.bold())
            Text(model.configuration.plans.first { $0.id == planID }?.displayName ?? "方案已移除")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if readiness.directIssues.isEmpty, readiness.externalBlockers.isEmpty {
                        Label("配置已就绪", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    ForEach(readiness.directIssues + readiness.externalBlockers) { issue in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(issue.message, systemImage: issue.severity == .error ? "exclamationmark.circle" : "info.circle")
                                .fixedSize(horizontal: false, vertical: true)
                            if let target = issue.repairTarget {
                                Button(target.actionTitle) {
                                    dismiss()
                                    model.showConfigurationRepair(target)
                                }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Menu("前往配置") {
                    Button("编辑方案") { dismiss(); model.selection = .plan(planID) }
                    Button("全局设置") { dismiss(); model.selection = .settings }
                    Divider()
                    ForEach(model.configuration.clients) { client in
                        Button(client.displayName) { dismiss(); model.selection = .client(client.id) }
                    }
                    if model.configuration.clients.isEmpty {
                        Button("添加客户端") { dismiss(); model.addClient() }
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 520, height: 380)
    }
}

extension ConfigurationRepairTarget {
    var actionTitle: String {
        switch self {
        case .settings: "前往全局设置"
        case .plan: "编辑相关方案"
        case .client: "编辑相关客户端"
        case .account: "编辑相关账号"
        }
    }
}

enum PlanReadinessState: Equatable {
    case ready
    case warnings(Int)
    case errors(Int)
    case blockedByOtherPlan(Int)
}

struct PlanReadiness: Equatable {
    let directIssues: [ReadinessIssue]
    let externalBlockers: [ReadinessIssue]

    init(planID: UUID, issues: [ReadinessIssue]) {
        directIssues = issues.filter { issue in
            switch issue.scope {
            case .shared: true
            case let .plan(sourcePlanID): sourcePlanID == planID
            }
        }
        externalBlockers = issues.filter { issue in
            guard issue.severity == .error else { return false }
            if case let .plan(sourcePlanID) = issue.scope {
                return sourcePlanID != planID
            }
            return false
        }
    }

    var state: PlanReadinessState {
        let directErrors = directIssues.count { $0.severity == .error }
        if directErrors > 0 {
            return .errors(directErrors + externalBlockers.count)
        }
        if !externalBlockers.isEmpty {
            return .blockedByOtherPlan(externalBlockers.count)
        }
        let warnings = directIssues.count { $0.severity == .warning }
        return warnings == 0 ? .ready : .warnings(warnings)
    }

    var hasBlockingErrors: Bool {
        switch state {
        case .errors, .blockedByOtherPlan: true
        case .ready, .warnings: false
        }
    }
}
