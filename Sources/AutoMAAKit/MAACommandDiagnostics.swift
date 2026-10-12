import Foundation

/// Observations for diagnostics only; never used to decide task success or recovery.
struct MAACommandDiagnostics: Sendable {
    private(set) var firstIssue: String?
    private(set) var lastStarted: String?
    private(set) var lastCompleted: String?
    private(set) var lastError: String?
    private(set) var notes: [String] = []
    private var lines: [String] = []
    private var byteCount = 0

    static let readLimit = MAACoreLog.readLimit
    static let outputLimit = 65_536

    var output: String { lines.joined(separator: "\n") }

    var summary: String {
        var parts: [String] = []
        if let firstIssue { parts.append("首次观察到异常：\(firstIssue)") }
        if let lastStarted { parts.append("最后观察到开始：\(lastStarted)") }
        if let lastCompleted { parts.append("最后观察到完成：\(lastCompleted)") }
        if let lastError { parts.append("最后核心错误：\(lastError)") }
        if lastStarted == nil, lastCompleted == nil { parts.append("未取得可识别的步骤回调，最后执行步骤未确认") }
        parts += notes
        return parts.joined(separator: "\n")
    }

    static func read(from root: URL, sensitiveValues: [String]) -> Self {
        Self(log: MAACoreLog.read(from: root), sensitiveValues: sensitiveValues)
    }

    init(log: MAACoreLog, sensitiveValues: [String]) {
        notes = log.notes
        for line in log.lines { consume(line, sensitiveValues: sensitiveValues) }
    }

    private mutating func consume(_ line: String, sensitiveValues: [String]) {
        let marker = "Assistant::append_callback | "
        let isError = line.contains("[ERR]") || line.contains("[ERROR]")
        guard let range = line.range(of: marker) else {
            if isError {
                let value = SensitiveDataRedactor.redact(line, sensitiveValues: sensitiveValues)
                observeIssue(value, isError: true)
                append(value)
            }
            return
        }
        // Parse the original JSON; masking before parsing can invalidate numeric values.
        let payload = line[range.upperBound...]
        guard let separator = payload.firstIndex(of: " "),
              let data = payload[separator...].data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            note("存在无法解析的核心回调，部分步骤未确认")
            return
        }
        let event = String(payload[..<separator])
        let details = object["details"] as? [String: Any] ?? [:]
        let step = details["task"] as? String ?? object["subtask"] as? String
        let description = [object["taskchain"] as? String, step].compactMap { $0 }.joined(separator: " / ")
        let label = String(SensitiveDataRedactor.redact(description, sensitiveValues: sensitiveValues).prefix(160))
        if !label.isEmpty {
            if event == "SubTaskStart" || event == "TaskChainStart" { lastStarted = label }
            if event == "SubTaskCompleted" || event == "TaskChainCompleted" { lastCompleted = label }
        }
        if event == "SubTaskStart", step == "OfflineConfirm" || step == "OfflineConfirmImpl" {
            observeIssue(label, isError: false)
        }
        if event.hasSuffix("Error") || event == "InitFailed"
            || (event == "ConnectionInfo" && (object["what"] as? String).map({ $0.hasSuffix("Failed") || $0 == "Disconnect" }) == true) {
            let fields = [event, description, object["what"] as? String, object["why"] as? String]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            observeIssue(SensitiveDataRedactor.redact(fields, sensitiveValues: sensitiveValues), isError: true)
        }
        append(SensitiveDataRedactor.redact(line, sensitiveValues: sensitiveValues))
    }

    private mutating func observeIssue(_ redactedValue: String, isError: Bool) {
        let value = String(redactedValue.prefix(240))
        if firstIssue == nil { firstIssue = value }
        if isError { lastError = value }
    }

    private mutating func append(_ line: String) {
        guard line.utf8.count + 1 <= Self.outputLimit else { note("已忽略过长的核心日志行"); return }
        lines.append(line)
        byteCount += line.utf8.count + 1
        while byteCount > Self.outputLimit {
            byteCount -= lines.removeFirst().utf8.count + 1
            note("核心回调仅保留最近片段")
        }
    }

    private mutating func note(_ value: String) {
        if !notes.contains(value) { notes.append(value) }
    }
}
