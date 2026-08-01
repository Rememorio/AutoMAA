import Foundation

public struct MAAConfigurationWriter: Sendable {
    public let directories: AppDirectories

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func prepare(_ configuration: AppConfiguration) throws {
        try directories.prepare()
        var generated: Set<String> = []
        for client in configuration.clients {
            generated.insert("profiles/\(safeName(client.profileName)).toml")
            try writeProfile(for: client)
            for account in client.accounts {
                for task in TaskKind.allCases {
                    generated.insert("tasks/\(taskName(clientID: client.id, accountID: account.id, task: task)).json")
                    try writeTask(task, account: account, client: client)
                }
            }
        }
        try removeStaleGeneratedFiles(keeping: generated)
        try removeOrphanedTaskFiles(keeping: generated)
        let manifest = try JSONEncoder().encode(generated.sorted())
        try manifest.write(to: directories.generatedManifest, options: .atomic)
    }

    public func taskName(clientID: UUID, accountID: UUID, task: TaskKind) -> String {
        "\(clientID.uuidString.lowercased())-\(accountID.uuidString.lowercased())-\(task.rawValue)"
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

    private func writeTask(_ task: TaskKind, account: AccountConfiguration, client: ClientConfiguration) throws {
        let parameters: [String: Any]
        switch task {
        case .fight:
            var value: [String: Any] = [
                "stage": account.fight.usesCustomSettings
                    ? account.fight.stage.trimmingCharacters(in: .whitespacesAndNewlines)
                    : "",
                "server": client.kind.serverCode,
                "client_type": client.kind.maaTaskClientType,
                "DrGrandet": account.fight.usesCustomSettings && account.fight.drGrandet,
            ]
            if account.fight.usesCustomSettings {
                if let medicine = account.fight.medicine { value["medicine"] = medicine }
                if let expiringMedicine = account.fight.expiringMedicine {
                    value["expiring_medicine"] = expiringMedicine
                }
                if let stone = account.fight.stone { value["stone"] = stone }
                if let times = account.fight.times { value["times"] = times }
                if let series = account.fight.series { value["series"] = series }
            }
            parameters = value
        case .recruit:
            if account.recruit.usesCustomSettings {
                let confirm = [
                    account.recruit.autoConfirm3 ? 3 : nil,
                    account.recruit.autoConfirm4 ? 4 : nil,
                    account.recruit.autoConfirm5 ? 5 : nil,
                    account.recruit.autoConfirm6 ? 6 : nil,
                ].compactMap { $0 }
                parameters = [
                    "refresh": account.recruit.refresh,
                    "select": [5, 4],
                    "confirm": confirm,
                    "times": account.recruit.times,
                    "expedite": account.recruit.expedite,
                    "skip_robot": account.recruit.preserveRobot,
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
            if account.infrast.usesCustomSettings {
                var facilities: [String] = []
                if account.infrast.collectManufacturing { facilities.append("Mfg") }
                if account.infrast.collectTrading { facilities.append("Trade") }
                if account.infrast.collectReception { facilities.append("Reception") }
                parameters = [
                    "mode": 20_000,
                    "facility": facilities,
                    "drones": account.infrast.drones.rawValue,
                    "reception_message_board": account.infrast.collectReception,
                    "reception_clue_exchange": account.infrast.collectReception,
                    "reception_send_clue": account.infrast.collectReception,
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
                    "filename": "",
                    "plan_index": 0,
                ]
            }
        case .award:
            if account.award.usesCustomSettings {
                parameters = [
                    "award": account.award.dailyWeekly,
                    "mail": account.award.mail,
                    "recruit": account.award.freeRecruit,
                    "orundum": account.award.orundum,
                    "mining": account.award.mining,
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
            .appending(path: "\(taskName(clientID: client.id, accountID: account.id, task: task)).json")
        try data.write(to: url, options: .atomic)
    }

    private func maaTaskType(_ task: TaskKind) -> String {
        switch task {
        case .fight: "Fight"
        case .recruit: "Recruit"
        case .infrast: "Infrast"
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
        let pattern = #"^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}-[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}-(fight|recruit|infrast|award)\.json$"#
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
