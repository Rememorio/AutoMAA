import CryptoKit
import Foundation

public struct SoftwareVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("v") {
            normalized.removeFirst()
        }
        normalized = String(normalized.split(whereSeparator: { $0 == "-" || $0 == "+" }).first ?? "")
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SoftwareVersion, rhs: SoftwareVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct SoftwareUpdateAsset: Equatable, Sendable {
    public let name: String
    public let size: Int
    public let downloadURL: URL

    public init(name: String, size: Int, downloadURL: URL) {
        self.name = name
        self.size = size
        self.downloadURL = downloadURL
    }
}

public struct SoftwareUpdateRelease: Equatable, Sendable {
    public let version: SoftwareVersion
    public let tagName: String
    public let releaseNotes: String
    public let pageURL: URL
    public let diskImage: SoftwareUpdateAsset
    public let checksum: SoftwareUpdateAsset

    public init(
        version: SoftwareVersion,
        tagName: String,
        releaseNotes: String,
        pageURL: URL,
        diskImage: SoftwareUpdateAsset,
        checksum: SoftwareUpdateAsset
    ) {
        self.version = version
        self.tagName = tagName
        self.releaseNotes = releaseNotes
        self.pageURL = pageURL
        self.diskImage = diskImage
        self.checksum = checksum
    }
}

public struct PreparedSoftwareUpdate: Equatable, Sendable {
    public let release: SoftwareUpdateRelease
    public let applicationURL: URL
    public let workingDirectory: URL

    public init(release: SoftwareUpdateRelease, applicationURL: URL, workingDirectory: URL) {
        self.release = release
        self.applicationURL = applicationURL
        self.workingDirectory = workingDirectory
    }
}

public enum SoftwareUpdateError: Equatable, LocalizedError, Sendable {
    case invalidCurrentVersion(String)
    case invalidRelease(String)
    case missingAssets(String)
    case invalidDownloadURL
    case network(String)
    case httpStatus(Int)
    case invalidDownload(String)
    case checksumFileInvalid
    case checksumMismatch
    case commandFailed(String, String)
    case invalidApplication(String)
    case unsupportedInstallLocation(String)
    case installerUnavailable
    case installerLaunchFailed(String)
    case updateTimedOut

    public var errorDescription: String? {
        switch self {
        case let .invalidCurrentVersion(version):
            "无法识别当前版本：\(version)"
        case let .invalidRelease(message):
            "Release 信息无效：\(message)"
        case let .missingAssets(version):
            "v\(version) 缺少匹配的 DMG 或 SHA-256 文件"
        case .invalidDownloadURL:
            "更新下载地址不是受信任的 GitHub HTTPS 地址"
        case let .network(message):
            "连接 GitHub 失败：\(message)"
        case let .httpStatus(status):
            "GitHub 返回了 HTTP \(status)"
        case let .invalidDownload(message):
            "下载的更新文件无效：\(message)"
        case .checksumFileInvalid:
            "Release 中的 SHA-256 文件格式无效"
        case .checksumMismatch:
            "更新包 SHA-256 校验失败，已停止安装"
        case let .commandFailed(command, output):
            "\(command) 执行失败：\(output)"
        case let .invalidApplication(message):
            "更新包中的 AutoMAA.app 无效：\(message)"
        case let .unsupportedInstallLocation(message):
            message
        case .installerUnavailable:
            "当前 AutoMAA.app 中缺少更新辅助程序，请手动安装最新版本"
        case let .installerLaunchFailed(message):
            "无法启动更新辅助程序：\(message)"
        case .updateTimedOut:
            "等待 AutoMAA 退出超时，更新已取消"
        }
    }
}

