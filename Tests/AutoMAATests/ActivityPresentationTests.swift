import AutoMAAKit
import Foundation
import Testing
@testable import AutoMAA

@Suite("Activity presentation")
struct ActivityPresentationTests {
    @Test("a historical fight reports its original uncertainty without prompting for a current action")
    func recordedFightReason() {
        let result = FightResult(status: .unconfirmed, stage: "1-7", reason: .interruptedBattle)
        #expect(ActivityResultLine(result).title == "作战结果未确认（目标：1-7） · 作战中断")
        #expect(result.description.contains("请检查游戏结果"))
    }

    @Test("timeline context follows visible rows and distinct identities even when display names match")
    func contextualLogSubtitles() {
        let account = AccountConfiguration(name: "示例")
        let namesake = AccountConfiguration(name: "示例")
        let client = ClientConfiguration(name: "客户端", kind: .official, appPath: "",
            address: "127.0.0.1:49195", profileName: "demo", bundleIdentifier: "test.client.one", accounts: [account, namesake])
        var second = client
        second.id = UUID()
        let clients = [client, second]
        let event = LogEntry(level: .info, message: "账号「原名称」：正在执行", clientID: client.id, accountID: account.id)
        var otherAccount = event
        otherAccount.accountID = namesake.id
        var otherClient = otherAccount
        otherClient.clientID = second.id
        var clientOnly = otherClient
        clientOnly.accountID = nil
        var warning = clientOnly
        warning.level = .warning
        var error = warning
        error.level = .error
        let visible = [event, event, otherAccount, otherClient, clientOnly, clientOnly, warning, error]
        let flags = visible.indices.map { ActivityRecordPresentation.showsContext(in: visible, at: $0) }
        #expect(flags == [true, false, true, true, true, false, true, true])
        #expect([event, otherAccount, otherClient].map { ActivityRecordPresentation.context($0, clients: clients) }
            == ["客户端 · 示例", "客户端 · 示例", "客户端 · 示例"])
        let filtered = Array(visible.dropFirst())
        #expect(ActivityRecordPresentation.showsContext(in: filtered, at: 0))
        #expect(filtered.first?.message == "账号「原名称」：正在执行")
    }

    @Test("carried fights in old history do not display drops earned in the original run")
    func carriedFightDrops() {
        let result = FightResult(status: .unconfirmed, totalDrops: "剿灭：合成玉 × 370")
        var entry = LogEntry(level: .warning, message: "账号：保留待确认作战，继续其他任务；请在活动记录的当前待办中处理",
                             phase: .runningTask, task: .fight, fightResult: result)
        #expect(entry.recordedDropsSummary == nil)
        #expect(entry.isCarriedForwardFight)
        entry.message = "账号：上次作战结果待核实，本次跳过作战并继续其他任务"
        #expect(entry.isCarriedForwardFight)
        entry.message = "已跳过"
        entry.carriedForwardFight = true
        #expect(entry.recordedDropsSummary == nil)
        entry.carriedForwardFight = nil
        entry.message = "理智作战：剿灭已完成；常规结果未确认"
        #expect(entry.recordedDropsSummary == result.dropsSummary)
    }

    @Test("terminal log markers reflect structured whole-run results and exclude routine events")
    func terminalLogOutcomes() {
        let partial = LogEntry(level: .warning, message: "部分完成", phase: .completed,
            runSummary: .init(completedSteps: 10, failedSteps: 0, unexecutedSteps: 5, totalSteps: 15))
        #expect(partial.terminalOutcome == .partial)
        let handled = LogEntry(level: .success, message: "已处理", phase: .completed,
            runSummary: .init(completedSteps: 0, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1,
                              manuallyHandledSteps: 1))
        #expect(handled.terminalOutcome == .handled)
        #expect(LogEntry(level: .success, message: "已完成", phase: .completed).terminalOutcome == .completed)
        #expect(LogEntry(level: .error, message: "失败", phase: .failed).terminalOutcome == .failed)
        #expect(LogEntry(level: .info, message: "已停止", phase: .cancelled).terminalOutcome == .cancelled)
        for entry in [LogEntry(level: .success, message: "已连接", phase: .launching),
                      .init(level: .success, message: "资源通过校验", phase: .updating),
                      .init(level: .success, message: "任务完成", phase: .runningTask, task: .mall),
                      .init(level: .success, message: "客户端已关闭", phase: .completed, clientID: UUID()),
                      .init(level: .success, message: "账号已完成", phase: .completed, accountID: UUID()),
                      .init(level: .error, message: "任务失败", phase: .failed, task: .mall),
                      .init(level: .warning, message: "需要处理", phase: .attention),
                      .init(level: .success, message: "较早的记录")] {
            #expect(entry.terminalOutcome == nil)
        }
    }

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

    @Test("history derives a consistent outcome from terminal phases and structured results")
    func historyOutcome() {
        let complete = LogEntry(level: .success, message: "完成", phase: .completed,
            runSummary: .init(completedSteps: 1, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1))
        #expect(session([complete]).outcome == .completed)
        #expect(session([.init(level: .success, message: "较早的完成记录")]).outcome == .completed)

        let notices = session([.init(level: .warning, message: "重试提醒"), complete])
        #expect(notices.outcome == .completed)
        #expect(ActivityRecordPresentation.summary(notices) == "本轮已处理 1/1 项")
        #expect(ActivityResultSummary(session: notices).notices.count == 1)

        let cases: [(LogEntry, ActivityOutcome)] = [
            (.init(level: .error, message: "失败", phase: .failed), .failed),
            (.init(level: .warning, message: "取消", phase: .cancelled), .cancelled),
            (.init(level: .info, message: "仍在运行", phase: .runningTask), .unfinished),
            (.init(level: .warning, message: "结果待核实", phase: .completed), .awaitingReview),
            (.init(level: .warning, message: "存在失败", phase: .completed,
                   runSummary: .init(completedSteps: 1, failedSteps: 1, unexecutedSteps: 0, totalSteps: 2)), .partial),
            (.init(level: .warning, message: "全部失败", phase: .completed,
                   runSummary: .init(completedSteps: 0, failedSteps: 1, unexecutedSteps: 0, totalSteps: 1)), .failed),
            (.init(level: .success, message: "待确认", phase: .completed,
                   runSummary: .init(completedSteps: 0, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1,
                                     unconfirmedSteps: 1)), .incomplete),
            (.init(level: .success, message: "剿灭待补打", phase: .completed,
                   runSummary: .init(completedSteps: 1, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1,
                                     pendingWeeklyAnnihilation: 1)), .weeklyPending)
        ]
        for (entry, outcome) in cases { #expect(session([entry]).outcome == outcome) }
    }

    @Test("manually handled work is described as handled rather than automatically completed")
    func manualHandlingStatus() {
        let handled = session([.init(level: .success, message: "本轮已处理", phase: .completed,
            runSummary: .init(completedSteps: 0, failedSteps: 0, unexecutedSteps: 0, totalSteps: 1,
                              manuallyHandledSteps: 1))])
        #expect(handled.outcome == .handled)
        #expect(!ActivityFilter.failed.includes(handled))
        let partial = session([.init(level: .warning, message: "仍有任务未执行", phase: .completed,
            runSummary: .init(completedSteps: 0, failedSteps: 0, unexecutedSteps: 1, totalSteps: 2,
                              manuallyHandledSteps: 1))])
        #expect(partial.outcome == .partiallyHandled)
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
        #expect(unfinished.outcome == .unfinished)
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
        let groups = ActivityDay.days(ActivityHistoryGroup.groups([after, before], calendar: calendar), calendar: calendar)
        #expect(groups.map { $0.groups.map(\.id) } == [["after"], ["before"]])
        #expect(groups[1].groups[0].latest.entries.count == 2)
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

    @Test("only earlier failures followed by the same recorded task's success belong to its handled details")
    func recoveredAttempts() throws {
        let run = UUID(), client = UUID(), account = UUID()
        let issue = LogEntry(level: .error, message: "失败", runID: run, phase: .runningTask,
                             clientID: client, accountID: account, task: .mall)
        let warning = LogEntry(level: .warning, message: "需要人工处理", runID: run, phase: .runningTask,
                               clientID: client, accountID: account, task: .mall)
        let done = LogEntry(level: .success, message: "重试后已完成", runID: run, phase: .runningTask,
                            clientID: client, accountID: account, task: .mall)
        var foreign = issue
        foreign.id = UUID()
        foreign.accountID = UUID()
        let entries = session([issue, warning, foreign, done]).entries
        let summary = ActivityResultSummary(session: .init(id: "recovered", runID: run, entries: entries))
        #expect(summary.earlierFailuresByOutcome[done.id]?.map(\.id) == [issue.id])
        #expect(summary.notices.map(\.id) == [warning.id])
        #expect(summary.exceptions.map(\.id) == [foreign.id])
        let legacy = ActivityResultSummary(session: .init(id: "legacy", runID: nil, entries: entries))
        #expect(legacy.earlierFailuresByOutcome.isEmpty)
    }

    @Test("record selection preserves a visible object and prefers the latest history when idle")
    func visibleSelection() {
        let plan = UUID(), stale = UUID()
        let history = ["recent", "older"]
        #expect(ActivityWorkspaceSelection.restored(nil, current: nil, history: history) == .session("recent"))
        #expect(ActivityWorkspaceSelection.restored(.session("older"), current: .plan(plan), history: history) == .session("older"))
        #expect(ActivityWorkspaceSelection.restored(.plan(stale), current: nil, history: history) == .session("recent"))
        #expect(ActivityWorkspaceSelection.restored(.plan(plan), current: nil, history: []) == nil)
        #expect(ActivityWorkspaceSelection.restored(.plan(stale), current: .plan(plan), history: history) == .plan(plan))
        #expect(ActivityWorkspaceSelection.restored(nil, current: .backgroundRun, history: history) == .backgroundRun)
        #expect(ActivityWorkspaceSelection.restored(nil, current: nil, history: []) == nil)
    }

    @Test("unconfirmed fights remain visible ahead of handled outcomes; incomplete history retains round totals")
    func separatesHandledTasks() {
        let account = UUID()
        let fight = LogEntry(level: .warning, message: "上次作战待核实", accountID: account, task: .fight,
                             fightResult: .init(status: .unconfirmed))
        let success = LogEntry(level: .success, message: "领取奖励已完成", accountID: account, task: .award)
        let result = LogEntry(level: .warning, message: "部分完成", phase: .completed,
                              runSummary: .init(completedSteps: 1, failedSteps: 0, unexecutedSteps: 0, totalSteps: 2, unconfirmedSteps: 1))
        let run = session([fight, success, result])
        let rendered = ActivityResultSummary(session: run)
        #expect(rendered.exceptions.map(\.id) == [fight.id])
        #expect(rendered.accounts.flatMap(\.completedTasks).map(\.id) == [success.id])
        #expect(ActivityRecordPresentation.summary(run).isEmpty)
        #expect(ActivityRecordPresentation.summary(session([result])).contains("1 项待核实"))
    }

    @Test("account results show each executed stage and its drops exactly once, including mixed outcomes")
    func visibleFightResults() throws {
        let weekly = FightResult(status: .completed, stage: "地图", times: 2, reason: .weeklyLimit,
                                 totalDrops: "合成玉 × 740", kind: .annihilation)
        let regular = FightResult(status: .completed, stage: "1-7", times: 3, totalDrops: "源岩 × 2", kind: .regular,
                                  missingDropRuns: 1)
        let combined = FightResult(status: .completed, stage: "地图 + 1-7", times: 5, totalDrops: "剿灭：合成玉 × 740\n常规：源岩 × 2")
        var event = LogEntry(level: .success, message: "理智作战", accountID: UUID(), task: .fight,
                             fightResult: combined, executedFightPhases: [weekly, regular])
        let rows = event.handledFightLines
        #expect(rows.map(\.title) == ["剿灭 · 地图 × 2 次", "1-7 × 3 次"])
        #expect(rows.map(\.drops) == ["总掉落：合成玉 × 740", "已识别掉落：源岩 × 2"])
        #expect(rows.last?.note == "1 次掉落未识别")
        #expect(try JSONDecoder().decode(LogEntry.self, from: JSONEncoder().encode(event)) == event)

        let interrupted = FightResult(status: .unconfirmed, stage: "1-7", times: 1, reason: .interruptedBattle,
                                      totalDrops: "龙门币 × 12", kind: .regular)
        event.level = .warning
        event.fightResult = interrupted
        event.executedFightPhases = [weekly, interrupted]
        #expect(event.handledFightLines == [rows[0]])
        #expect(event.exceptionLine.title.contains("未确认"))
        #expect(event.exceptionLine.drops == "已识别掉落：龙门币 × 12")
        let account = try #require(event.accountID)
        let otherAccount = UUID()
        let award = LogEntry(level: .success, message: "领取奖励已完成", accountID: account, task: .award)
        let other = LogEntry(level: .success, message: "基建已完成", accountID: otherAccount, task: .infrast)
        let summary = ActivityResultSummary(session: session([award, other, event, event]))
        #expect(summary.exceptions.map(\.id) == [event.id])
        #expect(summary.accounts.compactMap(\.fight).flatMap(\.handledFightLines) == [rows[0]])
        #expect(summary.accounts.map { $0.completedTasks.map(\.id) } == [[award.id], [other.id]])
    }

    @Test("skipped and manually handled tasks have no inherited harvest, and old combined records keep their wording")
    func historicalFightEvidence() throws {
        let prior = FightResult(status: .manuallyHandled, stage: "1-7", times: 9, totalDrops: "旧掉落")
        let weekly = FightResult(status: .completed, stage: "Annihilation", times: 1, kind: .annihilation)
        var event = LogEntry(level: .info, message: "已人工处理", accountID: UUID(), task: .fight,
                             fightResult: prior, executedFightPhases: [weekly])
        #expect(event.handledFightLines.map(\.title) == ["剿灭 × 1 次", "常规作战已人工处理"])
        #expect(event.handledFightLines.compactMap(\.drops).isEmpty)
        #expect(event.recordedDropsSummary == nil)
        event.fightResult = weekly
        event.executedFightPhases = []
        #expect(event.handledFightLines.map(\.title) == ["本轮作战已处理，本次未执行"])
        event.carriedForwardFight = true
        #expect(event.handledFightLines.isEmpty)
        #expect(event.exceptionLine == .init(title: "上次作战待核实，本次跳过"))

        event.carriedForwardFight = nil
        event.executedFightPhases = nil
        event.message = "理智作战：剿灭已完成（地图 × 1）；常规无需作战 · 理智不足"
        let restored = try JSONDecoder().decode(LogEntry.self, from: JSONEncoder().encode(event))
        #expect(restored.executedFightPhases == nil)
        #expect(restored.handledFightLines.map(\.title) == [event.message])
    }

    @Test("a settled phase remains visible when cancellation precedes the final report and is shown only once")
    func interruptedBetweenPhases() {
        let account = UUID()
        let settled = FightResult(status: .completed, stage: "Annihilation", times: 1, totalDrops: "合成玉 × 370")
        let phase = LogEntry(level: .info, message: "剿灭已完成", phase: .runningTask, accountID: account, task: .fight,
                             executedFightPhases: [settled])
        let stopped = LogEntry(level: .info, message: "已停止", phase: .cancelled)
        let interrupted = ActivityResultSummary(session: session([phase, phase, stopped]))
        #expect(interrupted.exceptions.isEmpty)
        #expect(interrupted.accounts.flatMap(\.fightLines) == [ActivityResultLine(settled)])

        let final = LogEntry(level: .success, message: "理智作战已完成", phase: .runningTask, accountID: account, task: .fight,
                             fightResult: settled, executedFightPhases: [settled])
        let completed = ActivityResultSummary(session: session([phase, final]))
        #expect(completed.accounts.flatMap(\.fightLines) == [ActivityResultLine(settled)])
        #expect(completed.accounts.allSatisfy { $0.unreportedFightPhases.isEmpty })
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
