import Foundation

public enum MAAConfigurationWriterError: LocalizedError, Equatable {
    case duplicateProfileName
    case duplicateClientID
    case duplicateAccountID
    case duplicatePlanID

    public var errorDescription: String? {
        switch self {
        case .duplicateProfileName: "每个客户端必须使用不同的 MAA Profile 名称"
        case .duplicateClientID: "客户端标识重复，请删除并重新添加重复项"
        case .duplicateAccountID: "账号标识重复，请删除并重新添加重复项"
        case .duplicatePlanID: "自动化方案标识重复，请删除并重新添加重复项"
        }
    }
}

public struct MAAConfigurationWriter: Sendable {
    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func prepare(_ configuration: AppConfiguration) throws {
        try directories.prepare()
        try validate(configuration)
        var generated: Set<String> = []
        for client in configuration.clients {
            generated.insert("profiles/\(safeName(client.profileName)).toml")
            try writeProfile(for: client)
            for plan in configuration.plans {
                for account in client.accounts {
                    for task in TaskKind.allCases {
                        generated.insert("tasks/\(taskName(planID: plan.id, clientID: client.id, accountID: account.id, task: task)).json")
                        try writeTask(task, plan: plan, account: account, client: client)
                    }
                }
            }
        }
        try removeStaleGeneratedFiles(keeping: generated)
        try removeOrphanedTaskFiles(keeping: generated)
        let manifest = try JSONEncoder().encode(generated.sorted())
        try manifest.write(to: directories.generatedManifest, options: .atomic)
    }

    public func taskName(planID: UUID, clientID: UUID, accountID: UUID, task: TaskKind) -> String {
        "\(planID.uuidString.lowercased())-\(clientID.uuidString.lowercased())-\(accountID.uuidString.lowercased())-\(task.rawValue)"
    }

    private func validate(_ configuration: AppConfiguration) throws {
        let profileNames = configuration.clients.map { safeName($0.profileName) }
        guard Set(profileNames).count == profileNames.count else {
            throw MAAConfigurationWriterError.duplicateProfileName
        }
        let clientIDs = configuration.clients.map(\.id)
        guard Set(clientIDs).count == clientIDs.count else {
            throw MAAConfigurationWriterError.duplicateClientID
        }
        let accountIDs = configuration.clients.flatMap { $0.accounts.map(\.id) }
        guard Set(accountIDs).count == accountIDs.count else {
            throw MAAConfigurationWriterError.duplicateAccountID
        }
        let planIDs = configuration.plans.map(\.id)
        guard Set(planIDs).count == planIDs.count else {
            throw MAAConfigurationWriterError.duplicatePlanID
        }
    }

