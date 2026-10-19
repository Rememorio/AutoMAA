import Foundation
import Darwin
import Testing
@testable import AutoMAAKit

@Suite("Port ownership inspection")
struct PortOwnershipProbeTests {
    private let address = "127.0.0.1:61488"

    @Test("local listeners include wildcard binds for both IP families", arguments: ["127.0.0.1", "0.0.0.0", "::1", "::"])
    func localListener(host: String) async throws {
        let ipv6 = host.contains(":")
        let descriptor = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
        defer { Darwin.close(descriptor) }
        var port: UInt16?
        for candidate in UInt16(61500)..<61600 {
            let bound: Int32
            if ipv6 {
                var address = sockaddr_in6()
                address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
                address.sin6_family = sa_family_t(AF_INET6)
                address.sin6_port = candidate.bigEndian
                try #require(inet_pton(AF_INET6, host, &address.sin6_addr) == 1)
                bound = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
                }
            } else {
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = candidate.bigEndian
                try #require(inet_pton(AF_INET, host, &address.sin_addr) == 1)
                bound = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
            }
            if bound == 0 { port = candidate; break }
        }
        let selected = try #require(port)
        try #require(listen(descriptor, 8) == 0)
        let destination = ipv6 ? "[::1]:\(selected)" : "127.0.0.1:\(selected)"
        #expect(try await PortProbe().inspect(destination) == .listening([getpid()]))
    }

    @Test("nonlocal destinations cannot inherit a local listener's ownership")
    func remoteAddress() async throws {
        do {
            _ = try await PortProbe(commandRunner: ProbeCommands([])).inspect("192.0.2.1:61488")
            Issue.record("A remote address was accepted as locally owned")
        } catch RuntimeError.portProbeFailed {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test("a refused connection is closed, while timeouts and detection errors are never free ports")
    func closedOrUnknown() async throws {
        let refused = reply(1, error: "nc: connectx failed: Connection refused\n")
        #expect(try await PortProbe(commandRunner: ProbeCommands([refused])).inspect(address) == .closed)
        for result in [reply(1, error: "Operation timed out"), reply(1), reply(127),
                       reply(1, error: "IPv6: Connection refused\nIPv4: Operation timed out"),
                       CommandResult(exitCode: 15, standardOutput: "", standardError: "Connection refused", timedOut: true)] {
            do {
                _ = try await PortProbe(commandRunner: ProbeCommands([result])).inspect(address)
                Issue.record("An indeterminate inspection was accepted")
            } catch RuntimeError.portProbeFailed {} catch { Issue.record("Unexpected error: \(error)") }
        }
    }

    @Test("listener ownership handles descriptor records and detects ambiguous owners")
    func owners() async throws {
        for (output, expected) in [("p61487\nf3\nf4\n", Set<Int32>([61487])),
                                   ("p61487\nf3\np61489\nf8\n", Set<Int32>([61487, 61489]))] {
            let probe = PortProbe(commandRunner: ProbeCommands([reply(0), reply(0, output: output)]))
            #expect(try await probe.inspect(address) == .listening(expected))
        }
        let unknown = PortProbe(commandRunner: ProbeCommands([reply(0), reply(1), reply(0)]))
        #expect(try await unknown.inspect(address) == .listening([]))
        for response in [reply(0, output: "malformed"), reply(0, output: "p0"), reply(1, error: "permission denied")] {
            do {
                _ = try await PortProbe(commandRunner: ProbeCommands([reply(0), response])).inspect(address)
                Issue.record("An invalid owner inspection was accepted")
            } catch RuntimeError.portProbeFailed {} catch { Issue.record("Unexpected error: \(error)") }
        }
    }

    @Test("a listener closing between reachability and ownership checks is confirmed closed", arguments: [Int32(0), 1])
    func closesDuringInspection(ownerExit: Int32) async throws {
        let commands = ProbeCommands([reply(0), reply(ownerExit), reply(1, error: "nc: Connection refused")])
        #expect(try await PortProbe(commandRunner: commands).inspect(address) == .closed)
        #expect(await commands.executables == ["/usr/bin/nc", "/usr/sbin/lsof", "/usr/bin/nc"])
    }

    @Test("a real local socket closing before lsof is reported as released")
    func realListenerExit() async throws {
        let commands = try ClosingPortCommands()
        let address = "127.0.0.1:\(commands.port)"
        #expect(try await PortProbe(commandRunner: commands).inspect(address) == .closed)
        #expect(try await PortProbe().inspect(address) == .closed)
    }

    @Test("an empty owner result never hides an inconclusive or cancelled confirmation", arguments: [false, true])
    func missingOwnerConfirmation(observeCancellation: Bool) async throws {
        for response in [reply(1, error: "Operation timed out"), reply(1), reply(127),
                         CommandResult(exitCode: 15, standardOutput: "", standardError: "", timedOut: true)] {
            let commands = ProbeCommands([reply(0), reply(1), response])
            do {
                _ = try await PortProbe(commandRunner: commands).inspect(address, observeCancellation: observeCancellation)
                Issue.record("An inconclusive confirmation was accepted")
            } catch RuntimeError.portProbeFailed {} catch { Issue.record("Unexpected error: \(error)") }
            #expect(await commands.cancellationModes == Array(repeating: observeCancellation, count: 3))
        }
        let cancelled = CommandResult(exitCode: 15, standardOutput: "", standardError: "", timedOut: false, cancelled: true)
        do {
            _ = try await PortProbe(commandRunner: ProbeCommands([reply(0), reply(1), cancelled]))
                .inspect(address, observeCancellation: observeCancellation)
            Issue.record("A cancelled confirmation was accepted")
        } catch RuntimeError.cancelled {} catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test("cancellation remains cancellation instead of being interpreted as a free port")
    func cancellation() async throws {
        let result = CommandResult(exitCode: 15, standardOutput: "", standardError: "", timedOut: false, cancelled: true)
        do {
            _ = try await PortProbe(commandRunner: ProbeCommands([result])).inspect(address)
            Issue.record("Cancellation was ignored")
        } catch RuntimeError.cancelled {} catch { Issue.record("Unexpected error: \(error)") }
    }

    private func reply(_ exit: Int32, output: String = "", error: String = "") -> CommandResult {
        .init(exitCode: exit, standardOutput: output, standardError: error, timedOut: false)
    }
}

private actor ProbeCommands: CommandRunning {
    var replies: [CommandResult]
    var executables: [String] = []
    var cancellationModes: [Bool] = []
    init(_ replies: [CommandResult]) { self.replies = replies }
    func run(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval,
             observeCancellation: Bool, startupScreenshotPolicy: StartupScreenshotPolicy?) async throws -> CommandResult {
        executables.append(executable)
        cancellationModes.append(observeCancellation)
        guard !replies.isEmpty else { throw RuntimeError.portProbeFailed("test") }
        return replies.removeFirst()
    }
}

private actor ClosingPortCommands: CommandRunning {
    let port: UInt16
    var descriptor: Int32?

    init() throws {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        try #require(socket >= 0)
        var selected: UInt16?
        for candidate in UInt16(61600)..<61700 {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = candidate.bigEndian
            inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
            let status = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            if status == 0 { selected = candidate; break }
        }
        do {
            port = try #require(selected)
            try #require(listen(socket, 8) == 0)
            descriptor = socket
        } catch {
            Darwin.close(socket)
            throw error
        }
    }

    deinit { if let descriptor { Darwin.close(descriptor) } }

    func run(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval,
             observeCancellation: Bool, startupScreenshotPolicy: StartupScreenshotPolicy?) async throws -> CommandResult {
        if executable == "/usr/sbin/lsof", let descriptor {
            Darwin.close(descriptor)
            self.descriptor = nil
        }
        return try await CommandRunner().run(executable: executable, arguments: arguments, environment: environment,
            timeout: timeout, observeCancellation: observeCancellation, startupScreenshotPolicy: startupScreenshotPolicy)
    }
}
