import Foundation

public enum ConfigurationProblemSeverity: Equatable, Sendable {
    case warning
    case error
}

public enum ConfigurationProblemScope: Equatable, Sendable {
    case shared
    case plan(UUID)
}

public struct ConfigurationProblem: Identifiable, Equatable, Sendable {
    public let id: String
    public let severity: ConfigurationProblemSeverity
    public let message: String
    public let scope: ConfigurationProblemScope

    public init(
        id: String,
        severity: ConfigurationProblemSeverity,
        message: String,
        scope: ConfigurationProblemScope = .shared
    ) {
        self.id = id
        self.severity = severity
        self.message = message
        self.scope = scope
    }
}

public enum MAAProfileName {
    public static func normalize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "default" : trimmed
    }
}

public enum ConfigurationValidator {
    public static func structuralProblems(in configuration: AppConfiguration) -> [ConfigurationProblem] {
        var result: [ConfigurationProblem] = []
        if configuration.schemaVersion != AppConfiguration.currentSchemaVersion {
            result.append(.init(
                id: "schema-version",
                severity: .error,
                message: "配置协议 schema v\(configuration.schemaVersion) 与当前版本不兼容"
            ))
        }
        appendDuplicateProblems(
            configuration.clients.map(\.id),
            id: "duplicate-client-id",
            message: "客户端标识重复，请删除并重新添加重复项",
            to: &result
        )
        appendDuplicateProblems(
            configuration.clients.flatMap { $0.accounts.map(\.id) },
            id: "duplicate-account-id",
            message: "账号标识重复，请删除并重新添加重复项",
            to: &result
        )
        appendDuplicateProblems(
            configuration.plans.map(\.id),
            id: "duplicate-plan-id",
            message: "自动化方案标识重复，请删除并重新添加重复项",
            to: &result
        )

        let profiles = configuration.clients.map { MAAProfileName.normalize($0.profileName) }
        appendDuplicateProblems(
            profiles,
            id: "duplicate-profile",
            message: "每个客户端需要使用不同的 MAA Profile 名称",
            to: &result
        )

        for plan in configuration.plans {
            let prefix = "plan-\(plan.id.uuidString.lowercased())"
            if Set(plan.stepOrder) != Set(TaskKind.allCases) || plan.stepOrder.count != TaskKind.allCases.count {
                result.append(.init(
                    id: "\(prefix)-step-order",
                    severity: .error,
                    message: "「\(plan.displayName)」的步骤顺序已损坏，请重新创建该方案",
                    scope: .plan(plan.id)
                ))
            }
            if plan.fight.enabled, plan.fight.usesCustomSettings {
                validate(plan.fight, prefix: "\(prefix)-fight", plan: plan, into: &result)
            }
            if plan.recruit.enabled, plan.recruit.usesCustomSettings {
                validate(plan.recruit, prefix: "\(prefix)-recruit", plan: plan, into: &result)
            }
            if plan.infrast.enabled, plan.infrast.usesCustomSettings {
                validate(plan.infrast, prefix: "\(prefix)-infrast", plan: plan, into: &result)
            }
            if plan.mall.enabled, plan.mall.usesCustomSettings, !(0...4).contains(plan.mall.formationIndex) {
                result.append(.init(
                    id: "\(prefix)-mall-formation",
                    severity: .error,
                    message: "「\(plan.displayName)」的信用关编队必须在 0 到 4 之间",
                    scope: .plan(plan.id)
                ))
            }
            if let problem = PlanScheduleValidator.problem(in: plan.schedule) {
                result.append(.init(
                    id: "\(prefix)-schedule",
                    severity: .error,
                    message: problem.message(planName: plan.displayName),
                    scope: .plan(plan.id)
                ))
            }
        }
        return result
    }

