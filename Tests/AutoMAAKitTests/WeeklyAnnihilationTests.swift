import Foundation
import XCTest
@testable import AutoMAAKit

final class WeeklyAnnihilationTests: XCTestCase {
    func testReviewedWeeklyConfirmationRequiresTheSameAttemptAndRound() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "weekly-review-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root), store = WeeklyAnnihilationStore(directories: directories)
        let execution = ExecutionStateStore(directories: directories)
        var client = client(.yoStarJP)
        let account = AccountConfiguration(name: "账号")
        client.accounts = [account]
        var plan = AutomationPlan.lightRoutine
        plan.fight.weeklyAnnihilation.enabled = true
        let configuration = AppConfiguration(cliPath: "/usr/bin/true", clients: [client], plans: [plan])
        let firstTime = date("2026-09-09T00:00:00Z"), secondTime = firstTime.addingTimeInterval(60)
        let weekStart = GameWeek(client: client.kind, at: firstTime).start
        let result = FightResult(status: .unnecessary, reason: .navigationUnavailable)
        var weekly = WeeklyAnnihilationState(), daily = ExecutionState()
        func review() throws -> FightRecoveryItem {
            let progress = try PlanContinuation(configuration: configuration, planID: plan.id,
                state: execution.loadForExecution(), history: [], weeklyAnnihilation: store.load(), now: secondTime)
            return try XCTUnwrap(progress.fightRecoveryItems.first)
        }
        weekly.record(result, client: client, accountID: account.id, weekStart: weekStart, at: firstTime)
        try store.save(weekly)
        let first = try review()
        weekly.record(result, client: client, accountID: account.id, weekStart: weekStart, at: secondTime)
        try store.save(weekly)
        let second = try review()
        XCTAssertNotEqual(first, second)
        XCTAssertThrowsError(try store.confirmComplete(first, client: client, at: secondTime))

