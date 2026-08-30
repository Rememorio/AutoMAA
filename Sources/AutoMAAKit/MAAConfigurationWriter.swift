import Foundation

public enum MAAConfigurationWriterError: LocalizedError, Equatable {
    case invalidConfiguration(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidConfiguration(message): message
        }
    }
}

public struct MAAConfigurationWriter: Sendable {
    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func prepare(
        _ configuration: AppConfiguration,
        fightStageMemory: FightStageMemory = .init()
    ) throws {
        try directories.prepare()
        try validate(configuration)
        var generated: Set<String> = []
        for client in configuration.clients {
            generated.insert("profiles/\(safeName(client.profileName)).toml")
            try writeProfile(for: client)
            for plan in configuration.plans {
                for account in client.accounts {
                    for task in TaskKind.allCases {
                        let fightStageResolution = task == .fight
                            ? FightStagePolicy.resolve(
                                plan.fight,
                                memory: fightStageMemory,
                                clientID: client.id,
                                accountID: account.id
                            )
                            : .omitted
                        guard fightStageResolution != .unavailable else { continue }
                        generated.insert("tasks/\(taskName(planID: plan.id, clientID: client.id, accountID: account.id, task: task)).json")
                        try writeTask(
                            task,
                            plan: plan,
                            account: account,
                            client: client,
                            fightStageResolution: fightStageResolution
                        )
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
        if let problem = ConfigurationValidator.structuralProblems(in: configuration).first(where: {
            $0.severity == .error
        }) {
            throw MAAConfigurationWriterError.invalidConfiguration(problem.message)
        }
    }

    private func writeProfile(for client: ClientConfiguration) throws {
        let lines = [
            "[connection]",
            "preset = \"PlayCover\"",
            "address = \"\(escaped(client.address))\"",
            "",
        ]
        let url = directories.maaConfig
            .appending(path: "profiles")
            .appending(path: "\(safeName(client.profileName)).toml")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeTask(
        _ task: TaskKind,
        plan: AutomationPlan,
        account: AccountConfiguration,
        client: ClientConfiguration,
        fightStageResolution: FightStageResolution
    ) throws {
        let parameters: [String: Any]
        switch task {
        case .fight:
            var value: [String: Any] = [
                "server": client.kind.serverCode,
                "client_type": client.kind.maaTaskClientType,
            ]
            if plan.fight.usesCustomSettings {
                guard case let .value(stage) = fightStageResolution else {
                    throw MAAConfigurationWriterError.invalidConfiguration(
                        "「\(plan.displayName)」缺少\(client.displayName) / \(account.displayName)的常规关卡记录"
                    )
                }
                value["stage"] = stage
                if let medicine = plan.fight.medicine { value["medicine"] = medicine }
                if let medicineExpireDays = plan.fight.medicineExpireDays {
                    value["medicine_expire_days"] = medicineExpireDays
                }
                if let stone = plan.fight.stone { value["stone"] = stone }
                if let times = plan.fight.times { value["times"] = times }
                if let series = plan.fight.series { value["series"] = series }
                value["DrGrandet"] = plan.fight.drGrandet
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
                    "first_tags": plan.recruit.firstTags,
                    "extra_tags_mode": plan.recruit.extraTagsMode.rawValue,
                    "times": plan.recruit.times,
                    "set_time": true,
                    "expedite": plan.recruit.expedite,
                    "expedite_times": 999,
                    "preserve_tags": plan.recruit.preserveTags,
                    "recruitment_time": ["3": 540, "4": 540, "5": 540, "6": 540],
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
                    "preserve_tags": ["支援机械"],
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
                    "filename": plan.infrast.mode == .customSchedule
                        ? plan.infrast.customSchedulePath.trimmingCharacters(in: .whitespacesAndNewlines)
                        : "",
                    "plan_index": plan.infrast.mode == .customSchedule
                        ? plan.infrast.customSchedulePlanIndex
                        : 0,
                ]
            } else {
                parameters = [
                    "mode": 0,
                    "facility": [
                        "Mfg", "Trade", "Control", "Power", "Reception",
                        "Office", "Dorm", "Processing", "Training",
                    ],
                    "drones": "_NotUse",
                    "threshold": InfrastConfiguration.maaDefaultThreshold,
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
                    "specialaccess": plan.award.specialAccess,
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
            "client_type": client.kind.maaClientType,
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
        MAAProfileName.normalize(value)
    }

    private func escaped(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x08: "\\b"
            case 0x09: "\\t"
            case 0x0A: "\\n"
            case 0x0C: "\\f"
            case 0x0D: "\\r"
            case 0x22: "\\\""
            case 0x5C: "\\\\"
            case 0x00...0x1F, 0x7F: String(format: "\\u%04X", scalar.value)
            default: String(scalar)
            }
        }.joined()
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
