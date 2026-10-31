import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Activity presentation")
struct ActivityPresentationTests {
    @Test("connection and maintenance milestones are emphasized without coloring routine results or failures")
    func logMilestoneEmphasis() {
        let plan = UUID(), client = UUID(), account = UUID()
        let emphasized: [LogEntry] = [
            .init(level: .success, message: "已连接", phase: .launching, planID: plan, clientID: client),
            .init(level: .success, message: "识别数据通过校验", phase: .updating, planID: plan),
            .init(level: .success, message: "MAA 已是最新版本", phase: .completed)
        ]
        for entry in emphasized { #expect(entry.highlightsMilestone) }

        let ordinary: [LogEntry] = [
            .init(level: .info, message: "正在连接", phase: .launching),
            .init(level: .info, message: "正在同步", phase: .updating),
            .init(level: .success, message: "账号已就绪", phase: .switchingAccount, accountID: account),
            .init(level: .success, message: "任务已完成", phase: .runningTask, task: .recruit),
            .init(level: .success, message: "已关闭客户端", phase: .closing),
            .init(level: .success, message: "方案已结束", phase: .completed, planID: plan),
            .init(level: .success, message: "较早的完成记录"),
            .init(level: .success, message: "整轮完成", phase: .completed,
                  runSummary: .init(completedSteps: 1, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1))
        ]
        for entry in ordinary { #expect(!entry.highlightsMilestone) }
        for phase in [RunnerPhase.launching, .updating, .completed] {
            for level in [LogLevel.warning, .error] {
                #expect(!LogEntry(level: level, message: "异常", phase: phase).highlightsMilestone)
            }
        }
    }

    @Test("ordinary completion omits its badge while exceptional outcomes remain explicit")
    func outcomeStatusVisibility() {
        let complete = LogEntry(level: .success, message: "完成", phase: .completed,
            runSummary: .init(completedSteps: 1, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1))
        #expect(!session([complete]).showsOutcomeStatus)
        #expect(!session([.init(level: .success, message: "较早的完成记录")]).showsOutcomeStatus)

        let notices = session([.init(level: .warning, message: "重试提醒"), complete])
        #expect(!notices.showsOutcomeStatus)
        #expect(ActivityRecordPresentation.summary(notices).contains("1 条提醒"))
        #expect(ActivityResultSummary(session: notices).notices.count == 1)

        let exceptions: [LogEntry] = [
            .init(level: .error, message: "失败", phase: .failed),
            .init(level: .warning, message: "取消", phase: .cancelled),
            .init(level: .info, message: "仍在运行", phase: .runningTask),
            .init(level: .warning, message: "完成但需留意", phase: .completed),
            .init(level: .success, message: "存在失败", phase: .completed,
                  runSummary: .init(completedSteps: 1, failedSteps: 1, unexecutedSteps: 0, totalSteps: 2)),
            .init(level: .success, message: "待确认", phase: .completed,
                  runSummary: .init(completedSteps: 0, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1,
                                    unconfirmedSteps: 1)),
            .init(level: .success, message: "人工处理", phase: .completed,
                  runSummary: .init(completedSteps: 0, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1,
                                    manuallyHandledSteps: 1)),
            .init(level: .success, message: "剿灭待补打", phase: .completed,
                  runSummary: .init(completedSteps: 1, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1,
                                    pendingWeeklyAnnihilation: 1))
        ]
        for entry in exceptions { #expect(session([entry]).showsOutcomeStatus) }
    }

    @Test("manually handled work is described as handled rather than automatically completed")
    func manualHandlingStatus() {
        let handled = session([.init(level: .success, message: "本轮已处理", phase: .completed,
            runSummary: .init(completedSteps: 0, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1,
                              manuallyHandledSteps: 1))])
        #expect(handled.historyStatusTitle == "已处理")
        #expect(!ActivityFilter.failed.includes(handled))
        let partial = session([.init(level: .warning, message: "仍有任务未执行", phase: .completed,
            runSummary: .init(completedSteps: 0, failedSteps: 0, unexecutedSteps: 1, totalSteps: 2,
                              manuallyHandledSteps: 1))])
        #expect(partial.historyStatusTitle == "部分处理")
        #expect(ActivityFilter.attention.includes(partial))
    }

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

    @Test("result notices retain earlier warnings without repeating displayed task failures")
    func resultNotices() {
        let account = UUID()
        let warning = LogEntry(level: .warning, message: "正在重试", accountID: account, task: .mall)
        let failure = LogEntry(level: .error, message: "信用商店连接失败", accountID: account, task: .mall)
        let cleanup = LogEntry(level: .error, message: "清理失败")
        let value = session([warning, failure, cleanup,
                             .init(level: .warning, message: "部分完成", phase: .completed)])
        let summary = ActivityResultSummary(session: value)
        #expect(summary.accounts.first?.outcomes.map(\.id) == [failure.id])
        #expect(summary.notices.map(\.id) == [warning.id, cleanup.id])
        #expect(value.entries.count == 4)

        let recovered = session([failure,
            .init(level: .success, message: "重试成功", accountID: account, task: .mall)])
        #expect(ActivityResultSummary(session: recovered).notices.map(\.id) == [failure.id])
    }

    @Test("account and maintenance notices are shown once when there is no task outcome")
    func noticesWithoutTaskOutcomes() {
        let unmatched = LogEntry(level: .warning, message: "账号未匹配", accountID: UUID())
        let account = ActivityResultSummary(session: session([unmatched]))
        #expect(account.accounts.first?.lastEvent.id == unmatched.id)
        #expect(account.notices.isEmpty)

        let earlier = LogEntry(level: .warning, message: "下载重试")
        let failed = LogEntry(level: .error, message: "更新失败", phase: .failed)
        #expect(ActivityResultSummary(session: session([earlier, failed])).notices.map(\.id) == [earlier.id])
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
