import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Mobile Swift and Dart interoperability")
@MainActor
struct MobileInteropTests {
    @Test("Dart exchanges the production protocol with a real Swift websocket listener",
          .enabled(if: ProcessInfo.processInfo.environment["AUTOMAA_INTEROP_DART"] != nil))
    func dartProtocolSmoke() async throws {
        let dart = try #require(ProcessInfo.processInfo.environment["AUTOMAA_INTEROP_DART"])
        #expect(FileManager.default.isExecutableFile(atPath: dart))
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-mobile-interop-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try MobileInteropFixture(root: root)
        defer { fixture.server.stop() }
        let port = try await fixture.server.start()
        let invitation = try fixture.authorization.beginPairing(hostName: "协议测试 Mac",
            endpoint: "wss://interop-mac.example.ts.net:43827/mobile")
        let invitationURL = root.appending(path: "invitation.json")
        try MobileProtocol.encode(invitation).write(to: invitationURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: invitationURL.path)
        let revokeURL = root.appending(path: "revoke-device")
        let revokedURL = root.appending(path: "device-revoked")
        let revocation = Task { @MainActor in
            while !Task.isCancelled {
                if FileManager.default.fileExists(atPath: revokeURL.path) {
                    do {
                        guard let deviceID = fixture.pairedDeviceID else {
                            throw MobileAccessError("Test device is not paired")
                        }
                        try fixture.authorization.revoke(deviceID)
                        for (socket, id) in fixture.clients where id == deviceID { fixture.server.disconnect(socket) }
                        try Data().write(to: revokedURL, options: .atomic)
                    } catch { Issue.record("Test revocation failed: \(error.localizedDescription)") }
                    return
                }
                do { try await Task.sleep(for: .milliseconds(20)) }
                catch { return }
            }
        }
        defer { revocation.cancel() }
        let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Mobile/tool/protocol_smoke.dart")
        let result = try await CommandRunner().run(executable: dart, arguments: [
            script.path, "--port", String(port), "--invitation", invitationURL.path,
            "--revoke", revokeURL.path, "--revoked", revokedURL.path,
        ], environment: ["DART_SUPPRESS_ANALYTICS": "true", "FLUTTER_SUPPRESS_ANALYTICS": "true"], timeout: 40)
        #expect(!result.timedOut)
        #expect(!result.cancelled)
        #expect(result.exitCode == 0, "Dart protocol smoke failed: \(result.combinedOutput)")
        #expect(result.standardOutput.contains("AUTOMAA_INTEROP_OK"))
        #expect(fixture.runCount == 1)
        #expect(fixture.stopCount == 1)
        #expect(fixture.pairCount == 1)
        #expect(fixture.authorization.configuration.devices.isEmpty)
        #expect(FileManager.default.fileExists(atPath: revokedURL.path))
    }
}

@MainActor
private final class MobileInteropFixture {
    let server = MobileWebSocketServer()
    let authorization: MobileAccessAuthorization
    let planID = UUID()
    let runID = UUID()
    let lockID = UUID()
    var clients: [UUID: UUID] = [:]
    var pairedDeviceID: UUID?
    var runCount = 0
    var stopCount = 0
    var pairCount = 0
    var running = false

    init(root: URL) throws {
        authorization = try MobileAccessAuthorization(store: MobileAccessStore(directories: AppDirectories(root: root)))
        try authorization.setEnabled(true)
        server.onMessage = { [weak self] socket, data in self?.receive(socket, data) }
        server.onDisconnect = { [weak self] socket in self?.clients[socket] = nil }
    }