public enum SoftwareUpdateReleaseResolver {
    public static func newerRelease(from data: Data, currentVersion: String) throws -> SoftwareUpdateRelease? {
        guard let current = SoftwareVersion(currentVersion) else {
            throw SoftwareUpdateError.invalidCurrentVersion(currentVersion)
        }
        let response: GitHubReleaseResponse
        do {
            response = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        } catch {
            throw SoftwareUpdateError.invalidRelease(error.localizedDescription)
        }
        guard !response.draft, !response.prerelease,
              let version = SoftwareVersion(response.tagName)
        else {
            throw SoftwareUpdateError.invalidRelease("版本号、草稿或预发布状态不符合要求")
        }
        guard version > current else { return nil }

        let diskImageName = "AutoMAA-\(version)-macOS-arm64.dmg"
        let checksumName = "\(diskImageName).sha256"
        guard let diskImage = response.assets.first(where: { $0.name == diskImageName }),
              let checksum = response.assets.first(where: { $0.name == checksumName })
        else {
            throw SoftwareUpdateError.missingAssets(version.description)
        }
        guard let pageURL = URL(string: response.htmlURL),
              let diskImageURL = URL(string: diskImage.browserDownloadURL),
              let checksumURL = URL(string: checksum.browserDownloadURL),
              isTrustedGitHubURL(pageURL),
              isTrustedGitHubURL(diskImageURL),
              isTrustedGitHubURL(checksumURL)
        else {
            throw SoftwareUpdateError.invalidDownloadURL
        }
        guard diskImage.size > 0, diskImage.size <= 250 * 1_024 * 1_024,
              checksum.size > 0, checksum.size <= 64 * 1_024
        else {
            throw SoftwareUpdateError.invalidRelease("附件大小超出安全范围")
        }

        return SoftwareUpdateRelease(
            version: version,
            tagName: response.tagName,
            releaseNotes: (response.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pageURL: pageURL,
            diskImage: SoftwareUpdateAsset(name: diskImage.name, size: diskImage.size, downloadURL: diskImageURL),
            checksum: SoftwareUpdateAsset(name: checksum.name, size: checksum.size, downloadURL: checksumURL)
        )
    }

    private static func isTrustedGitHubURL(_ url: URL) -> Bool {
        url.scheme == "https" && ["github.com", "api.github.com"].contains(url.host?.lowercased() ?? "")
    }
}

public enum SoftwareUpdateVerifier {
    public static func expectedSHA256(from data: Data, fileName: String) throws -> String {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw SoftwareUpdateError.checksumFileInvalid
        }
        for line in contents.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { continue }
            let hash = String(fields[0]).lowercased()
            let listedName = String(fields[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            guard listedName == fileName,
                  hash.count == 64,
                  hash.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdef").contains($0) })
            else { continue }
            return hash
        }
        throw SoftwareUpdateError.checksumFileInvalid
    }

    public static func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public actor SoftwareUpdateService {
    public static let defaultRepository = "Rememorio/AutoMAA"

    private let currentVersion: String
    private let repository: String
    private let session: URLSession
    private let commandRunner = CommandRunner()

    public init(currentVersion: String, repository: String = defaultRepository) {
        self.currentVersion = currentVersion
        self.repository = repository
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration)
    }

