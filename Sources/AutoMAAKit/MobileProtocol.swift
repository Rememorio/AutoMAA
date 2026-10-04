import CryptoKit
import Foundation
import Security

public enum MobileProtocol {
    public static let version = 1
    public static let maximumRequestBytes = 16_384

    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    public static func secret() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw MobileAccessError("无法生成安全凭据，请重试")
        }
        return Data(bytes).base64EncodedString()
    }

    public static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func matches(_ secret: String, hash: String) -> Bool {
        let candidate = Array(digest(Data(secret.utf8)).utf8)
        let expected = Array(hash.utf8)
        guard candidate.count == expected.count else { return false }
        return zip(candidate, expected).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    public static func validEndpoint(_ value: String) -> Bool {
        guard let url = URLComponents(string: value), url.scheme == "wss",
              let host = url.host, host.hasSuffix(".ts.net"), host.split(separator: ".").count >= 4,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path == "/mobile", let port = url.port, (1024...65535).contains(port) else { return false }
        return true
    }
}

public struct MobileAccessError: LocalizedError, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct MobilePairingCode: Codable, Sendable {
    public var version = MobileProtocol.version
    public let hostID: UUID
    public let hostName: String
    public let endpoint: String
    public let secret: String
    public let expiresAt: Date
}

public struct MobileRequest: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case pair, authenticate, snapshot, history, historyDetails, run, stop, receipt
    }
    public var version = MobileProtocol.version
    public var id: UUID
    public var operation: Operation
    public var secret: String?
    public var deviceID: UUID?
    public var deviceName: String?
    public var sessionID: UUID?
    public var planID: UUID?
    public var revision: String?
    public var run: WorkflowRunIdentity?
    public var before: String?
    public var historyID: String?
    public var commandID: UUID?
    public init(id: UUID = UUID(), operation: Operation) {
        self.id = id
        self.operation = operation
    }
}

public struct MobileReply: Codable, Sendable {
    public var id: UUID?
    public var type: String
    public var message: String?
    public var outcome: String?
    public var deviceID: UUID?
    public var secret: String?
    public var snapshot: MobileSnapshot?
    public var history: [MobileHistoryItem]?
    public var events: [MobileLog]?
    public var next: String?
    public init(id: UUID? = nil, type: String, message: String? = nil) {
        self.id = id
        self.type = type
        self.message = message
    }
}

public struct MobileSnapshot: Codable, Sendable {
    public var hostID: UUID
    public var sessionID: UUID
    public var hostName: String
    public var appVersion = ""
    public var updatedAt = Date()
    public var revision = ""
    public var busy = false
    public var stopping = false
    public var run: WorkflowRunIdentity?
    public var phase = ""
    public var message = ""
    public var progress = 0.0
    public var canStop = false
    public var plans: [MobilePlan] = []
    public init(hostID: UUID, sessionID: UUID, hostName: String) {
        self.hostID = hostID
        self.sessionID = sessionID
        self.hostName = hostName
    }
}

public struct MobilePlan: Codable, Sendable {
    public var id: UUID
    public var name: String
    public var accounts: [String] = []
    public var tasks: [String] = []
    public var parameters: [String] = []
    public var schedule = ""
    public var action = "运行方案"
    public var canRun = false
    public var pending: [String] = []
    public var warnings: [String] = []
    public init(id: UUID, name: String) { self.id = id; self.name = name }
}

public struct MobileHistoryItem: Codable, Sendable {
    public var id: String
    public var title: String
    public var startedAt: Date
    public var status: String
    public var hasAttention = false
    public var failed = false
    public init(id: String, title: String, startedAt: Date, status: String) {
        self.id = id; self.title = title; self.startedAt = startedAt; self.status = status
    }
}

public struct MobileLog: Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: String
    public let message: String
    public let details: String?
    public init(_ entry: LogEntry, sensitiveValues: [String]) {
        id = entry.id
        timestamp = entry.timestamp
        level = entry.level.rawValue
        message = String(SensitiveDataRedactor.redact(entry.message, sensitiveValues: sensitiveValues).prefix(2048))
        details = entry.details.map { String(SensitiveDataRedactor.redact($0, sensitiveValues: sensitiveValues).prefix(4096)) }
    }
}
