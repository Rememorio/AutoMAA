import Foundation

public struct ReleaseNotes: Codable, Equatable, Identifiable, Sendable {
    public var version: String
    public var body: String
    public var pageURL: URL?
    public var publishedAt: Date?
    public var sourceURL: URL?
    public var id: String { "\(pageURL?.absoluteString ?? "local")#\(version)" }

    public init(version: String, body: String, pageURL: URL? = nil, publishedAt: Date? = nil, sourceURL: URL? = nil) {
        self.version = version
        self.body = body
        self.pageURL = pageURL.flatMap(Self.safePageURL)
        self.publishedAt = publishedAt
        self.sourceURL = sourceURL.flatMap(Self.safeSourceURL)
    }

    public static func safePageURL(_ url: URL) -> URL? {
        guard url.scheme == "https" || url.scheme == "http",
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }

    public static func safeSourceURL(_ url: URL) -> URL? {
        guard url.query == nil, url.fragment == nil else { return nil }
        return safePageURL(url)
    }

    public var highlights: [String] {
        let blocks = ReleaseNotesMarkdown.blocks(body)
        let bullets = blocks.compactMap { block -> String? in
            if case let .bullet(text) = block { return text }
            return nil
        }
        return Array(bullets.prefix(3))
    }
}

public enum ReleaseNotesBlock: Equatable, Sendable {
    case heading(String, Int)
    case paragraph(String)
    case bullet(String)
    case code(String)
    case divider
}

public enum ReleaseNotesMarkdown {
    public static func blocks(_ markdown: String) -> [ReleaseNotesBlock] {
        var blocks: [ReleaseNotesBlock] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flush()
                if let value = code { blocks.append(.code(value.joined(separator: "\n"))); code = nil }
                else { code = [] }
            } else if code != nil {
                code?.append(raw)
            } else if line.isEmpty {
                flush()
            } else if line.hasPrefix("<summary>") {
                flush()
                let title = line.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                if !title.isEmpty { blocks.append(.heading(title, 3)) }
            } else if line.hasPrefix("<details") || line == "</details>" {
                flush()
            } else if line == "---" || line == "----" || line == "***" {
                flush(); blocks.append(.divider)
            } else if line.hasPrefix("#"), let space = line.firstIndex(of: " "),
                      line[..<space].allSatisfy({ $0 == "#" }) {
                flush()
                blocks.append(.heading(String(line[line.index(after: space)...]), line.distance(from: line.startIndex, to: space)))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flush(); blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flush()
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        return blocks
    }

    public static func bundledVersions(_ changelog: String, repository: String) -> [ReleaseNotes] {
        var result: [ReleaseNotes] = []
        var version: String?
        var lines: [String] = []
        func flush() {
            guard let version else { return }
            result.append(.init(version: version, body: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                                pageURL: URL(string: "https://github.com/\(repository)/releases/tag/v\(version)")))
        }
        for line in changelog.components(separatedBy: .newlines) {
            if line.hasPrefix("## ") {
                flush()
                version = line.dropFirst(3).split(separator: " ").first.flatMap { SoftwareVersion(String($0))?.description }
                lines = []
            } else if version != nil {
                lines.append(line)
            }
        }
        flush()
        return result
    }
}

public struct ReleaseNotesCache: Sendable {
    public struct State: Codable, Sendable {
        public var releases: [ReleaseNotes] = []
        public var lastOpenedVersion: String?
        public var unreadVersion: String?
        public init() {}
    }
    private let url: URL

    public init(directories: AppDirectories) {
        url = directories.root.appending(path: "release-notes.json")
    }

    public func load() -> State {
        guard let data = try? Data(contentsOf: url), data.count <= 8 * 1_024 * 1_024,
              let state = try? JSONDecoder().decode(State.self, from: data) else { return .init() }
        return state
    }