    public static func readinessProblems(
        in configuration: AppConfiguration,
        planID: UUID?,
        fightStageMemory: FightStageMemory = .init(),
        fileManager: FileManager = .default
    ) -> [ConfigurationProblem] {
        var result = structuralProblems(in: configuration)
        if let planID {
            result.removeAll { problem in
                guard problem.severity == .warning,
                      case let .plan(sourcePlanID) = problem.scope
                else { return false }
                return sourcePlanID != planID
            }
        }
        guard !result.contains(where: { $0.severity == .error && $0.id.hasPrefix("duplicate-") }) else {
            return result
        }
        if !fileManager.isExecutableFile(atPath: configuration.cliPath) {
            result.append(.init(
                id: "maa-cli-missing",
                severity: .error,
                message: "找不到可执行的 maa-cli：\(configuration.cliPath)"
            ))
        }
        guard let planID, let plan = configuration.plans.first(where: { $0.id == planID }) else {
            result.append(.init(id: "plan-missing", severity: .error, message: "至少需要创建一个自动化方案"))
            return result
        }
        let planName = plan.displayName
        if plan.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(.init(
                id: "plan-name-empty",
                severity: .error,
                message: "方案名称不能为空",
                scope: .plan(plan.id)
            ))
        }
        if plan.enabledTasks.isEmpty {
            result.append(.init(
                id: "plan-tasks-empty",
                severity: .error,
                message: "「\(planName)」没有启用任何步骤",
                scope: .plan(plan.id)
            ))
        }
        if plan.infrast.enabled,
           plan.infrast.usesCustomSettings,
           plan.infrast.mode == .customSchedule {
            let path = plan.infrast.customSchedulePath.trimmingCharacters(in: .whitespacesAndNewlines)
            var isDirectory = ObjCBool(false)
            if path.isEmpty || !fileManager.fileExists(atPath: path, isDirectory: &isDirectory) || isDirectory.boolValue {
                result.append(.init(
                    id: "plan-custom-infrast-missing",
                    severity: .error,
                    message: "「\(planName)」的自定义基建排班文件不存在",
                    scope: .plan(plan.id)
                ))
            }
        }

