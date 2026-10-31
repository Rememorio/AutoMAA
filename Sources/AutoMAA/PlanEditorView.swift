import AutoMAAKit
import SwiftUI

private enum PlanDetailSection { case settings, activity }

struct PlanEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var plan: AutomationPlan
    @State private var selectedTask: TaskKind?
    @State private var showsArrangement = false
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
                    ContentUnavailableView("选择任务", systemImage: "slider.horizontal.3",
                                           description: Text("在执行顺序中选择要设置的任务。"))
                }
            case .activity:
                PlanActivityView(planID: plan.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .workspaceToolbar(title: plan.displayName) {
            Button {
                showsArrangement = true
            } label: {
                Label("执行安排…", systemImage: "calendar.badge.clock")
            }
            .help("执行安排 · 设置账号、定时与运行策略")
            .accessibilityLabel("执行安排")

            planMenu
        } detail: {
            Picker("右侧内容", selection: $detailSection) {
                Label("任务设置", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
                    .help("任务设置 · 调整所选任务的参数")
                    .accessibilityLabel("任务设置")
                    .tag(PlanDetailSection.settings)
                Label("运行概况", systemImage: "checklist")
                    .labelStyle(.iconOnly)
                    .help("运行概况 · 查看本方案今日待办、当前进度与最近结果")
                    .accessibilityLabel("运行概况")
                    .tag(PlanDetailSection.activity)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .accessibilityHint("切换所选任务的设置与本方案运行概况")
        }
        .onAppear { selectInitialTask() }
        .onChange(of: plan.id) { _, _ in selectInitialTask() }
        .onChange(of: isCurrentPlanRunning) { _, running in
            if running { detailSection = .activity }
        }
        .sheet(isPresented: $showsArrangement) {
            PlanExecutionArrangement(plan: plan)
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

    private var planMenu: some View {
        Menu {
            Button("重命名方案…") { showsRename = true }
                .disabled(model.isWorkflowRunning)
            Button("复制方案") {
                guard !model.isWorkflowRunning else { return }
                model.duplicatePlan(plan.id)
            }
            .disabled(model.isWorkflowRunning)
            Divider()
            Button("删除方案…", role: .destructive) { confirmsDelete = true }
                .disabled(model.isWorkflowRunning)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15))
                .frame(width: 28, height: 28)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("方案操作")
        .accessibilityLabel("方案操作")
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("执行顺序")
                        .font(.subheadline.weight(.medium))
                    Text("\(plan.enabledTasks.count) 项已启用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                Text("\(accountSummary) · \(scheduleSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            Divider()

            List(selection: $selectedTask) {
                ForEach(plan.stepOrder) { task in
                    taskRow(task)
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
            .onChange(of: selectedTask) { _, task in
                if task != nil { detailSection = .settings }
            }

            Text(model.isWorkflowRunning ? "运行结束后可调整任务与参数" : "拖动或使用右键菜单调整顺序")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func taskRow(_ task: TaskKind) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Toggle("启用\(task.title)", isOn: enabledBinding(for: task))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(model.isWorkflowRunning)
            Button {
                selectTask(task)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: task.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(plan.isEnabled(task) ? Color.maaAccent : .secondary)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).font(.body.weight(.medium))
                        Text(taskSummary(task))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(taskSummary(task))
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(model.isWorkflowRunning ? "查看" : "编辑")\(task.title)参数")
            .accessibilityValue(taskSummary(task))
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
        targetAccountCount == 0 ? "尚未选择账号" : "执行 \(targetAccountCount) 个账号"
    }

    private var scheduleSummary: String {
        if model.isPlanScheduleCurrent(plan) {
            return "定时：\(PlanScheduleFormatter.summary(plan.schedule))"
        }
        if plan.schedule.enabled || model.installedPlanIDs.contains(plan.id) {
            return model.isSynchronizingSchedules ? "定时同步中" : "定时需检查"
        }
        return "未设定时"
    }

    private var isCurrentPlanRunning: Bool {
        model.isWorkflowRunning && model.activePlanID == plan.id
    }

    private func selectInitialTask() {
        selectedTask = plan.stepOrder.first
        detailSection = isCurrentPlanRunning ? .activity : .settings
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
        switch task {
        case .fight:
            var parts = [plan.fight.usesCustomSettings ? (plan.fight.stageStrategy == .fixed ? plan.fight.stage : plan.fight.stageStrategy.title) : "MAA 推荐参数"]
            if plan.fight.usesCustomSettings, let times = plan.fight.times { parts.append("最多 \(times) 次") }
            if plan.fight.weeklyAnnihilation.enabled { parts.append("每周剿灭") }
            return parts.joined(separator: " · ")
        case .recruit:
            return plan.recruit.usesCustomSettings
                ? "\(plan.recruit.times) 次招募 · \(plan.recruit.expedite ? "使用加急许可" : "不使用加急许可")"
                : "MAA 推荐参数"
        case .infrast:
            return plan.infrast.usesCustomSettings ? plan.infrast.mode.title : "完整换班 · 心情 30%"
        case .mall:
            guard plan.mall.usesCustomSettings else { return "MAA 推荐参数" }
            return [plan.mall.visitFriends ? "访友信用" : nil, plan.mall.shopping ? "商店购物" : nil, plan.mall.creditFight ? "信用作战" : nil]
                .compactMap { $0 }.joined(separator: " · ")
        case .award:
            guard plan.award.usesCustomSettings else { return "日常与周常奖励" }
            let count = [plan.award.dailyWeekly, plan.award.mail, plan.award.freeRecruit, plan.award.orundum, plan.award.mining, plan.award.specialAccess].filter { $0 }.count
            return "\(count) 项奖励"
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