    public func check() async throws -> SoftwareUpdateRelease? {
        let repositoryParts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard repositoryParts.count == 2,
              repositoryParts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
        else {
            throw SoftwareUpdateError.invalidDownloadURL
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AutoMAA/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SoftwareUpdateError.network("未收到 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SoftwareUpdateError.httpStatus(http.statusCode)
        }
        return try SoftwareUpdateReleaseResolver.newerRelease(from: data, currentVersion: currentVersion)
    }

    public func prepare(_ release: SoftwareUpdateRelease, directories: AppDirectories) async throws -> PreparedSoftwareUpdate {
        try directories.prepare()
        let updatesRoot = directories.root.appending(path: "Updates", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: updatesRoot, withIntermediateDirectories: true)
        for previous in (try? FileManager.default.contentsOfDirectory(
            at: updatesRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? [] {
            try? FileManager.default.removeItem(at: previous)
        }
        let workingDirectory = updatesRoot.appending(
            path: "\(release.version)-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        do {
            let checksumURL = workingDirectory.appending(path: release.checksum.name)
            let diskImageURL = workingDirectory.appending(path: release.diskImage.name)
            try await download(release.checksum, to: checksumURL)
            try await download(release.diskImage, to: diskImageURL)

            let checksumData = try Data(contentsOf: checksumURL)
            let expected = try SoftwareUpdateVerifier.expectedSHA256(
                from: checksumData,
                fileName: release.diskImage.name
            )
            let actual = try SoftwareUpdateVerifier.sha256(of: diskImageURL)
            guard expected == actual else { throw SoftwareUpdateError.checksumMismatch }

            try await verifyDiskImage(diskImageURL)
            let stagedApplication = try await stageApplication(
                from: diskImageURL,
                in: workingDirectory,
                expectedVersion: release.version.description
            )
            return PreparedSoftwareUpdate(
                release: release,
                applicationURL: stagedApplication,
                workingDirectory: workingDirectory
            )
        } catch {
            try? FileManager.default.removeItem(at: workingDirectory)
            throw error
        }
    }

    private func download(_ asset: SoftwareUpdateAsset, to destination: URL) async throws {
        var lastError: Error = SoftwareUpdateError.network("未知网络错误")
        for attempt in 0..<3 {
            do {
                try await downloadOnce(asset, to: destination)
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < 2, isRetryable(error) else { throw error }
                try await Task.sleep(for: .milliseconds(attempt == 0 ? 500 : 1_500))
            }
        }
        throw lastError
    }

    private func downloadOnce(_ asset: SoftwareUpdateAsset, to destination: URL) async throws {
        var request = URLRequest(url: asset.downloadURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 300)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("AutoMAA/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await session.download(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw SoftwareUpdateError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw SoftwareUpdateError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        let downloadedSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard downloadedSize == asset.size else {
            throw SoftwareUpdateError.invalidDownload("\(asset.name) 大小不一致")
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var lastError: Error = SoftwareUpdateError.network("未知网络错误")
        for attempt in 0..<3 {
            do {
                return try await session.data(for: request)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                lastError = SoftwareUpdateError.network(error.localizedDescription)
                guard attempt < 2 else { break }
                try await Task.sleep(for: .milliseconds(attempt == 0 ? 500 : 1_500))
            }
        }
        throw lastError
    }

    private func isRetryable(_ error: Error) -> Bool {
        switch error {
        case SoftwareUpdateError.network:
            true
        case let SoftwareUpdateError.httpStatus(status):
            status == 408 || status == 429 || (500...599).contains(status)
        case SoftwareUpdateError.invalidDownload:
            true
        default:
            false
        }
    }

    private func verifyDiskImage(_ diskImageURL: URL) async throws {
        let result = try await commandRunner.run(
            executable: "/usr/bin/hdiutil",
            arguments: ["verify", diskImageURL.path],
            timeout: 120
        )
        guard result.exitCode == 0, !result.timedOut, !result.cancelled else {
            throw commandError("校验磁盘映像", result)
        }
    }

    private func stageApplication(
        from diskImageURL: URL,
        in workingDirectory: URL,
        expectedVersion: String
    ) async throws -> URL {
        let mountRoot = workingDirectory.appending(path: "Mount", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: mountRoot, withIntermediateDirectories: true)
        let attach = try await commandRunner.run(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", "-nobrowse", "-readonly", "-plist", "-mountroot", mountRoot.path, diskImageURL.path],
            timeout: 120
        )
        guard attach.exitCode == 0, !attach.timedOut, !attach.cancelled else {
            throw commandError("挂载磁盘映像", attach)
        }
        let mountedURL: URL
        do {
            mountedURL = try mountPoint(from: attach.standardOutput, under: mountRoot)
        } catch {
            for candidate in (try? FileManager.default.contentsOfDirectory(
                at: mountRoot,
                includingPropertiesForKeys: nil
            )) ?? [] {
                await detach(candidate)
            }
            throw error
        }
        do {
            let source = mountedURL.appending(path: "AutoMAA.app", directoryHint: .isDirectory)
            try await SoftwareUpdateApplicationValidator().validate(source, expectedVersion: expectedVersion)
            let destination = workingDirectory.appending(path: "AutoMAA.app", directoryHint: .isDirectory)
            let copy = try await commandRunner.run(
                executable: "/usr/bin/ditto",
                arguments: [source.path, destination.path],
                timeout: 180
            )
            guard copy.exitCode == 0, !copy.timedOut, !copy.cancelled else {
                throw commandError("暂存 AutoMAA.app", copy)
            }
            try await SoftwareUpdateApplicationValidator().validate(destination, expectedVersion: expectedVersion)
            await detach(mountedURL)
            return destination
        } catch {
            await detach(mountedURL)
            throw error
        }
    }

    private func mountPoint(from output: String, under mountRoot: URL) throws -> URL {
        guard let data = output.data(using: .utf8),
              let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]],
              let mountPath = entities.compactMap({ $0["mount-point"] as? String }).last
        else {
            throw SoftwareUpdateError.invalidDownload("无法读取磁盘映像挂载点")
        }
        let mountURL = URL(filePath: mountPath).standardizedFileURL
        let rootPath = mountRoot.standardizedFileURL.path + "/"
        guard mountURL.path.hasPrefix(rootPath) else {
            throw SoftwareUpdateError.invalidDownload("磁盘映像挂载到了意外位置")
        }
        return mountURL
    }

    private func detach(_ mountedURL: URL) async {
        let result = try? await commandRunner.run(
            executable: "/usr/bin/hdiutil",
            arguments: ["detach", mountedURL.path],
            timeout: 30,
            observeCancellation: false
        )
        if result?.exitCode != 0 {
            _ = try? await commandRunner.run(
                executable: "/usr/bin/hdiutil",
                arguments: ["detach", "-force", mountedURL.path],
                timeout: 30,
                observeCancellation: false
            )
        }
    }

    private func commandError(_ action: String, _ result: CommandResult) -> SoftwareUpdateError {
        let output = result.combinedOutput.isEmpty ? "退出码 \(result.exitCode)" : String(result.combinedOutput.prefix(300))
        return .commandFailed(action, output)
    }
}

public struct SoftwareUpdateApplicationValidator: Sendable {
    private let commandRunner = CommandRunner()

    public init() {}

    public func validate(_ applicationURL: URL, expectedVersion: String?) async throws {
        let values = try applicationURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let infoURL = applicationURL.appending(path: "Contents/Info.plist")
        guard values.isDirectory == true, values.isSymbolicLink != true,
              applicationURL.pathExtension == "app",
              let infoData = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "com.rememorio.AutoMAA"
        else {
            throw SoftwareUpdateError.invalidApplication("Bundle ID 或目录结构不正确")
        }
        let version = info["CFBundleShortVersionString"] as? String
        if let expectedVersion, version != expectedVersion {
            throw SoftwareUpdateError.invalidApplication("版本应为 \(expectedVersion)，实际为 \(version ?? "未知")")
        }
        guard let executableName = info["CFBundleExecutable"] as? String,
              !executableName.isEmpty,
              !executableName.contains("/"),
              !executableName.contains("\\")
        else {
            throw SoftwareUpdateError.invalidApplication("缺少主执行文件")
        }
        let executableURL = applicationURL.appending(path: "Contents/MacOS/\(executableName)")
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SoftwareUpdateError.invalidApplication("主执行文件不可执行")
        }

        let architecture = try await commandRunner.run(
            executable: "/usr/bin/lipo",
            arguments: ["-archs", executableURL.path],
            timeout: 30
        )
        guard architecture.exitCode == 0,
              architecture.standardOutput.split(whereSeparator: \.isWhitespace).contains("arm64")
        else {
            throw SoftwareUpdateError.invalidApplication("不包含 arm64 可执行文件")
        }

        let signature = try await commandRunner.run(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", "--verbose=2", applicationURL.path],
            timeout: 60
        )
        guard signature.exitCode == 0, !signature.timedOut else {
            let output = signature.combinedOutput.isEmpty ? "代码签名校验失败" : String(signature.combinedOutput.prefix(300))
            throw SoftwareUpdateError.invalidApplication(output)
        }
    }
}

public struct SoftwareUpdateInstallationRequest: Sendable {
    public let currentApplicationURL: URL
    public let stagedApplicationURL: URL
    public let expectedVersion: String
    public let relaunch: Bool

