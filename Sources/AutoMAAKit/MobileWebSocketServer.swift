import Foundation
import Network

@MainActor
public final class MobileWebSocketServer {
    public var onConnect: (UUID) -> Void = { _ in }
    public var onMessage: (UUID, Data) -> Void = { _, _ in }
    public var onDisconnect: (UUID) -> Void = { _ in }
    public var onFailure: () -> Void = {}
    private var listener: NWListener?
    private var connections: [UUID: NWConnection] = [:]
    private var pendingSends: [UUID: Int] = [:]
    private var startup: CheckedContinuation<UInt16, Error>?

    public init() {}
    public func start() async throws -> UInt16 {
        stop()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        options.maximumMessageSize = MobileProtocol.maximumRequestBytes
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self, weak listener] connection in
            Task { @MainActor in
                guard let self, self.listener === listener else { connection.cancel(); return }
                self.accept(connection)
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startup = continuation
                listener.stateUpdateHandler = { [weak self, weak listener] state in
                    Task { @MainActor in
                        guard let self, self.listener === listener else { return }
                        switch state {
                        case .ready:
                            if let port = listener?.port?.rawValue { self.startup?.resume(returning: port); self.startup = nil }
                        case .failed:
                            self.stop()
                            self.onFailure()
                        default: break
                        }
                    }
                }
                listener.start(queue: .main)
                if Task.isCancelled { stop() }
            }
        } onCancel: {
            Task { @MainActor [weak self, weak listener] in
                guard let self, self.listener === listener else { return }
                self.stop()
            }
        }
    }
    public func stop() {
        startup?.resume(throwing: CancellationError())
        startup = nil
        listener?.cancel()
        listener = nil
        for id in Array(connections.keys) { disconnect(id) }
    }
    public func disconnect(_ id: UUID) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        pendingSends[id] = nil
        connection.cancel()
        onDisconnect(id)
    }
    public func send(_ reply: MobileReply, to id: UUID) {
        guard let connection = connections[id] else { return }
        let pending = pendingSends[id, default: 0]
        if reply.type == "snapshot", reply.id == nil, pending > 0 { return }
        guard pending < 8, let data = try? MobileProtocol.encode(reply), data.count <= 1_048_576 else {
            disconnect(id); return
        }
        pendingSends[id] = pending + 1
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "mobile", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true,
                        completion: .contentProcessed { [weak self] error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                self.pendingSends[id, default: 1] -= 1
                if error != nil { self.disconnect(id) }
            }
        })
    }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 12 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .failed = state { self?.disconnect(id) }
                if case .cancelled = state { self?.disconnect(id) }
            }
        }
        connection.start(queue: .main)
        onConnect(id)
        receive(id, connection)
    }
    private func receive(_ id: UUID, _ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                guard error == nil, metadata?.opcode != .close else { self.disconnect(id); return }
                if let data, !data.isEmpty {
                    guard data.count <= MobileProtocol.maximumRequestBytes, metadata?.opcode == .text else {
                        self.disconnect(id); return
                    }
                    self.onMessage(id, data)
                }
                self.receive(id, connection)
            }
        }
    }
}
