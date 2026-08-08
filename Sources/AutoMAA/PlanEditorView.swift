import AppKit
import AutoMAAKit
import SwiftUI
import UniformTypeIdentifiers

struct PlanEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var plan: AutomationPlan
    @State private var confirmDelete = false
    @State private var useCustomFightStage = false

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                targetPanel
                schedulePanel
                orderPanel
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    fightCard
                    recruitCard
                    infrastCard
                    mallCard
                    awardCard
                    policyCard
                }
                actions
            }
            .padding(28)
            .frame(maxWidth: 1_060)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(plan.displayName)
        .confirmationDialog("删除「\(plan.displayName)」？", isPresented: $confirmDelete) {
            Button("删除方案", role: .destructive) { model.deletePlan(plan.id) }
        } message: {
            Text("账号和客户端不会被删除，对应的系统定时任务会一并移除。")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.maaAccent.opacity(0.12))
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(Color.maaAccent)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 5) {
                EditableDisplayNameField(label: "方案名称", placeholder: "例如：工作日早晨", text: $plan.name)
                Text("\(targetAccounts.count) 个账号 · \(plan.enabledTasks.count) 个步骤")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            PlanRunButton(planID: plan.id, readyTitle: "立即运行", controlSize: .large)
                .fontWeight(.semibold)
        }
    }

    private var targetPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("执行账号", systemImage: "person.2.fill")
                        .font(.headline)
                    Spacer()
                    Toggle("所有已启用账号", isOn: $plan.includesAllEnabledAccounts)
                        .toggleStyle(.switch)
                }
                Text("使用“所有已启用账号”时，今后新添加的账号会自动加入；关闭后可精确选择。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !plan.includesAllEnabledAccounts {
                    Divider()
                    if model.configuration.clients.isEmpty {
                        Text("请先添加客户端和账号")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.configuration.clients) { client in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(client.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 16) {
                                    ForEach(client.accounts) { account in
                                        Toggle(account.displayName, isOn: accountBinding(account.id))
                                            .toggleStyle(.checkbox)
                                            .disabled(!client.enabled || !account.enabled)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var schedulePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("定时运行", systemImage: "clock.badge.checkmark.fill")
                        .font(.headline)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { plan.schedule.enabled },
                        set: { model.setPlanScheduleEnabled(plan.id, $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(model.isRunning)
                }
                ForEach(Array(plan.schedule.rules.enumerated()), id: \.element.id) { index, rule in
                    scheduleRuleRow(rule, index: index)
                }
                HStack {
                    Button {
                        model.addPlanScheduleRule(plan.id)
                    } label: {
                        Label("添加时段", systemImage: "plus")
                    }
                    .disabled(model.isRunning || plan.schedule.scheduledWeekdays.count == ScheduleWeekday.allCases.count)
                    .help(plan.schedule.scheduledWeekdays.count == ScheduleWeekday.allCases.count
                          ? "先从现有时段取消一个星期"
                          : "为尚未安排的星期添加另一个时间")
                    Spacer()
                    if plan.schedule.enabled {
                        Label("修改后自动应用", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    StatusDot(color: scheduleStatusColor)
                    Text(scheduleStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("macOS 会在登录会话中独立唤起，无需保持 AutoMAA 打开。若需准时执行，请接通电源、保持系统唤醒且不要停留在锁屏；显示器可以单独熄灭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scheduleRuleRow(_ rule: WeeklyScheduleRule, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("时段 \(index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                DatePicker("时间", selection: scheduleTime(rule), displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .disabled(model.isRunning)
                if plan.schedule.rules.count > 1 {
                    Button(role: .destructive) {
                        model.removePlanScheduleRule(plan.id, ruleID: rule.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("删除这个时段")
                    .disabled(model.isRunning)
                }
            }
            HStack(spacing: 7) {
                ForEach(ScheduleWeekday.allCases) { weekday in
                    let selected = rule.weekdays.contains(weekday)
                    let occupied = usedWeekdays(excluding: rule.id).contains(weekday)
                    Button {
                        model.togglePlanScheduleWeekday(plan.id, ruleID: rule.id, weekday: weekday)
                    } label: {
                        Text(weekday.shortTitle)
                            .font(.caption.weight(.semibold))
                            .frame(width: 28, height: 24)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(
                                selected ? Color.maaAccent : Color.primary.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isRunning || (!selected && occupied))
                    .opacity(!selected && occupied ? 0.35 : 1)
                    .help(occupied && !selected ? "已由其他时段使用\(weekday.title)" : weekday.title)
                    .accessibilityLabel(weekday.title)
                    .accessibilityValue(selected ? "已选择" : "未选择")
                }
                Spacer()
            }
        }
        .padding(11)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var orderPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("步骤顺序", systemImage: "arrow.up.arrow.down")
                        .font(.headline)
                    Spacer()
                    Text("每个方案独立记录当日完成状态")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(Array(plan.stepOrder.enumerated()), id: \.element) { index, task in
                        HStack(spacing: 7) {
                            Text("\(index + 1)")
                                .font(.caption2.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: task.symbol)
                                .foregroundStyle(plan.isEnabled(task) ? Color.maaAccent : Color.secondary)
                            Text(task.title)
                                .font(.caption.weight(.medium))
                            VStack(spacing: 0) {
                                Button { move(task, by: -1) } label: { Image(systemName: "chevron.left") }
                                    .disabled(index == 0)
                                Button { move(task, by: 1) } label: { Image(systemName: "chevron.right") }
                                    .disabled(index == plan.stepOrder.count - 1)
                            }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var fightCard: some View {
        PlanTaskCard(task: .fight, enabled: $plan.fight.enabled, usesCustomSettings: $plan.fight.usesCustomSettings) {
            LabeledContent("关卡") {
                if customFightStage.wrappedValue {
                    TextField("如 1-7 或活动关卡", text: $plan.fight.stage)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                } else {
                    Picker("关卡", selection: $plan.fight.stage) {
                        ForEach(FightStagePreset.allCases) { preset in
                            Text(preset.title).tag(preset.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
            }
            Toggle("手动输入关卡名", isOn: customFightStage)
            Divider()
            optionalStepper("吃理智药", value: $plan.fight.medicine, defaultValue: 999, range: 0...999)
            optionalStepper("使用临期理智药（天数）", value: $plan.fight.medicineExpireDays, defaultValue: 2, range: 1...365)
            optionalStepper("吃源石", value: $plan.fight.stone, defaultValue: 0, range: 0...99)
            optionalStepper("指定次数", value: $plan.fight.times, defaultValue: 5, range: 1...9_999)
            Picker("连战次数", selection: $plan.fight.series) {
                Text("保持当前").tag(Int?.none)
                Text("关闭连战").tag(Int?.some(-1))
                Text("AUTO").tag(Int?.some(0))
                ForEach((1...10).reversed(), id: \.self) { value in
                    Text("\(value)").tag(Int?.some(value))
                }
            }
            Divider()
            Toggle("博朗台碎石模式", isOn: $plan.fight.drGrandet)
        }
    }

    private var recruitCard: some View {
        PlanTaskCard(task: .recruit, enabled: $plan.recruit.enabled, usesCustomSettings: $plan.recruit.usesCustomSettings) {
            Stepper("招募次数：\(plan.recruit.times)", value: $plan.recruit.times, in: 0...12)
            Toggle("刷新标签", isOn: $plan.recruit.refresh)
            Toggle("使用加急许可", isOn: $plan.recruit.expedite)
            Divider()
            Text("自动确认星级")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Toggle("3★", isOn: $plan.recruit.autoConfirm3)
                Toggle("4★", isOn: $plan.recruit.autoConfirm4)
                Toggle("5★", isOn: $plan.recruit.autoConfirm5)
                Toggle("6★", isOn: $plan.recruit.autoConfirm6)
            }
            .toggleStyle(.checkbox)
            Picker("额外标签策略", selection: $plan.recruit.extraTagsMode) {
                ForEach(RecruitExtraTagsMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            LabeledContent("三星首选标签") {
                TextField("可留空", text: stringList($plan.recruit.firstTags))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
            }
            LabeledContent("保留并跳过") {
                TextField("例如 支援机械", text: stringList($plan.recruit.preserveTags))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
            }
        }
    }

    private var infrastCard: some View {
        PlanTaskCard(task: .infrast, enabled: $plan.infrast.enabled, usesCustomSettings: $plan.infrast.usesCustomSettings) {
            Picker("基建模式", selection: $plan.infrast.mode) {
                ForEach(InfrastMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            Text(plan.infrast.mode.detail)
                .font(.caption)
                .foregroundStyle(plan.infrast.mode == .collectOnly ? Color.maaAccent : Color.secondary)
            if plan.infrast.mode == .customSchedule {
                Divider()
                Text("排班文件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("MAA 基建排班 JSON", text: $plan.infrast.customSchedulePath)
                        .textFieldStyle(.roundedBorder)
                    Button("选择…") { chooseInfrastSchedule() }
                }
                Stepper("方案序号：\(plan.infrast.customSchedulePlanIndex)", value: $plan.infrast.customSchedulePlanIndex, in: 0...99)
            } else {
                Divider()
                Text("处理设施")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 7) {
                    ForEach(InfrastFacility.allCases) { facility in
                        Toggle(facility.title, isOn: facilityBinding(facility))
                            .toggleStyle(.checkbox)
                    }
                }
                Picker("无人机用途", selection: $plan.infrast.drones) {
                    ForEach(DroneUsage.allCases) { usage in Text(usage.title).tag(usage) }
                }
                if plan.infrast.mode == .fullShift {
                    Divider()
                    Text("上岗最低心情：\(Int(plan.infrast.threshold * 100))%")
                    Slider(value: $plan.infrast.threshold, in: 0...1, step: 0.05)
                    Text("仅筛选本次换班时的候选干员，不会在心情降到该值时自动换班。每天完整换班一次建议 90%；降低阈值会增加可选干员，但可能在下次换班前疲劳。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("宿舍空位补信赖未满干员", isOn: $plan.infrast.dormTrust)
                    Toggle("不将已进驻干员放入宿舍", isOn: $plan.infrast.dormNotStationed)
                    Toggle("源石碎片自动补货", isOn: $plan.infrast.replenish)
                    Toggle("训练完成后继续尝试专精", isOn: $plan.infrast.continueTraining)
                }
            }
            Divider()
            Toggle("领取会客室信息板信用", isOn: $plan.infrast.receptionMessageBoard)
            Toggle("进行线索交流", isOn: $plan.infrast.receptionClueExchange)
            Toggle("赠送线索", isOn: $plan.infrast.receptionSendClue)
        }
    }

    private var mallCard: some View {
        PlanTaskCard(task: .mall, enabled: $plan.mall.enabled, usesCustomSettings: $plan.mall.usesCustomSettings) {
            Toggle("访问好友基建领取信用", isOn: $plan.mall.visitFriends)
            Toggle("在信用商店购物", isOn: $plan.mall.shopping)
            if plan.mall.shopping {
                Divider()
                LabeledContent("优先购买") {
                    TextField("招聘许可、龙门币", text: stringList($plan.mall.buyFirst))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 210)
                }
                LabeledContent("购物黑名单") {
                    TextField("家具零件", text: stringList($plan.mall.blacklist))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 210)
                }
                Toggle("信用溢出时无视黑名单", isOn: $plan.mall.forceShoppingIfCreditFull)
                Toggle("只购买折扣物品", isOn: $plan.mall.onlyBuyDiscount)
                Toggle("保留 300 信用", isOn: $plan.mall.reserveMaxCredit)
            }
            Divider()
            Toggle("借助战打一局 OF-1 赚次日信用", isOn: $plan.mall.creditFight)
            if plan.mall.creditFight {
                Picker("编队", selection: $plan.mall.formationIndex) {
                    Text("当前编队").tag(0)
                    ForEach(1...4, id: \.self) { Text("第 \($0) 编队").tag($0) }
                }
            }
        }
    }

    private var awardCard: some View {
        PlanTaskCard(task: .award, enabled: $plan.award.enabled, usesCustomSettings: $plan.award.usesCustomSettings) {
            Toggle("日常与周常奖励", isOn: $plan.award.dailyWeekly)
            Toggle("邮件", isOn: $plan.award.mail)
            Toggle("免费单抽", isOn: $plan.award.freeRecruit)
            Toggle("幸运墙 / 签到", isOn: $plan.award.orundum)
            Toggle("限时采矿", isOn: $plan.award.mining)
            Toggle("活动专属赠送", isOn: $plan.award.specialAccess)
        }
    }

    private var policyCard: some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                Label("执行策略", systemImage: "arrow.clockwise.circle.fill")
                    .font(.headline)
                Divider()
                Toggle("运行前热更新 MAA 资源", isOn: $plan.policy.hotUpdateBeforeRun)
                Stepper("单步骤失败重试：\(plan.policy.maxRetries) 次", value: $plan.policy.maxRetries, in: 0...3)
                Toggle("某一步失败后继续后续步骤", isOn: $plan.policy.continueAfterStepFailure)
                Text("同一方案当天重跑会跳过已成功步骤；不同方案的完成状态彼此隔离。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button("复制方案") { model.duplicatePlan(plan.id) }
            Spacer()
            Button("删除方案", role: .destructive) { confirmDelete = true }
        }
        .padding(.top, 4)
    }

    private var targetAccounts: [AccountConfiguration] {
        model.configuration.clients.filter(\.enabled).flatMap { $0.accounts.filter(plan.includes) }
    }

    private var scheduleInstalled: Bool {
        model.installedPlanIDs.contains(plan.id)
    }

    private var scheduleStatusColor: Color {
        if scheduleProblem != nil || scheduleConflict != nil { return .orange }
        if plan.schedule.enabled {
            if model.isPlanScheduleCurrent(plan) { return .green }
            return model.isSynchronizingSchedules ? .maaAccent : .red
        }
        return scheduleInstalled ? .red : .secondary
    }

    private var scheduleStatusText: String {
        if let scheduleProblem {
            return scheduleProblem.message(planName: plan.displayName)
        }
        if let scheduleConflict {
            let time = PlanScheduleFormatter.time(hour: scheduleConflict.slot.hour, minute: scheduleConflict.slot.minute)
            return "与「\(scheduleConflict.firstPlanName)」的\(scheduleConflict.slot.weekday.title) \(time) 冲突"
        }
        if plan.schedule.enabled {
            if model.isPlanScheduleCurrent(plan) {
                let next = PlanScheduleFormatter.nextRunLabel(plan.schedule).map { " · 下次 \($0)" } ?? ""
                return "已启用 · \(PlanScheduleFormatter.summary(plan.schedule))\(next)"
            }
            if model.isSynchronizingSchedules { return "正在同步系统定时任务…" }
            return scheduleInstalled
                ? "系统定时任务与当前设置不一致，请重新切换开关"
                : "系统定时任务未安装，请重新切换开关"
        }
        if scheduleInstalled {
            return model.isSynchronizingSchedules
                ? "正在移除系统定时任务…"
                : "系统定时任务仍存在，请重新开启后关闭"
        }
        return "关闭时不会自动运行"
    }

    private var scheduleProblem: PlanScheduleProblem? {
        PlanScheduleValidator.problem(in: plan.schedule)
    }

    private var scheduleConflict: PlanScheduleConflict? {
        guard plan.schedule.enabled else { return nil }
        return model.scheduleConflict(planID: plan.id, schedule: plan.schedule)
    }

    private func usedWeekdays(excluding ruleID: UUID) -> Set<ScheduleWeekday> {
        plan.schedule.rules
            .filter { $0.id != ruleID }
            .reduce(into: []) { $0.formUnion($1.weekdays) }
    }

    private func scheduleTime(_ rule: WeeklyScheduleRule) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: rule.hour, minute: rule.minute, second: 0, of: Date()) ?? Date()
        } set: { date in
            let components = Calendar.current.dateComponents([.hour, .minute], from: date)
            model.setPlanScheduleRuleTime(
                plan.id,
                ruleID: rule.id,
                hour: components.hour ?? 0,
                minute: components.minute ?? 0
            )
        }
    }

    private func accountBinding(_ accountID: UUID) -> Binding<Bool> {
        Binding {
            plan.accountIDs.contains(accountID)
        } set: { included in
            if included { plan.accountIDs.insert(accountID) }
            else { plan.accountIDs.remove(accountID) }
        }
    }

    private func facilityBinding(_ facility: InfrastFacility) -> Binding<Bool> {
        Binding {
            plan.infrast.facilities.contains(facility)
        } set: { enabled in
            if enabled { plan.infrast.facilities.append(facility) }
            else { plan.infrast.facilities.removeAll { $0 == facility } }
        }
    }

    private func stringList(_ values: Binding<[String]>) -> Binding<String> {
        Binding {
            values.wrappedValue.joined(separator: "、")
        } set: { text in
            values.wrappedValue = text
                .components(separatedBy: CharacterSet(charactersIn: "、,，;；"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    private func chooseInfrastSchedule() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        if !plan.infrast.customSchedulePath.isEmpty {
            panel.directoryURL = URL(filePath: plan.infrast.customSchedulePath).deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url {
            plan.infrast.customSchedulePath = url.path
        }
    }

    private func move(_ task: TaskKind, by offset: Int) {
        guard let index = plan.stepOrder.firstIndex(of: task) else { return }
        let destination = index + offset
        guard plan.stepOrder.indices.contains(destination) else { return }
        plan.stepOrder.swapAt(index, destination)
    }

    private var customFightStage: Binding<Bool> {
        Binding {
            useCustomFightStage || FightStagePreset(rawValue: plan.fight.stage) == nil
        } set: { enabled in
            if !enabled { plan.fight.stage = FightStagePreset.currentOrLast.rawValue }
            useCustomFightStage = enabled
        }
    }

    private func optionalToggle(_ value: Binding<Int?>, defaultValue: Int) -> Binding<Bool> {
        Binding {
            value.wrappedValue != nil
        } set: { enabled in
            value.wrappedValue = enabled ? (value.wrappedValue ?? defaultValue) : nil
        }
    }

    private func optionalValue(_ value: Binding<Int?>, defaultValue: Int) -> Binding<Int> {
        Binding { value.wrappedValue ?? defaultValue } set: { value.wrappedValue = $0 }
    }

    private func optionalStepper(
        _ title: String,
        value: Binding<Int?>,
        defaultValue: Int,
        range: ClosedRange<Int>
    ) -> some View {
        HStack {
            Toggle(title, isOn: optionalToggle(value, defaultValue: defaultValue))
            Spacer()
            if value.wrappedValue != nil {
                Stepper("\(value.wrappedValue ?? defaultValue)", value: optionalValue(value, defaultValue: defaultValue), in: range)
                    .fixedSize()
            }
        }
    }
}

private struct PlanTaskCard<Content: View>: View {
    let task: TaskKind
    @Binding var enabled: Bool
    @Binding var usesCustomSettings: Bool
    let content: Content

    init(
        task: TaskKind,
        enabled: Binding<Bool>,
        usesCustomSettings: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.task = task
        _enabled = enabled
        _usesCustomSettings = usesCustomSettings
        self.content = content()
    }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 10) {
                    TaskIcon(task: task, enabled: enabled)
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(enabled ? Color.primary : Color.secondary)
                    Spacer()
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("启用\(task.title)")
                }
                VStack(alignment: .leading, spacing: 11) {
                    Divider()
                    HStack {
                        Text("参数")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("自定义参数", isOn: $usesCustomSettings)
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                    }
                    if usesCustomSettings {
                        VStack(alignment: .leading, spacing: 9) { content }
                    } else {
                        Label(defaultSummary, systemImage: "arrow.uturn.backward.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.48)
            }
        }
    }

    private var defaultSummary: String {
        switch task {
        case .fight: "MAA 推荐默认：当前/上次关卡，不使用理智药或源石，不限制次数。"
        case .recruit: "MAA 推荐默认：4 次、不加急，自动确认 3★/4★/5★并保留支援机械。"
        case .infrast: "MAA 推荐默认：对全部设施执行常规换班，不使用无人机，上岗最低心情为 30%。"
        case .mall: "MAA 推荐默认：访友领信用并按推荐清单购物。"
        case .award: "MAA 推荐默认：只领取每日与每周任务奖励。"
        }
    }
}
