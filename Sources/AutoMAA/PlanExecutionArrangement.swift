import AutoMAAKit
import SwiftUI

struct PlanArrangementRequest: Identifiable {
    let id: UUID
    let opensAtSchedule: Bool
}

struct PlanExecutionArrangement: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var includesAllEnabledAccounts: Bool
    @State private var accountIDs: Set<UUID>
    @State private var schedule: PlanSchedule
    @State private var policy: ExecutionPolicy
    @State private var error: String?
    private let planID: UUID
    private let planName: String

    private let opensAtSchedule: Bool

    init(plan: AutomationPlan, opensAtSchedule: Bool) {
        self.opensAtSchedule = opensAtSchedule
        planID = plan.id
        planName = plan.displayName
        _includesAllEnabledAccounts = State(initialValue: plan.includesAllEnabledAccounts)
        _accountIDs = State(initialValue: plan.accountIDs)
        _schedule = State(initialValue: plan.schedule)
        _policy = State(initialValue: plan.policy)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("执行安排").font(.headline)
                Text(planName).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            Divider()

            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error {
                            Label(error, systemImage: "exclamationmark.circle")
                                .font(.callout).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if model.isWorkflowRunning {
                            Label("运行结束后可修改执行安排", systemImage: "lock")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        accountSection
                        Divider()
                        scheduleSection.id("schedule")
                        Divider()
                        policySection
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("formContent")
                    .toggleStyle(.checkbox)
                    .disabled(model.isWorkflowRunning)
                }
                .onAppear {
                    if opensAtSchedule { reader.scrollTo("schedule", anchor: .top) }
                }
                .onChange(of: error) { _, message in
                    if message != nil { reader.scrollTo("formContent", anchor: .top) }
                }
            }

            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button { dismiss() } label: {
                    Text(model.isWorkflowRunning ? "关闭" : "取消").frame(minWidth: 56)
                }
                    .keyboardShortcut(.cancelAction)
                if !model.isWorkflowRunning {
                    Button(action: apply) {
                        Text("应用").frame(minWidth: 56)
                    }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent).tint(.maaAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 560, height: 520)
        .focusedSceneValue(\.workspaceActive, false)
    }

    private var accountSection: some View {
        PlanFormSection("执行账号 · \(targetAccountCount) 个") {
            Picker("账号范围", selection: $includesAllEnabledAccounts) {
                Text("所有已启用账号").tag(true)
                Text("指定账号").tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .fixedSize(horizontal: true, vertical: false)
            if model.configuration.clients.isEmpty {
                Text("请先在“客户端与账号”中添加客户端。")
                    .font(.callout).foregroundStyle(.secondary)
            } else if !includesAllEnabledAccounts {
                ForEach(model.configuration.clients) { client in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(client.displayName + (client.enabled ? "" : " · 已停用"))
                            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        if client.accounts.isEmpty {
                            Text("尚未添加账号").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(client.accounts) { account in
                            Toggle(account.displayName + (account.enabled ? "" : " · 已停用"), isOn: accountBinding(account.id))
                                .toggleStyle(.checkbox)
                                .disabled(!client.enabled || !account.enabled)
                        }
                    }
                }
            }
        }
    }

    private var scheduleSection: some View {
        PlanFormSection("定时运行") {
            Toggle("启用定时运行", isOn: $schedule.enabled)
                .help("AutoMAA 关闭后仍可定时运行。")
            if schedule.enabled {
                ForEach(Array(schedule.rules.enumerated()), id: \.element.id) { index, rule in
                    scheduleRule(rule, index: index)
                }
                Button("添加时段", systemImage: "plus", action: addScheduleRule)
                    .help("同一天可以安排多个时间，每个时段开启新一轮")
                Text("每个时段开启新一轮，作战额度重新计算。运行时 Mac 须保持唤醒、登录并解锁。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func scheduleRule(_ rule: WeeklyScheduleRule, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if index > 0 { Divider().padding(.vertical, 4) }
            HStack(spacing: 10) {
                Text("时段 \(index + 1)").font(.caption.weight(.medium))
                DatePicker("运行时间", selection: scheduleTime(rule.id), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .accessibilityLabel("时段 \(index + 1) 运行时间")
                    .fixedSize()
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    guard schedule.rules.count > 1 else { return }
                    schedule.rules.removeAll { $0.id == rule.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除时段 \(index + 1)")
                .accessibilityLabel("删除时段 \(index + 1)")
                .disabled(schedule.rules.count == 1)
            }
            HStack(spacing: 7) {
                ForEach(ScheduleWeekday.allCases) { weekday in
                    Toggle(weekday.shortTitle, isOn: weekdayBinding(weekday, ruleID: rule.id))
                        .toggleStyle(.button)
                        .help(weekday.title)
                        .accessibilityLabel("时段 \(index + 1) \(weekday.title)")
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private var policySection: some View {
        PlanFormSection("执行策略") {
            Toggle("运行前更新识别数据", isOn: $policy.hotUpdateBeforeRun)
            Stepper("单步失败重试 \(policy.maxRetries) 次", value: $policy.maxRetries, in: ExecutionPolicy.retryRange)
                .fixedSize(horizontal: true, vertical: false)
            Toggle("单步失败后继续其他步骤", isOn: $policy.continueAfterStepFailure)
        }
    }

    private var targetAccountCount: Int {
        model.configuration.clients.filter(\.enabled).flatMap { client in
            client.accounts.filter { $0.enabled && (includesAllEnabledAccounts || accountIDs.contains($0.id)) }
        }.count
    }

    private func accountBinding(_ id: UUID) -> Binding<Bool> {
        Binding {
            accountIDs.contains(id)
        } set: { included in
            if included { accountIDs.insert(id) }
            else { accountIDs.remove(id) }
        }
    }

    private func scheduleTime(_ id: UUID) -> Binding<Date> {
        Binding {
            let rule = schedule.rules.first { $0.id == id }
            return Calendar.current.date(bySettingHour: rule?.hour ?? 8, minute: rule?.minute ?? 0, second: 0, of: Date()) ?? Date()
        } set: { date in
            guard let index = schedule.rules.firstIndex(where: { $0.id == id }) else { return }
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            schedule.rules[index].hour = components.hour ?? 0
            schedule.rules[index].minute = components.minute ?? 0
        }
    }

    private func weekdayBinding(_ weekday: ScheduleWeekday, ruleID: UUID) -> Binding<Bool> {
        Binding {
            schedule.rules.first { $0.id == ruleID }?.weekdays.contains(weekday) == true
        } set: { enabled in
            guard let index = schedule.rules.firstIndex(where: { $0.id == ruleID }) else { return }
            if enabled { schedule.rules[index].weekdays.insert(weekday) }
            else { schedule.rules[index].weekdays.remove(weekday) }
        }
    }

    private func addScheduleRule() {
        if !schedule.addRule() { error = "所选星期的所有分钟都已安排，请调整现有时段" }
    }

    private func apply() {
        error = model.applyPlanExecutionArrangement(
            planID,
            includesAllEnabledAccounts: includesAllEnabledAccounts,
            accountIDs: accountIDs,
            schedule: schedule,
            policy: policy
        )
        if error == nil { dismiss() }
    }
}
