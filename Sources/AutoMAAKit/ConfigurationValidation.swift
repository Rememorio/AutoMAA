import Foundation

public enum ConfigurationProblemSeverity: Equatable, Sendable {
    case warning
    case error
}

public struct ConfigurationProblem: Identifiable, Equatable, Sendable {
    public let id: String
    public let severity: ConfigurationProblemSeverity
    public let message: String

    public init(id: String, severity: ConfigurationProblemSeverity, message: String) {
        self.id = id
        self.severity = severity
        self.message = message
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
                    message: "「\(plan.displayName)」的步骤顺序已损坏，请重新创建该方案"
                ))
            }
            if plan.fight.enabled, plan.fight.usesCustomSettings {
                validate(plan.fight, prefix: "\(prefix)-fight", planName: plan.name, into: &result)
            }
            if plan.recruit.enabled, plan.recruit.usesCustomSettings {
                validate(plan.recruit, prefix: "\(prefix)-recruit", planName: plan.name, into: &result)
            }
            if plan.infrast.enabled, plan.infrast.usesCustomSettings {
                validate(plan.infrast, prefix: "\(prefix)-infrast", planName: plan.name, into: &result)
            }
            if plan.mall.enabled, plan.mall.usesCustomSettings, !(0...4).contains(plan.mall.formationIndex) {
                result.append(.init(
                    id: "\(prefix)-mall-formation",
                    severity: .error,
                    message: "「\(plan.displayName)」的信用关编队必须在 0 到 4 之间"
                ))
            }
            if !(0...23).contains(plan.schedule.hour) || !(0...59).contains(plan.schedule.minute) {
                result.append(.init(
                    id: "\(prefix)-schedule-time",
                    severity: .error,
                    message: "「\(plan.displayName)」的定时时间无效"
                ))
            }
        }
        return result
    }

    public static func readinessProblems(
        in configuration: AppConfiguration,
        planID: UUID?,
        fileManager: FileManager = .default
    ) -> [ConfigurationProblem] {
        var result = structuralProblems(in: configuration)
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
            result.append(.init(id: "plan-name-empty", severity: .error, message: "方案名称不能为空"))
        }
        if plan.enabledTasks.isEmpty {
            result.append(.init(id: "plan-tasks-empty", severity: .error, message: "「\(planName)」没有启用任何步骤"))
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
                    message: "「\(planName)」的自定义基建排班文件不存在"
                ))
            }
        }

        let activeClients = configuration.clients.filter { client in
            client.enabled && client.accounts.contains(where: plan.includes)
        }
        if activeClients.isEmpty {
            result.append(.init(id: "plan-accounts-empty", severity: .error, message: "「\(planName)」没有可执行的账号"))
        }
        for client in activeClients {
            let clientName = client.displayName
            if client.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.init(
                    id: "client-\(client.id)-name-empty",
                    severity: .error,
                    message: "客户端名称不能为空"
                ))
            }
            if !fileManager.fileExists(atPath: client.appPath) {
                result.append(.init(
                    id: "client-\(client.id)-app-missing",
                    severity: .warning,
                    message: "\(clientName) 的应用路径不存在，运行时会跳过该客户端"
                ))
            }
            if client.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.init(
                    id: "client-\(client.id)-bundle-missing",
                    severity: .warning,
                    message: "\(clientName) 缺少 Bundle Identifier，运行时会跳过该客户端"
                ))
            }
            if (try? PortAddress(client.address)) == nil {
                result.append(.init(
                    id: "client-\(client.id)-address-invalid",
                    severity: .warning,
                    message: "\(clientName) 的 MaaTools 地址无效，运行时会跳过该客户端"
                ))
            }

            let enabledAccounts = client.accounts.filter(\.enabled)
            let targetAccounts = client.accounts.filter(plan.includes)
            for account in targetAccounts where account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.init(
                    id: "account-\(account.id)-name-empty",
                    severity: .error,
                    message: "\(clientName) 中的账号名称不能为空"
                ))
            }
            if !client.kind.supportsAccountSwitching {
                if enabledAccounts.count > 1 {
                    result.append(.init(
                        id: "client-\(client.id)-account-switch-unsupported",
                        severity: .error,
                        message: "\(clientName) 的\(client.kind.title)不支持自动切换账号，请只启用一个账号"
                    ))
                }
                for account in targetAccounts where !account.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.init(
                        id: "account-\(account.id)-selector-unsupported",
                        severity: .error,
                        message: "\(account.displayName) 属于\(client.kind.title)，账号片段必须留空"
                    ))
                }
            } else if enabledAccounts.count > 1 {
                for account in targetAccounts where account.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    result.append(.init(
                        id: "account-\(account.id)-selector-empty",
                        severity: .warning,
                        message: "\(account.displayName) 缺少唯一账号片段，运行时会跳过该账号"
                    ))
                }
                let selectors = enabledAccounts
                    .map { $0.accountSelector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                if Set(selectors).count != selectors.count {
                    result.append(.init(
                        id: "client-\(client.id)-selector-duplicate",
                        severity: .error,
                        message: "\(clientName) 的账号片段不能重复"
                    ))
                }
            }
        }
        return result
    }

    private static func validate(
        _ value: FightConfiguration,
        prefix: String,
        planName: String,
        into result: inout [ConfigurationProblem]
    ) {
        let name = ConfigurationDisplayName.resolve(planName, fallback: "未命名方案")
        let checks: [(String, Bool, String)] = [
            ("medicine", value.medicine.map { $0 >= 0 } ?? true, "理智药数量不能为负数"),
            ("medicine-expire-days", value.medicineExpireDays.map { (1...365).contains($0) } ?? true, "临期理智药天数必须在 1 到 365 之间"),
            ("stone", value.stone.map { $0 >= 0 } ?? true, "源石数量不能为负数"),
            ("times", value.times.map { $0 > 0 } ?? true, "作战次数必须大于 0"),
            ("series", value.series.map { (-1...10).contains($0) } ?? true, "连战次数必须在 -1 到 10 之间"),
        ]
        for (field, valid, message) in checks where !valid {
            result.append(.init(id: "\(prefix)-\(field)", severity: .error, message: "「\(name)」的\(message)"))
        }
    }

    private static func validate(
        _ value: RecruitConfiguration,
        prefix: String,
        planName: String,
        into result: inout [ConfigurationProblem]
    ) {
        let name = ConfigurationDisplayName.resolve(planName, fallback: "未命名方案")
        if !(0...12).contains(value.times) {
            result.append(.init(id: "\(prefix)-times", severity: .error, message: "「\(name)」的招募次数必须在 0 到 12 之间"))
        }
        for (field, values) in [("首选标签", value.firstTags), ("保留标签", value.preserveTags)] {
            let normalized = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if normalized.contains(where: \.isEmpty) || Set(normalized).count != normalized.count {
                result.append(.init(
                    id: "\(prefix)-tags-\(field)",
                    severity: .error,
                    message: "「\(name)」的\(field)不能包含空值或重复项"
                ))
            }
        }
    }

    private static func validate(
        _ value: InfrastConfiguration,
        prefix: String,
        planName: String,
        into result: inout [ConfigurationProblem]
    ) {
        let name = ConfigurationDisplayName.resolve(planName, fallback: "未命名方案")
        if value.mode != .customSchedule,
           (value.facilities.isEmpty || Set(value.facilities).count != value.facilities.count) {
            result.append(.init(
                id: "\(prefix)-facilities",
                severity: .error,
                message: "「\(name)」必须选择至少一个且不重复的基建设施"
            ))
        }
        if !(0...1).contains(value.threshold) {
            result.append(.init(id: "\(prefix)-threshold", severity: .error, message: "「\(name)」的基建心情阈值必须在 0 到 1 之间"))
        }
        if value.customSchedulePlanIndex < 0 {
            result.append(.init(id: "\(prefix)-plan-index", severity: .error, message: "「\(name)」的基建排班方案序号不能为负数"))
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
