import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Activity presentation")
struct ActivityPresentationTests {
    @Test("attention keeps successful context and failure excludes recovered errors")
    func sessionFilters() {
        let recovered = session([
            .init(level: .error, message: "第一次失败", task: .recruit),
            .init(level: .success, message: "重试完成", task: .recruit),
            .init(level: .warning, message: "运行结束", phase: .completed,
                  runSummary: .init(completedSteps: 1, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1))
        ])
        #expect(ActivityFilter.attention.includes(recovered))
        #expect(!ActivityFilter.failed.includes(recovered))
        let failed = session([.init(level: .warning, message: "部分完成", phase: .completed,
            runSummary: .init(completedSteps: 1, failedSteps: 1, unexecutedSteps: 0, totalSteps: 2))])
        #expect(ActivityFilter.failed.includes(failed))
        #expect(ActivityFilter.attention.includes(failed))
        let pending = session([.init(level: .success, message: "本轮结束", phase: .completed,
            runSummary: .init(completedSteps: 1, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1, pendingWeeklyAnnihilation: 1))])
        #expect(ActivityFilter.attention.includes(pending))
        #expect(!ActivityFilter.failed.includes(pending))
        let unfinished = session([.init(level: .info, message: "开始作战", phase: .runningTask)])
        #expect(unfinished.hasUnfinishedActivity)
        #expect(unfinished.historyStatusTitle == "未记录结束")
        #expect(ActivityFilter.attention.includes(unfinished))
        #expect(!ActivityFilter.failed.includes(unfinished))
    }

    @Test("search matches the whole run by context or details without removing its result")
    func searchPreservesRun() {
        let value = session([
            .init(level: .info, message: "常规目标 ZZ-7", details: "资源详情"),
            .init(level: .warning, message: "切换兜底"),
            .init(level: .success, message: "完成 1-7", phase: .completed)
        ])
        for query in [" zz-7 ", "资源详情", "示例账号", "轻量", "  "] {
            let filtered = [value].filter {
                ActivityFilter.attention.includes($0)
                    && ActivitySearch.matches($0, query: query, title: "轻量日常", context: { _ in "示例账号" })
            }
            #expect(filtered.first?.entries == value.entries)
        }
        #expect(!ActivitySearch.matches(value, query: "不存在", title: "轻量日常", context: { _ in nil }))
    }

    @Test("cross-midnight runs stay together under their starting day")
    func dayGroups() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let start = ISO8601DateFormatter().date(from: "2026-09-17T15:59:00Z")!
        let before = ActivitySession(id: "before", runID: UUID(), entries: [
            .init(timestamp: start, level: .info, message: "开始"),
            .init(timestamp: start.addingTimeInterval(120), level: .success, message: "结束")
        ])
        let after = ActivitySession(id: "after", runID: UUID(), entries: [
            .init(timestamp: start.addingTimeInterval(180), level: .success, message: "另一轮")
        ])
        let groups = ActivityDay.groups([before, after], calendar: calendar)
        #expect(groups.map { $0.sessions.map(\.id) } == [["after"], ["before"]])
        #expect(groups[1].sessions[0].entries.count == 2)
    }

    @Test("account summaries retain final fallback outcomes and do not invent completion")
    func accountOutcomes() {
        let client = UUID(), account = UUID(), second = UUID()
        let value = session([
            .init(level: .warning, message: "原目标不可进入", clientID: client, accountID: account, task: .fight,
                  fightResult: .init(status: .failed, stage: "ZZ-7", reason: .stageUnavailable)),
            .init(level: .success, message: "兜底完成", clientID: client, accountID: account, task: .fight,
                  fightResult: .init(status: .completed, stage: "1-7", times: 2, fallbackFrom: "ZZ-7")),
            .init(level: .info, message: "正在准备账号", clientID: client, accountID: second),
            .init(level: .warning, message: "账号未匹配", clientID: client, accountID: second)
        ])
        let groups = ActivityAccountSummary.groups(in: value)
        #expect(groups.count == 2)
        #expect(groups[0].outcomes.count == 1)
        #expect(groups[0].outcomes.first?.fightResult?.fallbackFrom == "ZZ-7")
        #expect(groups[1].outcomes.isEmpty)
        #expect(groups[1].lastEvent.message == "账号未匹配")
        #expect(value.entries.count == 4)
    }

    private func session(_ entries: [LogEntry]) -> ActivitySession {
        let start = Date(timeIntervalSince1970: 1_000)
        return ActivitySession(id: UUID().uuidString, runID: UUID(), entries: entries.enumerated().map { index, value in
            var entry = value
            entry.timestamp = start.addingTimeInterval(Double(index))
            return entry
        })
    }
}
