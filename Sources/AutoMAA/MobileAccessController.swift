import AppKit
import AutoMAAKit
import Foundation

@MainActor
final class MobileAccessController: ObservableObject {
    struct Approval: Identifiable {
        let id: UUID
        let request: MobileRequest
        var name: String { request.deviceName ?? "手机" }
    }
    @Published private(set) var enabled = false
    @Published private(set) var connecting = false
    @Published private(set) var endpoint: String?
    @Published private(set) var error: String?
    @Published private(set) var devices: [MobileDevice] = []
    @Published private(set) var pairing: MobilePairingCode?
    @Published private(set) var approval: Approval?
    private weak var model: AppModel?
    private var authorization: MobileAccessAuthorization?
    private let server = MobileWebSocketServer()
    private var service: MobileTailscaleService?
    private var task: Task<Void, Never>?
    private var cleanup: Task<Void, Never>?
    private var generation = UUID()
    private var clients: [UUID: UUID] = [:]
    private var connectedAt: [UUID: Date] = [:]
    private var requests: [UUID: (Date, Int)] = [:]
    var hostName: String { String((Host.current().localizedName ?? "AutoMAA Mac").prefix(80)) }

    init(model: AppModel) {
        self.model = model
        do {
            let access = try MobileAccessAuthorization(store: MobileAccessStore(directories: model.directories))
            authorization = access
            enabled = access.configuration.enabled
            devices = access.configuration.devices
        } catch { self.error = "手机授权配置无法读取或保存，请检查数据目录权限。" }
        server.onConnect = { [weak self] id in self?.connectedAt[id] = Date() }
        server.onDisconnect = { [weak self] id in
            self?.clients[id] = nil
            self?.connectedAt[id] = nil
            self?.requests[id] = nil
            if self?.approval?.id == id { self?.approval = nil }
        }
        server.onMessage = { [weak self] id, data in self?.receive(id, data) }
        server.onFailure = { [weak self] in
            self?.stop()
            self?.error = "手机连接服务已停止，请重试连接。"
        }
    }