    public init(
        currentApplicationURL: URL,
        stagedApplicationURL: URL,
        expectedVersion: String,
        relaunch: Bool = true
    ) {
        self.currentApplicationURL = currentApplicationURL
        self.stagedApplicationURL = stagedApplicationURL
        self.expectedVersion = expectedVersion
        self.relaunch = relaunch
    }
}

public struct SoftwareUpdateInstaller: Sendable {
    private let commandRunner = CommandRunner()
    private let validator = SoftwareUpdateApplicationValidator()

    public init() {}

    public static func validateInstallLocation(_ applicationURL: URL) throws {
        guard applicationURL.pathExtension == "app",
              applicationURL.lastPathComponent == "AutoMAA.app"
        else {
            throw SoftwareUpdateError.unsupportedInstallLocation("请先将 AutoMAA.app 放入“应用程序”文件夹并重新打开")
        }
        let values = try applicationURL.resourceValues(forKeys: [.volumeIsReadOnlyKey, .isSymbolicLinkKey])
        guard values.volumeIsReadOnly != true, values.isSymbolicLink != true else {
            throw SoftwareUpdateError.unsupportedInstallLocation("当前 App 位于只读磁盘映像中，请先拖入“应用程序”文件夹")
        }
        let parent = applicationURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw SoftwareUpdateError.unsupportedInstallLocation("AutoMAA 所在目录不可写，请手动从 DMG 更新")
        }
    }

