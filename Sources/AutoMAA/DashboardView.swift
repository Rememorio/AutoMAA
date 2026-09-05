import AutoMAAKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        AppPage(width: PageLayout.contentWidth) {
            header
            metrics
            routines
            executionFlow
            readiness
            recentActivity
        }
        .navigationTitle("自动化总览")
    }

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let greeting = DashboardGreeting.resolve(at: context.date)
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text(model.isWorkflowRunning ? model.activeStatusMessage : greeting.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var metrics: some View {
        Panel {
            HStack(spacing: 16) {
                metric(title: "自动化方案", value: model.configuration.plans.count, symbol: "clock.arrow.circlepath")
                Divider().frame(height: 32)
                metric(title: "客户端", value: model.activeClientCount, symbol: "macwindow")
                Divider().frame(height: 32)
                metric(title: "启用账号", value: model.activeAccountCount, symbol: "person.2.fill")
                Divider().frame(height: 32)
                metric(title: "定时方案", value: model.activeScheduleCount, symbol: "clock.badge.checkmark.fill")
            }
        }
    }

    private func metric(title: String, value: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .number)
                .font(.title2.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var routines: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("自动化方案", detail: "查看准备状态，选择方案后可展开运行检查。")
            if model.configuration.plans.isEmpty {
                Panel {
                    VStack(spacing: 14) {
                        Image(systemName: "clock.badge.plus")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.maaAccent)
                        Text("创建你的第一个自动化方案")
                            .font(.headline)
                        Button("使用轻量日常模板") { model.addPlan(.lightRoutine) }
                            .buttonStyle(.borderedProminent)
                            .tint(.maaAction)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .topLeading)], spacing: 12) {
                    ForEach(model.configuration.plans) { plan in
                        routineCard(plan)
                    }
                }
            }
        }
    }

    private func routineCard(_ plan: AutomationPlan) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Color.maaAccent)
                    Text(plan.displayName)
                        .font(.headline)
                    if model.activePlanID == plan.id {
                        StatusBadge(title: "正在运行", color: Color.maaAccent)
                    } else if !model.isWorkflowRunning, model.currentPlanID == plan.id {
                        StatusBadge(title: "正在查看", color: Color.secondary)
                    }
                    Spacer()
                    if model.isPlanScheduleCurrent(plan) {
                        Label(PlanScheduleFormatter.nextRunLabel(plan.schedule) ?? "已启用", systemImage: "clock.fill")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .help(PlanScheduleFormatter.summary(plan.schedule))
                    } else if plan.schedule.enabled {
                        Label(model.isSynchronizingSchedules ? "同步中" : "待同步", systemImage: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(model.isSynchronizingSchedules ? Color.maaAccent : Color.orange)
                    } else if model.installedPlanIDs.contains(plan.id) {
                        Label("需修复", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("仅手动")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(plan.enabledTasks) { task in
                        Image(systemName: task.symbol)
                            .font(.caption)
                            .foregroundStyle(Color.maaAccent)
                            .frame(width: 25, height: 25)
                            .background(Color.maaAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                            .help(task.title)
                    }
                    Spacer()
                    Text("\(targetCount(plan)) 个账号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    readinessBadge(for: plan)
                    Spacer()
                    Button("编辑") { model.selection = .plan(plan.id) }
                    PlanRunButton(planID: plan.id)
                }
            }
        }
    }

    private var executionFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                sectionTitle(
                    selectedPlan.map { "「\($0.displayName)」执行路径" } ?? "执行路径",
                    detail: "客户端严格串行；确认当前客户端关闭、连接释放后，才启动下一项。"
                )
                Spacer()
                currentPlanMenu
            }
            Panel {
                if let plan = selectedPlan {
                    let clients = model.configuration.clients.filter { $0.enabled && $0.accounts.contains(where: plan.includes) }
                    if clients.isEmpty {
                        Text("「\(plan.displayName)」还没有可执行账号")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 10) {
                            ForEach(Array(clients.enumerated()), id: \.element.id) { index, client in
                                clientNode(client, plan: plan)
                                if index < clients.count - 1 {
                                    VStack(spacing: 4) {
                                        Image(systemName: "arrow.right")
                                            .foregroundStyle(Color.maaAccent)
                                        Text("关闭并释放")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 68)
                                }
                            }
                        }
                    }
                } else {
                    Text("请选择一个方案")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func clientNode(_ client: ClientConfiguration, plan: AutomationPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: client.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(Color.maaAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(client.displayName)
                        .font(.subheadline.weight(.semibold))
                    Text(client.address)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(client.accounts.filter(plan.includes)) { account in
                    Text(account.displayName)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.maaAccent.opacity(0.09), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readiness: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(
                selectedPlan.map { "「\($0.displayName)」运行检查" } ?? "运行检查",
                detail: "这里展开当前方案的详细结果；全部方案的状态摘要显示在上方卡片中。"
            )
            Panel {
                if let plan = selectedPlan, let readiness = selectedPlanReadiness {
                    if readiness.directIssues.isEmpty, readiness.externalBlockers.isEmpty {
                        Label(
                            "「\(plan.displayName)」已准备就绪",
                            systemImage: "checkmark.seal.fill"
                        )
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if !readiness.directIssues.isEmpty {
                                if !readiness.externalBlockers.isEmpty {
                                    Text("当前方案与共享配置")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(readiness.directIssues) { issue in
                                    readinessIssueRow(issue)
                                }
                            }

                            if !readiness.externalBlockers.isEmpty {
                                if !readiness.directIssues.isEmpty { Divider() }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("其他方案阻止运行")
                                        .font(.caption.weight(.semibold))
                                    Text("AutoMAA 会统一生成全部方案的任务文件，请先修复以下结构问题。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(readiness.externalBlockers) { issue in
                                    readinessIssueRow(issue)
                                }
                            }
                        }
                    }
                } else {
                    Label(
                        "请先创建一个自动化方案",
                        systemImage: "exclamationmark.circle.fill"
                    )
                        .font(.headline)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var selectedPlanID: UUID? {
        model.activePlanID ?? model.currentPlanID
    }

    private var selectedPlan: AutomationPlan? {
        guard let selectedPlanID else { return nil }
        return model.configuration.plans.first(where: { $0.id == selectedPlanID })
    }

    private var selectedPlanReadiness: PlanReadiness? {
        guard let selectedPlanID else { return nil }
        return model.planReadiness(for: selectedPlanID)
    }

    private var currentPlanMenu: some View {
        Menu {
            ForEach(model.configuration.plans) { plan in
                Button {
                    model.selectCurrentPlan(plan.id)
                } label: {
                    if selectedPlanID == plan.id {
                        Label(plan.displayName, systemImage: "checkmark")
                    } else {
                        Text(plan.displayName)
                    }
                }
            }
        } label: {
            Label("切换方案", systemImage: "arrow.left.arrow.right")
                .font(.caption.weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.configuration.plans.isEmpty || model.isWorkflowRunning)
        .help(model.isWorkflowRunning ? "流程结束后可以切换查看方案" : "切换下方执行路径和运行检查，不会打开编辑页")
    }

    private func readinessBadge(for plan: AutomationPlan) -> some View {
        let state = model.planReadiness(for: plan.id).state
        let tint = readinessTint(state)
        return Button {
            model.selectCurrentPlan(plan.id)
        } label: {
            Label(readinessTitle(state), systemImage: readinessSymbol(state))
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(tint.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isWorkflowRunning)
        .help("选择「\(plan.displayName)」并在下方查看完整运行检查")
        .accessibilityHint("选择此方案并显示完整运行检查")
    }

    private func readinessIssueRow(_ issue: ReadinessIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
            Text(issue.message)
                .font(.callout)
            Spacer()
        }
    }

    private func readinessTitle(_ state: PlanReadinessState) -> String {
        switch state {
        case .ready: "已就绪"
        case let .warnings(count): "\(count) 项提醒"
        case let .errors(count): "\(count) 项问题"
        case .blockedByOtherPlan: "受其他方案影响"
        }
    }

    private func readinessSymbol(_ state: PlanReadinessState) -> String {
        switch state {
        case .ready: "checkmark.circle.fill"
        case .warnings: "exclamationmark.triangle.fill"
        case .errors, .blockedByOtherPlan: "exclamationmark.circle.fill"
        }
    }

    private func readinessTint(_ state: PlanReadinessState) -> Color {
        switch state {
        case .ready: .green
        case .warnings: .orange
        case .errors, .blockedByOtherPlan: .red
        }
    }

    private var recentActivity: some View {
        let latest = ActivityHistory.sessions(from: model.activityEntries).first
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("最近活动", detail: nil)
                Spacer()
                if latest != nil {
                    Button("查看全部") { model.selection = .activity }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.maaAccent)
                }
            }
            Panel {
                if let latest, let lastEntry = latest.entries.last {
                    HStack(spacing: 13) {
                        Image(systemName: activitySymbol(latest))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(activityTint(latest))
                            .frame(width: 34, height: 34)
                            .background(
                                activityTint(latest).opacity(0.11),
                                in: RoundedRectangle(cornerRadius: 9)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(activityTitle(latest))
                                    .font(.callout.weight(.semibold))
                                Text(activityStatus(latest))
                                    .font(.caption)
                                    .foregroundStyle(activityTint(latest))
                            }
                            Text(lastEntry.message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        Text(lastEntry.timestamp, format: .dateTime.month().day().hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("还没有运行记录")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        SectionHeading(title: title, detail: detail)
    }

    private func targetCount(_ plan: AutomationPlan) -> Int {
        model.configuration.clients.filter(\.enabled).flatMap { $0.accounts.filter(plan.includes) }.count
    }

    private func activityTitle(_ session: ActivitySession) -> String {
        if let planID = session.planID,
           let plan = model.configuration.plans.first(where: { $0.id == planID }) {
            return plan.displayName
        }
        return session.runID == nil ? "较早的运行记录" : "MAA 维护"
    }

    private func activityStatus(_ session: ActivitySession) -> String {
        if session.runSummary?.isPartial == true { return "部分完成，需处理" }
        if session.finalPhase == .completed, session.finalLevel == .warning { return "完成，需留意" }
        return session.finalPhase?.displayName ?? "运行记录"
    }

    private func activitySymbol(_ session: ActivitySession) -> String {
        if session.finalPhase == .completed, session.finalLevel == .warning {
            return "exclamationmark.circle.fill"
        }
        return session.finalPhase?.statusSymbol ?? session.finalLevel.symbol
    }

    private func activityTint(_ session: ActivitySession) -> Color {
        if session.finalPhase == .completed, session.finalLevel == .warning { return .orange }
        return session.finalPhase?.statusTint ?? session.finalLevel.color
    }

}
