import AppKit
import AutoMAAKit
import SwiftUI
import UniformTypeIdentifiers

struct PlanTaskInspector: View {
    @EnvironmentObject private var model: AppModel
    @Binding var plan: AutomationPlan
    let task: TaskKind
    @State private var useCustomFightStage: Bool?
    @State private var fightStageEditor: FightStageEditorContext?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label(task.title, systemImage: task.symbol)
                    .font(.headline)
                Text("第 \((plan.stepOrder.firstIndex(of: task) ?? 0) + 1) 项 · 对 \(targetAccounts.count) 个账号分别执行")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !plan.isEnabled(task) {
                        Text("任务已停用，参数仍会保留。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.isWorkflowRunning {
                        Label("运行结束后可修改参数", systemImage: "lock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    parameterMode
                    parameters
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .toggleStyle(.checkbox)
                .disabled(model.isWorkflowRunning)
            }
            .id("\(plan.id.uuidString)-\(task.rawValue)")
        }
        .onChange(of: plan.id) { _, _ in useCustomFightStage = nil }
        .sheet(item: $fightStageEditor) { context in
            FightStageEditorSheet(context: context) { stage in
                guard !model.isWorkflowRunning else { return "运行结束后可保存。" }
                if model.setFightRecoveryStage(stage, clientID: context.clientID, accountID: context.accountID) { return nil }
                return model.feedback.notice?.message ?? "常规目标未能保存，请重试。"
            }
        }
    }

    private var parameterMode: some View {
        Picker("参数模式", selection: usesCustomSettings) {
            Text("MAA 推荐参数").tag(false)
            Text("自定义参数").tag(true)
        }
        .pickerStyle(.menu)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityLabel("\(task.title)参数模式")
        .help("切回推荐参数仍保留自定义值")
    }

