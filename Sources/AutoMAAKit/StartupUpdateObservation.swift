import Foundation

enum StartupUpdateObservation {
    static func isWaitingForDownload(_ log: MAACoreLog) -> Bool {
        guard log.isComplete else { return false }
        var waiting = false
        for line in log.lines {
            guard let marker = line.range(of: "Assistant::append_callback | ") else {
                if line.contains("[ERR]") || line.contains("[ERROR]") { waiting = false }
                continue
            }
            let payload = line[marker.upperBound...]
            guard let separator = payload.firstIndex(of: " "),
                  let data = payload[separator...].data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return false }
            let kind = payload[..<separator]
            if kind == "InitFailed" { return false }
            if kind == "ConnectionInfo", let what = event["what"] as? String,
               what.hasSuffix("Failed") || what == "Disconnect" { return false }
            switch kind {
            case "SubTaskStart", "SubTaskCompleted":
                let task = (event["details"] as? [String: Any])?["task"] as? String
                waiting = event["taskchain"] as? String == "StartUp"
                    && event["subtask"] as? String == "ProcessTask"
                    && (task == "GameStartUpdateOCR" || task == "StartUp@GameStartUpdateOCR")
            case "TaskChainStart", "TaskChainCompleted", "TaskChainStopped", "TaskChainError",
                 "SubTaskError", "AllTasksCompleted":
                waiting = false
            default: break
            }
        }
        return waiting
    }
}
