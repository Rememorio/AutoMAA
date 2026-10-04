import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Mobile access authorization")
@MainActor
struct MobileAccessTests {
    @Test("initializing a disabled service does not create authorization files")
    func initializationDoesNotWrite() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        #expect(!fixture.authorization.configuration.enabled)
        #expect(fixture.authorization.configuration.devices.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
        _ = try MobileAccessAuthorization(store: fixture.store)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.path))
        try fixture.authorization.setEnabled(true)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "MobileAccess/devices.json").path))
    }

    @Test("pairing expires at the boundary and each invitation can be consumed only once")
    func pairingExpiryAndSingleUse() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        let authorization = fixture.authorization
        try authorization.setEnabled(true)
        let first = try fixture.pairing()
        #expect(Data(base64Encoded: first.secret)?.count == 32)
        fixture.clock.date = first.expiresAt.addingTimeInterval(-0.001)
        try authorization.validatePairing(secret: first.secret)
        fixture.clock.date = first.expiresAt
        #expect(throws: MobileAccessError.self) { try authorization.validatePairing(secret: first.secret) }
        #expect(throws: MobileAccessError.self) { try authorization.approvePairing(secret: first.secret, name: "Test phone") }
        let second = try fixture.pairing()
        #expect(first.secret != second.secret)
        #expect(throws: MobileAccessError.self) { try authorization.validatePairing(secret: first.secret) }
        let (device, credential) = try authorization.approvePairing(secret: second.secret, name: "  Test phone  ")
        #expect(device.name == "Test phone")
        #expect(credential != second.secret)
        #expect(authorization.pairing == nil)
        #expect(throws: MobileAccessError.self) { try authorization.approvePairing(secret: second.secret, name: "Other phone") }
        #expect(try authorization.authenticate(deviceID: device.id, secret: credential) == device)
        #expect(throws: MobileAccessError.self) { try authorization.authenticate(deviceID: device.id, secret: second.secret) }
    }

    @Test("disabled services reject pairing, authentication, commands, and receipts")
    func disabledServiceDeniesAllAccess() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        let authorization = fixture.authorization
        #expect(!authorization.configuration.enabled)
        #expect(throws: MobileAccessError.self) { try fixture.pairing() }
        let (device, credential) = try fixture.device()
        let request = fixture.command()
        _ = try authorization.perform(request, deviceID: device.id) { "accepted" }
        let code = try fixture.pairing()
        try authorization.setEnabled(false)
        #expect(authorization.pairing == nil)
        #expect(!authorization.isAuthorized(device.id))
        #expect(authorization.receipt(request.id, deviceID: device.id) == nil)
        #expect(throws: MobileAccessError.self) { try authorization.validatePairing(secret: code.secret) }
        #expect(throws: MobileAccessError.self) { try authorization.authenticate(deviceID: device.id, secret: credential) }
        #expect(throws: MobileAccessError.self) {
            try authorization.perform(request, deviceID: device.id) { Issue.record("Disabled device executed a command"); return "bad" }
        }
        try authorization.setEnabled(true)
        #expect(try authorization.authenticate(deviceID: device.id, secret: credential) == device)
        #expect(authorization.receipt(request.id, deviceID: device.id)?.type == "accepted")
        #expect(throws: MobileAccessError.self) { try authorization.validatePairing(secret: code.secret) }
    }

    @Test("host identity and revocation persist but invitations and receipts do not survive restart")
    func restartAndRevocation() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        let authorization = fixture.authorization
        let (device, credential) = try fixture.device()
        let request = fixture.command()
        _ = try authorization.perform(request, deviceID: device.id) { "first" }
        let pairing = try fixture.pairing()
        let restarted = try MobileAccessAuthorization(store: fixture.store)
        #expect(restarted.configuration.hostID == authorization.configuration.hostID)
        #expect(restarted.sessionID != authorization.sessionID)
        #expect(try restarted.authenticate(deviceID: device.id, secret: credential) == device)
        #expect(restarted.pairing == nil)
        #expect(restarted.receipt(request.id, deviceID: device.id) == nil)
        #expect(throws: MobileAccessError.self) { try restarted.validatePairing(secret: pairing.secret) }
        #expect(throws: MobileAccessError.self) {
            try restarted.perform(request, deviceID: device.id) { Issue.record("Old session executed after restart"); return "bad" }
        }
        try restarted.revoke(device.id)
        #expect(!restarted.isAuthorized(device.id))
        #expect(throws: MobileAccessError.self) { try restarted.authenticate(deviceID: device.id, secret: credential) }
        let afterRevocation = try MobileAccessAuthorization(store: fixture.store)
        #expect(afterRevocation.configuration.devices.isEmpty)
        #expect(throws: MobileAccessError.self) { try afterRevocation.authenticate(deviceID: device.id, secret: credential) }
        try afterRevocation.setEnabled(false)
        #expect(try !MobileAccessAuthorization(store: fixture.store).configuration.enabled)
    }

    @Test("only hashed credentials persist and mobile authorization files are private")
    func credentialsAndPermissions() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        let code = try fixture.pairing(enabling: true)
        let (device, credential) = try fixture.authorization.approvePairing(secret: code.secret, name: "Test phone")
        let directory = fixture.root.appending(path: "MobileAccess")
        let file = directory.appending(path: "devices.json")
        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(!contents.contains(credential))
        #expect(!contents.contains(code.secret))
        #expect(contents.contains(MobileProtocol.digest(Data(credential.utf8))))
        #expect(device.credentialHash.count == 64)
        #expect(try fixture.permissions(directory) == 0o700)
        #expect(try fixture.permissions(file) == 0o600)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try fixture.store.save(fixture.authorization.configuration)
        #expect(try fixture.permissions(directory) == 0o700)
        #expect(try fixture.permissions(file) == 0o600)
        #expect(MobileProtocol.matches(credential, hash: device.credentialHash))
        #expect(!MobileProtocol.matches(credential + "x", hash: device.credentialHash))
        #expect(!MobileProtocol.matches(credential, hash: ""))
    }

    @Test("corrupt authorization files fail closed instead of issuing a new host identity")
    func corruptStoreFailsClosed() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        let file = fixture.root.appending(path: "MobileAccess/devices.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not valid json".utf8).write(to: file, options: .atomic)
        #expect(throws: (any Error).self) { try MobileAccessAuthorization(store: fixture.store) }
        #expect(try String(contentsOf: file, encoding: .utf8) == "not valid json")
    }

    @Test("invalid names and excess devices cannot consume a valid invitation")
    func deviceInputAndCapacity() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        let authorization = fixture.authorization
        let code = try fixture.pairing(enabling: true)
        for name in [" ", String(repeating: "a", count: 61), "bad\u{0000}name", "bad\nname"] {
            #expect(throws: MobileAccessError.self) { try authorization.approvePairing(secret: code.secret, name: name) }
            #expect(authorization.configuration.devices.isEmpty)
            try authorization.validatePairing(secret: code.secret)
        }
        for index in 0..<20 {
            let pairing = try fixture.pairing()
            _ = try authorization.approvePairing(secret: pairing.secret, name: "Test phone \(index)")
        }
        let full = try fixture.pairing()
        #expect(throws: MobileAccessError.self) { try authorization.approvePairing(secret: full.secret, name: "Excess phone") }
        #expect(authorization.configuration.devices.count == 20)
        authorization.cancelPairing()
        #expect(throws: MobileAccessError.self) { try authorization.validatePairing(secret: full.secret) }
    }

    @Test("only valid secure tailnet endpoints can be paired")
    func endpointValidation() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        try fixture.authorization.setEnabled(true)
        #expect(MobileProtocol.validEndpoint(MobileAccessFixture.endpoint))
        for endpoint in [
            "ws://host.example.ts.net:43827/mobile", "wss://example.com:43827/mobile",
            "wss://host.ts.net:43827/mobile", "wss://host.example.ts.net/mobile",
            "wss://host.example.ts.net:443/mobile", "wss://host.example.ts.net:43827/other",
            "wss://user@host.example.ts.net:43827/mobile", "wss://host.example.ts.net:43827/mobile?q=x",
            "wss://host.example.ts.net:43827/mobile#x", "wss://host.example.ts.net.evil.example:43827/mobile",
        ] {
            #expect(!MobileProtocol.validEndpoint(endpoint))
            #expect(throws: MobileAccessError.self) { try fixture.authorization.beginPairing(hostName: "Test Mac", endpoint: endpoint) }
        }
    }

    @Test("version, session, operation, and device authorization are checked before execution")
    func commandGuards() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        let (device, _) = try fixture.device()
        let valid = fixture.command()
        var invalid: [MobileRequest] = []
        var changed = valid; changed.version += 1; invalid.append(changed)
        changed = valid; changed.sessionID = UUID(); invalid.append(changed)
        changed = valid; changed.sessionID = nil; invalid.append(changed)
        changed = valid; changed.operation = .snapshot; invalid.append(changed)
        for request in invalid {
            #expect(throws: MobileAccessError.self) {
                try fixture.authorization.perform(request, deviceID: device.id) { Issue.record("Invalid command executed"); return "bad" }
            }
        }
        #expect(throws: MobileAccessError.self) {
            try fixture.authorization.perform(valid, deviceID: UUID()) { Issue.record("Unknown device executed"); return "bad" }
        }
        #expect(fixture.authorization.receipt(valid.id, deviceID: device.id) == nil)
    }

    @Test("repeated command ids reuse the receipt while changed payloads and other devices are rejected")
    func duplicateAndConflictingCommands() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        let authorization = fixture.authorization
        let (first, _) = try fixture.device()
        let (second, _) = try fixture.device()
        let request = fixture.command()
        var executions = 0
        let reply = try authorization.perform(request, deviceID: first.id) { executions += 1; return "Started" }
        let duplicate = try authorization.perform(request, deviceID: first.id) { executions += 1; return "Must not execute" }
        #expect(executions == 1)
        #expect(reply.id == request.id)
        #expect(duplicate.type == "accepted")
        #expect(duplicate.message == "Started")
        #expect(authorization.receipt(request.id, deviceID: second.id) == nil)
        #expect(throws: MobileAccessError.self) { try authorization.perform(request, deviceID: second.id) { "bad" } }
        var conflicting = request
        conflicting.planID = UUID()
        #expect(throws: MobileAccessError.self) { try authorization.perform(conflicting, deviceID: first.id) { "bad" } }
        conflicting = request
        conflicting.revision = "changed"
        #expect(throws: MobileAccessError.self) { try authorization.perform(conflicting, deviceID: first.id) { "bad" } }
        conflicting = request
        conflicting.operation = .stop
        #expect(throws: MobileAccessError.self) { try authorization.perform(conflicting, deviceID: first.id) { "bad" } }
        try authorization.revoke(first.id)
        #expect(authorization.receipt(request.id, deviceID: first.id) == nil)
        #expect(throws: MobileAccessError.self) { try authorization.perform(request, deviceID: first.id) { "bad" } }
    }

    @Test("rejected operations are cached and cannot later become accepted under the same id")
    func rejectedCommandsStayRejected() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        let (device, _) = try fixture.device()
        let request = fixture.command()
        var executions = 0
        let rejected = try fixture.authorization.perform(request, deviceID: device.id) {
            executions += 1
            throw MobileAccessError("Test rejection")
        }
        let duplicate = try fixture.authorization.perform(request, deviceID: device.id) { executions += 1; return "bad" }
        #expect(executions == 1)
        #expect(rejected.type == "rejected")
        #expect(duplicate.type == "rejected")
        #expect(duplicate.message == "Test rejection")
        #expect(fixture.authorization.receipt(request.id, deviceID: device.id)?.type == "rejected")
    }

    @Test("a full receipt cache rejects new mutations without evicting existing receipts")
    func receiptCapacityDoesNotEvict() throws {
        let fixture = try MobileAccessFixture()
        defer { fixture.remove() }
        let (device, _) = try fixture.device()
        let first = fixture.command()
        _ = try fixture.authorization.perform(first, deviceID: device.id) { "First receipt" }
        for _ in 1..<4096 {
            _ = try fixture.authorization.perform(fixture.command(), deviceID: device.id) { "Accepted" }
        }
        #expect(throws: MobileAccessError.self) {
            try fixture.authorization.perform(fixture.command(), deviceID: device.id) { Issue.record("Full cache executed a new command"); return "bad" }
        }
        let duplicate = try fixture.authorization.perform(first, deviceID: device.id) { Issue.record("Evicted original receipt"); return "bad" }
        #expect(duplicate.message == "First receipt")
    }

    @Test("mobile protocol roundtrips and log output is bounded and redacted")
    func protocolAndLogRedaction() throws {
        var request = MobileRequest(operation: .stop)
        request.sessionID = UUID()
        request.run = .init(runID: UUID(), planID: UUID(), lockID: UUID())
        #expect(try MobileProtocol.decode(MobileRequest.self, from: MobileProtocol.encode(request)) == request)
        let text = "user@example.com 12345678901 match-secret /Users/test-private/file"
        let entry = LogEntry(level: .info, message: text + String(repeating: "m", count: 2200),
                             details: text + String(repeating: "d", count: 4300))
        let log = MobileLog(entry, sensitiveValues: ["match-secret"])
        #expect(log.message.count == 2048)
        #expect(log.details?.count == 4096)
        for secret in ["user@example.com", "12345678901", "match-secret", "test-private"] {
            #expect(!log.message.contains(secret))
            #expect(log.details?.contains(secret) == false)
        }
    }

    @Test("loopback websocket exchanges text and reconnects after a server restart")
    func loopbackWebSocketRestart() async throws {
        let server = MobileWebSocketServer()
        defer { server.onMessage = { _, _ in }; server.stop() }
        var received: [String] = []
        server.onMessage = { id, data in
            received.append(String(decoding: data, as: UTF8.self))
            server.send(MobileReply(type: "echo", message: "Test reply"), to: id)
        }
        for index in 0..<2 {
            let port = try await server.start()
            let session = URLSession(configuration: .ephemeral)
            let socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/mobile")!)
            socket.resume()
            var reply: MobileReply?
            var failure: String?
            let work = Task { @MainActor in
                do {
                    try await socket.send(.string("Test request \(index)"))
                    let message = try await socket.receive()
                    if case let .string(text) = message {
                        reply = try MobileProtocol.decode(MobileReply.self, from: Data(text.utf8))
                    }
                } catch { failure = error.localizedDescription }
            }
            await waitFor { reply != nil || failure != nil }
            #expect(failure == nil)
            #expect(reply?.type == "echo")
            #expect(reply?.message == "Test reply")
            #expect(received.last == "Test request \(index)")
            socket.cancel(with: .goingAway, reason: nil)
            work.cancel()
            session.invalidateAndCancel()
            await work.value
            server.stop()
        }
        #expect(received.count == 2)
    }

    @Test("websocket rejects oversized and binary messages without delivering them to the application")
    func loopbackWebSocketMessageLimits() async throws {
        for message in [URLSessionWebSocketTask.Message.string(String(repeating: "x", count: MobileProtocol.maximumRequestBytes + 1)),
                        .data(Data("binary".utf8))] {
            let server = MobileWebSocketServer()
            defer { server.stop() }
            var disconnects = 0
            var delivered = 0
            server.onDisconnect = { _ in disconnects += 1 }
            server.onMessage = { _, _ in delivered += 1 }
            let port = try await server.start()
            let session = URLSession(configuration: .ephemeral)
            let socket = session.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/mobile")!)
            socket.resume()
            let work = Task { try? await socket.send(message) }
            await waitFor { disconnects > 0 }
            #expect(disconnects == 1)
            #expect(delivered == 0)
            socket.cancel(with: .goingAway, reason: nil)
            work.cancel()
            session.invalidateAndCancel()
            _ = await work.value
            server.stop()
        }
    }

    private func waitFor(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
private final class MobileAccessFixture {
    static let endpoint = "wss://test-mac.example.ts.net:43827/mobile"
    final class Clock { var date = Date(timeIntervalSince1970: 1_800_000_000) }
    let root = FileManager.default.temporaryDirectory.appending(path: "automaa-mobile-test-\(UUID())")
    let clock = Clock()
    let store: MobileAccessStore
    let authorization: MobileAccessAuthorization

    init() throws {
        store = MobileAccessStore(directories: AppDirectories(root: root))
        let clock = clock
        authorization = try MobileAccessAuthorization(store: store, now: { clock.date })
    }
    func pairing(enabling: Bool = false) throws -> MobilePairingCode {
        if enabling { try authorization.setEnabled(true) }
        return try authorization.beginPairing(hostName: "Test Mac", endpoint: Self.endpoint)
    }
    func device() throws -> (MobileDevice, String) {
        let code = try pairing(enabling: true)
        return try authorization.approvePairing(secret: code.secret, name: "Test phone")
    }
    func command() -> MobileRequest {
        var request = MobileRequest(operation: .run)
        request.sessionID = authorization.sessionID
        request.planID = UUID()
        request.revision = "test-revision"
        return request
    }
    func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}