    @ViewBuilder
    private var parameters: some View {
        if usesCustomSettings.wrappedValue {
            switch task {
            case .fight: fightParameters
            case .recruit: recruitParameters
            case .infrast: infrastParameters
            case .mall: mallParameters
            case .award: awardParameters
            }
        } else {
            Text(recommendedSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if task == .fight {
            weeklyAnnihilation
            fightRecovery
            fightAccountDetails
        }
    }

    private var fightParameters: some View {
        VStack(alignment: .leading, spacing: 20) {
            PlanFormSection("常规作战") {
                Picker("关卡策略", selection: fightStageStrategy) {
                    ForEach(FightStageStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .help(plan.fight.stageStrategy.detail)
                if let stageStrategyHint { parameterHint(stageStrategyHint) }
                if plan.fight.stageStrategy == .fixed {
                    if customFightStage.wrappedValue {
                        HStack(spacing: 8) {
                            Text("关卡")
                            TextField("如 1-7 或活动关卡", text: $plan.fight.stage)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: FormWidth.stage)
                                .accessibilityLabel("固定关卡")
                        }
                    } else {
                        Picker("关卡", selection: $plan.fight.stage) {
                            if FightStagePreset(rawValue: plan.fight.stage) == nil {
                                Text("自定义：\(plan.fight.stage)").tag(plan.fight.stage)
                            }
                            ForEach(FightStagePreset.allCases.filter { $0 != .currentOrLast }) { preset in
                                Text(preset.title).tag(preset.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    Toggle("手动输入关卡名", isOn: customFightStage)
                    if plan.fight.stage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parameterHint("填写要执行的固定关卡。", warning: true)
                    }
                }
                HStack(spacing: 8) {
                    Text("兜底关卡")
                    TextField("可选，留空关闭", text: $plan.fight.fallbackStage)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: FormWidth.stage)
                        .accessibilityLabel("兜底关卡，留空关闭")
                        .help(fallbackExplanation)
                }
                if !plan.fight.fallbackStage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parameterHint(fallbackExplanation)
                }
            }
            PlanFormSection("理智与次数") {
                optionalStepper("临期理智药", field: .medicineExpireDays, value: $plan.fight.medicineExpireDays, defaultValue: 2, range: 1...365, unit: "天内")
                if let days = plan.fight.medicineExpireDays {
                    parameterHint("使用 \(days) 天\(days == 2 ? "（48 小时）" : "")内过期的理智药，独立于普通药额度。")
                }
                optionalStepper("普通理智药额度", field: .medicine, value: $plan.fight.medicine, defaultValue: 999, range: 0...999, unit: "瓶")
                optionalStepper("源石额度", field: .stone, value: $plan.fight.stone, defaultValue: 0, range: 0...99, unit: "颗")
                optionalStepper("限制作战次数", field: .times, value: $plan.fight.times, defaultValue: 5, range: 1...9_999, unit: "次")
                Picker("连战次数", selection: $plan.fight.series) {
                    Text("MAA 默认（1 次）").tag(Int?.none)
                    Text("保持游戏连战次数").tag(Int?.some(-1))
                    Text("AUTO").tag(Int?.some(0))
                    ForEach(1...10, id: \.self) { value in
                        Text("\(value) 次").tag(Int?.some(value))
                    }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                Toggle("博朗台碎石模式", isOn: $plan.fight.drGrandet)
                parameterHint("额度对各账号分别计算；关闭可选项沿用 MAA 默认。")
            }
        }
    }

    private var weeklyAnnihilation: some View {
        PlanFormSection("每周剿灭") {
            Toggle("每周优先剿灭", isOn: $plan.fight.weeklyAnnihilation.enabled)
            if plan.fight.weeklyAnnihilation.enabled {
                Picker("本周开始日", selection: $plan.fight.weeklyAnnihilation.startDay) {
                    ForEach(ScheduleWeekday.allCases) { day in Text(day.title).tag(day) }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                parameterHint("仅用自然理智；按各服游戏周计算，账号进度跨方案共享。")
            }
        }
    }

    private var recruitParameters: some View {
        VStack(alignment: .leading, spacing: 20) {
            PlanFormSection("招募安排") {
                Stepper("招募次数：\(plan.recruit.times)", value: $plan.recruit.times, in: 0...12)
                    .fixedSize(horizontal: true, vertical: false)
                Toggle("刷新招募标签", isOn: $plan.recruit.refresh)
                Toggle("使用加急许可", isOn: $plan.recruit.expedite)
            }
            PlanFormSection("自动确认星级") {
                HStack(spacing: 12) {
                    Toggle("3 星", isOn: $plan.recruit.autoConfirm3)
                    Toggle("4 星", isOn: $plan.recruit.autoConfirm4)
                    Toggle("5 星", isOn: $plan.recruit.autoConfirm5)
                    Toggle("6 星", isOn: $plan.recruit.autoConfirm6)
                }
                .toggleStyle(.checkbox)
            }
            PlanFormSection("标签策略") {
                Picker("额外标签", selection: $plan.recruit.extraTagsMode) {
                    ForEach(RecruitExtraTagsMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                listField("三星首选标签", prompt: "可留空", values: $plan.recruit.firstTags)
                listField("保留并跳过", prompt: "例如 支援机械", values: $plan.recruit.preserveTags)
            }
        }
    }

    private var infrastParameters: some View {
        VStack(alignment: .leading, spacing: 20) {
            PlanFormSection("基建安排") {
                Picker("基建模式", selection: $plan.infrast.mode) {
                    ForEach(InfrastMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.menu)
                .fixedSize(horizontal: true, vertical: false)
                .help(plan.infrast.mode.detail)
                if plan.infrast.mode == .collectOnly {
                    parameterHint("收取产物，并处理无人机与会客室。")
                }
                if plan.infrast.mode == .customSchedule {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MAA 排班文件").font(.callout)
                        HStack(spacing: 8) {
                            TextField("排班 JSON 文件", text: $plan.infrast.customSchedulePath)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel("MAA 排班文件")
                            ActionTextButton(title: "选择文件…", symbol: "folder", help: "选择 MAA 排班文件…") {
                                chooseInfrastSchedule()
                            }
                        }
                    }
                    Stepper("方案序号：\(plan.infrast.customSchedulePlanIndex)", value: $plan.infrast.customSchedulePlanIndex, in: 0...99)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Picker("无人机用途", selection: $plan.infrast.drones) {
                        ForEach(DroneUsage.allCases) { usage in Text(usage.title).tag(usage) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            if plan.infrast.mode != .customSchedule {
                PlanFormSection("处理设施") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 10) {
                        ForEach(InfrastFacility.allCases) { facility in
                            Toggle(facility.title, isOn: facilityBinding(facility))
                                .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: FormWidth.list, alignment: .leading)
                    if plan.infrast.facilities.isEmpty {
                        parameterHint("至少选择一个处理设施。", warning: true)
                    }
                }
            }
            if plan.infrast.mode == .fullShift {
                PlanFormSection("换班偏好") {
                    Text("上岗最低心情：\(Int(plan.infrast.threshold * 100))%")
                    Slider(value: $plan.infrast.threshold, in: 0...1, step: 0.05)
                        .frame(maxWidth: FormWidth.quantityRow)
                        .accessibilityLabel("上岗最低心情")
                        .accessibilityValue("\(Int(plan.infrast.threshold * 100))%")
                    parameterHint("仅筛选本次换班的候选干员。每天完整换班一次建议 90%。")
                    Toggle("宿舍空位补信赖未满干员", isOn: $plan.infrast.dormTrust)
                    Toggle("已进驻干员不放入宿舍", isOn: $plan.infrast.dormNotStationed)
                    Toggle("源石碎片自动补货", isOn: $plan.infrast.replenish)
                    Toggle("训练完成后继续尝试专精", isOn: $plan.infrast.continueTraining)
                }
            }
            PlanFormSection("会客室") {
                Toggle("领取信息板信用", isOn: $plan.infrast.receptionMessageBoard)
                Toggle("进行线索交流", isOn: $plan.infrast.receptionClueExchange)
                Toggle("赠送线索", isOn: $plan.infrast.receptionSendClue)
            }
        }
    }

    private var mallParameters: some View {
        VStack(alignment: .leading, spacing: 20) {
            PlanFormSection("信用与购物") {
                Toggle("访问好友领取信用", isOn: $plan.mall.visitFriends)
                Toggle("购买商店物品", isOn: $plan.mall.shopping)
                if plan.mall.shopping {
                    listField("优先购买", prompt: "招聘许可、龙门币", values: $plan.mall.buyFirst)
                    listField("不购买", prompt: "加急许可、家具零件", values: $plan.mall.blacklist)
                    Toggle("信用溢出时忽略黑名单", isOn: $plan.mall.forceShoppingIfCreditFull)
                    Toggle("只购买折扣物品", isOn: $plan.mall.onlyBuyDiscount)
                    Toggle("保留 300 信用点", isOn: $plan.mall.reserveMaxCredit)
                }
            }
            PlanFormSection("信用作战") {
                Toggle("借助战通关 OF-1", isOn: $plan.mall.creditFight)
                if plan.mall.creditFight {
                    Picker("使用编队", selection: $plan.mall.formationIndex) {
                        Text("当前编队").tag(0)
                        ForEach(1...4, id: \.self) { Text("编队 \($0)").tag($0) }
                    }
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    parameterHint("赚取次日信用，需要可用的助战与理智。")
                }
            }
        }
    }

    private var awardParameters: some View {
        PlanFormSection("奖励范围") {
            Toggle("日常与周常奖励", isOn: $plan.award.dailyWeekly)
            Toggle("领取邮件", isOn: $plan.award.mail)
            Toggle("免费单抽", isOn: $plan.award.freeRecruit)
            Toggle("幸运墙 / 签到", isOn: $plan.award.orundum)
            Toggle("限时采矿", isOn: $plan.award.mining)
            Toggle("活动专属赠送", isOn: $plan.award.specialAccess)
        }
    }

    @ViewBuilder
    private var fightRecovery: some View {
        let items = model.continuation(for: plan.id).fightRecoveryItems
        if !items.isEmpty {
            PlanFormSection("需要处理") {
                ForEach(items) { item in
                    FightRecoveryRow(item: item, context: recoveryLabel(item))
                }
            }
        }
    }

    @ViewBuilder
    private var fightAccountDetails: some View {
        if (plan.fight.weeklyAnnihilation.enabled || showsRecoveryStage), !fightStageMemoryRows.isEmpty {
            DisclosureGroup("账号状态与常规目标") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(fightStageMemoryRows) { row in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(row.label).font(.callout.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                if showsRecoveryStage {
                                    ActionIconButton(title: "设置\(row.label)的常规目标…", symbol: "pencil") {
                                        fightStageEditor = FightStageEditorContext(row: row)
                                    }
                                }
                            }
                            if let status = row.weeklyStatus {
                                Text(status.title)
                                    .font(.caption)
                                    .foregroundStyle(status == .unconfirmed ? Color.orange : .secondary)
                            }
                            if showsRecoveryStage {
                                parameterHint(row.stage.map { "恢复目标：\($0)；游戏中的新常规关卡优先" }
                                    ?? "运行时先识别游戏关卡；可预设已解锁的常规目标用于恢复。")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private var targetAccounts: [AccountConfiguration] {
        model.configuration.clients.filter(\.enabled).flatMap { $0.accounts.filter(plan.includes) }
    }

    private var fightStageMemoryRows: [FightStageMemoryRow] {
        model.configuration.clients.filter(\.enabled).flatMap { client in
            client.accounts.filter(plan.includes).map { account in
                FightStageMemoryRow(
                    clientID: client.id,
                    accountID: account.id,
                    label: "\(client.displayName) / \(account.displayName)",
                    stage: model.fightStageMemory.stage(clientID: client.id, accountID: account.id),
                    weeklyStatus: plan.fight.weeklyAnnihilation.enabled
                        ? model.weeklyAnnihilation.status(for: plan.fight.weeklyAnnihilation, client: client, accountID: account.id, at: model.currentDate)
                        : nil
                )
            }
        }
    }

    private func recoveryLabel(_ item: FightRecoveryItem) -> String {
        guard let client = model.configuration.clients.first(where: { $0.id == item.step.clientID }),
              let account = client.accounts.first(where: { $0.id == item.step.accountID })
        else { return plan.displayName }
        return "\(client.displayName) / \(account.displayName)"
    }

    private var showsRecoveryStage: Bool {
        plan.fight.weeklyAnnihilation.enabled
            ? !plan.fight.usesCustomSettings || plan.fight.stageStrategy != .fixed
            : plan.fight.usesCustomSettings && plan.fight.stageStrategy == .rememberedRegular
    }

    private var stageStrategyHint: String? {
        if plan.fight.weeklyAnnihilation.enabled, plan.fight.stageStrategy != .fixed {
            return "识别并记住常规目标，剿灭结束后恢复。"
        }
        switch plan.fight.stageStrategy {
        case .gameCurrentOrLast: return plan.fight.stageStrategy.detail
        case .rememberedRegular: return "优先游戏中的常规关卡；无法识别或遇到剿灭时使用记录目标。"
        case .fixed: return nil
        }
    }

    private var fallbackExplanation: String {
        "没有可用的常规目标，或选关失败且尚未开战时尝试兜底；沿用剩余额度，保留原目标。"
    }

    private var usesCustomSettings: Binding<Bool> {
        switch task {
        case .fight: $plan.fight.usesCustomSettings
        case .recruit: $plan.recruit.usesCustomSettings
        case .infrast: $plan.infrast.usesCustomSettings
        case .mall: $plan.mall.usesCustomSettings
        case .award: $plan.award.usesCustomSettings
        }
    }

    private var customFightStage: Binding<Bool> {
        Binding {
            useCustomFightStage ?? (FightStagePreset(rawValue: plan.fight.stage) == nil)
        } set: { useCustomFightStage = $0 }
    }

    private var fightStageStrategy: Binding<FightStageStrategy> {
        Binding {
            plan.fight.stageStrategy
        } set: { strategy in
            plan.fight.stageStrategy = strategy
            if strategy == .fixed, plan.fight.stage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                plan.fight.stage = FightStagePreset.oneSeven.rawValue
            }
        }
    }

    private func facilityBinding(_ facility: InfrastFacility) -> Binding<Bool> {
        Binding {
            plan.infrast.facilities.contains(facility)
        } set: { enabled in
            if enabled, !plan.infrast.facilities.contains(facility) { plan.infrast.facilities.append(facility) }
            if !enabled { plan.infrast.facilities.removeAll { $0 == facility } }
        }
    }

    private func chooseInfrastSchedule() {
        guard !model.isWorkflowRunning else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        if !plan.infrast.customSchedulePath.isEmpty {
            panel.directoryURL = URL(filePath: plan.infrast.customSchedulePath).deletingLastPathComponent()
        }
        if panel.runModal() == .OK, let url = panel.url, !model.isWorkflowRunning {
            plan.infrast.customSchedulePath = url.path
        }
    }

    private func optionalStepper(
        _ title: String,
        field: FightOptionalParameter,
        value: Binding<Int?>,
        defaultValue: Int,
        range: ClosedRange<Int>,
        unit: String
    ) -> some View {
        let memory = PlanOptionalParameterMemory.shared
        let isEnabled = Binding {
            value.wrappedValue != nil
        } set: { enabled in
            guard !model.isWorkflowRunning else { return }
            if enabled {
                value.wrappedValue = value.wrappedValue ?? memory.value(planID: plan.id, field: field) ?? defaultValue
            } else {
                if let current = value.wrappedValue { memory.remember(current, planID: plan.id, field: field) }
                value.wrappedValue = nil
            }
        }
        let number = Binding {
            value.wrappedValue ?? memory.value(planID: plan.id, field: field) ?? defaultValue
        } set: { current in
            guard !model.isWorkflowRunning else { return }
            memory.remember(current, planID: plan.id, field: field)
            value.wrappedValue = current
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle(title, isOn: isEnabled)
                    .toggleStyle(.checkbox)
                Spacer(minLength: 4)
                if value.wrappedValue != nil {
                    TextField(title, value: number, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 58)
                        .accessibilityLabel(title)
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                        .frame(width: 24, alignment: .leading)
                    Stepper(title, value: number, in: range)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityLabel("调整\(title)")
                        .accessibilityValue("\(number.wrappedValue) \(unit)")
                }
            }
            .frame(maxWidth: FormWidth.quantityRow, alignment: .leading)
            if let current = value.wrappedValue,
               current < range.lowerBound || (field == .medicineExpireDays && current > range.upperBound) {
                parameterHint(field == .medicineExpireDays
                    ? "到期天数需要在 1 到 365 之间。"
                    : "请输入不小于 \(range.lowerBound) 的整数。", warning: true)
            }
        }
    }

    private func listField(_ title: String, prompt: String, values: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout)
            DelimitedListField(title, prompt: prompt, values: values)
                .frame(maxWidth: FormWidth.list, alignment: .leading)
        }
    }

    private func parameterHint(_ text: String, warning: Bool = false) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(warning ? Color.orange : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var recommendedSummary: String {
        switch task {
        case .fight: "使用自然理智，不指定作战次数；未指定恢复目标时跟随游戏当前或上次关卡。"
        case .recruit: "执行 4 次，不使用加急许可；自动确认 3 / 4 / 5 星，保留支援机械。"
        case .infrast: "全部设施完整换班，最低心情 30%；不使用无人机，处理会客室并继续训练。"
        case .mall: "访问好友并购物；优先招聘许可、龙门币，避开加急许可、家具零件。信用溢出时继续购物。"
        case .award: "领取已完成的日常与周常任务奖励。"
        }
    }
}

struct PlanFormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum FightOptionalParameter: Hashable {
    case medicine, medicineExpireDays, stone, times
}

@MainActor
final class PlanOptionalParameterMemory {
    static let shared = PlanOptionalParameterMemory()
    private var values: [UUID: [FightOptionalParameter: Int]] = [:]

    func value(planID: UUID, field: FightOptionalParameter) -> Int? {
        values[planID]?[field]
    }

    func remember(_ value: Int, planID: UUID, field: FightOptionalParameter) {
        values[planID, default: [:]][field] = value
    }
}

private struct FightStageMemoryRow: Identifiable {
    let clientID: UUID
    let accountID: UUID
    let label: String
    let stage: String?
    let weeklyStatus: WeeklyAnnihilationStatus?
    var id: String { "\(clientID.uuidString)-\(accountID.uuidString)" }
}

private struct FightStageEditorContext: Identifiable {
    let clientID: UUID
    let accountID: UUID
    let label: String
    let stage: String?

    init(row: FightStageMemoryRow) {
        clientID = row.clientID
        accountID = row.accountID
        label = row.label
        stage = row.stage
    }

    var id: String { "\(clientID.uuidString)-\(accountID.uuidString)" }
}

private struct FightStageEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool
    @State private var stage: String
    @State private var saveError: String?
    let context: FightStageEditorContext
    let onSave: (String) -> String?

    init(context: FightStageEditorContext, onSave: @escaping (String) -> String?) {
        self.context = context
        self.onSave = onSave
        _stage = State(initialValue: context.stage ?? "")
    }

    private var normalizedStage: String? { FightStagePolicy.regularStage(from: stage, times: 1) }

    var body: some View {
        VStack(spacing: 0) {
            Text("设置常规目标").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(context.label).font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text("关卡")
                        TextField("如 1-7 或 PR-A-1", text: $stage)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: FormWidth.stage)
                            .focused($fieldFocused)
                            .accessibilityLabel("常规目标关卡")
                            .disabled(model.isWorkflowRunning)
                    }
                    Text("恢复剿灭或临时兜底之前的目标。请选择 MAA 可导航的已解锁关卡；游戏内的新常规关卡优先。")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !stage.isEmpty, normalizedStage == nil {
                        Text(FightStagePolicy.regularStageHint)
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.isWorkflowRunning {
                        Text("运行结束后可保存").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.bottom, 20)
            }
            Divider()
            HStack(spacing: 12) {
                Spacer()
                Button { dismiss() } label: {
                    Text("取消").frame(minWidth: 56)
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    guard let normalizedStage else { return }
                    saveError = onSave(normalizedStage)
                    if saveError == nil { dismiss() }
                } label: {
                    Text("保存").frame(minWidth: 56)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent).tint(.maaAction)
                .disabled(model.isWorkflowRunning || normalizedStage == nil)
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: 440, height: 320)
        .focusedSceneValue(\.workspaceActive, false)
        .onChange(of: stage) { _, _ in saveError = nil }
        .onAppear { fieldFocused = true }
    }
}
