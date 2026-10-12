import Foundation

/// Recognizes a failed return from Settings, before the account picker or login flow is reached.
enum StartupNavigationObservation {
    private enum Stage {
        case none, started, switching, openingSettings, settingsCompleted, navigationFailed, accountFailed, failed
    }

    static func failedInSettings(_ log: MAACoreLog) -> Bool {
        guard log.isComplete else { return false }
        var stage = Stage.none
        for line in log.lines {
            guard let marker = line.range(of: "Assistant::append_callback | ") else { continue }
            let payload = line[marker.upperBound...]
            guard let separator = payload.firstIndex(of: " "),
                  let data = payload[separator...].data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            let kind = payload[..<separator]
            if kind == "InitFailed" { return false }
            if kind == "ConnectionInfo", let what = event["what"] as? String,
               what.hasSuffix("Failed") || what == "Disconnect" { return false }
            guard event["taskchain"] as? String == "StartUp" else { continue }
            let subtask = event["subtask"] as? String
            let task = (event["details"] as? [String: Any])?["task"] as? String
            let isNavigation = event["first"] as? [String] == ["SwitchAccount@StartUpBegin"]
            switch kind {
            case "TaskChainStart": stage = .started
            case "TaskChainCompleted", "TaskChainStopped": stage = .none
            case "SubTaskStart":
                if subtask == "AccountSwitchTask" {
                    stage = stage == .started ? .switching : .none
                } else if subtask == "ProcessTask", stage == .switching, isNavigation, task == "Settings" {
                    stage = .openingSettings
                } else if subtask != "ProcessTask" || stage != .switching || !isNavigation
                    || !["StartUpBegin", "SwitchAccount", "ReturnButton"].contains(task ?? "") {
                    stage = .none
                }
            case "SubTaskCompleted":
                if stage == .openingSettings, subtask == "ProcessTask", isNavigation, task == "Settings" {
                    stage = .settingsCompleted
                } else if subtask != "ProcessTask" || stage != .switching || !isNavigation
                    || !["StartUpBegin", "SwitchAccount", "ReturnButton"].contains(task ?? "") {
                    stage = .none
                }
            case "SubTaskError":
                if stage == .settingsCompleted, subtask == "ProcessTask", isNavigation {
                    stage = .navigationFailed
                } else if stage == .navigationFailed, subtask == "AccountSwitchTask" {
                    stage = .accountFailed
                } else {
                    stage = .none
                }
            case "TaskChainError": stage = stage == .accountFailed ? .failed : .none
            default: break
            }
        }
        return stage == .failed
    }
}
