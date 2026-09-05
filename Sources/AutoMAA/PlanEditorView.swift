import AppKit
import AutoMAAKit
import SwiftUI
import UniformTypeIdentifiers

struct PlanEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var plan: AutomationPlan
    @State private var confirmDelete = false
    @State private var useCustomFightStage = false
    @State private var fightStageEditor: FightStageEditorContext?

    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 14, alignment: .topLeading)]

    var body: some View {
        AppPage(width: PageLayout.contentWidth) {
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
        .navigationTitle(plan.displayName)
        .confirmationDialog("删除「\(plan.displayName)」？", isPresented: $confirmDelete) {
            Button("删除方案", role: .destructive) { model.deletePlan(plan.id) }
        } message: {
            Text("账号和客户端不会被删除，对应的系统定时任务会一并移除。")
        }
        .sheet(item: $fightStageEditor) { context in
            FightStageEditorSheet(context: context) { stage in
                model.setFightRecoveryStage(
                    stage,
                    clientID: context.clientID,
                    accountID: context.accountID
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            EntityIcon(symbol: "clock.arrow.circlepath")
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
                    SectionHeading(title: "执行账号", symbol: "person.2.fill")
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
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .topLeading)], alignment: .leading, spacing: 10) {
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
                    SectionHeading(title: "定时运行", symbol: "clock.badge.checkmark.fill")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { plan.schedule.enabled },
                        set: { model.setPlanScheduleEnabled(plan.id, $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("启用定时运行")
                    .disabled(model.isWorkflowRunning)
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
                    .disabled(model.isWorkflowRunning || plan.schedule.scheduledWeekdays.count == ScheduleWeekday.allCases.count)
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
                    .disabled(model.isWorkflowRunning)
                if plan.schedule.rules.count > 1 {
                    Button(role: .destructive) {
                        model.removePlanScheduleRule(plan.id, ruleID: rule.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("删除这个时段")
                    .accessibilityLabel("删除时段 \(index + 1)")
                    .disabled(model.isWorkflowRunning)
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
                            .frame(width: 30, height: 28)
                            .foregroundStyle(Color.primary)
                            .background(
                                selected ? Color.maaAccent.opacity(0.16) : Color.primary.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(selected ? Color.maaAccent : .clear, lineWidth: 1)
                            .allowsHitTesting(false)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isWorkflowRunning || (!selected && occupied))
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
                    SectionHeading(title: "步骤顺序", symbol: "arrow.up.arrow.down")
                    Spacer()
                    Text("每个方案独立记录当日完成状态")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), alignment: .leading)], spacing: 8) {
                    ForEach(Array(plan.stepOrder.enumerated()), id: \.element) { index, task in
                        HStack(spacing: 7) {
                            Text("\(index + 1)")
                                .font(.caption2.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: task.symbol)
                                .foregroundStyle(plan.isEnabled(task) ? Color.maaAccent : Color.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).font(.caption.weight(.medium))
                                if !plan.isEnabled(task) {
                                    Text("未启用").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                            ReorderButtons(name: task.title, index: index, count: plan.stepOrder.count) { move(task, by: $0) }
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
            Picker("关卡策略", selection: fightStageStrategy) {
                ForEach(FightStageStrategy.allCases) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }
            Text(plan.fight.stageStrategy.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if plan.fight.stageStrategy == .fixed {
                LabeledContent("关卡") {
                    if customFightStage.wrappedValue {
                        TextField("如 1-7 或活动关卡", text: $plan.fight.stage)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 190)
                    } else {
                        Picker("关卡", selection: $plan.fight.stage) {
                            ForEach(FightStagePreset.allCases.filter { $0 != .currentOrLast }) { preset in
                                Text(preset.title).tag(preset.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 190)
                    }
                }
                Toggle("手动输入关卡名", isOn: customFightStage)
            } else if plan.fight.stageStrategy == .rememberedRegular {
                VStack(alignment: .leading, spacing: 7) {
                    Text("账号恢复状态")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(fightStageMemoryRows) { row in
                        fightStageMemoryRow(row)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
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
            .tint(.maaAction)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), alignment: .leading)], alignment: .leading, spacing: 7) {
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
                SectionHeading(title: "执行策略", symbol: "arrow.clockwise.circle.fill")
                Divider()
                Toggle("运行前更新识别数据", isOn: $plan.policy.hotUpdateBeforeRun)
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

    private var fightStageMemoryRows: [FightStageMemoryRow] {
        model.configuration.clients.filter(\.enabled).flatMap { client in
            client.accounts.filter(plan.includes).map { account in
                let entry = model.fightStageMemory.entry(clientID: client.id, accountID: account.id)
                return FightStageMemoryRow(
                    clientID: client.id,
                    accountID: account.id,
                    label: "\(client.displayName) / \(account.displayName)",
                    stage: entry?.stage,
                    recoveryRequired: entry?.recoveryRequiredAt != nil
                )
            }
        }
    }

    private func fightStageMemoryRow(_ row: FightStageMemoryRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: row.recoveryRequired ? "arrow.uturn.backward.circle.fill" : "location.fill")
                    .foregroundStyle(row.recoveryRequired ? Color.orange : Color.maaAccent)
                Text(row.label)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.recoveryRequired ? "待恢复" : "跟随游戏")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(row.recoveryRequired ? Color.orange : Color.secondary)
            }
            HStack(spacing: 8) {
                Text(fightStageStatusText(row))
                    .font(.caption)
                    .foregroundStyle(row.recoveryRequired && row.stage == nil ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(row.stage == nil ? "设置备用关卡" : "修改") {
                    fightStageEditor = FightStageEditorContext(row: row)
                }
                .controlSize(.small)
                .disabled(model.isWorkflowRunning)
            }
            if row.recoveryRequired {
                Button("游戏已手动切回，继续跟随") {
                    model.continueFollowingGameStage(clientID: row.clientID, accountID: row.accountID)
                }
                .controlSize(.small)
                .disabled(model.isWorkflowRunning)
                .help("确认游戏当前/上次已是常规关卡，并取消这次自动恢复")
            }
        }
        .padding(.vertical, 3)
    }

    private func fightStageStatusText(_ row: FightStageMemoryRow) -> String {
        if row.recoveryRequired {
            return row.stage.map { "下次理智作战将先恢复到 \($0)" }
                ?? "缺少恢复关卡，运行前检查会阻止理智作战"
        }
        return row.stage.map { "备用常规关卡：\($0)；成功作战后自动更新" }
            ?? "首次成功完成常规作战后会自动记住备用关卡"
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
            if !enabled { plan.fight.stage = FightStagePreset.oneSeven.rawValue }
            useCustomFightStage = enabled
        }
    }

    private var fightStageStrategy: Binding<FightStageStrategy> {
        Binding {
            plan.fight.stageStrategy
        } set: { strategy in
            plan.fight.stageStrategy = strategy
            if strategy == .fixed,
               plan.fight.stage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                plan.fight.stage = FightStagePreset.oneSeven.rawValue
            }
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

private struct FightStageMemoryRow: Identifiable {
    let clientID: UUID
    let accountID: UUID
    let label: String
    let stage: String?
    let recoveryRequired: Bool

    var id: String { "\(clientID.uuidString)-\(accountID.uuidString)" }
}

private struct FightStageEditorContext: Identifiable {
    let clientID: UUID
    let accountID: UUID
    let label: String
    let stage: String?
    let recoveryRequired: Bool

    init(row: FightStageMemoryRow) {
        clientID = row.clientID
        accountID = row.accountID
        label = row.label
        stage = row.stage
        recoveryRequired = row.recoveryRequired
    }

    var id: String { "\(clientID.uuidString)-\(accountID.uuidString)" }
}

private struct FightStageEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool
    @State private var stage: String

    let context: FightStageEditorContext
    let onSave: (String) -> Bool

    init(context: FightStageEditorContext, onSave: @escaping (String) -> Bool) {
        self.context = context
        self.onSave = onSave
        _stage = State(initialValue: context.stage ?? "")
    }

    private var normalizedStage: String? {
        FightStagePolicy.regularStage(from: stage, times: 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(context.recoveryRequired ? "设置剿灭恢复关卡" : "设置备用常规关卡")
                    .font(.title3.weight(.semibold))
                Text(context.label)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(context.recoveryRequired
                 ? "下次理智作战会先明确返回这个关卡；成功后恢复状态自动清除。"
                 : "平时仍跟随游戏当前/上次；只有 AutoMAA 执行剿灭后才会使用这个关卡恢复。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("关卡") {
                TextField("关卡", text: $stage, prompt: Text("如 1-7 或活动关卡"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .frame(minWidth: 220)
            }
            if !stage.isEmpty, normalizedStage == nil {
                Label("请输入 1 到 128 个字符的非剿灭关卡名", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.orange)
            }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(context.recoveryRequired ? "保存恢复关卡" : "保存备用关卡") {
                    guard let normalizedStage, onSave(normalizedStage) else { return }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(normalizedStage == nil)
            }
        }
        .padding(20)
        .frame(width: 430)
        .onAppear { fieldFocused = true }
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
                            .accessibilityLabel("\(task.title)自定义参数")
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
