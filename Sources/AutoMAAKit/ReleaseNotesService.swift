import Foundation

public struct ReleaseNotesCollection: Sendable {
    public var releases: [ReleaseNotes]
    public var notice: String?

    public init(releases: [ReleaseNotes], notice: String? = nil) {
        self.releases = releases
        self.notice = notice
    }
}

public protocol ReleaseNotesServing: Sendable {
    func application(repository: String, from: String, through: String) async throws -> ReleaseNotesCollection
    func maa(manifestURL: URL, version: String?) async throws -> ReleaseNotesCollection
    func resources(comparisonURL: URL) async throws -> ReleaseNotesCollection
}

public extension ReleaseNotesServing {
    func latestMAA(cliPath: String, directories: AppDirectories, channel: MAAUpdateChannel,
                   cachedNotes: [ReleaseNotes] = []) async throws -> ReleaseNotesCollection {
        try await UpdateDeadline(timeout: UpdatePolicy.checkTimeout).perform(operation: "读取 MAA 发布说明") {
            var data: Data?
            if let url = MAACoreReleaseManifestEndpoint.configurationURL(in: directories.maaConfig) {
                let result = try await CommandRunner().run(executable: cliPath,
                    arguments: ["convert", url.path, "--format", "json", "--batch"],
                    environment: ["MAA_CONFIG_DIR": directories.maaConfig.path], timeout: UpdatePolicy.checkTimeout)
                try Task.checkCancellation()
                guard result.exitCode == 0, !result.timedOut, !result.cancelled else {
                    throw ReleaseNotesError.unavailable("无法读取 maa-cli 的更新来源配置")
                }
                data = Data(result.standardOutput.utf8)
            }
            let url = try MAACoreReleaseManifestEndpoint.url(channel: channel, configurationData: data)
            do {
                return try await maa(manifestURL: url, version: nil)
            } catch {
                try Task.checkCancellation()
                let source = ReleaseNotes.safeSourceURL(url)
                let cached = cachedNotes.filter { source != nil && $0.sourceURL == source && MAASemanticVersion($0.version) != nil }
                    .max { MAASemanticVersion($0.version)! < MAASemanticVersion($1.version)! }
                guard let cached else { throw error }
                return .init(releases: [cached], notice: "暂时无法确认最新说明，显示本机保存的 v\(cached.version)：\(ReleaseNotesError.message(for: error))")
            }
        }
    }
}

public struct ReleaseNotesService: ReleaseNotesServing {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func application(repository: String, from: String, through: String) async throws -> ReleaseNotesCollection {
        guard let repositoryURL = MAAResourceVersion.githubRepository("https://github.com/\(repository)"),
              let current = SoftwareVersion(from), let target = SoftwareVersion(through), target >= current else {
            throw ReleaseNotesError.unavailable("无法确定要查看的版本范围")
        }
        return try await UpdateDeadline(timeout: UpdatePolicy.checkTimeout).perform(operation: "读取更新说明") {
            if current == target {
                let release = try await githubRelease(repository: repositoryURL, tag: "v\(target)")
                guard !release.prerelease, SoftwareVersion(release.tag_name) == target else {
                    throw ReleaseNotesError.unavailable("上游说明与所选正式版本不匹配")
                }
                return .init(releases: [release.notes])
            }
            var notes: [ReleaseNotes] = []
            var complete = false
            for page in 1...3 {
                let url = URL(string: "https://api.github.com/repos\(repositoryURL.path)/releases?per_page=30&page=\(page)")!
                let releases = try JSONDecoder().decode([GitHubNotes].self, from: await data(at: url))
                let published = releases.filter { !$0.draft && !$0.prerelease }
                notes += published.compactMap { release in
                    guard let version = SoftwareVersion(release.tag_name), version > current, version <= target else { return nil }
                    return release.notes
                }
                if releases.count < 30 {
                    complete = true
                    break
                }
            }
            notes.sort { (SoftwareVersion($0.version) ?? target) > (SoftwareVersion($1.version) ?? target) }
            return .init(releases: notes, notice: complete ? nil : "仅显示最近取得的版本说明，更早变化可在发布页查看。")
        }
    }

    public func maa(manifestURL: URL, version: String?) async throws -> ReleaseNotesCollection {
        if let version, MAASemanticVersion(version) == nil {
            throw ReleaseNotesError.unavailable("无法确定要查看的 MAA 版本")
        }
        return try await UpdateDeadline(timeout: UpdatePolicy.checkTimeout).perform(operation: "读取 MAA 发布说明") {
            let manifest = try JSONDecoder().decode(MAAManifestNotes.self, from: await data(at: manifestURL))
            guard let published = MAASemanticVersion(manifest.version) else {
                throw ReleaseNotesError.unavailable("上游清单没有提供有效版本号")
            }
            if let version, let expected = MAASemanticVersion(version), expected != published {
                guard let page = manifest.details?.html_url.flatMap(URL.init(string:)),
                      let repository = githubRepository(fromReleasePage: page) else {
                    throw ReleaseNotesError.unavailable("上游清单已指向其他版本，暂时无法取得本次实际启用版本的说明")
                }
                let release = try await githubRelease(repository: repository, tag: "v\(expected)")
                guard MAASemanticVersion(release.tag_name) == expected else {
                    throw ReleaseNotesError.unavailable("上游说明与本次实际启用的版本不匹配")
                }
                var notes = release.notes
                notes.sourceURL = ReleaseNotes.safeSourceURL(manifestURL)
                return .init(releases: [notes])
            }
            return .init(releases: [.init(version: published.description, body: manifest.details?.body ?? "",
                                         pageURL: manifest.details?.html_url.flatMap(URL.init(string:)),
                                         publishedAt: manifest.details?.published_at.flatMap(Self.date), sourceURL: manifestURL)])
        }
    }

