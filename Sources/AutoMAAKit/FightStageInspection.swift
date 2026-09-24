import Foundation

/// A separate Custom command navigates and observes; it never appends a Fight task.
enum FightStageInspection: Equatable, Sendable {
    case regular(String)
    case annihilation
    case unavailable
    case unknown

    static let taskName = "automaa-stage-inspection"

    static func read(_ callbacks: String, command: CommandResult) -> Self? {
        guard command.exitCode == 0, !command.timedOut, !command.cancelled else { return nil }
        var completed = false
        var failed = false
        var observation: Self?
        for line in callbacks.split(separator: "\n") {
            guard let marker = line.range(of: "Assistant::append_callback | "),
                  let brace = line[marker.upperBound...].firstIndex(of: "{"),
                  let data = String(line[brace...]).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  event["taskchain"] as? String == "Custom" else { continue }
            let kind = line[marker.upperBound..<brace].trimmingCharacters(in: .whitespaces)
            if kind == "TaskChainCompleted" { completed = true }
            if ["TaskChainError", "TaskChainStopped", "SubTaskError"].contains(kind) { failed = true }
            guard kind == "SubTaskCompleted", let details = event["details"] as? [String: Any],
                  details["action"] as? String == "DoNothing" else { continue }
            switch details["task"] as? String {
            case "AutoMAAInspectAnnihilation", "AutoMAAInspectAnnihilationActive": observation = .annihilation
            case "AutoMAAInspectStage":
                let text = (details["result"] as? [String: Any])?["text"] as? String ?? ""
                observation = FightStagePolicy.regularStage(from: text, times: 1).map(Self.regular) ?? .unknown
            case "AutoMAAInspectUnknown": observation = .unknown
            case "AutoMAAInspectUnavailable": observation = .unavailable
            default: break
            }
        }
        return completed && !failed ? observation : nil
    }

    static func prepare(at root: URL, client: ClientConfiguration) throws {
        let manager = FileManager.default
        for path in ["profiles", "tasks", "resource/tasks"] {
            try manager.createDirectory(at: root.appending(path: path), withIntermediateDirectories: true)
        }
        // JSON avoids interpolating connection values into TOML. This profile is used only by the probe.
        let profile: [String: Any] = [
            "connection": ["preset": "PlayCover", "address": client.address],
            "resource": ["user_resource": true],
        ]
        let task: [String: Any] = [
            "client_type": client.kind.maaClientType,
            "tasks": [["type": "Custom", "params": ["task_names": ["AutoMAAInspect"]]]],
        ]
        for (path, object) in [("profiles/\(taskName).json", profile), ("tasks/\(taskName).json", task),
                               ("resource/tasks/automaa-inspection.json", resourceTasks)] {
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                .write(to: root.appending(path: path), options: .atomic)
        }
    }

    static var resourceTasks: [String: Any] {
        func node(_ base: String, next: [String] = []) -> [String: Any] {
            ["baseTask": base, "action": "DoNothing", "sub": [], "next": next,
             "onErrorNext": [], "exceededNext": [], "reduceOtherTimes": [], "maxTimes": 3]
        }
        let entry = "AutoMAAInspect"
        var home = node("Fight", next: [entry])
        home["template"] = "SwitchTheme@ToggleSettingsMenu.png"
        home["sub"] = ["Terminal-Entry"]
        var last = node("GoLastBattle", next: [entry])
        last["action"] = "ClickSelf"
        last["maxTimes"] = 1
        last["exceededNext"] = ["AutoMAAInspectUnavailable"]
        var stage = node("ClickedCorrectStage")
        stage["text"] = [String]()
        var annihilation = node("UsePrts-Annihilation")
        annihilation["template"] = "UsePrts-Annihilation.png"
        var annihilationActive = node("UsePrts-AnnihilationSuccess")
        annihilationActive["template"] = "UsePrts-AnnihilationSuccess.png"
        return [
            entry: ["algorithm": "JustReturn", "next": ["AutoMAAInspectReady", "AutoMAAInspectLast", "AutoMAAInspectHome"]],
            "AutoMAAInspectHome": home,
            "AutoMAAInspectLast": last,
            "AutoMAAInspectReady": node("StartButton1", next: ["AutoMAAInspectAnnihilation", "AutoMAAInspectAnnihilationActive", "AutoMAAInspectStage", "AutoMAAInspectUnknown"]),
            "AutoMAAInspectAnnihilation": annihilation,
            "AutoMAAInspectAnnihilationActive": annihilationActive,
            "AutoMAAInspectStage": stage,
            "AutoMAAInspectUnknown": ["algorithm": "JustReturn", "action": "DoNothing"],
            "AutoMAAInspectUnavailable": ["algorithm": "JustReturn", "action": "DoNothing"],
        ]
    }
}
