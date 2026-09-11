import Foundation

enum MAARecruitmentNotice: Equatable, Hashable, Sendable {
    case highRarity(level: Int, tags: [String])
    case preservedTag(tag: String, tags: [String])
    case specialTag(String)
}

enum MAAOutputNoticeParser {
    enum RecruitmentAction: String {
        case recruited, refreshed
    }

    struct RecruitmentResult {
        let level: Int
        var tags: [String]
        var action: RecruitmentAction?

        func matches(_ other: Self) -> Bool {
            level == other.level && tags.map { $0.lowercased() }.sorted() == other.tags.map { $0.lowercased() }.sorted()
        }
    }

    static func recruitmentNotices(
        in output: String,
        preservedTags: [String]
    ) -> [MAARecruitmentNotice] {
        recruitmentOutput(in: output, preservedTags: preservedTags).notices
    }

    static func recruitmentOutput(
        in output: String,
        preservedTags: [String],
        taskSucceeded: Bool = true
    ) -> (notices: [MAARecruitmentNotice], handled: [RecruitmentResult]) {
        let lines = MAAOutputText.lines(in: output)
        var notices: [MAARecruitmentNotice] = []
        var detailed: [RecruitmentResult] = []
        var summarized: [RecruitmentResult] = []
        var isReadingDetectedTags = false

        for line in lines {
            if isDetectedTagsHeader(line) {
                isReadingDetectedTags = true
                continue
            }

            if let payload = payload(after: "RecruitResult:", in: line) {
                if let result = recruitResult(from: payload) { detailed.append(result) }
            } else if isReadingDetectedTags {
                if let result = summarizedRecruitResult(from: line) {
                    summarized.append(result)
                } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    isReadingDetectedTags = false
                }
            }
        }

        // Match occurrences individually: identical tags can belong to another unresolved slot.
        for result in summarized {
            if let index = detailed.firstIndex(where: { $0.matches(result) }) {
                detailed.remove(at: index)
            }
        }
        let results = summarized + detailed
        var handled: [RecruitmentResult] = []
        for result in results {
            let preservedTag = firstMatch(in: result.tags, candidates: preservedTags)
            if taskSucceeded, result.action != nil {
                if result.level >= 5 || preservedTag != nil { handled.append(result) }
                continue
            }

            if result.level >= 5 {
                append(.highRarity(level: result.level, tags: result.tags), to: &notices)
            } else if let tag = preservedTag {
                append(.preservedTag(tag: tag, tags: result.tags), to: &notices)
            }
        }

        for line in lines {
            guard let value = payload(after: "RecruitingTips:", in: line),
                  let tag = normalizedTag(String(value)),
                  !results.contains(where: { result in
                      result.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
                  })
            else { continue }
            append(.specialTag(tag), to: &notices)
        }

        return (notices, handled)
    }

    private static func isDetectedTagsHeader(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedCaseInsensitiveCompare("Detected tags:") == .orderedSame
    }

    private static func summarizedRecruitResult(from line: String) -> RecruitmentResult? {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separator = value.firstIndex(of: "."),
              !value[..<separator].isEmpty,
              value[..<separator].allSatisfy(\.isNumber)
        else { return nil }
        let payload = value[value.index(after: separator)...]
        guard var result = recruitResult(from: payload) else { return nil }
        if let last = result.tags.last, let action = RecruitmentAction(rawValue: last.lowercased()) {
            result.action = action
            result.tags.removeLast()
        }
        guard !result.tags.isEmpty else { return nil }
        return result
    }

    private static func recruitResult(from value: Substring) -> RecruitmentResult? {
        let payload = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let level = payload.prefix { $0 == "★" }.count
        guard (1...6).contains(level) else { return nil }
        let tags = payload.dropFirst(level)
            .split(separator: ",", omittingEmptySubsequences: true)
            .compactMap { normalizedTag(String($0)) }
            .filter { $0.localizedCaseInsensitiveCompare("none") != .orderedSame }
        guard !tags.isEmpty else { return nil }
        return RecruitmentResult(level: level, tags: tags)
    }

    private static func payload(after marker: String, in line: String) -> Substring? {
        guard let range = line.range(of: marker, options: [.caseInsensitive, .literal]) else { return nil }
        return line[range.upperBound...]
    }

    private static func firstMatch(in values: [String], candidates: [String]) -> String? {
        let normalized = candidates.compactMap(normalizedTag)
        return values.first { value in
            normalized.contains { $0.localizedCaseInsensitiveCompare(value) == .orderedSame }
        }
    }

    private static func normalizedTag(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        return trimmed
    }

    private static func append(_ notice: MAARecruitmentNotice, to notices: inout [MAARecruitmentNotice]) {
        if !notices.contains(notice) { notices.append(notice) }
    }
}

enum MAAOutputText {
    static func lines(in output: String) -> [String] {
        output.components(separatedBy: .newlines).map(strippingANSIEscapeSequences)
    }

    private static func strippingANSIEscapeSequences(_ value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"\x1B\[[0-?]*[ -/]*[@-~]"#) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: "")
    }
}