    public func save(_ state: State) throws {
        var bounded = state
        bounded.releases = Array(state.releases.prefix(40))
        var data = try JSONEncoder().encode(bounded)
        while data.count > 8 * 1_024 * 1_024, !bounded.releases.isEmpty {
            bounded.releases.removeLast()
            data = try JSONEncoder().encode(bounded)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

public struct MAAResourceVersion: Codable, Equatable, Sendable {
    public var revision: String?
    public var updatedAt: String?
    public var activity: String?
    public var repositoryURL: URL?

    public init(revision: String? = nil, updatedAt: String? = nil, activity: String? = nil, repositoryURL: URL? = nil) {
        self.revision = revision
        self.updatedAt = updatedAt
        self.activity = activity
        self.repositoryURL = repositoryURL
    }

    public var label: String { revision.map { String($0.prefix(8)) } ?? updatedAt ?? "未提供版本信息" }

    static func read(at directory: URL, repository: Bool) -> Self {
        struct Version: Decodable {
            struct Activity: Decodable { let name: String? }
            let last_updated: String?
            let activity: Activity?
        }
        let versionURL = (repository ? directory.appending(path: "resource") : directory).appending(path: "version.json")
        let version = smallData(at: versionURL).flatMap { try? JSONDecoder().decode(Version.self, from: $0) }
        var result = Self(updatedAt: version?.last_updated.map { String($0.prefix(40)) },
                          activity: version?.activity?.name.map { String($0.prefix(120)) })
        guard repository else { return result }
        let git = directory.appending(path: ".git")
        guard let head = smallText(at: git.appending(path: "HEAD"))?.trimmingCharacters(in: .whitespacesAndNewlines) else { return result }
        if isRevision(head) { result.revision = head }
        else if head.hasPrefix("ref: refs/") {
            let ref = String(head.dropFirst(5))
            if !ref.split(separator: "/").contains(".."),
               let value = smallText(at: git.appending(path: ref))?.trimmingCharacters(in: .whitespacesAndNewlines), isRevision(value) {
                result.revision = value
            } else if let packed = smallText(at: git.appending(path: "packed-refs")) {
                result.revision = packed.split(whereSeparator: \.isNewline).compactMap { line -> String? in
                    let fields = line.split(separator: " ")
                    guard fields.count == 2, fields[1] == ref, isRevision(String(fields[0])) else { return nil }
                    return String(fields[0])
                }.first
            }
        }
        if let config = smallText(at: git.appending(path: "config")) {
            var origin = false
            for line in config.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
                if line.hasPrefix("[") { origin = line == "[remote \"origin\"]" }
                else if origin, line.hasPrefix("url"), let separator = line.firstIndex(of: "=") {
                    let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
                    result.repositoryURL = githubRepository(value)
                }
            }
        }
        return result
    }

    public static func isRevision(_ value: String) -> Bool {
        [40, 64].contains(value.count) && value.allSatisfy { "0123456789abcdef".contains($0) }
    }

    static func githubRepository(_ value: String) -> URL? {
        let normalized = value.replacingOccurrences(of: "git@github.com:", with: "https://github.com/")
        guard let url = URL(string: normalized), url.host?.lowercased() == "github.com",
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
        let parts = url.path.split(separator: "/")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        var name = String(parts[1])
        if name.hasSuffix(".git") { name.removeLast(4) }
        return URL(string: "https://github.com/\(parts[0])/\(name)")
    }

    private static func smallData(at url: URL) -> Data? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 1_024 * 1_024 else { return nil }
        return try? Data(contentsOf: url)
    }
    private static func smallText(at url: URL) -> String? {
        smallData(at: url).flatMap { String(data: $0, encoding: .utf8) }
    }
}

public struct MAAInstalledVersions: Codable, Equatable, Sendable {
    public var core: String?
    public var baseResources: MAAResourceVersion
    public var recognitionData: MAAResourceVersion

    public init(core: String?, baseResources: MAAResourceVersion, recognitionData: MAAResourceVersion) {
        self.core = core
        self.baseResources = baseResources
        self.recognitionData = recognitionData
    }
}

public struct MAAUpdateInformation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var before: MAAInstalledVersions
    public var after: MAAInstalledVersions?
    public var manifestURL: URL?
    public var date: Date

    public init(id: UUID = UUID(), title: String, before: MAAInstalledVersions, after: MAAInstalledVersions? = nil, manifestURL: URL? = nil, date: Date = Date()) {
        self.id = id
        self.title = title
        self.before = before
        self.after = after
        self.manifestURL = manifestURL
        self.date = date
    }

    public var resourceComparisonURL: URL? {
        guard let after, let repository = after.recognitionData.repositoryURL,
              MAAResourceVersion.githubRepository(repository.absoluteString) == repository,
              repository == before.recognitionData.repositoryURL,
              let old = before.recognitionData.revision, let new = after.recognitionData.revision,
              MAAResourceVersion.isRevision(old), MAAResourceVersion.isRevision(new), old != new else { return nil }
        return repository.appending(path: "compare/\(old)...\(new)")
    }

    public var recognitionSummary: String? {
        guard let after else { return nil }
        let old = before.recognitionData, new = after.recognitionData
        if let revision = new.revision, revision == old.revision {
            return "识别数据 \(new.label) · 仓库修订未变"
        }
        if old.revision == nil, new.revision == nil {
            return new.updatedAt.map { "识别数据标注时间：\($0)" } ?? "识别数据已同步；上游未提供修订信息"
        }
        return "识别数据 \(old.label) → \(new.label)"
    }

    public var coreVersionForNotes: String? { after == nil ? before.core : after?.core }
}