        let activeClients = configuration.clients.filter { client in
            client.enabled && client.accounts.contains(where: plan.includes)
        }
        if activeClients.isEmpty {
            result.append(.init(
                id: "plan-accounts-empty",
                severity: .error,
                message: "「\(planName)」没有可执行的账号",
                scope: .plan(plan.id)
            ))
        }
        for client in activeClients {
            let clientName = client.displayName
            if client.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.init(
                    id: "client-\(client.id)-name-empty",
                    severity: .error,
                    message: "客户端名称不能为空",
                    scope: .plan(plan.id)
                ))
            }
            if !fileManager.fileExists(atPath: client.appPath) {
                result.append(.init(
                    id: "client-\(client.id)-app-missing",
                    severity: .warning,
                    message: "\(clientName) 的应用路径不存在，运行时会跳过该客户端",
                    scope: .plan(plan.id)
                ))
            }
            if client.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.init(
                    id: "client-\(client.id)-bundle-missing",
                    severity: .warning,
                    message: "\(clientName) 缺少 Bundle Identifier，运行时会跳过该客户端",
                    scope: .plan(plan.id)
                ))
            }
            if (try? PortAddress(client.address)) == nil {
                result.append(.init(
                    id: "client-\(client.id)-address-invalid",
                    severity: .warning,
                    message: "\(clientName) 的 MaaTools 地址无效，运行时会跳过该客户端",
                    scope: .plan(plan.id)
                ))
            }

            let enabledAccounts = client.accounts.filter(\.enabled)
            let targetAccounts = client.accounts.filter(plan.includes)
            if plan.fight.enabled,
               plan.fight.usesCustomSettings,
               plan.fight.stageStrategy == .rememberedRegular {
                for account in targetAccounts where fightStageMemory.requiresRecovery(
                    clientID: client.id,
                    accountID: account.id
                ) && fightStageMemory.stage(clientID: client.id, accountID: account.id) == nil {
                    result.append(.init(
                        id: "plan-\(plan.id)-fight-memory-\(client.id)-\(account.id)",
                        severity: .error,
                        message: "「\(planName)」需要为\(clientName) / \(account.displayName)从剿灭恢复，但尚无备用常规关卡；请设置恢复关卡，或确认游戏已手动切回后继续跟随",
                        scope: .plan(plan.id)
                    ))
                }
            }
            for account in targetAccounts where account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.init(
                    id: "account-\(account.id)-name-empty",
                    severity: .error,
                    message: "\(clientName) 中的账号名称不能为空",
                    scope: .plan(plan.id)
                ))
            }
            if !client.kind.supportsAccountSwitching {
                if enabledAccounts.count > 1 {
                    result.append(.init(
                        id: "client-\(client.id)-account-switch-unsupported",
                        severity: .error,
                        message: "\(clientName) 的\(client.kind.title)不支持自动切换账号，请只启用一个账号",
                        scope: .plan(plan.id)
                    ))
                }
                for account in targetAccounts where !account.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.init(
                        id: "account-\(account.id)-selector-unsupported",
                        severity: .error,
                        message: "\(account.displayName) 属于\(client.kind.title)，账号片段必须留空",
                        scope: .plan(plan.id)
                    ))
                }
            } else if enabledAccounts.count > 1 {
                for account in targetAccounts where account.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.init(
                        id: "account-\(account.id)-selector-empty",
                        severity: .warning,
                        message: "\(account.displayName) 缺少唯一账号片段，运行时会跳过该账号",
                        scope: .plan(plan.id)
                    ))
                }
                let selectors = enabledAccounts
                    .map { $0.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                if Set(selectors).count != selectors.count {
                    result.append(.init(
                        id: "client-\(client.id)-selector-duplicate",
                        severity: .error,
                        message: "\(clientName) 的账号片段不能重复",
                        scope: .plan(plan.id)
                    ))
                }
            }
        }
        return result
    }

    private static func validate(
        _ value: FightConfiguration,
        prefix: String,
        plan: AutomationPlan,
        into result: inout [ConfigurationProblem]
    ) {
        let name = plan.displayName
        if value.stageStrategy == .fixed {
            let stage = value.stage.trimmingCharacters(in: .whitespacesAndNewlines)
            if stage.isEmpty || stage.count > 128 || stage.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
                result.append(.init(
                    id: "\(prefix)-stage",
                    severity: .error,
                    message: "「\(name)」的固定关卡名必须为 1 到 128 个有效字符",
                    scope: .plan(plan.id)
                ))
            }
        }
        let checks: [(String, Bool, String)] = [
            ("medicine", value.medicine.map { $0 >= 0 } ?? true, "理智药数量不能为负数"),
            ("medicine-expire-days", value.medicineExpireDays.map { (1...365).contains($0) } ?? true, "临期理智药天数必须在 1 到 365 之间"),
            ("stone", value.stone.map { $0 >= 0 } ?? true, "源石数量不能为负数"),
            ("times", value.times.map { $0 > 0 } ?? true, "作战次数必须大于 0"),
            ("series", value.series.map { (-1...10).contains($0) } ?? true, "连战次数必须在 -1 到 10 之间"),
        ]
        for (field, valid, message) in checks where !valid {
            result.append(.init(
                id: "\(prefix)-\(field)",
                severity: .error,
                message: "「\(name)」的\(message)",
                scope: .plan(plan.id)
            ))
        }
    }

    private static func validate(
        _ value: RecruitConfiguration,
        prefix: String,
        plan: AutomationPlan,
        into result: inout [ConfigurationProblem]
    ) {
        let name = plan.displayName
        if !(0...12).contains(value.times) {
            result.append(.init(
                id: "\(prefix)-times",
                severity: .error,
                message: "「\(name)」的招募次数必须在 0 到 12 之间",
                scope: .plan(plan.id)
            ))
        }
        for (field, values) in [("首选标签", value.firstTags), ("保留标签", value.preserveTags)] {
            let normalized = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if normalized.contains(where: \.isEmpty) || Set(normalized).count != normalized.count {
                result.append(.init(
                    id: "\(prefix)-tags-\(field)",
                    severity: .error,
                    message: "「\(name)」的\(field)不能包含空值或重复项",
                    scope: .plan(plan.id)
                ))
            }
        }
    }

    private static func validate(
        _ value: InfrastConfiguration,
        prefix: String,
        plan: AutomationPlan,
        into result: inout [ConfigurationProblem]
    ) {
        let name = plan.displayName
        if value.mode != .customSchedule,
           (value.facilities.isEmpty || Set(value.facilities).count != value.facilities.count) {
            result.append(.init(
                id: "\(prefix)-facilities",
                severity: .error,
                message: "「\(name)」必须选择至少一个且不重复的基建设施",
                scope: .plan(plan.id)
            ))
        }
        if !(0...1).contains(value.threshold) {
            result.append(.init(
                id: "\(prefix)-threshold",
                severity: .error,
                message: "「\(name)」的基建心情阈值必须在 0 到 1 之间",
                scope: .plan(plan.id)
            ))
        } else if value.mode == .fullShift,
                  value.threshold < InfrastConfiguration.dailyFullShiftThreshold {
            let percentage = Int((value.threshold * 100).rounded())
            result.append(.init(
                id: "\(prefix)-threshold-fatigue-risk",
                severity: .warning,
                message: "「\(name)」的上岗最低心情为 \(percentage)%；阈值只在换班时筛选候选干员，每天一次完整换班建议使用 90%，否则干员可能在下次换班前疲劳",
                scope: .plan(plan.id)
            ))
        }
        if value.customSchedulePlanIndex < 0 {
            result.append(.init(
                id: "\(prefix)-plan-index",
                severity: .error,
                message: "「\(name)」的基建排班方案序号不能为负数",
                scope: .plan(plan.id)
            ))
        }
    }

    private static func appendDuplicateProblems<T: Hashable>(
        _ values: [T],
        id: String,
        message: String,
        to result: inout [ConfigurationProblem]
    ) {
        if Set(values).count != values.count {
            result.append(.init(id: id, severity: .error, message: message))
        }
    }

}
