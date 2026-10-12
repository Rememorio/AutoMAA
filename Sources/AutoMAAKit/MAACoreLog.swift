import Foundation

/// A bounded, command-local snapshot. Raw lines live only until the command is classified and redacted.
struct MAACoreLog: Sendable {
    var lines: [String] = []
    var notes: [String] = []
    var isComplete: Bool { notes.isEmpty }

    static let readLimit = 262_144
    static let lineLimit = 32_768

    static func read(from root: URL) -> Self {
        var result = Self()
        var foundLog = false
        var foundCurrentLog = false
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
                if name == "asst.log" { foundCurrentLog = true }
                let size = try handle.seekToEnd()
                let offset = size > UInt64(readLimit) ? size - UInt64(readLimit) : 0
                try handle.seek(toOffset: offset)
                let data = try handle.read(upToCount: readLimit) ?? Data()
                var lines = data.split(separator: 10, omittingEmptySubsequences: false).dropLast()
                if offset > 0 {
                    lines = lines.dropFirst()
                    result.note("核心日志较长，仅分析末尾片段，较早步骤可能缺失")
                }
                if data.last != 10, !data.isEmpty { result.note("核心日志末尾不完整，已忽略未写完的行") }
                for line in lines {
                    guard line.count <= lineLimit else {
                        result.note("已忽略过长的核心日志行")
                        continue
                    }
                    guard let text = String(bytes: line, encoding: .utf8) else {
                        result.note("存在无法解码的核心日志行")
                        continue
                    }
                    result.lines.append(text)
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                continue
            } catch {
                result.note("核心日志读取失败：\(name)")
            }
        }
        if !foundLog { result.note("本次命令没有可读取的核心日志") }
        else if !foundCurrentLog { result.note("仅取得轮转备份，当前核心日志不可用") }
        return result
    }

    private mutating func note(_ value: String) {
        if !notes.contains(value) { notes.append(value) }
    }
}
