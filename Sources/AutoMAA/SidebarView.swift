import AppKit
import AutoMAAKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            brand
            List(selection: $model.selection) {
                Section {
                    Label("今日总览", systemImage: "square.grid.2x2.fill")
                        .tag(SidebarSelection.overview)
                }

                Section {
                    ForEach(model.configuration.plans) { plan in
                        HStack(spacing: 9) {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(Color.maaAccent)
                            Text(plan.displayName)
                                .lineLimit(1)
                            Spacer()
                            if model.isPlanScheduleCurrent(plan) {
                                Text(PlanScheduleFormatter.nextRunLabel(plan.schedule) ?? "已启用")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .help(PlanScheduleFormatter.summary(plan.schedule))
                            } else if plan.schedule.enabled {
                                Image(systemName: model.isSynchronizingSchedules
                                      ? "arrow.triangle.2.circlepath"
                                      : "clock.badge.exclamationmark")
                                    .font(.caption2)
                                    .foregroundStyle(model.isSynchronizingSchedules ? Color.maaAccent : Color.orange)
                                    .help(model.isSynchronizingSchedules ? "正在同步定时任务" : "定时任务尚未同步")
                            } else if model.installedPlanIDs.contains(plan.id) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .help("关闭失败，系统定时任务仍存在")
                            }
                        }
                        .tag(SidebarSelection.plan(plan.id))
                    }
                } header: {
                    HStack {
                        Text("自动化方案")
                        Spacer()
                        Menu {
                            Button("轻量日常") { model.addPlan(.lightRoutine) }
                            Button("完整日常") { model.addPlan(.completeRoutine) }
                            Divider()
                            Button("空白方案") {
                                var plan = AutomationPlan(name: "新方案")
                                plan.fight.enabled = false
                                plan.recruit.enabled = false
                                plan.infrast.enabled = false
                                plan.mall.enabled = false
                                plan.award.enabled = false
                                model.addPlan(plan)
                            }
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("添加自动化方案")
                    }
                }

                Section {
                    ForEach(model.configuration.clients) { client in
                        DisclosureGroup {
                            ForEach(client.accounts) { account in
                                HStack(spacing: 9) {
                                    StatusDot(color: account.enabled ? .maaAccent : .secondary.opacity(0.5))
                                    Text(account.displayName)
                                        .lineLimit(1)
                                }
                                .tag(SidebarSelection.account(client.id, account.id))
                            }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: client.kind.symbol)
                                    .foregroundStyle(client.enabled ? Color.maaAccent : Color.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(client.displayName)
                                        .lineLimit(1)
                                    Text(client.kind.title)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(client.accounts.filter(\.enabled).count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { model.selection = .client(client.id) }
                        }
                    }
                } header: {
                    HStack {
                        Text("客户端与账号")
                        Spacer()
                        Button {
                            model.addClient()
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.plain)
                        .help("添加客户端")
                    }
                }

                Section("应用") {
                    Label("活动记录", systemImage: "clock.arrow.circlepath")
                        .tag(SidebarSelection.activity)
                    Label("全局设置", systemImage: "gearshape.fill")
                        .tag(SidebarSelection.settings)
                    Label("关于 AutoMAA", systemImage: "info.circle.fill")
                        .tag(SidebarSelection.about)
                }
            }
            .listStyle(.sidebar)

            statusFooter
        }
        .background(.thinMaterial)
    }

    private var brand: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text("AutoMAA")
                    .font(.headline)
                Text("MAA 日常自动化")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 11) {
            workflowStatus

            if model.isWorkflowRunning {
                if model.activePlanID != nil {
                    WorkflowProgressView(progress: model.activeProgress)
                }

                if model.canCancelRun || model.isCancellingRun {
                    Button { model.cancelRun() } label: {
                        Label(
                            model.isCancellingRun ? "正在取消…" : model.runningPlanID == nil ? "取消更新" : "安全停止",
                            systemImage: "stop.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isCancellingRun)
                    .controlSize(.large)
                    .tint(.red)
                    .help(model.runningPlanID == nil
                          ? "取消当前更新，清理下载进程与临时文件"
                          : "停止当前 MAA 命令，关闭客户端并释放连接")
                } else {
                    Label("定时任务正在后台运行", systemImage: "clock.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                currentPlanPicker

                if model.canRun {
                    Button {
                        model.runSelectedPlan()
                    } label: {
                        Label("运行这个方案", systemImage: "play.fill")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.maaAccent)
                    .help("按当前方案依次执行客户端和账号")
                } else {
                    Button {} label: {
                        Label("配置未完成", systemImage: "exclamationmark.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(true)
                    .help("请先处理当前方案的配置问题")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var currentPlanPicker: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("查看与运行方案")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Menu {
                ForEach(model.configuration.plans) { plan in
                    Button {
                        model.selectCurrentPlan(plan.id)
                    } label: {
                        if model.currentPlanID == plan.id {
                            Label(plan.displayName, systemImage: "checkmark")
                        } else {
                            Text(plan.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(Color.maaAccent)
                    Text(model.currentPlan?.displayName ?? "选择方案")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .disabled(model.configuration.plans.isEmpty)
            .help("切换要查看和运行的方案，不会打开编辑页")
        }
    }

    private var workflowStatus: some View {
        HStack(spacing: 9) {
            Image(systemName: statusSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 26, height: 26)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("运行状态：\(statusTitle)，\(statusDetail)")
    }

    private var statusColor: Color {
        if model.isWorkflowRunning { return model.activePhase.statusTint }
        return switch currentReadinessState {
        case .ready: .green
        case .warnings: .orange
        case .errors, .blockedByOtherPlan, nil: .red
        }
    }

    private var statusSymbol: String {
        if model.isWorkflowRunning { return model.activePhase.statusSymbol }
        return switch currentReadinessState {
        case .ready: "checkmark.circle.fill"
        case .warnings: "exclamationmark.circle.fill"
        case .errors, .blockedByOtherPlan, nil: "exclamationmark.triangle.fill"
        }
    }

    private var statusTitle: String {
        if model.isWorkflowRunning { return model.activePhase.displayName }
        return switch currentReadinessState {
        case .ready: "已准备就绪"
        case .warnings: "可以运行"
        case .errors, .blockedByOtherPlan, nil: "需要完善配置"
        }
    }

    private var statusDetail: String {
        if model.isWorkflowRunning { return model.activeStatusMessage }
        switch currentReadinessState {
        case .ready:
            let plan = model.currentPlan
            let accounts = model.configuration.clients.filter(\.enabled).flatMap { $0.accounts.filter { plan?.includes($0) == true } }.count
            return "\(accounts) 个账号 · \(plan?.enabledTasks.count ?? 0) 个步骤"
        case let .warnings(count):
            return "\(count) 项提醒"
        case let .errors(count):
            return "\(count) 项问题待处理"
        case let .blockedByOtherPlan(count):
            return "其他方案有 \(count) 项问题"
        case nil:
            return "请先创建自动化方案"
        }
    }

    private var currentReadinessState: PlanReadinessState? {
        guard let currentPlanID = model.currentPlanID else { return nil }
        return model.planReadiness(for: currentPlanID).state
    }
}