    public func resources(comparisonURL: URL) async throws -> ReleaseNotesCollection {
        guard let repository = githubRepository(fromReleasePage: comparisonURL),
              comparisonURL.pathComponents.count == 5, comparisonURL.pathComponents[3] == "compare" else {
            throw ReleaseNotesError.unavailable("上游没有提供可比较的资源修订")
        }
        let range = comparisonURL.lastPathComponent.components(separatedBy: "...")
        guard range.count == 2, range.allSatisfy(MAAResourceVersion.isRevision) else {
            throw ReleaseNotesError.unavailable("资源修订号无效")
        }
        return try await UpdateDeadline(timeout: UpdatePolicy.checkTimeout).perform(operation: "读取识别数据变更") {
            let url = URL(string: "https://api.github.com/repos\(repository.path)/compare/\(range[0])...\(range[1])?per_page=20")!
            let response = try JSONDecoder().decode(GitHubComparison.self, from: await data(at: url))
            guard response.status == "ahead" || response.status == "identical" else {
                throw ReleaseNotesError.unavailable("前后资源修订不在同一条更新路径上，请查看上游比较页")
            }
            let body = response.commits.map { commit in
                let title = commit.commit.message.split(whereSeparator: \.isNewline).first.map(String.init) ?? "资源变更"
                return "- \(title)"
            }.joined(separator: "\n")
            return .init(releases: [.init(version: "\(range[0].prefix(8)) → \(range[1].prefix(8))", body: body, pageURL: comparisonURL, sourceURL: comparisonURL)],
                         notice: response.total_commits > response.commits.count ? "显示前 \(response.commits.count) 条提交，共 \(response.total_commits) 条；完整内容见上游比较页。" : nil)
        }
    }

    private func githubRelease(repository: URL, tag: String) async throws -> GitHubNotes {
        let url = URL(string: "https://api.github.com/repos\(repository.path)/releases/tags/\(tag)")!
        let release = try JSONDecoder().decode(GitHubNotes.self, from: await data(at: url))
        guard !release.draft else { throw ReleaseNotesError.unavailable("该版本尚未正式发布说明") }
        return release
    }

    private func githubRepository(fromReleasePage url: URL) -> URL? {
        guard url.host?.lowercased() == "github.com", url.user == nil, url.password == nil else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return MAAResourceVersion.githubRepository("https://github.com/\(parts[0])/\(parts[1])")
    }

    private func data(at url: URL) async throws -> Data {
        guard ReleaseNotes.safePageURL(url) != nil else { throw ReleaseNotesError.unavailable("更新说明来源地址无效") }
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: UpdatePolicy.checkTimeout)
        request.setValue("AutoMAA", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ReleaseNotesError.unavailable("上游暂时无法提供更新说明")
        }
        guard response.expectedContentLength <= 2 * 1_024 * 1_024 else { throw ReleaseNotesError.oversized }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 2 * 1_024 * 1_024 else { throw ReleaseNotesError.oversized }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }

    private static func date(_ value: String) -> Date? { ISO8601DateFormatter().date(from: value) }

    private struct GitHubNotes: Decodable {
        let tag_name: String
        let body: String?
        let html_url: String
        let published_at: String?
        let draft: Bool
        let prerelease: Bool
        var notes: ReleaseNotes {
            .init(version: tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name, body: body ?? "",
                  pageURL: URL(string: html_url), publishedAt: published_at.flatMap(ReleaseNotesService.date))
        }
    }
    private struct MAAManifestNotes: Decodable {
        struct Details: Decodable {
            let body: String?
            let html_url: String?
            let published_at: String?
        }
        let version: String
        let details: Details?
    }
    private struct GitHubComparison: Decodable {
        struct Commit: Decodable {
            struct Message: Decodable { let message: String }
            let commit: Message
        }
        let status: String
        let total_commits: Int
        let commits: [Commit]
    }
}

public enum ReleaseNotesError: LocalizedError {
    case unavailable(String)
    case oversized

    public static func message(for error: Error) -> String {
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet: return "网络不可用，请检查网络连接"
            case .timedOut: return "读取超时，请稍后重试"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .networkConnectionLost:
                return "无法连接更新说明来源，请稍后重试"
            default: break
            }
        }
        return error.localizedDescription
    }

    public var errorDescription: String? {
        switch self {
        case let .unavailable(message): message
        case .oversized: "更新说明过长，请前往上游页面查看完整内容"
        }
    }
}