    public func install(
        _ request: SoftwareUpdateInstallationRequest,
        beforeRelaunch: @Sendable () throws -> Void = {}
    ) async throws {
        try Self.validateInstallLocation(request.currentApplicationURL)
        try await validator.validate(request.currentApplicationURL, expectedVersion: nil)
        try await validator.validate(request.stagedApplicationURL, expectedVersion: request.expectedVersion)

        let manager = FileManager.default
        let parent = request.currentApplicationURL.deletingLastPathComponent()
        let token = UUID().uuidString
        let replacement = parent.appending(path: ".AutoMAA-update-\(token).app", directoryHint: .isDirectory)
        let backup = parent.appending(path: ".AutoMAA-backup-\(token).app", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: replacement) }

        let copy = try await commandRunner.run(
            executable: "/usr/bin/ditto",
            arguments: [request.stagedApplicationURL.path, replacement.path],
            timeout: 180,
            observeCancellation: false
        )
        guard copy.exitCode == 0, !copy.timedOut else {
            throw SoftwareUpdateError.commandFailed("复制新版本", copy.combinedOutput)
        }
        try await validator.validate(replacement, expectedVersion: request.expectedVersion)

        try manager.moveItem(at: request.currentApplicationURL, to: backup)
        do {
            try manager.moveItem(at: replacement, to: request.currentApplicationURL)
            try await validator.validate(request.currentApplicationURL, expectedVersion: request.expectedVersion)
            try beforeRelaunch()
            if request.relaunch {
                let opened = try await commandRunner.run(
                    executable: "/usr/bin/open",
                    arguments: [request.currentApplicationURL.path],
                    timeout: 30,
                    observeCancellation: false
                )
                guard opened.exitCode == 0 else {
                    throw SoftwareUpdateError.commandFailed("重新打开 AutoMAA", opened.combinedOutput)
                }
            }
            try? manager.removeItem(at: backup)
        } catch {
            try? manager.removeItem(at: request.currentApplicationURL)
            try? manager.moveItem(at: backup, to: request.currentApplicationURL)
            throw error
        }
    }
}

public struct SoftwareUpdateResult: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        case success
        case failure
    }

    public let status: Status
    public let version: String
    public let message: String
    public let createdAt: Date

    public init(status: Status, version: String, message: String, createdAt: Date = .now) {
        self.status = status
        self.version = version
        self.message = message
        self.createdAt = createdAt
    }
}

public struct SoftwareUpdateResultStore: Sendable {
    public let url: URL

    public init(directories: AppDirectories) {
        url = directories.root.appending(path: "update-result.json")
    }

    public init(url: URL) {
        self.url = url
    }

    public func save(_ result: SoftwareUpdateResult) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: url, options: .atomic)
    }

    public func loadAndClear() -> SoftwareUpdateResult? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try? decoder.decode(SoftwareUpdateResult.self, from: data)
        try? FileManager.default.removeItem(at: url)
        return result
    }
}

private struct GitHubReleaseResponse: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let htmlURL: String
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case draft
        case prerelease
        case assets
    }
}
