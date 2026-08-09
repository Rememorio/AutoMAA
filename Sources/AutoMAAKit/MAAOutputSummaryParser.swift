import Foundation

struct MAAFightSummary: Equatable, Sendable {
    let stage: String
    let times: Int
    let totalDrops: String?
}

enum MAAOutputSummaryParser {
    static func fightSummary(in output: String) -> MAAFightSummary? {
        var summary: MAAFightSummary?

        for line in MAAOutputText.lines(in: output) {
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let header = fightHeader(from: value) {
                summary = MAAFightSummary(stage: header.stage, times: header.times, totalDrops: nil)
                continue
            }
            guard let current = summary,
                  let drops = field(after: "total drops:", in: value, maximumLength: 4_096)
            else { continue }
            summary = MAAFightSummary(stage: current.stage, times: current.times, totalDrops: drops)
        }

        return summary
    }

    private static func fightHeader(from line: String) -> (stage: String, times: Int)? {
        let marker = "Fight "
        guard line.range(of: marker, options: [.anchored, .caseInsensitive, .literal]) != nil else {
            return nil
        }
        let payload = line.dropFirst(marker.count)
        guard let timesRange = payload.range(
            of: " times",
            options: [.backwards, .caseInsensitive, .literal]
        ) else { return nil }

        let suffix = payload[timesRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard suffix.isEmpty || suffix.localizedCaseInsensitiveCompare(", drops:") == .orderedSame else {
            return nil
        }

        let components = payload[..<timesRange.lowerBound].split(whereSeparator: \.isWhitespace)
        guard components.count >= 2,
              let times = Int(components.last ?? ""),
              times >= 0,
              let stage = normalizedField(
                  components.dropLast().joined(separator: " "),
                  maximumLength: 128
              )
        else { return nil }
        return (stage, times)
    }

    private static func field(after marker: String, in line: String, maximumLength: Int) -> String? {
        guard line.range(of: marker, options: [.anchored, .caseInsensitive, .literal]) != nil else {
            return nil
        }
        return normalizedField(String(line.dropFirst(marker.count)), maximumLength: maximumLength)
    }

    private static func normalizedField(_ value: String, maximumLength: Int) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= maximumLength,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        return trimmed
    }
}
