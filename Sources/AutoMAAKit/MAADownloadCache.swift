import CryptoKit
import Foundation

struct MAACoreReleaseManifest: Decodable, Sendable {
    struct Details: Decodable, Sendable {
        struct Asset: Decodable, Sendable {
            let name: String
            let size: Int64
            let browserDownloadURL: String?
            let mirrors: [String]?

            enum CodingKeys: String, CodingKey {
                case name, size, mirrors
                case browserDownloadURL = "browser_download_url"
            }
        }
        let assets: [Asset]
    }

    let version: String
    var details: Details? = nil

    func coreVersion() throws -> MAASemanticVersion {
        guard let value = MAASemanticVersion(version) else {
            throw MAACoreReleaseManifestError.invalidVersion(version)
        }
        return value
    }

    var macOSAsset: Details.Asset? {
        guard !version.contains("/"), !version.contains("\\"),
              let version = try? coreVersion() else { return nil }
        return details?.assets.first {
            $0.name == "MAA-v\(version)-macos-runtime-universal.zip" && $0.size > 0
        }
    }

    var downloadIdentity: MAACoreDownloadIdentity? {
        guard let asset = macOSAsset, let source = asset.browserDownloadURL,
              let url = URL(string: source), ["http", "https"].contains(url.scheme), url.host != nil
        else { return nil }
        return .init(version: version, name: asset.name, size: asset.size,
                     source: source, mirrors: asset.mirrors ?? [])
    }

    static func read(at url: URL) -> Self? {
        guard let size = MAADownloadCache.regularFileSize(url), size <= 2 * 1_024 * 1_024,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

struct MAACoreDownloadIdentity: Codable, Equatable, Sendable {
    let version: String
    let name: String
    let size: Int64
    let source: String
    let mirrors: [String]
}

/// A maa-cli cache, never an installation. Only the manifest and archive survive an attempt.
struct MAADownloadCache: Sendable {
    static let retention: TimeInterval = 7 * 24 * 60 * 60
    static let maximumBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
    let directory: URL
    let manifestURL: URL
    let channel: MAAUpdateChannel
    private let root: URL
    private let lock: ProcessLock

    private struct Integrity: Codable {
        let name: String
        let size: Int64
        let sha256: String
    }

    init(paths: MAAInstallationPaths, manifestURL: URL, channel: MAAUpdateChannel) throws {
        root = paths.cache.appending(path: ".automaa-downloads", directoryHint: .isDirectory)
        try Self.ensureDirectory(root)
        lock = try ProcessLock(url: root.appending(path: ".lock"))
        let scope = [paths.data.standardizedFileURL.path, manifestURL.absoluteString, channel.rawValue]
        let digest = SHA256.hash(data: try JSONEncoder().encode(scope))
        directory = root.appending(path: digest.map { String(format: "%02x", $0) }.joined(), directoryHint: .isDirectory)
        self.manifestURL = manifestURL
        self.channel = channel
        try prune()
        try Self.ensureDirectory(directory)
    }

    var manifestFile: URL { directory.appending(path: "core-manifest-\(channel.rawValue).json") }
    private var integrityFile: URL { directory.appending(path: "integrity.json") }

    func cachedDownload() -> (identity: MAACoreDownloadIdentity, file: URL, size: Int64)? {
        guard let identity = MAACoreReleaseManifest.read(at: manifestFile)?.downloadIdentity,
              identity.size <= Self.maximumBytes else { return nil }
        let archive = directory.appending(path: identity.name)
        if Self.regularFileSize(archive) == identity.size { return (identity, archive, identity.size) }
        let partial = archive.appendingPathExtension("partial")
        guard let size = Self.regularFileSize(partial), size > 0, size <= identity.size else { return nil }
        return (identity, partial, size)
    }

    /// Revalidate the current source before maa-cli can reuse its size-verified download.
    func prepare(fetcher: any MAACoreReleaseManifestFetching) async throws -> MAACoreDownloadIdentity? {
        guard let cached = cachedDownload() else {
            try clear(except: [])
            return nil
        }
        if let data = try? Data(contentsOf: integrityFile),
           let integrity = try? JSONDecoder().decode(Integrity.self, from: data),
           integrity.name == cached.file.lastPathComponent {
            let checksum = try SoftwareUpdateVerifier.sha256(of: cached.file)
            if integrity.size != cached.size || integrity.sha256 != checksum {
                try clear(except: [])
                return nil
            }
        }
        let current = try await fetcher.manifest(at: manifestURL).downloadIdentity
        guard current == cached.identity else {
            try clear(except: [])
            return nil
        }
        try clear(except: [manifestFile.lastPathComponent, cached.file.lastPathComponent])
        return cached.identity
    }

    func retainedMessage() -> String? {
        guard let cached = cachedDownload() else { return nil }
        return cached.file.pathExtension == "partial"
            ? "已保留引擎包下载进度，下次更新将尝试续传"
            : "已保留完整引擎包，下次更新可复用"
    }

    func finish() throws {
        if let cached = cachedDownload() {
            let checksum = try SoftwareUpdateVerifier.sha256(of: cached.file)
            let integrity = Integrity(name: cached.file.lastPathComponent, size: cached.size, sha256: checksum)
            try clear(except: [manifestFile.lastPathComponent, cached.file.lastPathComponent])
            try JSONEncoder().encode(integrity).write(to: integrityFile, options: .atomic)
        } else {
            try clear(except: [])
        }
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: directory.path)
        try prune()
    }

    func discard() throws { try clear(except: []) }

    private func clear(except names: Set<String>) throws {
        for item in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where !names.contains(item.lastPathComponent) {
            try FileManager.default.removeItem(at: item)
        }
    }

    private func prune() throws {
        let manager = FileManager.default
        let cutoff = Date().addingTimeInterval(-Self.retention)
        var entries: [(url: URL, date: Date, size: Int64)] = []
        for url in try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) {
            let name = url.lastPathComponent
            guard name.count == 64, name.allSatisfy({ $0.isHexDigit }),
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            let date = values.contentModificationDate ?? .distantPast
            if date < cutoff {
                try manager.removeItem(at: url)
            } else {
                let files = try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])
                entries.append((url, date, files.reduce(0) { $0 + (Self.regularFileSize($1) ?? 0) }))
            }
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        for entry in entries.sorted(by: { $0.date < $1.date }) where total > Self.maximumBytes {
            try manager.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    static func regularFileSize(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else { return nil }
        return Int64(size)
    }

    private static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
    }
}
