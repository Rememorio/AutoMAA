import AutoMAAKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metrics
                routines
                executionFlow
                readiness
                recentActivity
            }
            .padding(28)
            .frame(maxWidth: 1_060, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("自动化总览")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(model.isRunning ? model.statusMessage : "账号只配置一次，用不同方案安排轻量收菜、完整换班或任何自定义日常。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metric(title: "自动化方案", value: "\(model.configuration.plans.count)", symbol: "clock.arrow.circlepath", color: .purple)
            metric(title: "客户端", value: "\(model.activeClientCount)", symbol: "macwindow", color: .maaBlue)
            metric(title: "启用账号", value: "\(model.activeAccountCount)", symbol: "person.2.fill", color: .maaAccent)
            metric(title: "定时方案", value: "\(model.configuration.plans.filter(\.schedule.enabled).count)", symbol: "clock.badge.checkmark.fill", color: .orange)
        }
    }

    private func metric(title: String, value: String, symbol: String, color: Color) -> some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var routines: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("自动化方案", detail: "每个方案独立选择账号、任务参数、完成记录和定时时间，也可以随时手动运行。")
            if model.configuration.plans.isEmpty {
                Panel {
                    VStack(spacing: 14) {
                        Image(systemName: "clock.badge.plus")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.maaAccent)
                        Text("创建你的第一个自动化方案")
                            .font(.headline)
                        Button("使用轻量日常模板") { model.addPlan(.lightRoutine) }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(model.configuration.plans) { plan in
                        routineCard(plan)
                    }
                }
            }
        }
    }

    private func routineCard(_ plan: AutomationPlan) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Color.maaAccent)
                    Text(plan.name)
                        .font(.headline)
                    Spacer()
                    if plan.schedule.enabled {
                        Label(String(format: "%02d:%02d", plan.schedule.hour, plan.schedule.minute), systemImage: "clock.fill")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text("仅手动")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(plan.enabledTasks) { task in
                        Image(systemName: task.symbol)
                            .font(.caption)
                            .foregroundStyle(Color.maaAccent)
                            .frame(width: 25, height: 25)
                            .background(Color.maaAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                            .help(task.title)
                    }
                    Spacer()
                    Text("\(targetCount(plan)) 个账号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Button("编辑") { model.selection = .plan(plan.id) }
                    Spacer()
                    Button {
                        model.runPlan(plan.id)
                    } label: {
                        Label("运行", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canRun(planID: plan.id))
                }
            }
        }
    }

    private var executionFlow: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("当前执行路径", detail: "客户端严格串行；确认当前客户端关闭、连接释放后，才启动下一项。")
            Panel {
                if let plan = model.selectedPlan {
                    let clients = model.configuration.clients.filter { $0.enabled && $0.accounts.contains(where: plan.includes) }
                    if clients.isEmpty {
                        Text("「\(plan.name)」还没有可执行账号")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 10) {
                            ForEach(Array(clients.enumerated()), id: \.element.id) { index, client in
                                clientNode(client, plan: plan)
                                if index < clients.count - 1 {
                                    VStack(spacing: 4) {
                                        Image(systemName: "arrow.right")
                                            .foregroundStyle(Color.maaAccent)
                                        Text("关闭并释放")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 68)
                                }
                            }
                        }
                    }
                } else {
                    Text("请选择一个方案")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func clientNode(_ client: ClientConfiguration, plan: AutomationPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: client.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(Color.maaAccent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(client.name)
                        .font(.subheadline.weight(.semibold))
                    Text(client.address)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 6) {
                ForEach(client.accounts.filter(plan.includes)) { account in
                    Text(account.name)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.maaAccent.opacity(0.09), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readiness: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("运行检查", detail: "以下检查针对侧边栏当前选中的方案。")
            Panel {
                if model.readinessIssues.isEmpty {
                    Label("「\(model.selectedPlan?.name ?? "方案")」已准备就绪", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.readinessIssues) { issue in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: issue.severity == .error ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                                Text(issue.message)
                                    .font(.callout)
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("最近活动", detail: nil)
            Panel {
                if model.logs.isEmpty {
                    Text("还没有运行记录")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.logs.suffix(4).reversed()) { log in
                            HStack(spacing: 10) {
                                StatusDot(color: log.level.color)
                                Text(log.message).font(.callout).lineLimit(1)
                                Spacer()
                                Text(log.timestamp, style: .time)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func targetCount(_ plan: AutomationPlan) -> Int {
        model.configuration.clients.filter(\.enabled).flatMap { $0.accounts.filter(plan.includes) }.count
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 11 { return "早上好，博士" }
        if hour < 18 { return "下午好，博士" }
        return "晚上好，博士"
    }
}
