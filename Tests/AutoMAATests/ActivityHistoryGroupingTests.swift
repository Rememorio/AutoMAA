import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Activity history grouping")
struct ActivityHistoryGroupingTests {
    let plan = UUID(), round = UUID()
    let address = "127.0.0.1:65493"

    private func blocked(_ time: Int, error: RuntimeError? = nil, typed: Bool = false,
                         planID: UUID? = nil, roundID: UUID? = nil) -> ActivitySession {
        let error = error ?? .portOccupiedByClient(address: address, client: "测试客户端")
        let start = Date(timeIntervalSince1970: Double(time)), id = UUID()
        let entries = [
            LogEntry(timestamp: start, level: .info, message: "准备方案", runID: id, phase: .preparing,
                     planID: planID ?? plan, roundID: roundID ?? round),
            LogEntry(timestamp: start, level: .error, message: "运行前检查未通过，未接管或关闭游戏：" + error.localizedDescription,
                     runID: id, phase: .failed, startBlocker: typed ? WorkflowStartBlocker(error: error) : nil,
                     planID: planID ?? plan, roundID: roundID ?? round)
        ]
        return ActivitySession(id: id.uuidString, runID: id, entries: entries)
    }

    @Test("repeated blocks keep individual runs searchable and selectable")
    func foldRepeatedAttempts() {
        let older = blocked(100), latest = blocked(120, typed: true)
        let maintenance = ActivitySession(id: "update", runID: UUID(), entries: [
            .init(timestamp: .init(timeIntervalSince1970: 110), level: .info, message: "更新", phase: .updating)])
        let groups = ActivityHistoryGroup.groups([latest, maintenance, older])
        #expect(latest.outcome == .blocked)
        #expect(older.outcome == .blocked)
        #expect(ActivityFilter.failed.includes(older))
        #expect(groups.map { $0.sessions.map(\.id) } == [[latest.id, older.id]])
        #expect(groups.first?.matching { $0.runID == older.runID }?.latest.id == older.id)
        #expect(ActivityRecordPresentation.listSummary(latest, attempts: 2) == "客户端占用端口 · 2 次尝试")
    }

    @Test("distinct blockers, rounds, plans, days, and intervening game attempts remain separate")
    func foldBoundaries() {
        let base = blocked(100)
        for other in [blocked(401), blocked(101, error: .portOccupiedByClient(address: address, client: "另一客户端")),
                      blocked(101, error: .portOccupiedByClient(address: "127.0.0.1:65494", client: "测试客户端")),
                      blocked(101, error: .portOccupied(address)), blocked(101, error: .clientAlreadyRunning("测试客户端")),
                      blocked(101, roundID: UUID()), blocked(101, planID: UUID())] {
            #expect(ActivityHistoryGroup.groups([other, base]).count == 2)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        #expect(ActivityHistoryGroup.groups([blocked(86_400), blocked(86_399)], calendar: calendar).count == 2)
        let otherRun = ActivitySession(id: "other", runID: UUID(), entries: [
            .init(timestamp: .init(timeIntervalSince1970: 110), level: .success, message: "完成", phase: .completed, planID: plan)])
        let visible = ActivityHistoryGroup.groups([blocked(120), otherRun, base]).compactMap { $0.matching(ActivityFilter.failed.includes) }
        #expect(visible.count == 2)
    }

    @Test("legacy diagnostics require an identifiable attempt without gameplay")
    func legacyAndMaintenanceBoundaries() throws {
        let base = blocked(120)
        #expect(try JSONDecoder().decode([LogEntry].self, from: JSONEncoder().encode(base.entries)) == base.entries)
        #expect(blocked(120, error: .portProbeFailed(address)).startBlocker == nil)
        let progress = LogEntry(timestamp: .init(timeIntervalSince1970: 119), level: .info, message: "启动", phase: .launching)
        #expect(ActivitySession(id: "ran", runID: UUID(), entries: [progress] + base.entries).startBlocker == nil)
        #expect(ActivitySession(id: "legacy", runID: nil, entries: base.entries).startBlocker == nil)
        let unknown = ActivitySession(id: "unidentified", runID: UUID(), entries: [.init(level: .error, message: "无法确定方案", phase: .failed)])
        #expect(!unknown.isStandaloneMaintenance)
        let embedded = ActivitySession(id: "plan", runID: UUID(), entries: [.init(level: .info, message: "同步资源", phase: .updating, planID: plan)])
        #expect(!embedded.isStandaloneMaintenance)
    }

    @Test("account rows remove a leading account label and equivalent notices appear only once")
    func resultContext() {
        let account = UUID()
        let warning = LogEntry(level: .warning, message: "账号「示例」：需要检查", phase: .switchingAccount, accountID: account)
        var duplicate = warning
        duplicate.id = UUID()
        var other = warning
        other.id = UUID()
        other.accountID = UUID()
        #expect(warning.accountResultMessage == "需要检查")
        #expect(LogEntry(level: .info, message: warning.message).accountResultMessage == warning.message)
        let done = LogEntry(level: .success, message: "完成", accountID: account, task: .award)
        let otherDone = LogEntry(level: .success, message: "完成", accountID: other.accountID, task: .award)
        let session = ActivitySession(id: "notices", runID: UUID(), entries: [warning, duplicate, other, done, otherDone])
        #expect(ActivityResultSummary(session: session).notices.map(\.id) == [warning.id, other.id])
        #expect(session.entries.count == 5)
    }
}
