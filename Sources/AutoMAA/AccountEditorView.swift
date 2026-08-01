import AutoMAAKit
import SwiftUI

struct AccountEditorView: View {
    @EnvironmentObject private var model: AppModel
    let client: ClientConfiguration
    @Binding var account: AccountConfiguration
    @State private var confirmDelete = false
    @State private var useCustomFightStage = false

    private let columns = [GridItem(.adaptive(minimum: 330), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                accountHeader
                selectorPanel
                orderPanel
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    fightCard
                    recruitCard
                    infrastCard
                    awardCard
                }
                deletePanel
            }
            .padding(28)
            .frame(maxWidth: 1_060)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(account.name)
        .confirmationDialog("删除 \(account.name)？", isPresented: $confirmDelete) {
            Button("删除账号", role: .destructive) {
                model.deleteAccount(clientID: client.id, accountID: account.id)
            }
        } message: {
            Text("只会删除 AutoMAA 中的配置，不会影响游戏账号。")
        }
    }

    private var accountHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle().fill(Color.maaAccent.opacity(0.12))
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.maaAccent)
            }
            .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 5) {
                TextField("账号名称", text: $account.name)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.bold))
                Text("\(client.name) · \(account.stepOrder.filter { account.isEnabled($0) }.count) 个步骤")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("启用账号", isOn: $account.enabled)
                .toggleStyle(.switch)
        }
    }

    private var selectorPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label("账号切换", systemImage: "person.text.rectangle")
                        .font(.headline)
                    Spacer()
                    if requiresSelector && account.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("必填", systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    } else if !requiresSelector {
                        Text("可选")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                TextField("填写登录页能唯一匹配该账号的片段", text: $account.accountSelector)
                    .textFieldStyle(.roundedBorder)
                Text(requiresSelector
                     ? "同一客户端启用了多个账号，每个账号都必须填写不同且唯一的匹配片段。"
                     : "单账号可以留空；填写后 MAA 会在已登录账号中按该片段进行匹配。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var orderPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("步骤顺序", systemImage: "arrow.up.arrow.down")
                        .font(.headline)
                    Spacer()
                    Text("每一步独立重试与记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    ForEach(Array(account.stepOrder.enumerated()), id: \.element) { index, task in
                        HStack(spacing: 7) {
                            Text("\(index + 1)")
                                .font(.caption2.bold().monospacedDigit())
                                .foregroundStyle(.secondary)
                            Image(systemName: task.symbol)
                                .foregroundStyle(account.isEnabled(task) ? Color.maaAccent : Color.secondary)
                            Text(task.title)
                                .font(.caption.weight(.medium))
                            VStack(spacing: 0) {
                                Button { move(task, by: -1) } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .disabled(index == 0)
                                Button { move(task, by: 1) } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .disabled(index == account.stepOrder.count - 1)
                            }
                            .buttonStyle(.plain)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private var fightCard: some View {
        TaskConfigCard(
            task: .fight,
            enabled: $account.fight.enabled,
            usesCustomSettings: $account.fight.usesCustomSettings
        ) {
            LabeledContent("关卡") {
                if customFightStage.wrappedValue {
                    TextField("如 1-7 或活动关卡", text: $account.fight.stage)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 190)
                } else {
                    Picker("关卡", selection: $account.fight.stage) {
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
            optionalStepper("吃理智药", value: $account.fight.medicine, defaultValue: 999, range: 0...999)
            optionalStepper("吃源石", value: $account.fight.stone, defaultValue: 0, range: 0...99)
            optionalStepper("指定次数", value: $account.fight.times, defaultValue: 5, range: 1...9_999)
            Picker("连战次数", selection: $account.fight.series) {
                Text("不使用").tag(Int?.none)
                Text("AUTO").tag(Int?.some(0))
                ForEach((1...6).reversed(), id: \.self) { value in
                    Text("\(value)").tag(Int?.some(value))
                }
            }
            Divider()
            Toggle(
                "无限使用 48 小时内过期的理智药",
                isOn: optionalToggle($account.fight.expiringMedicine, defaultValue: 999)
            )
            Toggle("博朗台碎石模式", isOn: $account.fight.drGrandet)
            Text("“当前/上次”会沿用游戏当前或最近关卡；源石默认不启用。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var recruitCard: some View {
        TaskConfigCard(
            task: .recruit,
            enabled: $account.recruit.enabled,
            usesCustomSettings: $account.recruit.usesCustomSettings
        ) {
            Stepper("招募次数：\(account.recruit.times)", value: $account.recruit.times, in: 0...12)
            Toggle("刷新标签", isOn: $account.recruit.refresh)
            Toggle("使用加急许可", isOn: $account.recruit.expedite)
            Divider()
            Text("自动确认星级")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Toggle("3★", isOn: $account.recruit.autoConfirm3)
                Toggle("4★", isOn: $account.recruit.autoConfirm4)
                Toggle("5★", isOn: $account.recruit.autoConfirm5)
                Toggle("6★", isOn: $account.recruit.autoConfirm6)
            }
            .toggleStyle(.checkbox)
            Toggle("保留小车标签", isOn: $account.recruit.preserveRobot)
        }
    }

    private var infrastCard: some View {
        TaskConfigCard(
            task: .infrast,
            enabled: $account.infrast.enabled,
            usesCustomSettings: $account.infrast.usesCustomSettings
        ) {
            Label("仅收菜，不换班", systemImage: "checkmark.shield.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.maaAccent)
            Text("固定使用 MAA Infrast 20000 模式。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("制造站收取", isOn: $account.infrast.collectManufacturing)
            Toggle("贸易站收取", isOn: $account.infrast.collectTrading)
            Toggle("会客室线索", isOn: $account.infrast.collectReception)
            Picker("无人机用途", selection: $account.infrast.drones) {
                ForEach(DroneUsage.allCases) { usage in
                    Text(usage.title).tag(usage)
                }
            }
        }
    }

    private var awardCard: some View {
        TaskConfigCard(
            task: .award,
            enabled: $account.award.enabled,
            usesCustomSettings: $account.award.usesCustomSettings
        ) {
            Toggle("日常与周常奖励", isOn: $account.award.dailyWeekly)
            Toggle("邮件", isOn: $account.award.mail)
            Toggle("免费单抽", isOn: $account.award.freeRecruit)
            Toggle("幸运墙 / 签到", isOn: $account.award.orundum)
            Toggle("限时采矿", isOn: $account.award.mining)
        }
    }

    private var deletePanel: some View {
        HStack {
            Spacer()
            Button("删除这个账号", role: .destructive) { confirmDelete = true }
        }
        .padding(.top, 4)
    }

    private func move(_ task: TaskKind, by offset: Int) {
        guard let index = account.stepOrder.firstIndex(of: task) else { return }
        let destination = index + offset
        guard account.stepOrder.indices.contains(destination) else { return }
        account.stepOrder.swapAt(index, destination)
    }

    private var requiresSelector: Bool {
        client.accounts.filter(\.enabled).count > 1
    }

    private var customFightStage: Binding<Bool> {
        Binding {
            useCustomFightStage || FightStagePreset(rawValue: account.fight.stage) == nil
        } set: { enabled in
            if !enabled { account.fight.stage = FightStagePreset.currentOrLast.rawValue }
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
        Binding {
            value.wrappedValue ?? defaultValue
        } set: {
            value.wrappedValue = $0
        }
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
                Stepper(
                    "\(value.wrappedValue ?? defaultValue)",
                    value: optionalValue(value, defaultValue: defaultValue),
                    in: range
                )
                .fixedSize()
            }
        }
    }
}

private struct TaskConfigCard<Content: View>: View {
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
                    Spacer()
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
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
                    VStack(alignment: .leading, spacing: 9) {
                        content
                    }
                } else {
                    Label(defaultSummary, systemImage: task == .infrast ? "exclamationmark.triangle.fill" : "arrow.uturn.backward.circle.fill")
                        .font(.caption)
                        .foregroundStyle(task == .infrast ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.48)
        }
    }

    private var defaultSummary: String {
        switch task {
        case .fight:
            "MAA 默认：当前/上次关卡，不使用理智药或源石，不限制次数。"
        case .recruit:
            "MAA 默认：4 次、不加急，自动确认 3★/4★/5★，1★ 手动确认。"
        case .infrast:
            "MAA 默认会执行常规换班并处理全部设施，不使用无人机；仅收菜请保持自定义开启。"
        case .award:
            "MAA 默认：只领取每日与每周任务奖励。"
        }
    }
}