    private func writeProfile(for client: ClientConfiguration) throws {
        var lines = [
            "[connection]",
            "preset = \"PlayCover\"",
            "address = \"\(escaped(client.address))\"",
        ]
        if let globalResource = client.kind.resourceName {
            lines.append("")
            lines.append("[resource]")
            lines.append("global_resource = \"\(globalResource)\"")
        }
        lines.append("")
        let url = directories.maaConfig
            .appending(path: "profiles")
            .appending(path: "\(safeName(client.profileName)).toml")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeTask(
        _ task: TaskKind,
        plan: AutomationPlan,
        account: AccountConfiguration,
        client: ClientConfiguration
    ) throws {
        let parameters: [String: Any]
        switch task {
        case .fight:
            var value: [String: Any] = [
                "stage": plan.fight.usesCustomSettings
                    ? plan.fight.stage.trimmingCharacters(in: .whitespacesAndNewlines)
                    : "",
                "server": client.kind.serverCode,
                "client_type": client.kind.maaTaskClientType,
                "DrGrandet": plan.fight.usesCustomSettings && plan.fight.drGrandet,
            ]
            if plan.fight.usesCustomSettings {
                if let medicine = plan.fight.medicine { value["medicine"] = medicine }
                if let expiringMedicine = plan.fight.expiringMedicine {
                    value["expiring_medicine"] = expiringMedicine
                }
                if let stone = plan.fight.stone { value["stone"] = stone }
                if let times = plan.fight.times { value["times"] = times }
                if let series = plan.fight.series { value["series"] = series }
            }
            parameters = value
        case .recruit:
            if plan.recruit.usesCustomSettings {
                let confirm = [
                    plan.recruit.autoConfirm3 ? 3 : nil,
                    plan.recruit.autoConfirm4 ? 4 : nil,
                    plan.recruit.autoConfirm5 ? 5 : nil,
                    plan.recruit.autoConfirm6 ? 6 : nil,
                ].compactMap { $0 }
                parameters = [
                    "refresh": plan.recruit.refresh,
                    "select": [5, 4],
                    "confirm": confirm,
                    "times": plan.recruit.times,
                    "expedite": plan.recruit.expedite,
                    "skip_robot": plan.recruit.preserveRobot,
                    "server": client.kind.serverCode,
                ]
            } else {
                parameters = [
                    "refresh": false,
                    "select": [4, 5],
                    "confirm": [3, 4, 5],
                    "first_tags": [],
                    "extra_tags_mode": 0,
                    "times": 4,
                    "set_time": true,
                    "expedite": false,
                    "expedite_times": 999,
                    "skip_robot": true,
                    "recruitment_time": ["3": 540, "4": 540, "5": 540, "6": 540],
                    "report_to_penguin": false,
                    "penguin_id": "",
                    "report_to_yituliu": false,
                    "yituliu_id": "",
                    "server": client.kind.serverCode,
                ]
            }
        case .infrast:
            if plan.infrast.usesCustomSettings {
                parameters = [
                    "mode": plan.infrast.mode.rawValue,
                    "facility": plan.infrast.facilities.map(\.rawValue),
                    "drones": plan.infrast.drones.rawValue,
                    "threshold": plan.infrast.threshold,
                    "replenish": plan.infrast.replenish,
                    "dorm_notstationed_enabled": plan.infrast.dormNotStationed,
                    "dorm_trust_enabled": plan.infrast.dormTrust,
                    "continue_training": plan.infrast.continueTraining,
                    "reception_message_board": plan.infrast.receptionMessageBoard,
                    "reception_clue_exchange": plan.infrast.receptionClueExchange,
                    "reception_send_clue": plan.infrast.receptionSendClue,
                    "filename": "",
                    "plan_index": 0,
                ]
            } else {
                parameters = [
                    "mode": 0,
                    "facility": [
                        "Mfg", "Trade", "Control", "Power", "Reception",
                        "Office", "Dorm", "Processing", "Training",
                    ],
                    "drones": "_NotUse",
                    "threshold": 0.3,
                    "replenish": false,
                    "dorm_notstationed_enabled": false,
                    "dorm_trust_enabled": false,
                    "continue_training": true,
                    "reception_message_board": true,
                    "reception_clue_exchange": true,
                    "reception_send_clue": true,
                    "filename": "",
                    "plan_index": 0,
                ]
            }
        case .mall:
            if plan.mall.usesCustomSettings {
                parameters = [
                    "visit_friends": plan.mall.visitFriends,
                    "shopping": plan.mall.shopping,
                    "buy_first": plan.mall.buyFirst,
                    "blacklist": plan.mall.blacklist,
                    "force_shopping_if_credit_full": plan.mall.forceShoppingIfCreditFull,
                    "only_buy_discount": plan.mall.onlyBuyDiscount,
                    "reserve_max_credit": plan.mall.reserveMaxCredit,
                    "credit_fight": plan.mall.creditFight,
                    "formation_index": plan.mall.formationIndex,
                ]
            } else {
                parameters = [
                    "visit_friends": true,
                    "shopping": true,
                    "buy_first": ["招聘许可", "龙门币"],
                    "blacklist": ["加急许可", "家具零件"],
                    "force_shopping_if_credit_full": true,
                    "only_buy_discount": false,
                    "reserve_max_credit": false,
                    "credit_fight": false,
                    "formation_index": 0,
                ]
            }
        case .award:
            if plan.award.usesCustomSettings {
                parameters = [
                    "award": plan.award.dailyWeekly,
                    "mail": plan.award.mail,
                    "recruit": plan.award.freeRecruit,
                    "orundum": plan.award.orundum,
                    "mining": plan.award.mining,
                    "specialaccess": false,
                ]
            } else {
                parameters = [
                    "award": true,
                    "mail": false,
                    "recruit": false,
                    "orundum": false,
                    "mining": false,
                    "specialaccess": false,
                ]
            }
        }

        let payload: [String: Any] = [
            "tasks": [[
                "name": task.title,
                "type": maaTaskType(task),
                "params": parameters,
            ]],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        let url = directories.maaConfig
            .appending(path: "tasks")
            .appending(path: "\(taskName(planID: plan.id, clientID: client.id, accountID: account.id, task: task)).json")
        try data.write(to: url, options: .atomic)
    }

    private func maaTaskType(_ task: TaskKind) -> String {
        switch task {
        case .fight: "Fight"
        case .recruit: "Recruit"
        case .infrast: "Infrast"
        case .mall: "Mall"
        case .award: "Award"
        }
    }

    private func safeName(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "default" : trimmed
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func removeStaleGeneratedFiles(keeping generated: Set<String>) throws {
        guard let data = try? Data(contentsOf: directories.generatedManifest),
              let previous = try? JSONDecoder().decode([String].self, from: data)
        else { return }
        for relativePath in Set(previous).subtracting(generated) {
            guard relativePath.hasPrefix("profiles/") || relativePath.hasPrefix("tasks/"),
                  !relativePath.contains("..")
            else { continue }
            let url = directories.maaConfig.appending(path: relativePath)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func removeOrphanedTaskFiles(keeping generated: Set<String>) throws {
        let tasksDirectory = directories.maaConfig.appending(path: "tasks")
        let uuid = #"[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}"#
        let pattern = "^(?:\(uuid)-){2,3}(fight|recruit|infrast|mall|award)\\.json$"
        let expression = try NSRegularExpression(pattern: pattern)
        let files = try FileManager.default.contentsOfDirectory(at: tasksDirectory, includingPropertiesForKeys: nil)
        for url in files {
            let name = url.lastPathComponent
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            guard expression.firstMatch(in: name, range: range) != nil,
                  !generated.contains("tasks/\(name)")
            else { continue }
            try FileManager.default.removeItem(at: url)
        }
    }
}
