import Foundation
import XCTest
@testable import AutoMAAKit

func inspectionCallbacks(_ observation: FightStageInspection) -> String {
    let task: String
    let text: String
    switch observation {
    case let .regular(stage): task = "AutoMAAInspectStage"; text = stage
    case .annihilation: task = "AutoMAAInspectAnnihilation"; text = ""
    case .unknown: task = "AutoMAAInspectUnknown"; text = ""
    case .unavailable: task = "AutoMAAInspectUnavailable"; text = ""
    }
    let event: [String: Any] = ["taskchain": "Custom", "subtask": "ProcessTask",
                              "details": ["task": task, "action": "DoNothing", "result": ["text": text]]]
    let data = try! JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
    return "Assistant::append_callback | SubTaskCompleted " + String(decoding: data, as: UTF8.self)
        + "\nAssistant::append_callback | TaskChainCompleted {\"taskchain\":\"Custom\"}\n"
}

func writeInspectionFixture(_ observation: FightStageInspection, environment: [String: String]) throws {
    let root = URL(filePath: try XCTUnwrap(environment["MAA_STATE_DIR"])).appending(path: "debug")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try inspectionCallbacks(observation).write(to: root.appending(path: "asst.log"), atomically: true, encoding: .utf8)
}

final class FightStageInspectionTests: XCTestCase {
    let success = CommandResult(exitCode: 0, standardOutput: "", standardError: "", timedOut: false)

    func testOnlyCompletedNonConsumingObservationsResolveAStage() {
        for observation in [FightStageInspection.regular("PA-8"), .annihilation, .unknown, .unavailable] {
            let callbacks = inspectionCallbacks(observation)
            XCTAssertEqual(FightStageInspection.read(callbacks, command: success), observation)
            XCTAssertNil(FightStageInspection.read(callbacks.replacingOccurrences(of: "TaskChainCompleted", with: "TaskChainStopped"), command: success))
            XCTAssertNil(FightStageInspection.read(callbacks.replacingOccurrences(of: "DoNothing", with: "ClickSelf"), command: success))
            XCTAssertNil(FightStageInspection.read(callbacks, command: .init(exitCode: 0, standardOutput: "", standardError: "", timedOut: true)))
        }
        XCTAssertEqual(FightStageInspection.read(inspectionCallbacks(.regular("カズデル")), command: success), .unknown)
        XCTAssertNil(FightStageInspection.read("", command: success))
        XCTAssertNil(FightStageInspection.read(inspectionCallbacks(.regular("PA-8")).replacingOccurrences(of: "Custom", with: "Fight"), command: success))
    }

    func testProbeGraphCannotStartBattleEnableDelegationOrSpendSanity() throws {
        let graph = try XCTUnwrap(FightStageInspection.resourceTasks as? [String: [String: Any]])
        let permittedBases = Set(["Fight", "GoLastBattle", "StartButton1", "UsePrts-Annihilation", "UsePrts-AnnihilationSuccess", "ClickedCorrectStage"])
        XCTAssertEqual(graph["AutoMAAInspectHome"]?["template"] as? String, "SwitchTheme@ToggleSettingsMenu.png")
        XCTAssertEqual(graph["AutoMAAInspectAnnihilation"]?["template"] as? String, "UsePrts-Annihilation.png")
        XCTAssertEqual(graph["AutoMAAInspectAnnihilationActive"]?["template"] as? String, "UsePrts-AnnihilationSuccess.png")
        for (name, node) in graph {
            XCTAssertTrue(name.hasPrefix("AutoMAAInspect"))
            if let base = node["baseTask"] as? String {
                XCTAssertTrue(permittedBases.contains(base))
                XCTAssertEqual(node["action"] as? String, name == "AutoMAAInspectLast" ? "ClickSelf" : "DoNothing")
                for edge in ["onErrorNext", "reduceOtherTimes"] { XCTAssertEqual(node[edge] as? [String], []) }
                XCTAssertEqual(node["exceededNext"] as? [String], name == "AutoMAAInspectLast" ? ["AutoMAAInspectUnavailable"] : [])
                XCTAssertEqual(node["sub"] as? [String], name == "AutoMAAInspectHome" ? ["Terminal-Entry"] : [])
            }
            for next in node["next"] as? [String] ?? [] { XCTAssertNotNil(graph[next]) }
        }
    }

    func testProbeOwnsOnlyItsTemporaryProfileResourceAndCustomTask() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let client = ClientConfiguration(name: "测试", kind: .yoStarJP, appPath: "/nonexistent/test.app",
                                         address: "127.0.0.1:65492", profileName: "unused", bundleIdentifier: "dev.automaa.tests.probe", accounts: [])
        try FightStageInspection.prepare(at: root, client: client)
        let data = try Data(contentsOf: root.appending(path: "tasks/\(FightStageInspection.taskName).json"))
        let task = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tasks = try XCTUnwrap(task["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0]["type"] as? String, "Custom")
        XCTAssertEqual(task["client_type"] as? String, client.kind.maaClientType)
    }
}
