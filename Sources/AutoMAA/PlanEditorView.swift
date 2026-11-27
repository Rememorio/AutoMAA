import AutoMAAKit
import SwiftUI

private enum PlanDetailSection { case settings, activity }

struct PlanEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var plan: AutomationPlan
    @State private var selectedTask: TaskKind?
    @State private var detailSection = PlanDetailSection.settings
    @State private var showsRename = false
    @State private var confirmsDelete = false

    init(plan: Binding<AutomationPlan>) {
        _plan = plan
        _selectedTask = State(initialValue: plan.wrappedValue.stepOrder.first)
    }

    var body: some View {
        WorkspaceColumns {
            taskList
        } detail: {
            switch detailSection {
            case .settings:
                if let selectedTask {
                    PlanTaskInspector(plan: $plan, task: selectedTask)
                } else {
                    ContentUnavailableView("选择任务", systemImage: "slider.horizontal.3")
                }
            case .activity:
                PlanActivityView(planID: plan.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .workspaceToolbar(for: .plan(plan.id), title: plan.displayName, actions: toolbarActions,
            modes: WorkspaceToolbarModes(options: [
                .init(title: "任务设置", symbol: "slider.horizontal.3", help: "任务设置 · 调整所选任务的参数"),
                .init(title: "运行概况", symbol: "checklist", help: "运行概况 · 查看本轮进度，继续未完成任务或处理作战结果")
            ], selectedIndex: detailSection == .settings ? 0 : 1) { index in
                detailSection = index == 0 ? .settings : .activity
            })
        .onAppear { selectInitialTask() }
        .onChange(of: plan.id) { _, _ in
            showsRename = false
            confirmsDelete = false
            selectInitialTask()
        }
        .onChange(of: model.planActivityRequest) { _, _ in applyDetailRequest() }
        .onChange(of: model.fightSettingsPlanID) { _, _ in applyDetailRequest() }
        .onChange(of: isCurrentPlanRunning) { _, running in
            if running { detailSection = .activity }
        }
        .sheet(isPresented: $showsRename) {
            PlanRenameSheet(name: plan.name) { name in
                guard !model.isWorkflowRunning else { return false }
                plan.name = name
                return true
            }
        }
        .confirmationDialog("删除「\(plan.displayName)」？", isPresented: $confirmsDelete) {
            Button("删除方案", role: .destructive) {
                guard !model.isWorkflowRunning else { return }
                model.deletePlan(plan.id)
            }
        } message: {
            Text("账号和客户端会保留，对应的系统定时任务会一并移除。")
        }
    }

    private var toolbarActions: [WorkspaceToolbarAction] {
        [
            .init(id: "plan.arrangement", title: "执行安排 · 设置账号、定时与运行策略", symbol: "calendar.badge.clock",
                  handler: { model.showArrangement(for: plan.id) }),
            .init(id: "plan.more", title: "方案操作", symbol: "ellipsis", menu: [
                .action("重命名方案…", isEnabled: !model.isWorkflowRunning) { showsRename = true },
                .action("复制方案", isEnabled: !model.isWorkflowRunning) {
                    guard !model.isWorkflowRunning else { return }
                    model.duplicatePlan(plan.id)
                },
                .separator,
                .action("删除方案…", isEnabled: !model.isWorkflowRunning) { confirmsDelete = true }
            ])
        ]
    }

    private var taskList: some View {
        let statuses = taskStatuses
        let progress = model.continuation(for: plan.id)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text([accountSummary, scheduleSummary].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if model.planRunState(planID: plan.id) == .configurationIncomplete,
                   detailSection == .settings || progress.resumableRoundID == nil {
                    Button("检查配置") { model.readinessRequest = PlanReadinessRequest(id: plan.id) }
                        .buttonStyle(.link).fixedSize()
                } else if detailSection == .settings, !model.isFightRecoveryBusy,
                          let action = progress.blockingFightAction {
                    Button(action) { model.reviewFight(in: plan.id) }
                        .buttonStyle(.link).fixedSize()
                }
            }
            .font(.caption)
            .padding(.horizontal, 14).padding(.vertical, 9)
            Divider()

            List(selection: taskSelection) {
                ForEach(plan.stepOrder) { task in
                    taskRow(task, status: statuses.status(for: task))
                        .tag(task)
                        .moveDisabled(model.isWorkflowRunning)
                        .listRowInsets(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 10))
                        .contextMenu { taskMenu(task) }
                }
                .onMove { source, destination in
                    guard !model.isWorkflowRunning else { return }
                    plan.stepOrder.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .accessibilityLabel("执行顺序")
            .accessibilityHint("可在任务菜单中上移或下移")
        }
    }

    private func taskRow(_ task: TaskKind, status: PlanTaskStatus) -> some View {
        let summary = taskSummary(task)
        let fightBudget = task == .fight ? plan.fight.regularFightBudgetSummary : nil
        return HStack(spacing: 8) {
            Toggle("启用\(task.title)", isOn: enabledBinding(for: task))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(model.isWorkflowRunning)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.body.weight(.medium))
                    if let fightBudget {
                        Text(fightBudget)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !summary.isEmpty {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).help(summary)
                    }
                }
                Spacer(minLength: 0)
                PlanTaskFeedback(status: status)
            }
            .contentShape(Rectangle())
            // The list owns selection and dragging. A click on the already selected task also reopens its settings.
            .simultaneousGesture(TapGesture().onEnded { selectTask(task) }, including: detailSection == .activity ? .all : .none)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(model.isWorkflowRunning ? "查看" : "编辑")\(task.title)参数")
            .accessibilityValue([fightBudget, summary, status.description].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，"))
            .accessibilityAction { selectTask(task) }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func taskMenu(_ task: TaskKind) -> some View {
        Button(model.isWorkflowRunning ? "查看参数" : "编辑参数") {
            selectTask(task)
        }
        Button(plan.isEnabled(task) ? "停用任务" : "启用任务") {
            enabledBinding(for: task).wrappedValue.toggle()
        }
        .disabled(model.isWorkflowRunning)
        Divider()
        Button("上移") { move(task, by: -1) }
            .disabled(model.isWorkflowRunning || plan.stepOrder.first == task)
        Button("下移") { move(task, by: 1) }
            .disabled(model.isWorkflowRunning || plan.stepOrder.last == task)
    }

    private var targetAccountCount: Int {
        model.configuration.clients.filter(\.enabled).flatMap { $0.accounts.filter(plan.includes) }.count
    }

    private var accountSummary: String {
        targetAccountCount == 0 ? "尚未选择账号" : "\(targetAccountCount) 个账号"
    }

    private var scheduleSummary: String? {
        if model.isPlanScheduleCurrent(plan) {
            if plan.schedule.rules.count > 1 { return "定时 \(plan.schedule.rules.count) 个时段" }
            return "定时：\(PlanScheduleFormatter.summary(plan.schedule))"
        }
        if plan.schedule.enabled || model.installedPlanIDs.contains(plan.id) {
            return model.isSynchronizingSchedules ? "定时同步中" : "定时需检查"
        }
        return nil
    }

    private var isCurrentPlanRunning: Bool {
        model.isWorkflowRunning && model.activePlanID == plan.id
    }

    private var taskSelection: Binding<TaskKind?> {
        Binding(get: { selectedTask }, set: { task in
            selectedTask = task
            if task != nil { detailSection = .settings }
        })
    }

    private var taskStatuses: PlanTaskStatusSnapshot {
        PlanTaskStatusSnapshot(plan: plan, clients: model.configuration.clients,
            state: model.executionState, entries: model.activityEntries,
            weeklyAnnihilation: model.weeklyAnnihilation,
            activeRun: model.isWorkflowRunning ? .init(planID: model.activePlanID, runID: model.activeRunID,
                phase: model.activePhase, isCancelling: model.isCancellingRun) : nil,
            now: model.currentDate)
    }

    private func selectInitialTask() {
        selectedTask = plan.stepOrder.first
        detailSection = isCurrentPlanRunning ? .activity : .settings
        applyDetailRequest()
    }

    private func applyDetailRequest() {
        if model.fightSettingsPlanID == plan.id {
            model.fightSettingsPlanID = nil
            selectTask(.fight)
        } else if model.planActivityRequest == plan.id {
            model.planActivityRequest = nil
            detailSection = .activity
        }
    }

    private func selectTask(_ task: TaskKind) {
        selectedTask = task
        detailSection = .settings
    }

    private func move(_ task: TaskKind, by offset: Int) {
        guard !model.isWorkflowRunning,
              let index = plan.stepOrder.firstIndex(of: task),
              plan.stepOrder.indices.contains(index + offset)
        else { return }
        plan.stepOrder.swapAt(index, index + offset)
        selectedTask = task
    }

    private func enabledBinding(for task: TaskKind) -> Binding<Bool> {
        Binding {
            plan.isEnabled(task)
        } set: { enabled in
            guard !model.isWorkflowRunning else { return }
            switch task {
            case .fight: plan.fight.enabled = enabled
            case .recruit: plan.recruit.enabled = enabled
            case .infrast: plan.infrast.enabled = enabled
            case .mall: plan.mall.enabled = enabled
            case .award: plan.award.enabled = enabled
            }
        }
    }

    private func taskSummary(_ task: TaskKind) -> String {
        guard plan.isEnabled(task) else { return "" }
        switch task {
        case .fight:
            var parts: [String] = []
            if plan.fight.usesCustomSettings {
                parts.append(plan.fight.stageStrategy == .fixed ? plan.fight.stage : plan.fight.stageStrategy.title)
            }
            if plan.fight.weeklyAnnihilation.enabled { parts.append("每周剿灭") }
            return parts.joined(separator: " · ")
        case .recruit:
            guard plan.recruit.usesCustomSettings else { return "" }
            return "\(plan.recruit.times) 次" + (plan.recruit.expedite ? " · 使用加急许可" : "")
        case .infrast:
            return plan.infrast.usesCustomSettings ? plan.infrast.mode.title : ""
        case .mall:
            guard plan.mall.usesCustomSettings else { return "" }
            return [plan.mall.visitFriends ? "访友信用" : nil, plan.mall.shopping ? "商店购物" : nil, plan.mall.creditFight ? "信用作战" : nil]
                .compactMap { $0 }.joined(separator: " · ")
        case .award:
            guard plan.award.usesCustomSettings else { return "" }
            let count = [plan.award.dailyWeekly, plan.award.mail, plan.award.freeRecruit, plan.award.orundum, plan.award.mining, plan.award.specialAccess].filter { $0 }.count
            return "\(count) 项奖励"
        }
    }
}

private struct PlanTaskFeedback: View {
    let status: PlanTaskStatus

    var body: some View {
        Group {
            switch status {
            case .none: Color.clear
            case .running: ProgressView().controlSize(.small)
            case .success: symbol(.completed)
            case .failure: symbol(.failed)
            case .cancelled: Image(systemName: "slash.circle").foregroundStyle(.secondary)
            case .attention: symbol(.awaitingReview)
            }
        }
        .font(.system(size: 14))
        .frame(width: 18, height: 18)
        .help(status.description)
        .accessibilityHidden(true)
    }

    private func symbol(_ outcome: ActivityOutcome) -> some View {
        Image(systemName: outcome.symbol).foregroundStyle(outcome.color)
    }
}

private extension PlanTaskStatus {
    var description: String {
        switch self {
        case .none: ""
        case .running: "正在执行当前账号的任务"
        case .success: "所有目标账号均已完成"
        case .failure: "有任务执行失败，查看运行概况了解原因"
        case .cancelled: "任务已取消，尚未完成的部分可继续运行"
        case .attention: "有结果需要处理，查看运行概况"
        }
    }
}

private struct PlanRenameSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    @FocusState private var isFocused: Bool
    let onSave: (String) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("重命名方案").font(.headline)
            TextField("方案名称", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: FormWidth.shortText)
                .focused($isFocused)
                .disabled(model.isWorkflowRunning)
            if model.isWorkflowRunning {
                Text("运行结束后可保存").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Spacer()
                Button { dismiss() } label: {
                    Text("取消").frame(minWidth: 56)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    if onSave(name.trimmingCharacters(in: .whitespacesAndNewlines)) { dismiss() }
                } label: {
                    Text("保存").frame(minWidth: 56)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent).tint(.maaAction)
                .disabled(model.isWorkflowRunning || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380, height: 180, alignment: .topLeading)
        .focusedSceneValue(\.workspaceActive, false)
        .onAppear { isFocused = true }
    }
}