    func restore() { if enabled { start() } }
    func setEnabled(_ value: Bool) {
        guard let authorization else { return }
        do {
            try authorization.setEnabled(value)
            enabled = value
            if value { start() } else { stop(); error = nil }
        } catch { self.error = "授权设置未保存，请检查数据目录权限后重试。" }
    }
    func start() {
        guard enabled, authorization != nil else { return }
        stop()
        error = nil
        connecting = true
        let attempt = generation
        let service = MobileTailscaleService()
        self.service = service
        task = Task { [weak self] in
            guard let self else { return }
            do {
                await self.cleanup?.value
                try Task.checkCancellation()
                let port = try await self.server.start()
                let address = try await service.start(localPort: port)
                try Task.checkCancellation()
                guard self.generation == attempt else { return }
                self.endpoint = address
                self.connecting = false
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(2))
                    guard self.generation == attempt else { return }
                    guard service.isRunning else { throw MobileAccessError("Tailscale 连接服务已退出，请重试连接。") }
                    self.tick()
                }
            } catch {
                guard self.generation == attempt else { return }
                self.stop()
                if !(error is CancellationError) { self.error = error.localizedDescription }
            }
        }
    }
    func stop() {
        generation = UUID()
        task?.cancel()
        task = nil
        let previous = cleanup
        let current = service?.stop()
        cleanup = Task { await previous?.value; await current?.value }
        service = nil
        server.stop()
        cancelPairing()
        endpoint = nil
        connecting = false
    }
    func shutdown() async {
        let pending = task
        stop()
        await pending?.value
        await cleanup?.value
    }
    func beginPairing() {
        guard let authorization, let endpoint else { return }
        cancelPairing()
        do { pairing = try authorization.beginPairing(hostName: hostName, endpoint: endpoint); error = nil }
        catch { self.error = error.localizedDescription }
    }
    func cancelPairing() {
        if let approval { server.disconnect(approval.id) }
        approval = nil
        pairing = nil
        authorization?.cancelPairing()
    }
    func approve() {
        guard let authorization, let approval else { return }
        do {
            let (device, secret) = try authorization.approvePairing(secret: approval.request.secret ?? "", name: approval.name)
            var reply = MobileReply(id: approval.request.id, type: "paired")
            reply.deviceID = device.id
            reply.secret = secret
            reply.snapshot = snapshot()
            clients[approval.id] = device.id
            server.send(reply, to: approval.id)
            devices = authorization.configuration.devices
            self.approval = nil
            pairing = nil
        } catch { self.error = error.localizedDescription; cancelPairing() }
    }
    func revoke(_ device: MobileDevice) {
        do {
            try authorization?.revoke(device.id)
            for (socket, id) in clients where id == device.id { server.disconnect(socket) }
            devices = authorization?.configuration.devices ?? []
        } catch { self.error = "撤销授权未保存，请检查数据目录权限后重试。" }
    }
    private func tick() {
        if let pairing, pairing.expiresAt <= Date() { cancelPairing() }
        for (id, date) in connectedAt where clients[id] == nil && approval?.id != id && Date().timeIntervalSince(date) > 30 {
            server.disconnect(id)
        }
        guard !clients.isEmpty else { return }
        model?.reloadActivityHistory()
        var reply = MobileReply(type: "snapshot")
        reply.snapshot = snapshot()
        for (socket, id) in clients {
            if authorization?.isAuthorized(id) == true { server.send(reply, to: socket) }
            else { server.disconnect(socket) }
        }
    }
    private func snapshot() -> MobileSnapshot? {
        guard let authorization else { return nil }
        return model?.mobileSnapshot(hostID: authorization.configuration.hostID, sessionID: authorization.sessionID, hostName: hostName)
    }
    private func receive(_ socket: UUID, _ data: Data) {
        guard let authorization, let model else { server.disconnect(socket); return }
        let now = Date()
        let recent = requests[socket] ?? (now, 0)
        let count = now.timeIntervalSince(recent.0) < 1 ? recent.1 + 1 : 1
        requests[socket] = (count == 1 ? now : recent.0, count)
        guard count <= 10, data.count <= MobileProtocol.maximumRequestBytes,
              let request = try? MobileProtocol.decode(MobileRequest.self, from: data),
              request.version == MobileProtocol.version else { server.disconnect(socket); return }
        do {
            if request.operation == .pair {
                guard clients[socket] == nil, approval == nil, let name = request.deviceName,
                      !name.isEmpty, name.count <= 60,
                      !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw MobileAccessError("配对请求无效或已有手机等待确认")
                }
                try authorization.validatePairing(secret: request.secret ?? "")
                approval = Approval(id: socket, request: request)
                server.send(MobileReply(id: request.id, type: "approval", message: "请在 Mac 上确认授权"), to: socket)
                return
            }
            if request.operation == .authenticate {
                guard let id = request.deviceID else { throw MobileAccessError("请重新配对") }
                _ = try authorization.authenticate(deviceID: id, secret: request.secret ?? "")
                clients[socket] = id
                model.reloadActivityHistory()
                var reply = MobileReply(id: request.id, type: "authenticated")
                reply.snapshot = snapshot()
                server.send(reply, to: socket)
                return
            }
            guard let id = clients[socket], authorization.isAuthorized(id) else { throw MobileAccessError("设备未授权，请重新配对") }
            model.reloadActivityHistory()
            var reply: MobileReply
            switch request.operation {
            case .snapshot:
                reply = MobileReply(id: request.id, type: "snapshot")
                reply.snapshot = snapshot()
            case .history, .historyDetails:
                reply = try model.mobileHistory(request)
            case .run, .stop:
                reply = try authorization.perform(request, deviceID: id) { try model.performMobileCommand(request) }
                reply.snapshot = snapshot()
            case .receipt:
                guard request.sessionID == authorization.sessionID, let command = request.commandID,
                      let receipt = authorization.receipt(command, deviceID: id) else {
                    throw MobileAccessError("未找到操作回执。请检查当前状态和活动记录，不要重复启动。")
                }
                reply = receipt
                reply.type = "receipt"
                reply.outcome = receipt.type
                reply.id = request.id
                reply.snapshot = snapshot()
            default: throw MobileAccessError("不支持此操作")
            }
            reply.message = reply.message.map(model.mobileRedact)
            server.send(reply, to: socket)
        } catch {
            server.send(MobileReply(id: request.id, type: clients[socket] == nil ? "unauthorized" : "rejected",
                                   message: model.mobileRedact(error.localizedDescription)), to: socket)
        }
    }
}
