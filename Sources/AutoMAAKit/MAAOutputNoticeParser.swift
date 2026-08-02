import Foundation

enum MAARecruitmentNotice: Equatable, Hashable, Sendable {
    case highRarity(level: Int, tags: [String])
    case preservedTag(tag: String, tags: [String])
    case specialTag(String)
}

enum MAAOutputNoticeParser {
    static func recruitmentNotices(
        in output: String,
        preservedTags: [String]
    ) -> [MAARecruitmentNotice] {
        let lines = output.components(separatedBy: .newlines).map(strippingANSIEscapeSequences)
        var notices: [MAARecruitmentNotice] = []
        var resultTags: [[String]] = []

        for line in lines {
            guard let payload = payload(after: "RecruitResult:", in: line),
                  let result = recruitResult(from: payload)
            else { continue }

            resultTags.append(result.tags)
            if result.level >= 5 {
                append(.highRarity(level: result.level, tags: result.tags), to: &notices)
            } else if let tag = firstMatch(in: result.tags, candidates: preservedTags) {
                append(.preservedTag(tag: tag, tags: result.tags), to: &notices)
            }
        }

        for line in lines {
            guard let value = payload(after: "RecruitingTips:", in: line),
                  let tag = normalizedTag(String(value)),
                  !resultTags.contains(where: { tags in
                      tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
                  })
            else { continue }
            append(.specialTag(tag), to: &notices)
        }

        return notices
    }

    private static func recruitResult(from value: Substring) -> (level: Int, tags: [String])? {
        let payload = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let level = payload.prefix { $0 == "★" }.count
        guard (1...6).contains(level) else { return nil }
        let tags = payload.dropFirst(level)
            .split(separator: ",", omittingEmptySubsequences: true)
            .compactMap { normalizedTag(String($0)) }
            .filter { $0.localizedCaseInsensitiveCompare("none") != .orderedSame }
        guard !tags.isEmpty else { return nil }
        return (level, tags)
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

    private static func strippingANSIEscapeSequences(_ value: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: #"\x1B\[[0-?]*[ -/]*[@-~]"#) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return expression.stringByReplacingMatches(in: value, range: range, withTemplate: "")
    }
}
