import AutoMAAKit
import Foundation
import SwiftUI

struct PlanReadinessRequest: Identifiable {
    let id: UUID
}

enum PlanReadinessDestination: Equatable {
    case configuration(ConfigurationRepairTarget)
    case newClient
    case newAccount(clientID: UUID, planID: UUID)
    case clients
    case arrangement(UUID)
}

struct PlanReadinessSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let planID: UUID
    let onNavigate: (PlanReadinessDestination) -> Void

    var body: some View {
        let readiness = model.planReadiness(for: planID)
        let issues = readiness.directIssues + readiness.externalBlockers
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("运行检查").font(.headline)
                Text(model.configuration.plans.first { $0.id == planID }?.displayName ?? "方案已移除")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.vertical, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if issues.isEmpty {
                        Label("配置已就绪", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    issueSection("需要处理", issues: issues.filter { $0.severity == .error })
                    issueSection("提醒", issues: issues.filter { $0.severity == .warning })
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            Divider()
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("完成").frame(minWidth: 56) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 560, height: 380)
        .onExitCommand { dismiss() }
    }

    @ViewBuilder
    private func issueSection(_ title: String, issues: [ReadinessIssue]) -> some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text("\(issues.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                ForEach(Array(issues.enumerated()), id: \.element.id) { index, issue in
                    if index > 0 { Divider().padding(.leading, 26) }
                    issueRow(issue)
                }
            }
        }
    }

    private func issueRow(_ issue: ReadinessIssue) -> some View {
        let destination = PlanReadiness.repairDestination(for: issue, clients: model.configuration.clients)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: issue.severity == .error ? "exclamationmark.circle" : "info.circle")
                    .foregroundStyle(issue.severity == .error ? Color.red : .orange)
                    .frame(width: 16)
                    .accessibilityLabel(issue.severity == .error ? "需要处理" : "提醒")
                Text(issue.id == "maa-cli-missing" ? "找不到可执行的 maa-cli" : issue.message)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                if let destination {
                    ActionTextButton(title: repairLabel(destination), symbol: "arrow.right", help: repairTitle(destination)) {
                        onNavigate(destination)
                    }
                }
            }
            if issue.id == "maa-cli-missing" {
                HStack(spacing: 8) {
                    Text(model.configuration.cliPath)
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                        .textSelection(.enabled).help(model.configuration.cliPath)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ClipboardCopyButton(subject: "maa-cli 路径") { model.configuration.cliPath }
                }
                .padding(.leading, 26)
            }
        }
    }

    private func repairLabel(_ destination: PlanReadinessDestination) -> String {
        switch destination {
        case .configuration(.settings): "MAA 环境"
        case .configuration(.client): "编辑客户端"
        case .configuration(.account): "编辑账号"
        case .configuration(.plan): "编辑方案"
        case .newClient: "添加客户端"
        case .newAccount: "添加账号"
        case .clients: "管理客户端与账号"
        case .arrangement: "选择执行账号"
        }
    }

    private func repairTitle(_ destination: PlanReadinessDestination) -> String {
        switch destination {
        case let .configuration(.client(id)):
            let name = model.configuration.clients.first { $0.id == id }?.displayName ?? "客户端"
            return "编辑客户端「\(name)」…"
        case let .configuration(.account(clientID, accountID)):
            let account = model.configuration.clients.first { $0.id == clientID }?.accounts.first { $0.id == accountID }
            return "编辑账号「\(account?.displayName ?? "账号")」…"
        case let .configuration(.plan(id)):
            let name = model.configuration.plans.first { $0.id == id }?.displayName ?? "方案"
            return "编辑方案「\(name)」"
        default: return destination.actionTitle
        }
    }
}

extension PlanReadinessDestination {
    var actionTitle: String {
        switch self {
        case let .configuration(target): target.actionTitle
        case .newClient: "添加客户端…"
        case .newAccount: "为该客户端添加执行账号"
        case .clients: "前往客户端与账号"
        case .arrangement: "在执行安排中选择账号"
        }
    }
}

extension ConfigurationRepairTarget {
    var actionTitle: String {
        switch self {
        case .settings: "前往 MAA 环境"
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

    static func repairDestination(for issue: ReadinessIssue, clients: [ClientConfiguration]) -> PlanReadinessDestination? {
        guard issue.id == "plan-accounts-empty", case let .plan(planID) = issue.scope else {
            return issue.repairTarget.map(PlanReadinessDestination.configuration)
        }
        if clients.isEmpty { return .newClient }
        let enabled = clients.filter(\.enabled)
        if enabled.contains(where: { $0.accounts.contains(where: \.enabled) }) { return .arrangement(planID) }
        if enabled.isEmpty, clients.count == 1 { return .configuration(.client(clients[0].id)) }
        guard enabled.count == 1, let client = enabled.first else { return .clients }
        if client.accounts.isEmpty { return .newAccount(clientID: client.id, planID: planID) }
        if client.accounts.count == 1 { return .configuration(.account(clientID: client.id, accountID: client.accounts[0].id)) }
        return .clients
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
