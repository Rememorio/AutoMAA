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
    @State private var showsMoreFightSettings = false
    @ScaledMetric(relativeTo: .body) private var fieldLabelWidth: CGFloat = 70

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).font(.headline).accessibilityAddTraits(.isHeader)
                    if !plan.isEnabled(task) {
                        Text("已停用").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                parameterMode.disabled(model.isWorkflowRunning)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if model.isWorkflowRunning {
                        Label("运行结束后可修改参数", systemImage: "lock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    parameters
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .toggleStyle(.checkbox)
            }
            .id("\(plan.id.uuidString)-\(task.rawValue)")
        }
        .onChange(of: plan.id) { _, _ in
            useCustomFightStage = nil
            showsMoreFightSettings = false
        }
        .sheet(item: $fightStageEditor) { context in
            FightStageEditorSheet(context: context)
        }
    }

    private var parameterMode: some View {
        Picker("\(task.title)参数模式", selection: usesCustomSettings) {
            Text("MAA 推荐参数").tag(false)
            Text("自定义参数").tag(true)
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
        .help("切回推荐参数仍保留自定义值")
    }

    @ViewBuilder
    private var parameters: some View {
        if usesCustomSettings.wrappedValue {
            switch task {
            case .fight: fightParameters
            case .recruit: recruitParameters.disabled(model.isWorkflowRunning)
            case .infrast: infrastParameters.disabled(model.isWorkflowRunning)
            case .mall: mallParameters.disabled(model.isWorkflowRunning)
            case .award: awardParameters.disabled(model.isWorkflowRunning)
            }
        } else {
            Text(recommendedSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if task == .fight {
            weeklyAnnihilation.disabled(model.isWorkflowRunning)
            fightAccountDetails
        }
    }

    private var fightParameters: some View {
        VStack(alignment: .leading, spacing: 20) {
            PlanFormSection("常规作战") {
                menuField("关卡策略", selection: fightStageStrategy) {
                    ForEach(FightStageStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                .help(plan.fight.stageStrategy.detail)
                if let stageStrategyHint { parameterHint(stageStrategyHint) }
                if plan.fight.stageStrategy == .fixed {
                    if customFightStage.wrappedValue {
                        fieldRow("关卡") {
                            TextField("如 1-7 或活动关卡", text: $plan.fight.stage)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: FormWidth.stage)
                                .accessibilityLabel("固定关卡")
                        }
                    } else {
                        menuField("关卡", selection: $plan.fight.stage) {
                            if FightStagePreset(rawValue: plan.fight.stage) == nil {
                                Text("自定义：\(plan.fight.stage)").tag(plan.fight.stage)
                            }
                            ForEach(FightStagePreset.allCases.filter { $0 != .currentOrLast }) { preset in
                                Text(preset.title).tag(preset.rawValue)
                            }
                        }
                    }
                    Toggle("手动输入关卡名", isOn: customFightStage)
                    if plan.fight.stage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parameterHint("填写要执行的固定关卡。", warning: true)
                    }
                }
                optionalStepper("限制作战次数", field: .times, value: $plan.fight.times, defaultValue: 5, range: 1...9_999, unit: "次")
                menuField("连战次数", selection: $plan.fight.series) {
                    Text("MAA 默认（1 次）").tag(Int?.none)
                    Text("保持游戏连战次数").tag(Int?.some(-1))
                    Text("AUTO").tag(Int?.some(0))
                    ForEach(1...10, id: \.self) { value in
                        Text("\(value) 次").tag(Int?.some(value))
                    }
                }
            }
            .disabled(model.isWorkflowRunning)

            DisclosureGroup(isExpanded: $showsMoreFightSettings) {
                VStack(alignment: .leading, spacing: 10) {
                    fieldRow("兜底关卡") {
                        TextField("可选，留空关闭", text: $plan.fight.fallbackStage)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: FormWidth.stage)
                            .accessibilityLabel("兜底关卡，留空关闭")
                            .help(fallbackExplanation)
                    }
                    if !plan.fight.fallbackStage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        parameterHint(fallbackExplanation)
                    }
                    optionalStepper("临期理智药", field: .medicineExpireDays, value: $plan.fight.medicineExpireDays, defaultValue: 2, range: 1...365, unit: "天内")
                    if plan.fight.medicineExpireDays != nil {
                        parameterHint("临期药单独计数，可超出普通药额度。")
                    }
                    optionalStepper("普通理智药额度", field: .medicine, value: $plan.fight.medicine, defaultValue: 999, range: 0...999, unit: "瓶")
                    optionalStepper("源石额度", field: .stone, value: $plan.fight.stone, defaultValue: 0, range: 0...99, unit: "颗")
                    Toggle("博朗台碎石模式", isOn: $plan.fight.drGrandet)
                    parameterHint("理智药和源石额度按账号计算。")
                }
                .padding(.top, 8)
                .disabled(model.isWorkflowRunning)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("更多作战设置")
                    if !showsMoreFightSettings, let summary = plan.fight.advancedOptionsSummary {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var weeklyAnnihilation: some View {
        PlanFormSection("每周剿灭") {
            Toggle("每周优先剿灭", isOn: $plan.fight.weeklyAnnihilation.enabled)
            if plan.fight.weeklyAnnihilation.enabled {
                menuField("本周开始日", selection: $plan.fight.weeklyAnnihilation.startDay) {
                    ForEach(ScheduleWeekday.allCases) { day in Text(day.title).tag(day) }
                }
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
                menuField("额外标签", selection: $plan.recruit.extraTagsMode) {
                    ForEach(RecruitExtraTagsMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                listField("三星首选标签", prompt: "可留空", values: $plan.recruit.firstTags)
                listField("保留并跳过", prompt: "例如 支援机械", values: $plan.recruit.preserveTags)
            }
        }
    }

    private var infrastParameters: some View {
        VStack(alignment: .leading, spacing: 20) {
            PlanFormSection("基建安排") {
                menuField("基建模式", selection: $plan.infrast.mode) {
                    ForEach(InfrastMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
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
                    menuField("无人机用途", selection: $plan.infrast.drones) {
                        ForEach(DroneUsage.allCases) { usage in Text(usage.title).tag(usage) }
                    }
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
                        .help("仅筛选本次换班的候选干员。")
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
                    menuField("使用编队", selection: $plan.mall.formationIndex) {
                        Text("当前编队").tag(0)
                        ForEach(1...4, id: \.self) { Text("编队 \($0)").tag($0) }
                    }
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
    private var fightAccountDetails: some View {
        if (plan.fight.weeklyAnnihilation.enabled || showsRecoveryStage), !fightStageMemoryRows.isEmpty {
            DisclosureGroup("账号状态与常规目标") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(fightStageMemoryRows) { row in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(row.label).font(.callout.weight(.medium))
                                .fixedSize(horizontal: false, vertical: true)
                            if let status = row.weeklyStatus {
                                Text(status.title)
                                    .font(.caption)
                                    .foregroundStyle(status == .unconfirmed ? Color.orange : .secondary)
                            }
                            if showsRecoveryStage {
                                ActionTextButton(title: "常规目标  \(row.stage ?? "未设置")", symbol: "chevron.right",
                                                 help: "设置\(row.label)的常规目标", symbolAfterTitle: true) {
                                    fightStageEditor = .init(clientID: row.clientID, accountID: row.accountID,
                                                             label: row.label, stage: row.stage)
                                }
                                .disabled(model.isWorkflowRunning)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 10)
            }
        }
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
        case .gameCurrentOrLast: return "游戏停在剿灭关卡时，本次也可能进入剿灭。"
        case .rememberedRegular: return "优先游戏中的常规关卡；无法识别或遇到剿灭时使用记录目标。"
        case .fixed: return nil
        }
    }

    private var fallbackExplanation: String {
        "无常规目标或开战前选关失败时使用，沿用剩余额度。"
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

    private func fieldRow(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: fieldLabelWidth, alignment: .leading)
                .accessibilityHidden(true)
            control()
        }
    }

    private func menuField<Value: Hashable>(
        _ title: String, selection: Binding<Value>, @ViewBuilder options: () -> some View
    ) -> some View {
        let picker = Picker(title, selection: selection, content: options)
            .pickerStyle(.menu)
            .labelsHidden()
        return fieldRow(title) {
            ViewThatFits(in: .horizontal) {
                picker.fixedSize()
                picker
            }
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

extension FightConfiguration {
    var regularFightBudgetSummary: String? {
        guard enabled else { return nil }
        var values = usesCustomSettings ? resourceLimits(includingZero: false) : []
        if values.isEmpty {
            values.append("自然理智")
            if usesCustomSettings, let times { values.append("每账号最多 \(times) 次") }
        } else if let times {
            values.append("最多 \(times) 次")
        }
        if weeklyAnnihilation.enabled { values.insert("常规", at: 0) }
        return values.joined(separator: " · ")
    }

    var advancedOptionsSummary: String? {
        guard usesCustomSettings else { return nil }
        var values = resourceLimits(includingZero: true)
        if drGrandet { values.append("博朗台碎石") }
        let fallback = fallbackStage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty { values.append("兜底 \(fallback)") }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func resourceLimits(includingZero: Bool) -> [String] {
        var values: [String] = []
        if let stone, stone != 0 || includingZero { values.append("源石最多 \(stone) 颗") }
        if let medicine, medicine != 0 || includingZero { values.append("理智药最多 \(medicine) 瓶") }
        if let medicineExpireDays { values.append("使用 \(medicineExpireDays) 天内到期药") }
        if !values.isEmpty { values[0] = "每账号" + values[0] }
        return values
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

struct FightStageEditorContext: Identifiable {
    let clientID: UUID
    let accountID: UUID
    let label: String
    let stage: String?

    var id: String { "\(clientID.uuidString)-\(accountID.uuidString)" }
}

struct FightStageEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool
    @State private var stage: String
    @State private var saveError: String?
    let context: FightStageEditorContext
    init(context: FightStageEditorContext) {
        self.context = context
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
                    Text("选择 MAA 可进入的已解锁常规关卡。游戏内的新常规目标优先。")
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
                    guard !model.isWorkflowRunning else {
                        saveError = "运行结束后可保存。"
                        return
                    }
                    saveError = model.saveFightRecoveryStage(normalizedStage, clientID: context.clientID, accountID: context.accountID)
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
