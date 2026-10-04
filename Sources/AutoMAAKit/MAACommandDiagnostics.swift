import Foundation

/// Observations for diagnostics only; never used to decide task success or recovery.
struct MAACommandDiagnostics: Sendable {
    private(set) var lastStarted: String?
    private(set) var lastCompleted: String?
    private(set) var lastError: String?
    private(set) var notes: [String] = []
    private var lines: [String] = []
    private var byteCount = 0

    static let readLimit = 262_144
    static let outputLimit = 65_536

    var output: String { lines.joined(separator: "\n") }

    var summary: String {
        var parts: [String] = []
        if let lastStarted { parts.append("最后观察到开始：\(lastStarted)") }
        if let lastCompleted { parts.append("最后观察到完成：\(lastCompleted)") }
        if let lastError { parts.append("最后核心错误：\(lastError)") }
        if lastStarted == nil, lastCompleted == nil { parts.append("未取得可识别的步骤回调，最后执行步骤未确认") }
        parts += notes
        return parts.joined(separator: "\n")
    }

    static func read(from root: URL, sensitiveValues: [String]) -> Self {
        var result = Self()
        var foundLog = false
        for name in ["asst.bak.log", "asst.log"] {
            let url = root.appending(path: "debug/\(name)")
            do {
                let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
                    result.note("核心日志读取失败：\(name) 不是普通文件")
                    continue
                }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                foundLog = true
                let size = try handle.seekToEnd()
                let offset = size > UInt64(readLimit) ? size - UInt64(readLimit) : 0
                try handle.seek(toOffset: offset)
                let data = try handle.read(upToCount: readLimit) ?? Data()
                // Discard partial boundary lines before decoding or redacting them.
                var lines = data.split(separator: 10, omittingEmptySubsequences: false).dropLast()
                if offset > 0 {
                    lines = lines.dropFirst()
                    result.note("核心日志较长，仅分析末尾片段，较早步骤可能缺失")
                }
                if data.last != 10, !data.isEmpty { result.note("核心日志末尾不完整，已忽略未写完的行") }
                for line in lines {
                    guard line.count <= outputLimit / 2 else {
                        result.note("已忽略过长的核心日志行")
                        continue
                    }
                    result.consume(String(decoding: line, as: UTF8.self), sensitiveValues: sensitiveValues)
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                continue
            } catch {
                result.note("核心日志读取失败：\(name)")
            }
        }
        if !foundLog { result.note("本次命令没有可读取的核心日志") }
        return result
    }

    private mutating func consume(_ line: String, sensitiveValues: [String]) {
        let marker = "Assistant::append_callback | "
        let isError = line.contains("[ERR]") || line.contains("[ERROR]")
        guard let range = line.range(of: marker) else {
            if isError {
                let value = SensitiveDataRedactor.redact(line, sensitiveValues: sensitiveValues)
                lastError = String(value.prefix(240))
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
        if event.hasSuffix("Error") || event == "InitFailed"
            || (event == "ConnectionInfo" && (object["what"] as? String).map({ $0.hasSuffix("Failed") || $0 == "Disconnect" }) == true) {
            let fields = [event, description, object["what"] as? String, object["why"] as? String]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            lastError = String(SensitiveDataRedactor.redact(fields, sensitiveValues: sensitiveValues).prefix(240))
        }
        append(SensitiveDataRedactor.redact(line, sensitiveValues: sensitiveValues))
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
