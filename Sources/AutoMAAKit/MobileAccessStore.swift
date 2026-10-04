import Foundation

public struct MobileDevice: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let pairedAt: Date
    let credentialHash: String
}

public struct MobileAccessConfiguration: Codable, Sendable {
    public var enabled = false
    public var hostID = UUID()
    public var devices: [MobileDevice] = []
    public init() {}
}

public struct MobileAccessStore: Sendable {
    private let directory: URL
    private var url: URL { directory.appending(path: "devices.json") }
    public init(directories: AppDirectories) {
        directory = directories.root.appending(path: "MobileAccess", directoryHint: .isDirectory)
    }
    public func load() throws -> MobileAccessConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        return try MobileProtocol.decode(MobileAccessConfiguration.self, from: Data(contentsOf: url))
    }
    public func save(_ configuration: MobileAccessConfiguration) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try MobileProtocol.encode(configuration).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

@MainActor
public final class MobileAccessAuthorization {
    public private(set) var configuration: MobileAccessConfiguration
    public private(set) var pairing: MobilePairingCode?
    public let sessionID = UUID()
    private let store: MobileAccessStore
    private let now: () -> Date
    private var commands: [UUID: (UUID, MobileRequest, MobileReply)] = [:]

    public init(store: MobileAccessStore, now: @escaping () -> Date = Date.init) throws {
        self.store = store
        self.now = now
        configuration = try store.load()
    }
    public func setEnabled(_ enabled: Bool) throws {
        var updated = configuration
        updated.enabled = enabled
        try store.save(updated)
        configuration = updated
        if !enabled { pairing = nil }
    }
    public func beginPairing(hostName: String, endpoint: String) throws -> MobilePairingCode {
        guard configuration.enabled, MobileProtocol.validEndpoint(endpoint) else {
            throw MobileAccessError("请先建立安全的手机连接服务")
        }
        let code = MobilePairingCode(hostID: configuration.hostID, hostName: hostName, endpoint: endpoint,
                                    secret: try MobileProtocol.secret(), expiresAt: now().addingTimeInterval(300))
        pairing = code
        return code
    }
    public func cancelPairing() { pairing = nil }
    public func validatePairing(secret: String) throws {
        guard configuration.enabled, let pairing, pairing.expiresAt > now(),
              MobileProtocol.matches(secret, hash: MobileProtocol.digest(Data(pairing.secret.utf8))) else {
            throw MobileAccessError("配对信息已过期或无效，请在 Mac 上重新配对")
        }
    }
    public func approvePairing(secret: String, name: String) throws -> (MobileDevice, String) {
        try validatePairing(secret: secret)
        guard configuration.devices.count < 20 else { throw MobileAccessError("请先移除不再使用的设备") }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw MobileAccessError("设备名称无效")
        }
        let credential = try MobileProtocol.secret()
        let device = MobileDevice(id: UUID(), name: name, pairedAt: now(),
                                  credentialHash: MobileProtocol.digest(Data(credential.utf8)))
        var updated = configuration
        updated.devices.append(device)
        try store.save(updated)
        configuration = updated
        pairing = nil
        return (device, credential)
    }
    public func authenticate(deviceID: UUID, secret: String) throws -> MobileDevice {
        guard configuration.enabled, let device = configuration.devices.first(where: { $0.id == deviceID }),
              MobileProtocol.matches(secret, hash: device.credentialHash) else {
            throw MobileAccessError("设备尚未授权或授权已撤销，请重新配对")
        }
        return device
    }
    public func isAuthorized(_ id: UUID) -> Bool {
        configuration.enabled && configuration.devices.contains { $0.id == id }
    }
    public func revoke(_ id: UUID) throws {
        var updated = configuration
        updated.devices.removeAll { $0.id == id }
        try store.save(updated)
        configuration = updated
    }
    public func perform(_ request: MobileRequest, deviceID: UUID,
                        execute: () throws -> String) throws -> MobileReply {
        guard isAuthorized(deviceID), request.version == MobileProtocol.version, request.sessionID == sessionID,
              request.operation == .run || request.operation == .stop else {
            throw MobileAccessError("连接或操作状态已变化，请刷新后重试")
        }
        if let (owner, original, reply) = commands[request.id] {
            guard owner == deviceID, original == request else { throw MobileAccessError("操作标识冲突，请刷新状态") }
            return reply
        }
        // Receipts live for the entire session; eviction could turn a retry into a second execution.
        guard commands.count < 4096 else { throw MobileAccessError("操作记录已满，请在 Mac 重启 AutoMAA") }
        let reply: MobileReply
        do { reply = MobileReply(id: request.id, type: "accepted", message: try execute()) }
        catch { reply = MobileReply(id: request.id, type: "rejected", message: error.localizedDescription) }
        commands[request.id] = (deviceID, request, reply)
        return reply
    }
    public func receipt(_ id: UUID, deviceID: UUID) -> MobileReply? {
        guard isAuthorized(deviceID), let (owner, _, reply) = commands[id], owner == deviceID else { return nil }
        return reply
    }
}