    var identity: WorkflowRunIdentity { .init(runID: runID, planID: planID, lockID: lockID) }
    var snapshot: MobileSnapshot {
        var value = MobileSnapshot(hostID: authorization.configuration.hostID,
                                  sessionID: authorization.sessionID, hostName: "协议测试 Mac")
        value.appVersion = "0.0.0-interop"
        value.revision = "interop-revision"
        value.phase = running ? "执行任务" : "空闲"
        value.message = "测试状态，不执行游戏"
        value.progress = running ? 0.5 : 0
        value.busy = running
        value.canStop = running
        value.run = running ? identity : nil
        var plan = MobilePlan(id: planID, name: "测试方案")
        plan.accounts = ["测试客户端 / 测试账号"]
        plan.tasks = ["收取奖励"]
        plan.canRun = !running
        value.plans = [plan]
        return value
    }

    private func receive(_ socket: UUID, _ data: Data) {
        guard let request = try? MobileProtocol.decode(MobileRequest.self, from: data),
              request.version == MobileProtocol.version else { server.disconnect(socket); return }
        do {
            if request.operation == .pair {
                try authorization.validatePairing(secret: request.secret ?? "")
                server.send(MobileReply(id: request.id, type: "approval"), to: socket)
                let (device, secret) = try authorization.approvePairing(secret: request.secret ?? "", name: request.deviceName ?? "")
                #expect(device.name == "测试手机 Interop")
                pairedDeviceID = device.id
                clients[socket] = device.id
                pairCount += 1
                var reply = MobileReply(id: request.id, type: "paired")
                reply.deviceID = device.id
                reply.secret = secret
                reply.snapshot = snapshot
                server.send(reply, to: socket)
                return
            }
            if request.operation == .authenticate {
                guard let deviceID = request.deviceID else { throw MobileAccessError("Missing device") }
                _ = try authorization.authenticate(deviceID: deviceID, secret: request.secret ?? "")
                clients[socket] = deviceID
                var reply = MobileReply(id: request.id, type: "authenticated")
                reply.snapshot = snapshot
                server.send(reply, to: socket)
                return
            }
            guard let deviceID = clients[socket], authorization.isAuthorized(deviceID) else {
                throw MobileAccessError("Device is not authorized")
            }
            var reply: MobileReply
            switch request.operation {
            case .snapshot:
                reply = MobileReply(id: request.id, type: "snapshot")
            case .run, .stop:
                reply = try authorization.perform(request, deviceID: deviceID) {
                    if request.operation == .run {
                        guard request.planID == self.planID, request.revision == "interop-revision", !self.running else {
                            throw MobileAccessError("Test run rejected")
                        }
                        self.runCount += 1
                        self.running = true
                        return "测试运行请求已接受"
                    }
                    guard request.run == self.identity, self.running else { throw MobileAccessError("Test stop rejected") }
                    self.stopCount += 1
                    self.running = false
                    return "测试停止请求已接受"
                }
            case .receipt:
                guard request.sessionID == authorization.sessionID, let commandID = request.commandID,
                      let receipt = authorization.receipt(commandID, deviceID: deviceID) else {
                    throw MobileAccessError("Test receipt is not available")
                }
                reply = receipt
                reply.id = request.id
                reply.type = "receipt"
                reply.outcome = receipt.type
            case .history:
                reply = MobileReply(id: request.id, type: "history")
                reply.history = [.init(id: "interop-history", title: "测试活动", startedAt: Date(), status: "正在运行")]
            case .historyDetails:
                guard request.historyID == "interop-history" else { throw MobileAccessError("Invalid test history id") }
                reply = MobileReply(id: request.id, type: "historyDetails")
                reply.events = [MobileLog(.init(level: .info, message: "测试日志 interop-sensitive"),
                                         sensitiveValues: ["interop-sensitive"])]
            default: throw MobileAccessError("Unsupported test operation")
            }
            reply.snapshot = snapshot
            server.send(reply, to: socket)
        } catch {
            let type = clients[socket].map(authorization.isAuthorized) == true ? "rejected" : "unauthorized"
            server.send(MobileReply(id: request.id, type: type, message: error.localizedDescription), to: socket)
        }
    }
}
