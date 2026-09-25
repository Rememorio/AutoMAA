import Foundation

public struct WorkflowRunIdentity: Codable, Equatable, Sendable {
    public let runID: UUID
    public let planID: UUID
    public let lockID: UUID

    public init(runID: UUID, planID: UUID, lockID: UUID) {
        self.runID = runID
        self.planID = planID
        self.lockID = lockID
    }
}

public enum WorkflowRunControlError: LocalizedError {
    case runEnded

    public var errorDescription: String? { "该次运行已结束或发生变化，请刷新后重试" }
}

public struct WorkflowRunControl: Sendable {
    private let directories: AppDirectories
    private var root: URL { directories.root.appending(path: "RunControl", directoryHint: .isDirectory) }
    private var activeURL: URL { root.appending(path: "active.json") }

    public init(directories: AppDirectories = .init()) {
        self.directories = directories
    }

    public func activeRun() -> WorkflowRunIdentity? {
        guard let identity = read(activeURL),
              ProcessLock.currentIdentity(at: directories.lock) == identity.lockID else { return nil }
        return identity
    }

    public func activate(_ identity: WorkflowRunIdentity) throws {
        guard ProcessLock.currentIdentity(at: directories.lock) == identity.lockID else {
            throw WorkflowRunControlError.runEnded
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for url in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.deletingPathExtension().lastPathComponent
            if name.hasPrefix("stop-"), UUID(uuidString: String(name.dropFirst(5))) != nil {
                try? FileManager.default.removeItem(at: url)
            }
        }
        try JSONEncoder().encode(identity).write(to: activeURL, options: .atomic)
    }

    public func requestStop(for identity: WorkflowRunIdentity) throws {
        guard activeRun() == identity else { throw WorkflowRunControlError.runEnded }
        try JSONEncoder().encode(identity).write(to: requestURL(identity.runID), options: .atomic)
    }

    public func isStopRequested(for identity: WorkflowRunIdentity) -> Bool {
        activeRun() == identity && read(requestURL(identity.runID)) == identity
    }

    public func finish(_ identity: WorkflowRunIdentity) {
        try? FileManager.default.removeItem(at: requestURL(identity.runID))
        if read(activeURL) == identity { try? FileManager.default.removeItem(at: activeURL) }
    }

    private func requestURL(_ runID: UUID) -> URL {
        root.appending(path: "stop-\(runID.uuidString.lowercased()).json")
    }

    private func read(_ url: URL) -> WorkflowRunIdentity? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkflowRunIdentity.self, from: data)
    }
}
