import Foundation
import XCTest
@testable import AutoMAAKit

final class FightStageMemoryTests: XCTestCase {
    static let mapNames = ["切尔诺伯格", "切爾諾伯格", "Chernobog", "Lungmen Outskirts", "チェルノボーグ", "カズデル", "체르노보그"]

    func testMapNamesAndInvalidOCRCannotBecomeRecoveryStages() {
        for stage in Self.mapNames + ["_INVALID_", "", "../1-7", "1-7@Fight", "not-a-stage", "1--7"] {
            XCTAssertNil(FightStagePolicy.regularStage(from: stage, times: 1), stage)
        }
        for stage in ["1-7", "SR-6", "PR-A-1", "OF-F3", "JT8-3", "H10-1-Hard", "R8-11"] {
            XCTAssertEqual(FightStagePolicy.regularStage(from: stage, times: 1), stage)
        }
    }

    func testLoadingInvalidStageKeepsOtherAccountsAndRequiresRecoveryWithoutRewritingFile() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let clientID = UUID(), accountID = UUID(), otherAccountID = UUID()
        let memory = FightStageMemory(entries: [
            .init(clientID: clientID, accountID: accountID, stage: "カズデル", updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
            .init(clientID: clientID, accountID: otherAccountID, stage: "1-7", updatedAt: Date(timeIntervalSince1970: 1_700_000_000)),
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(memory)
        try original.write(to: directories.fightStageMemory)
        let loaded = try FightStageMemoryStore(directories: directories).load()
        XCTAssertNil(loaded.stage(clientID: clientID, accountID: accountID))
        XCTAssertTrue(loaded.requiresRecovery(clientID: clientID, accountID: accountID))
        XCTAssertEqual(loaded.stage(clientID: clientID, accountID: otherAccountID), "1-7")
        XCTAssertEqual(try Data(contentsOf: directories.fightStageMemory), original)
        let store = FightStageMemoryStore(directories: directories)
        try store.save(loaded)
        XCTAssertEqual(try store.load(), loaded)
        try store.save(loaded)
        let backups = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("fight-stage-memory.backup-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
    }

    func testOnlyConfirmedRegularCompletionCanReplaceMemoryAndClearRecovery() {
        let clientID = UUID(), accountID = UUID()
        let original = FightStageMemory(entries: [.init(clientID: clientID, accountID: accountID, stage: "1-7", recoveryRequiredAt: Date())])
        let rejected = [
            FightResult(status: .completed, stage: "CE-6", times: 1),
            FightResult(status: .completed, times: 1, kind: .regular),
            FightResult(status: .completed, stage: "_INVALID_", times: 1, kind: .regular),
            FightResult(status: .completed, stage: "CE-6", times: 0, kind: .regular),
            FightResult(status: .unnecessary, stage: "CE-6", kind: .regular),
            FightResult(status: .unconfirmed, stage: "CE-6", times: 1, kind: .regular),
            FightResult(status: .failed, stage: "CE-6", times: 1, kind: .regular),
        ]
        for result in rejected {
            var memory = original
            XCTAssertFalse(memory.recordSuccessfulFight(result, clientID: clientID, accountID: accountID))
            XCTAssertEqual(memory, original)
        }
        var memory = original
        XCTAssertTrue(memory.recordSuccessfulFight(.init(status: .completed, stage: "CE-6", times: 1, kind: .regular), clientID: clientID, accountID: accountID))
        XCTAssertEqual(memory.stage(clientID: clientID, accountID: accountID), "CE-6")
        XCTAssertFalse(memory.requiresRecovery(clientID: clientID, accountID: accountID))
    }

    func testInvalidInMemoryTargetCannotBypassReadinessAndDuplicateStorageIsNotRepaired() throws {
        let clientID = UUID(), accountID = UUID()
        let invalid = FightStageMemoryEntry(clientID: clientID, accountID: accountID, stage: "カズデル")
        let memory = FightStageMemory(entries: [invalid])
        XCTAssertNil(memory.stage(clientID: clientID, accountID: accountID))
        XCTAssertTrue(memory.requiresRecovery(clientID: clientID, accountID: accountID))
        var config = FightConfiguration()
        config.stageStrategy = .rememberedRegular
        XCTAssertEqual(FightStagePolicy.resolve(config, memory: memory, clientID: clientID, accountID: accountID), .unavailable)
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        try directories.prepare()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(FightStageMemory(entries: [invalid, invalid]))
        try data.write(to: directories.fightStageMemory)
        XCTAssertThrowsError(try FightStageMemoryStore(directories: directories).load())
        XCTAssertEqual(try Data(contentsOf: directories.fightStageMemory), data)
    }
}
