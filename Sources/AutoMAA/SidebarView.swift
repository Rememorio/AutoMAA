import AppKit
import AutoMAAKit
import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var expandedClientIDs: Set<UUID> = []

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
                            Image(systemName: "plus").frame(width: 28, height: 28).contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("添加自动化方案")
                        .accessibilityLabel("添加自动化方案")
                    }
                }

                Section {
                    ForEach(model.configuration.clients) { client in
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedClientIDs.contains(client.id) },
                            set: { if $0 { expandedClientIDs.insert(client.id) } else { expandedClientIDs.remove(client.id) } }
                        )) {
                            ForEach(client.accounts) { account in
                                HStack(spacing: 9) {
                                    Image(systemName: account.enabled ? "person.crop.circle" : "person.crop.circle.badge.xmark")
                                        .foregroundStyle(account.enabled ? Color.maaAccent : .secondary)
                                    Text(account.displayName)
                                        .lineLimit(1)
                                        .help(account.displayName + (account.enabled ? "" : "（已停用）"))
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
                        }
                        .tag(SidebarSelection.client(client.id))
                    }
                } header: {
                    HStack {
                        Text("客户端与账号")
                        Spacer()
                        Button {
                            model.addClient()
                        } label: {
                            Image(systemName: "plus").frame(width: 28, height: 28).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("添加客户端")
                        .accessibilityLabel("添加客户端")
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
        .onChange(of: model.selection, initial: true) { _, selection in
            if case let .account(clientID, _) = selection { expandedClientIDs.insert(clientID) }
        }
    }

    private var brand: some View {
        HStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
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
                    StopOperationButton(fillsWidth: true)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                } else {
                    Label("定时任务正在后台运行", systemImage: "clock.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("查看运行") { model.selection = .activity }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
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
        model.isWorkflowRunning ? model.activePhase.statusTint : .secondary
    }

    private var statusSymbol: String {
        model.isWorkflowRunning ? model.activePhase.statusSymbol : "pause.circle"
    }

    private var statusTitle: String {
        model.isWorkflowRunning ? model.activePhase.displayName : "当前空闲"
    }

    private var statusDetail: String {
        model.isWorkflowRunning ? model.activeStatusMessage : (model.activeScheduleCount > 0 ? "定时任务会自动运行" : "尚未启用定时运行")
    }
}
