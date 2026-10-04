import AutoMAAKit
import Foundation

extension AppModel {
    func mobileRedact(_ value: String) -> String {
        String(SensitiveDataRedactor.redact(value, sensitiveValues: configuration.clients.flatMap {
            $0.accounts.map(\.accountSelector)
        }).prefix(2048))
    }

    func mobileRevision() throws -> String {
        var state = executionState
        state.updatedAt = Date(timeIntervalSince1970: 0)
        let values = [try MobileProtocol.encode(configuration), try MobileProtocol.encode(state),
                      try MobileProtocol.encode(weeklyAnnihilation), try MobileProtocol.encode(fightStageMemory)]
        var data = Data()
        for value in values {
            let object = try JSONSerialization.jsonObject(with: value)
            data.append(try JSONSerialization.data(withJSONObject: Self.mobileCanonicalJSON(object), options: .sortedKeys))
        }
        data.append(Data(String(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970).utf8))
        return MobileProtocol.digest(data)
    }

    private static func mobileCanonicalJSON(_ value: Any, key: String = "") -> Any {
        if let object = value as? [String: Any] { return object.mapValues { $0 }.reduce(into: [String: Any]()) {
            $0[$1.key] = mobileCanonicalJSON($1.value, key: $1.key)
        } }
        if let array = value as? [Any] {
            let values = array.map { mobileCanonicalJSON($0) }
            if ["accountIDs", "completedSteps", "weekdays"].contains(key) {
                return values.sorted { String(describing: $0) < String(describing: $1) }
            }
            return values
        }
        return value
    }

    func mobileSnapshot(hostID: UUID, sessionID: UUID, hostName: String) -> MobileSnapshot {
        var result = MobileSnapshot(hostID: hostID, sessionID: sessionID, hostName: mobileRedact(hostName))
        result.appVersion = currentApplicationVersion
        result.revision = (try? mobileRevision()) ?? ""
        let control = WorkflowRunControl(directories: directories)
        result.run = control.activeRun()
        result.busy = isWorkflowRunning || result.run != nil || applicationUpdateState.blocksWorkflow
        result.stopping = isCancellingRun || result.run.map { control.isStopRequested(for: $0) } == true
        result.phase = activePhase.displayName
        result.message = mobileRedact(activeStatusMessage)
        result.progress = activeProgress.isFinite ? min(1, max(0, activeProgress)) : 0
        result.canStop = result.run != nil && !result.stopping
        result.plans = configuration.plans.prefix(100).map { plan in
            let continuation = continuation(for: plan.id)
            var item = MobilePlan(id: plan.id, name: mobileRedact(plan.displayName))
            let accounts = configuration.clients.filter(\.enabled).flatMap { client in
                client.accounts.filter { plan.includes($0) }.map { mobileRedact("\(client.displayName) / \($0.displayName)") }
            }
            item.accounts = Array(accounts.prefix(50))
            if accounts.count > 50 { item.accounts.append("另有 \(accounts.count - 50) 个账号，请在 Mac 查看完整范围") }
            item.tasks = plan.enabledTasks.map(\.title)
            item.schedule = isPlanScheduleCurrent(plan)
                ? "下次：\(PlanScheduleFormatter.nextRunLabel(plan.schedule) ?? "待确认")（Mac 时间）"
                : "定时未启用"
            item.action = runTitle(for: plan.id)
            item.canRun = !result.busy && !result.revision.isEmpty && canRun(planID: plan.id) && continuation.pending > 0
            item.pending = continuation.pendingItems.prefix(30).map {
                mobileRedact("\(pendingWorkContext($0.step)) · \($0.title) · \($0.detail ?? "待执行")")
            }
            if continuation.pendingItems.count > 30 { item.pending.append("更多待办请在 Mac 查看") }
            item.warnings = readinessIssues(for: plan.id).prefix(10).map { mobileRedact($0.message) }
            if continuation.unconfirmed > 0 { item.warnings.append("有未确认结果，请在 Mac 检查；这些阶段不会自动重跑。") }
            item.parameters = [runHelp(for: plan.id)]
            if plan.fight.enabled {
                let fight = plan.fight
                item.parameters.append(fight.usesCustomSettings ? "作战：AutoMAA 自定义参数" : "作战：MAA 推荐参数")
                if fight.usesCustomSettings {
                    let stage = fight.stageStrategy == .fixed && !fight.stage.isEmpty ? " · \(fight.stage)" : ""
                    item.parameters.append(mobileRedact("关卡策略：\(fight.stageStrategy.title)\(stage)"))
                    item.parameters.append("理智药：\(fight.medicine.map(String.init) ?? "MAA 默认")；源石：\(fight.stone.map(String.init) ?? "MAA 默认")")
                    if let days = fight.medicineExpireDays { item.parameters.append("使用 \(days) 天内过期的理智药") }
                    if let times = fight.times { item.parameters.append("作战次数上限：\(times)") }
                } else { item.parameters.append("用药与次数遵循 MAA 推荐参数，不使用理智药或源石。") }
                if FightStagePolicy.requiresExplicitRegularStage(in: fight) {
                    item.parameters.append("常规关卡先按现有策略识别；需要恢复时使用各账号记录的目标。")
                    var targetCount = 0
                    for client in configuration.clients.filter(\.enabled) {
                        for account in client.accounts.filter({ plan.includes($0) }) {
                            guard targetCount < 20 else { break }
                            let target = fightStageMemory.stage(clientID: client.id, accountID: account.id) ?? "待开战前识别"
                            item.parameters.append(mobileRedact("\(account.displayName) · 常规目标：\(target)"))
                            targetCount += 1
                        }
                    }
                    if accounts.count > targetCount { item.parameters.append("更多账号目标请在 Mac 查看") }
                } else if !fight.usesCustomSettings {
                    item.parameters.append("常规作战使用游戏当前或上次关卡。")
                }
                if fight.weeklyAnnihilation.enabled { item.parameters.append("包含本周剿灭安排") }
            }
            return item
        }
        var remainingBytes = 512 * 1024
        result.plans = Array(result.plans.prefix { plan in
            guard let data = try? MobileProtocol.encode(plan), data.count <= remainingBytes else { return false }
            remainingBytes -= data.count
            return true
        })
        if result.plans.count < configuration.plans.count {
            result.message += "；当前显示 \(result.plans.count) 个方案，更多内容请在 Mac 查看。"
        }
        return result
    }

