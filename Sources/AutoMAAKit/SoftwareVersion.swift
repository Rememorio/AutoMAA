import Foundation

/// Semantic version precedence ignores build metadata; description retains the exact release identity.
public struct SoftwareVersion: Codable, Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    private let prerelease: [String]
    private let buildMetadata: [String]

    public init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("v") || normalized.hasPrefix("V") { normalized.removeFirst() }
        let build = normalized.split(separator: "+", omittingEmptySubsequences: false)
        guard build.count <= 2 else { return nil }
        let release = build[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = release[0].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard core.count == 3, core.allSatisfy(Self.isCanonicalNumber),
              let major = Int(core[0]), let minor = Int(core[1]), let patch = Int(core[2]) else { return nil }
        let prerelease = release.count == 2 ? release[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        let metadata = build.count == 2 ? build[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init) : []
        guard (prerelease + metadata).allSatisfy(Self.isIdentifier),
              prerelease.allSatisfy({ !Self.isNumber($0) || Self.isCanonicalNumber($0) }) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        buildMetadata = metadata
    }

    public var coreVersion: String { "\(major).\(minor).\(patch)" }
    public var isPrerelease: Bool { !prerelease.isEmpty }
    public var description: String {
        coreVersion + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
            + (buildMetadata.isEmpty ? "" : "+" + buildMetadata.joined(separator: "."))
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let left = (lhs.major, lhs.minor, lhs.patch), right = (rhs.major, rhs.minor, rhs.patch)
        if left != right { return left < right }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumeric = isNumber(left), rightNumeric = isNumber(right)
            if leftNumeric != rightNumeric { return leftNumeric }
            if leftNumeric && left.count != right.count { return left.count < right.count }
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    private static func isNumber(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func isCanonicalNumber(_ value: String) -> Bool {
        isNumber(value) && (value == "0" || !value.hasPrefix("0"))
    }

    private static func isIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45
        }
    }

    private enum CodingKeys: String, CodingKey { case major, minor, patch, prerelease, buildMetadata }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let core = try "\(values.decode(Int.self, forKey: .major)).\(values.decode(Int.self, forKey: .minor)).\(values.decode(Int.self, forKey: .patch))"
        let prerelease = try values.decodeIfPresent([String].self, forKey: .prerelease) ?? []
        let metadata = try values.decodeIfPresent([String].self, forKey: .buildMetadata) ?? []
        let value = core + (prerelease.isEmpty ? "" : "-" + prerelease.joined(separator: "."))
            + (metadata.isEmpty ? "" : "+" + metadata.joined(separator: "."))
        guard let parsed = Self(value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid semantic version"))
        }
        self = parsed
    }
}

public enum ApplicationReleaseVersion {
    public static func current(in bundle: Bundle = .main) -> String? {
        if let value = bundle.object(forInfoDictionaryKey: "AutoMAAReleaseVersion") { return value as? String }
        return bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    public static func validate(info: [String: Any], expectedVersion: String?) throws {
        let value = (info["AutoMAAReleaseVersion"] ?? info["CFBundleShortVersionString"]) as? String
        guard let value, let version = SoftwareVersion(value), version.description == value,
              info["CFBundleShortVersionString"] as? String == version.coreVersion else {
            throw SoftwareUpdateError.invalidApplication("完整版本号与应用版本不匹配")
        }
        if let expectedVersion, value != expectedVersion {
            throw SoftwareUpdateError.invalidApplication("版本应为 \(expectedVersion)，实际为 \(value)")
        }
    }
}