        daily.startRound(for: plan.id, at: secondTime)
        try execution.save(daily)
        XCTAssertThrowsError(try store.confirmComplete(second, client: client, at: secondTime))
        XCTAssertEqual(try store.load(), weekly)
        let confirmed = try store.confirmComplete(review(), client: client, at: secondTime)
        XCTAssertEqual(confirmed.status(for: policy, client: client, accountID: account.id, at: secondTime), .completed)
    }

    func testClosedEntranceResetsNextWeekAndConfirmationRespectsTheRunnerLock() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "weekly-confirm-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root)
        let store = WeeklyAnnihilationStore(directories: directories)
        let client = client(.yoStarJP), account = UUID(), now = date("2026-09-09T00:00:00Z")
        var weekly = WeeklyAnnihilationState()
        weekly.record(.init(status: .unnecessary, reason: .navigationUnavailable), client: client, accountID: account,
                      weekStart: GameWeek(client: client.kind, at: now).start, at: now)
        try store.save(weekly)
        XCTAssertEqual(weekly.status(for: policy, client: client, accountID: account, at: now.addingTimeInterval(7 * 86400)), .pending)
        XCTAssertFalse(weekly.canConfirmComplete(client: client, accountID: account, at: now.addingTimeInterval(7 * 86400)))
        let lock = try ProcessLock(url: directories.lock)
        try withExtendedLifetime(lock) {
            XCTAssertThrowsError(try store.confirmComplete(client: client, accountID: account, at: now))
            XCTAssertEqual(try store.load(), weekly)
        }
    }

    func testConfirmationSavesOnlyCurrentWeeklyStateAndRejectsStaleRepeatedActions() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "weekly-confirm-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directories = AppDirectories(root: root), client = client(.yoStarJP)
        let store = WeeklyAnnihilationStore(directories: directories)
        let account = UUID(), now = date("2026-09-09T00:00:00Z")
        var weekly = WeeklyAnnihilationState()
        weekly.record(.init(status: .unnecessary, reason: .navigationUnavailable), client: client, accountID: account,
                      weekStart: GameWeek(client: client.kind, at: now).start, at: now)
        try store.save(weekly)
        let daily = Data("unchanged".utf8)
        try daily.write(to: directories.executionState)
        let confirmed = try store.confirmComplete(client: client, accountID: account, at: now)
        XCTAssertEqual(confirmed.status(for: policy, client: client, accountID: account, at: now), .completed)
        XCTAssertEqual(try Data(contentsOf: directories.executionState), daily)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directories.fightStageMemory.path))
        XCTAssertThrowsError(try store.confirmComplete(client: client, accountID: account, at: now))
        try store.save(weekly)
        XCTAssertThrowsError(try store.confirmComplete(client: client, accountID: account, at: now.addingTimeInterval(7 * 86400)))
        XCTAssertEqual(try store.load(), weekly)
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func client(_ kind: ClientKind) -> ClientConfiguration {
        .init(name: "Client", kind: kind, appPath: "/test/Game.app", address: "127.0.0.1:65491", profileName: "weekly-test", bundleIdentifier: "dev.automaa.tests.weekly", accounts: [])
    }
    private let policy = WeeklyAnnihilationConfiguration(enabled: true)

    func testEveryServerUsesItsGameWeekBoundaryWithoutSystemTimezone() {
        for kind in ClientKind.allCases {
            let timestamp = switch kind {
            case .official, .bilibili, .txwy: "2026-09-06T20:00:00Z"
            case .yoStarJP, .yoStarKR: "2026-09-06T19:00:00Z"
            case .yoStarEN: "2026-09-07T11:00:00Z"
            }
            let boundary = date(timestamp)
            XCTAssertEqual(GameWeek(client: kind, at: boundary).start, boundary)
            XCTAssertEqual(GameWeek(client: kind, at: boundary.addingTimeInterval(-1)).start, boundary.addingTimeInterval(-7 * 86400))
            XCTAssertEqual(GameWeek(client: kind, at: boundary).weekday, .monday)
            XCTAssertEqual(GameWeek(client: kind, at: boundary.addingTimeInterval(-1)).weekday, .sunday)
        }
    }

    func testStartDayIncludesTheRemainderOfTheSameGameWeek() {
        let monday = date("2026-09-06T20:00:00Z")
        for day in 0..<7 {
            let week = GameWeek(client: .official, at: monday.addingTimeInterval(Double(day * 86400)))
            for start in 0..<7 { XCTAssertEqual(week.hasReached(ScheduleWeekday.allCases[start]), day >= start) }
        }
    }

    func testCompletionRequiresPositiveWeeklyLimitEvidence() {
        let client = client(.yoStarJP)
        let account = UUID(), now = date("2026-09-09T00:00:00Z")
        for result in [FightResult(status: .completed, times: 1), .init(status: .completed, times: 4, reason: .insufficientSanity),
                       .init(status: .unnecessary, reason: .insufficientSanity), .init(status: .failed, reason: .commandFailed)] {
            var state = WeeklyAnnihilationState()
            state.record(result, client: client, accountID: account, weekStart: GameWeek(client: client.kind, at: now).start, at: now)
            XCTAssertEqual(state.status(for: policy, client: client, accountID: account, at: now), .pending)
        }
        for reason in [FightStopReason.weeklyLimit, .confirmedWeeklyLimit] {
            var state = WeeklyAnnihilationState()
            state.record(.init(status: .unnecessary, reason: reason), client: client, accountID: account,
                         weekStart: GameWeek(client: client.kind, at: now).start, at: now)
            XCTAssertEqual(state.status(for: policy, client: client, accountID: account, at: now), .completed)
            XCTAssertEqual(state.status(for: policy, client: client, accountID: account, at: now.addingTimeInterval(7 * 86400)), .pending)
            XCTAssertEqual(state.status(for: policy, client: client, accountID: UUID(), at: now), .pending)
            var changedServer = client
            changedServer.kind = .official
            XCTAssertEqual(state.status(for: policy, client: changedServer, accountID: account, at: now), .pending)
        }
    }

    func testUnconfirmedAttemptSurvivesWeekRolloverAndCannotConfirmTheNewWeek() {
        let client = client(.official)
        let account = UUID(), now = date("2026-09-13T19:59:59Z")
        var state = WeeklyAnnihilationState()
        state.record(.init(status: .unconfirmed, reason: .navigationUnavailable), client: client, accountID: account,
                     weekStart: GameWeek(client: client.kind, at: now).start, at: now)
        XCTAssertTrue(state.canConfirmComplete(client: client, accountID: account, at: now))
        XCTAssertFalse(state.canConfirmComplete(client: client, accountID: account, at: now.addingTimeInterval(1)))
        XCTAssertEqual(state.status(for: policy, client: client, accountID: account, at: now.addingTimeInterval(1)), .unconfirmed)
        XCTAssertEqual(state.status(for: .init(), client: client, accountID: account, at: now), .disabled)
    }

    func testWeeklyConfigurationHasOneRequiredShapeAndPreservesDisabledChoice() throws {
        var fight = FightConfiguration()
        XCTAssertFalse(fight.weeklyAnnihilation.enabled)
        XCTAssertEqual(fight.weeklyAnnihilation.startDay, .monday)
        fight.weeklyAnnihilation.startDay = .friday
        fight.usesCustomSettings = false
        let data = try JSONEncoder().encode(fight)
        XCTAssertEqual(try JSONDecoder().decode(FightConfiguration.self, from: data), fight)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("annihilationFirst"))
    }

    func testWeeklyStoreRoundTripsAndRejectsDuplicateEntries() throws {
        let directories = AppDirectories(root: FileManager.default.temporaryDirectory.appending(path: "weekly-tests-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: directories.root) }
        let store = WeeklyAnnihilationStore(directories: directories)
        XCTAssertEqual(try store.load(), .init())
        var state = WeeklyAnnihilationState()
        let client = client(.yoStarJP), now = date("2026-09-09T00:00:00Z")
        state.record(.init(status: .unnecessary, reason: .insufficientSanity), client: client, accountID: UUID(),
                     weekStart: GameWeek(client: client.kind, at: now).start, at: now)
        try store.save(state)
        XCTAssertEqual(try store.load(), state)
        let original = try Data(contentsOf: directories.weeklyAnnihilation)
        state.entries += state.entries
        XCTAssertThrowsError(try store.save(state))
        XCTAssertEqual(try Data(contentsOf: directories.weeklyAnnihilation), original)
        try Data("broken".utf8).write(to: directories.weeklyAnnihilation)
        XCTAssertThrowsError(try store.load())
    }

    func testSharedConfirmationPreservesASeparateUnconfirmedRegularTarget() {
        let account = AccountConfiguration(name: "Account")
        var client = client(.yoStarJP)
        client.accounts = [account]
        var plan = AutomationPlan.lightRoutine
        plan.fight.weeklyAnnihilation.enabled = true
        let step = WorkflowStep(planID: plan.id, clientID: client.id, accountID: account.id, task: .fight)
        let now = date("2026-09-09T00:00:00Z"), week = GameWeek(client: client.kind, at: date("2026-09-09T00:00:00Z"))
        var state = ExecutionState()
        var progress = FightProgress(regularStage: "CE-6")
        progress.regular = .init(status: .unconfirmed, stage: "CE-6", reason: .interruptedBattle)
        state.fightProgress = [step.key: progress]
        var weekly = WeeklyAnnihilationState()
        weekly.record(.init(status: .unconfirmed, reason: .navigationUnavailable), client: client, accountID: account.id,
                      weekStart: week.start, at: now)
        state.prepareWeeklyAnnihilation(plan: plan, clients: [client], weekly: weekly, at: now)
        XCTAssertEqual(state.fightProgress?[step.key]?.annihilation?.status, .unconfirmed)
        XCTAssertEqual(state.fightResults?[step.key]?.stage, "CE-6")
        weekly.record(.init(status: .unnecessary, reason: .confirmedWeeklyLimit), client: client, accountID: account.id,
                      weekStart: week.start, at: now)
        state.prepareWeeklyAnnihilation(plan: plan, clients: [client], weekly: weekly, at: now)
        XCTAssertTrue(state.needsFightConfirmation(step.key))
        XCTAssertEqual(state.fightProgress?[step.key]?.annihilation?.reason, .confirmedWeeklyLimit)
        XCTAssertEqual(state.fightProgress?[step.key]?.regularStage, "CE-6")
    }
}