    func performMobileCommand(_ request: MobileRequest) throws -> String {
        reloadActivityHistory()
        switch request.operation {
        case .run:
            guard let id = request.planID, configuration.plans.contains(where: { $0.id == id }),
                  request.revision == (try mobileRevision()) else {
                throw MobileAccessError("方案或执行记录已变化，请刷新后重新确认")
            }
            guard WorkflowRunControl(directories: directories).activeRun() == nil,
                  canRun(planID: id), continuation(for: id).pending > 0 else {
                throw MobileAccessError("当前无法运行，请检查运行状态、待办及方案配置")
            }
            runPlan(id, resumeToday: true)
            guard isRunning, runningPlanID == id else {
                throw MobileAccessError(mobileRedact(configurationSaveError ?? "运行请求未接受，请在 Mac 检查配置"))
            }
            return "运行请求已接受，请查看实际进度"
        case .stop:
            guard let identity = request.run else { throw MobileAccessError("缺少运行标识，请刷新状态") }
            try WorkflowRunControl(directories: directories).requestStop(for: identity)
            return "已请求安全停止，正在等待当前客户端和连接清理"
        default: throw MobileAccessError("不支持此控制操作")
        }
    }

    func mobileHistory(_ request: MobileRequest) throws -> MobileReply {
        let sessions = ActivityHistory.sessions(from: activityEntries).sorted {
            $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt > $1.startedAt
        }
        var reply = MobileReply(id: request.id, type: request.operation == .history ? "history" : "historyDetails")
        if request.operation == .history {
            let start: Int
            if let before = request.before {
                guard let index = sessions.firstIndex(where: { $0.id == before }) else { throw MobileAccessError("记录已更新，请重新加载列表") }
                start = index + 1
            } else { start = 0 }
            let page = Array(sessions.dropFirst(start).prefix(20))
            reply.history = page.map { session in
                let title = configuration.plans.first(where: { $0.id == session.planID })?.displayName ?? "运行与维护"
                let activeID = WorkflowRunControl(directories: directories).activeRun()?.runID
                var item = MobileHistoryItem(id: session.id, title: mobileRedact(title), startedAt: session.startedAt,
                                             status: activeID != nil && session.runID == activeID ? "正在运行" : session.historyStatusTitle)
                item.hasAttention = ActivityFilter.attention.includes(session)
                item.failed = ActivityFilter.failed.includes(session)
                return item
            }
            if sessions.count > start + page.count { reply.next = page.last?.id }
        } else {
            guard let session = sessions.first(where: { $0.id == request.historyID }) else { throw MobileAccessError("记录不存在，请重新加载列表") }
            let entries = Array(session.entries.reversed())
            let start: Int
            if let before = request.before {
                guard let id = UUID(uuidString: before), let index = entries.firstIndex(where: { $0.id == id }) else {
                    throw MobileAccessError("记录已更新，请重新加载详情")
                }
                start = index + 1
            } else { start = 0 }
            let page = Array(entries.dropFirst(start).prefix(30))
            let sensitive = configuration.clients.flatMap { $0.accounts.map(\.accountSelector) }
            reply.events = page.map { MobileLog($0, sensitiveValues: sensitive) }
            if entries.count > start + page.count { reply.next = page.last?.id.uuidString }
        }
        return reply
    }
}
