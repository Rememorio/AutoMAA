import Foundation

public struct SupportDiagnostics: Equatable, Sendable {
    public let applicationVersion: String
    public let applicationBuild: String
    public let operatingSystem: String
    public let architecture: String
    public let maaVersionSummary: String
    public let configurationSchemaVersion: Int
    public let updateRepository: String

    public init(
        applicationVersion: String,
        applicationBuild: String,
        operatingSystem: String,
        architecture: String,
        maaVersionSummary: String,
        configurationSchemaVersion: Int,
        updateRepository: String
    ) {
        self.applicationVersion = applicationVersion
        self.applicationBuild = applicationBuild
        self.operatingSystem = operatingSystem
        self.architecture = architecture
        self.maaVersionSummary = maaVersionSummary
        self.configurationSchemaVersion = configurationSchemaVersion
        self.updateRepository = updateRepository
    }

    public var text: String {
        var lines = [
            "AutoMAA: v\(applicationVersion) (build \(applicationBuild))",
            "macOS: \(operatingSystem)",
            "架构: \(architecture)",
        ]
        let versions = maaVersionSummary
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(Self.safeMAAVersionLine)
        if versions.isEmpty {
            lines.append("MAA 环境: 未检测或不可用")
        } else {
            lines.append(contentsOf: versions)
        }
        lines.append("配置协议: v\(configurationSchemaVersion)")
        lines.append("更新源: \(updateRepository)")
        return lines.joined(separator: "\n")
    }

    private static func safeMAAVersionLine(_ line: String) -> String? {
        let prefix = if line.hasPrefix("maa-cli ") {
            "maa-cli "
        } else if line.hasPrefix("MaaCore ") {
            "MaaCore "
        } else {
            ""
        }
        guard !prefix.isEmpty else { return nil }
        let version = line.dropFirst(prefix.count)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".+-_"))
        guard !version.isEmpty, version.count <= 64,
              version.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        return prefix + version
    }
}
