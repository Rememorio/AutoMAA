import Foundation
import Testing
@testable import AutoMAAKit

@Suite("Native client process identity")
struct NativeClientRuntimeTests {
    @Test("a temporary native app is identified by PID and launch time and cannot be adopted twice")
    @MainActor
    func isolatedApplication() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "automaa-native-client-tests-\(UUID())")
        let app = root.appending(path: "Fixture.app")
        let macOS = app.appending(path: "Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let identifier = "dev.automaa.tests.native.\(UUID().uuidString.lowercased())"
        let source = root.appending(path: "main.m")
        try """
        #import <AppKit/AppKit.h>
        int main(void) {
            [NSApplication sharedApplication];
            [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
            [NSApp run];
            return 0;
        }
        """.write(to: source, atomically: true, encoding: .utf8)
        let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "Fixture",
                                   "CFBundleName": "AutoMAA Test Fixture", "CFBundlePackageType": "APPL",
                                   "LSBackgroundOnly": true]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appending(path: "Contents/Info.plist"), options: .atomic)
        let commands = CommandRunner()
        let build = try await commands.run(executable: "/usr/bin/xcrun",
            arguments: ["clang", "-framework", "AppKit", source.path, "-o", macOS.appending(path: "Fixture").path], timeout: 30)
        try #require(build.exitCode == 0 && !build.timedOut, "\(build.standardError)")
        let client = ClientConfiguration(name: "隔离进程测试", kind: .official, appPath: app.path,
            address: "127.0.0.1:61486", profileName: "native-test", bundleIdentifier: identifier,
            accounts: [AccountConfiguration(name: "测试账号")])
        let controller = GameProcessController()
        let instance = try await controller.launch(client)
        defer { _ = controller.terminate(client, instance: instance, force: true) }
        #expect(instance.pid > 0)
        #expect(instance.launchedAt != nil)
        #expect(controller.instances(for: client) == [instance])
        do {
            _ = try await controller.launch(client)
            Issue.record("An existing instance was adopted")
        } catch RuntimeError.clientAlreadyRunning {} catch { Issue.record("Unexpected error: \(error)") }
        let stale = GameProcessIdentity(pid: instance.pid, launchedAt: Date(timeIntervalSince1970: 1))
        _ = controller.terminate(client, instance: stale, force: true)
        #expect(controller.instances(for: client) == [instance])
        #expect(controller.terminate(client, instance: instance, force: true))
        for _ in 0..<100 {
            if controller.instances(for: client).isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.instances(for: client).isEmpty)
    }
}
